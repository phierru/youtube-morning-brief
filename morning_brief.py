#!/usr/bin/env python3
"""YouTube Morning Brief.

Fetches new videos from configured YouTube channels via their RSS feeds,
pulls transcripts with yt-dlp, summarizes each video with the Claude CLI,
and writes a daily markdown report per subject into a markdown folder.

Run daily by a LaunchAgent (com.morningbrief.daily).
"""

import argparse
import fcntl
import json
import os
import re
import shutil
import signal
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

# The prompt content below includes untrusted third-party text (titles,
# descriptions, transcripts). These flags make the CLI non-agentic: no user
# settings/hooks, no MCP servers, no tools, no persisted session.
CLAUDE_SANDBOX_FLAGS = [
    "--setting-sources", "",
    "--strict-mcp-config",
    "--disallowedTools", "*",
    "--no-session-persistence",
]

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

_lock_handle = None  # kept open for the process lifetime (flock)


def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


def acquire_lock():
    """Single-instance guard via flock — race-free, released automatically on
    process exit. The file holds the PID so external tools (the Mac app) can
    display run-in-progress state."""
    global _lock_handle
    handle = open(LOCK_PATH, "a+")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()  # do NOT touch the holder's lockfile
        log("another run is in progress — exiting")
        sys.exit(0)
    handle.seek(0)
    handle.truncate()
    handle.write(str(os.getpid()))
    handle.flush()
    _lock_handle = handle


def release_lock():
    if _lock_handle is not None:
        LOCK_PATH.unlink(missing_ok=True)  # safe: we hold the flock
        _lock_handle.close()


def on_interrupt(signum, _frame):
    """Stop promptly on SIGTERM/SIGINT (the app's Stop button, or Ctrl-C).

    Raising unwinds through the blocking subprocess.run, which kills the
    in-flight child (claude/yt-dlp) on its way out, and the finally in
    __main__ releases the lock. The current subject writes nothing, so the
    next run simply redoes it — videos are only marked seen once summarized.
    """
    log(f"interrupted (signal {signum}) — stopping, no report written")
    raise SystemExit(130)


def subject_slug(name):
    """Filesystem-safe version of a subject name (used for the folder and
    filename). Display name is used everywhere else."""
    slug = re.sub(r"[\\/:\0\n\r\t]+", "-", name).strip(" .")
    return slug or "untitled"


def validate_config(cfg):
    """Structural validation mirroring config.schema.json.
    Returns a list of human-readable problems; empty when valid."""
    if not isinstance(cfg, dict):
        return ["config root must be a JSON object"]
    errors = []
    subs = cfg.get("subjects")
    if not isinstance(subs, list):
        errors.append('"subjects" must be a list')
    else:
        for i, s in enumerate(subs):
            if (not isinstance(s, dict) or not isinstance(s.get("name"), str)
                    or not s["name"].strip()):
                errors.append(f'subjects[{i}] needs a non-empty string "name"')
                continue
            chans = s.get("channels")
            if not isinstance(chans, list):
                errors.append(f'subject "{s["name"]}": "channels" must be a list')
                continue
            for j, c in enumerate(chans):
                if (not isinstance(c, dict) or not isinstance(c.get("name"), str)
                        or not isinstance(c.get("id"), str)
                        or not re.fullmatch(r"UC[0-9A-Za-z_-]{22}", c["id"])):
                    errors.append(f'subject "{s["name"]}" channel #{j + 1}: '
                                  'needs "name" and a valid "id" (UC…, 24 chars)')
    for key in ("vault_path", "report_dir"):
        if not isinstance(cfg.get(key), str) or not cfg[key]:
            errors.append(f'"{key}" must be a non-empty string')
    bounds = (("lookback_hours", 1, 336, False),
              ("min_duration_seconds", 0, 3600, False),
              ("max_transcript_chars", 1000, 500_000, False),
              ("transcript_defer_hours", 0, 168, True))
    for key, lo, hi, optional in bounds:
        v = cfg.get(key)
        if v is None and optional:
            continue
        if not isinstance(v, int) or isinstance(v, bool) or not lo <= v <= hi:
            errors.append(f'"{key}" must be an integer between {lo} and {hi}')
    if not isinstance(cfg.get("claude_model", "sonnet"), str):
        errors.append('"claude_model" must be a string')
    return errors


def load_json(path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def save_state(state):
    tmp = STATE_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(STATE_PATH)


def seen_key(subject_name, video_id):
    return f"{subject_name}|{video_id}"


def is_seen(state, subject_name, video_id):
    # legacy entries (pre-v1.0.1) were keyed by bare video ID
    return (seen_key(subject_name, video_id) in state["seen"]
            or video_id in state["seen"])


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
    except (subprocess.TimeoutExpired, ValueError, OSError) as exc:
        log(f"  probe failed ({type(exc).__name__}) — continuing without metadata")
        return None, None


def fetch_transcript(url):
    """Download English (auto-)subtitles with yt-dlp and return plain text.
    Returns None on any failure — the caller decides whether to defer."""
    with tempfile.TemporaryDirectory() as tmp:
        try:
            subprocess.run(
                [str(YTDLP), "--skip-download", "--no-warnings",
                 "--write-subs", "--write-auto-subs",
                 "--sub-langs", "en.*,en-orig,en", "--sub-format", "vtt",
                 "-o", "sub", url],
                capture_output=True, text=True, timeout=300, cwd=tmp,
            )
        except subprocess.TimeoutExpired:
            log("  transcript download timed out")
            return None
        except OSError as exc:
            log(f"  transcript download failed: {exc}")
            return None
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
                [CLAUDE, "-p", "--model", cfg.get("claude_model", "sonnet"),
                 *CLAUDE_SANDBOX_FLAGS],
                input=prompt, capture_output=True, text=True, timeout=600,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
            # the CLI reports failures on stdout and leaves stderr empty, so
            # fall back to it — otherwise usage limits, auth and model errors
            # all get logged as a bare "no output".
            err = (r.stderr.strip() or r.stdout.strip()
                   or f"exit {r.returncode}, no output")[:300]
        except subprocess.TimeoutExpired:
            err = "timeout"
        except OSError as exc:
            err = f"cannot execute {CLAUDE}: {exc}"
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


def filter_already_written(sections, existing_text):
    """Drop sections whose video already appears in the note — makes same-day
    appends idempotent even after a mid-run crash lost seen-state."""
    return [s for s in sections if f"watch?v={s['id']}" not in existing_text]


def write_report(sections, cfg, today, subject):
    """sections: list of {"id": video_id, "text": markdown}."""
    slug = subject_slug(subject)
    report_dir = Path(cfg["vault_path"]) / cfg["report_dir"] / slug
    report_dir.mkdir(parents=True, exist_ok=True)
    path = report_dir / f"{today:%Y-%m-%d} {slug} Brief.md"

    if path.exists():  # same-day rerun: append newly found videos (no digest)
        existing = path.read_text()
        sections = filter_already_written(sections, existing)
        if not sections:
            return path, False, 0
        body = "\n\n---\n\n".join(s["text"] for s in sections)
        path.write_text(existing + "\n\n---\n\n" + body + "\n")
        return path, False, len(sections)

    texts = [s["text"] for s in sections]
    digest = make_digest(texts, subject, cfg) if len(sections) >= 2 else None
    safe_subject = subject.replace("\n", " ").replace('"', "'")
    header = (
        f'---\ntype: youtube-brief\nsubject: "{safe_subject}"\ndate: {today:%Y-%m-%d}\n---\n\n'
        f"# {subject} Brief — {today:%A, %d %B %Y}\n\n"
        f"_{len(sections)} new video(s)._\n\n"
    )
    digest_block = f"## Digest\n\n{digest}\n\n---\n\n" if digest else ""
    path.write_text(header + digest_block + "\n\n---\n\n".join(texts) + "\n")
    return path, bool(digest), len(sections)


def process_subject(subject, cfg, state, now, cutoff):
    sname = subject["name"]
    candidates = []
    for ch in subject["channels"]:
        try:
            entries = parse_entries(fetch_feed(ch["id"]), ch["name"])
        except Exception as exc:
            log(f"[{sname}] feed error for {ch['name']}: {exc}")
            continue
        fresh = [e for e in entries
                 if e["published"] >= cutoff and not is_seen(state, sname, e["id"])]
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
            state["seen"][seen_key(sname, v["id"])] = now.isoformat()
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
        sections.append({
            "id": v["id"],
            "text": (
                f"## {v['title']}\n"
                f"**{v['channel']}** · {fmt_duration(dur)} · published {local_pub:%d.%m.%Y %H:%M}\n"
                f"▶️ [Watch on YouTube]({v['url']})\n\n"
                f"{summary}"
            ),
        })
        state["seen"][seen_key(sname, v["id"])] = now.isoformat()

    if sections:
        path, with_digest, written = write_report(sections, cfg, datetime.now(), sname)
        log(f"[{sname}] report written: {path} ({written} videos"
            f"{', with digest' if with_digest else ''})")
    else:
        log(f"[{sname}] no new videos — no report written")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lookback", type=int, default=None,
                    help="override lookback_hours from config (for catch-up runs)")
    args = ap.parse_args()

    cfg = load_json(CONFIG_PATH, None)
    if cfg is None:
        log("FATAL: cannot read config.json (missing or not valid JSON)")
        sys.exit(1)
    problems = validate_config(cfg)
    if problems:
        for p in problems:
            log(f"FATAL: config.json invalid: {p}")
        sys.exit(1)

    signal.signal(signal.SIGTERM, on_interrupt)
    signal.signal(signal.SIGINT, on_interrupt)

    acquire_lock()
    state = load_json(STATE_PATH, {"seen": {}})
    now = datetime.now(timezone.utc)
    lookback = args.lookback or cfg["lookback_hours"]
    cutoff = now - timedelta(hours=lookback)

    for subject in cfg["subjects"]:
        process_subject(subject, cfg, state, now, cutoff)
        save_state(state)  # checkpoint: a later crash can't lose this subject

    # prune state entries older than 30 days
    limit = now - timedelta(days=30)
    state["seen"] = {k: ts for k, ts in state["seen"].items()
                     if datetime.fromisoformat(ts) >= limit}
    save_state(state)


if __name__ == "__main__":
    try:
        main()
    finally:
        release_lock()
