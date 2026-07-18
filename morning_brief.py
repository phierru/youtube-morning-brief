#!/usr/bin/env python3
"""YouTube Morning Brief.

Fetches new videos from configured YouTube channels via their RSS feeds,
pulls transcripts with yt-dlp, summarizes each video with the Claude CLI,
and writes a daily markdown report into the Obsidian vault.

Run daily by a LaunchAgent (com.francescolardieri.youtube-morning-brief).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_PATH = SCRIPT_DIR / "config.json"
STATE_PATH = SCRIPT_DIR / "state.json"
LOCK_PATH = SCRIPT_DIR / "run.lock"
YTDLP = SCRIPT_DIR / ".venv" / "bin" / "yt-dlp"
CLAUDE = shutil.which("claude") or "/opt/homebrew/bin/claude"

ATOM = "{http://www.w3.org/2005/Atom}"
YT = "{http://www.youtube.com/xml/schemas/2015}"
MEDIA = "{http://search.yahoo.com/mrss/}"

SUMMARY_PROMPT = """You are writing one section of a daily video briefing for Francesco.
Below are the title, channel, description, and transcript of a YouTube video.

Write ONLY the following markdown (no preamble, no code fences, start directly with "**Summary**"):

**Summary**
2-4 sentences: what the video is about and its main message.

**Key takeaways**
- 3-6 concise bullets with the most important points, findings, or demos.

**Products & tools mentioned**
- [Product/Tool Name](link) — one line on how it was used or discussed.
Use links found in the video description when available. If a product is clearly
discussed but has no link in the description, link to
https://www.google.com/search?q=<product+name> instead. If no products or tools
are mentioned, write "- None mentioned."

Keep it factual and skimmable. Do not invent products that are not in the
transcript or description.

=== VIDEO TITLE ===
{title}

=== CHANNEL ===
{channel}

=== DESCRIPTION ===
{description}

=== TRANSCRIPT ===
{transcript}
"""

DIGEST_PROMPT = """You are writing the opening digest of today's "{subject}" video briefing for Francesco.
Below are the per-video briefing sections (title, channel, video link, summary, takeaways).

Write ONLY the following markdown (no preamble, no code fences, start directly with "**Top themes**"):

**Top themes**
- 3-5 bullets synthesizing the biggest stories or themes across all videos,
merging overlapping coverage and noting which channels covered each theme.

**At a glance**
- **Channel** — [Video Title](url): one-sentence gist.
(one line per video, most important first; use the exact video URLs given)

Keep it tight and skimmable.

=== SECTIONS ===
{sections}
"""


def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


def acquire_lock():
    """Single-instance guard: the lockfile holds the running PID so external
    tools (the Mac app) can display run-in-progress state."""
    if LOCK_PATH.exists():
        try:
            pid = int(LOCK_PATH.read_text().strip())
        except ValueError:
            pid = None
        if pid and pid_alive(pid):
            log(f"another run is in progress (pid {pid}) — exiting")
            sys.exit(0)
        log("stale lock found — clearing")
        LOCK_PATH.unlink(missing_ok=True)
    LOCK_PATH.write_text(str(os.getpid()))


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def load_json(path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def fetch_feed(channel_id, attempts=4, wait=30):
    """Fetch a channel RSS feed, retrying to ride out transient network loss
    (e.g. Wi-Fi still reconnecting right after the Mac wakes)."""
    url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return ET.fromstring(resp.read())
        except Exception:
            if attempt == attempts:
                raise
            log(f"  feed fetch failed (attempt {attempt}/{attempts}), retrying in {wait}s")
            time.sleep(wait)


def parse_entries(root, channel_name):
    entries = []
    for e in root.findall(f"{ATOM}entry"):
        vid = e.findtext(f"{YT}videoId")
        title = e.findtext(f"{ATOM}title") or "(untitled)"
        published = e.findtext(f"{ATOM}published")
        group = e.find(f"{MEDIA}group")
        description = ""
        if group is not None:
            description = group.findtext(f"{MEDIA}description") or ""
        if not vid or not published:
            continue
        entries.append({
            "id": vid,
            "title": title,
            "channel": channel_name,
            "url": f"https://www.youtube.com/watch?v={vid}",
            "published": datetime.fromisoformat(published),
            "description": description,
        })
    return entries


def video_probe(url):
    """Return (duration_seconds, live_status) via yt-dlp; (None, None) on failure."""
    try:
        r = subprocess.run(
            [str(YTDLP), "--skip-download", "--no-warnings",
             "--print", "%(duration)s|%(live_status)s", url],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0 or "|" not in r.stdout:
            return None, None
        dur_s, live = r.stdout.strip().split("|", 1)
        dur = int(float(dur_s)) if dur_s not in ("NA", "") else None
        return dur, live
    except (subprocess.TimeoutExpired, ValueError):
        return None, None


def fetch_transcript(url):
    """Download English (auto-)subtitles with yt-dlp and return plain text."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [str(YTDLP), "--skip-download", "--no-warnings",
             "--write-subs", "--write-auto-subs",
             "--sub-langs", "en.*,en-orig,en", "--sub-format", "vtt",
             "-o", "sub", url],
            capture_output=True, text=True, timeout=300, cwd=tmp,
        )
        vtts = sorted(Path(tmp).glob("*.vtt"))
        if not vtts:
            return None
        return vtt_to_text(vtts[0].read_text(errors="replace"))


def vtt_to_text(vtt):
    lines, prev = [], None
    for raw in vtt.splitlines():
        line = re.sub(r"<[^>]+>", "", raw).strip()
        if (not line or line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE"))
                or "-->" in raw or line.isdigit()):
            continue
        if line != prev:  # auto-subs repeat lines as they scroll
            lines.append(line)
            prev = line
    return " ".join(lines)


def run_claude(prompt, cfg, attempts=2, wait=60):
    err = ""
    for attempt in range(1, attempts + 1):
        try:
            r = subprocess.run(
                [CLAUDE, "-p", "--model", cfg.get("claude_model", "sonnet")],
                input=prompt, capture_output=True, text=True, timeout=600,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
            err = r.stderr.strip()[:300]
        except subprocess.TimeoutExpired:
            err = "timeout"
        if attempt < attempts:
            log(f"  claude call failed ({err or 'no output'}), retrying in {wait}s")
            time.sleep(wait)
    log(f"  claude call failed after {attempts} attempts: {err or 'no output'}")
    return None


def summarize(video, transcript, cfg):
    prompt = SUMMARY_PROMPT.format(
        title=video["title"],
        channel=video["channel"],
        description=video["description"][:6000],
        transcript=transcript[:cfg["max_transcript_chars"]],
    )
    return run_claude(prompt, cfg)


def make_digest(sections, subject, cfg):
    prompt = DIGEST_PROMPT.format(subject=subject,
                                  sections="\n\n---\n\n".join(sections))
    return run_claude(prompt, cfg)


def fmt_duration(seconds):
    if seconds is None:
        return "?"
    m, s = divmod(seconds, 60)
    return f"{m}:{s:02d} min"


def write_report(sections, cfg, today, subject):
    report_dir = Path(cfg["vault_path"]) / cfg["report_dir"] / subject
    report_dir.mkdir(parents=True, exist_ok=True)
    path = report_dir / f"{today:%Y-%m-%d} {subject} Brief.md"

    body = "\n\n---\n\n".join(sections)
    if path.exists():  # same-day rerun: append newly found videos (no digest)
        path.write_text(path.read_text() + "\n\n---\n\n" + body + "\n")
        return path, False
    digest = make_digest(sections, subject, cfg) if len(sections) >= 2 else None
    header = (
        f"---\ntype: youtube-brief\nsubject: {subject}\ndate: {today:%Y-%m-%d}\n---\n\n"
        f"# {subject} Brief — {today:%A, %d %B %Y}\n\n"
        f"_{len(sections)} new video(s)._\n\n"
    )
    digest_block = f"## Digest\n\n{digest}\n\n---\n\n" if digest else ""
    path.write_text(header + digest_block + body + "\n")
    return path, bool(digest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lookback", type=int, default=None,
                    help="override lookback_hours from config (for catch-up runs)")
    args = ap.parse_args()

    cfg = load_json(CONFIG_PATH, None)
    if cfg is None:
        log("FATAL: cannot read config.json")
        sys.exit(1)

    acquire_lock()
    state = load_json(STATE_PATH, {"seen": {}})
    now = datetime.now(timezone.utc)
    lookback = args.lookback or cfg["lookback_hours"]
    cutoff = now - timedelta(hours=lookback)

    for subject in cfg["subjects"]:
        sname = subject["name"]
        candidates = []
        for ch in subject["channels"]:
            try:
                entries = parse_entries(fetch_feed(ch["id"]), ch["name"])
            except Exception as exc:
                log(f"[{sname}] feed error for {ch['name']}: {exc}")
                continue
            fresh = [e for e in entries
                     if e["published"] >= cutoff and e["id"] not in state["seen"]]
            log(f"[{sname}] {ch['name']}: {len(entries)} in feed, {len(fresh)} new")
            candidates.extend(fresh)

        candidates.sort(key=lambda e: e["published"])

        sections = []
        for v in candidates:
            log(f"[{sname}] processing: {v['channel']} — {v['title']}")
            dur, live = video_probe(v["url"])
            if live in ("is_live", "is_upcoming", "post_live"):
                log(f"  skipped for now ({live}) — will retry next run")
                continue  # not marked seen
            if dur is not None and dur < cfg["min_duration_seconds"]:
                log(f"  skipped (short, {dur}s)")
                state["seen"][v["id"]] = now.isoformat()
                continue

            transcript = fetch_transcript(v["url"])
            if not transcript:
                age_h = (now - v["published"]).total_seconds() / 3600
                if age_h < cfg.get("transcript_defer_hours", 24):
                    log(f"  no transcript yet ({age_h:.0f}h old) — deferred to next run")
                    continue  # not marked seen
                log("  still no transcript after defer window, using description only")
                transcript = "(no transcript available — summarize from the description only)"

            summary = summarize(v, transcript, cfg)
            if summary is None:
                continue  # not marked seen -> retried tomorrow

            local_pub = v["published"].astimezone()
            sections.append(
                f"## {v['title']}\n"
                f"**{v['channel']}** · {fmt_duration(dur)} · published {local_pub:%d.%m.%Y %H:%M}\n"
                f"▶️ [Watch on YouTube]({v['url']})\n\n"
                f"{summary}"
            )
            state["seen"][v["id"]] = now.isoformat()

        if sections:
            path, with_digest = write_report(sections, cfg, datetime.now(), sname)
            log(f"[{sname}] report written: {path} ({len(sections)} videos"
                f"{', with digest' if with_digest else ''})")
        else:
            log(f"[{sname}] no new videos — no report written")

    # prune state entries older than 30 days
    limit = now - timedelta(days=30)
    state["seen"] = {k: ts for k, ts in state["seen"].items()
                     if datetime.fromisoformat(ts) >= limit}
    STATE_PATH.write_text(json.dumps(state, indent=2))


if __name__ == "__main__":
    try:
        main()
    finally:
        if LOCK_PATH.exists() and LOCK_PATH.read_text().strip() == str(os.getpid()):
            LOCK_PATH.unlink(missing_ok=True)
