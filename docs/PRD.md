# Morning Brief — Product Requirements Document

**Status:** Draft v1 · 2026-07-18
**Owner:** Francesco Lardieri

## 1. Background

Morning Brief is a personal automation that monitors YouTube channels grouped
into subjects (currently *AI & Tech* and *Geopolitics*), and every morning at
07:00 produces one markdown briefing per subject in an Obsidian vault. Each
brief opens with a cross-video digest (top themes + at-a-glance list) followed
by per-video sections: summary, key takeaways, and products/sources with links,
plus a link to the original video.

The existing pipeline (Python, this repo) works end-to-end:

- **Detection** — public RSS feeds per channel, no API key.
- **Transcripts** — `yt-dlp` caption download, VTT flattened to text.
- **Summaries** — `claude` CLI (Sonnet), one call per video + one digest call.
- **Delivery** — daily note per subject in
  `<vault>/Claude/YouTube Briefs/<Subject>/`.
- **Scheduling** — LaunchAgent `com.francescolardieri.youtube-morning-brief`,
  daily 07:00.
- Robustness: dedup via `state.json`, shorts skipped, live/caption-less videos
  deferred, network + Claude retries.

All management today happens by editing `config.json` and the LaunchAgent
plist by hand (or asking Claude). This PRD covers a native macOS app that
makes the system self-service.

## 2. Goal

A minimalist, native **SwiftUI macOS app** ("Morning Brief") that lets the
user manage the pipeline without touching config files or `launchctl`:

1. Start/stop (enable/disable) the scheduled agent.
2. Change the daily run time.
3. Add/remove channels within a subject.
4. Add/remove subjects (briefs).
5. Trigger a manual run and watch it live.
6. Edit tuning settings.

The app is launched **on demand** and shows a **menu bar icon** while running;
quitting it leaves nothing behind. It is a frontend only — the Python
pipeline, `config.json`, and the LaunchAgent remain the single sources of
truth, so everything the app does can still be done by hand.

## 3. Non-goals

- No rewrite of the pipeline in Swift.
- No iOS/web version, no LAN access, no auth.
- No browsing/rendering of generated briefs (Obsidian does that).
- No per-subject schedules (one global run time).
- No App Store distribution, notarization, or sandboxing.

## 4. Users

Single user: Francesco, technical, runs the pipeline on his own Mac.

## 5. Functional requirements

### 5.1 Menu bar
- Icon visible while the app runs; reflects state (enabled / disabled /
  run in progress).
- Menu: status line (next scheduled run, last run result), Run Now,
  Open Morning Brief, Quit.

### 5.2 Dashboard
- Toggle **Enabled** ⇄ **Disabled** → `launchctl bootstrap` / `bootout` of the
  LaunchAgent.
- Time picker for the daily run → rewrites `StartCalendarInterval` in the
  plist and reloads the agent.
- Shows next run time, last run time and outcome (parsed from
  `logs/brief.log`), and per-subject video count of the last run.
- **Run Now** button with optional "look back N hours" override
  (maps to `--lookback`).

### 5.3 Subjects & channels
- List subjects; add (name only) and remove (with confirmation; vault notes
  are never touched).
- Per subject: list channels (name + ID), remove channel, add channel by
  pasting a YouTube URL or @handle. The app resolves the channel ID
  (`externalId` scrape), verifies the RSS feed, and shows the resolved channel
  name for confirmation before saving.
- All writes go to `config.json` atomically, preserving unknown keys.

### 5.4 Settings
- Editable: `lookback_hours`, `min_duration_seconds`,
  `transcript_defer_hours`, `max_transcript_chars`, `claude_model`.
- Validation (numeric ranges, model name non-empty); Save/Revert.

### 5.5 Log viewer
- Live-tail of `logs/brief.log`; a manual Run Now streams its output into the
  same view.
- Indicates whether a run is currently in progress.

### 5.6 Pipeline: run lock
- `morning_brief.py` acquires a lockfile so a scheduled run and a manual run
  can never overlap; the app surfaces "run in progress" from the lock.

## 6. Technical approach

- Swift Package (SPM) executable target, SwiftUI, `MenuBarExtra` +
  `WindowGroup`; macOS 14+.
- No Xcode project; `build.sh` produces `Morning Brief.app` (ad-hoc signed)
  and installs to `/Applications`.
- Shell-outs via `Process`: `launchctl`, the pipeline venv Python.
- Channel resolution via `URLSession` (page scrape + RSS verification).
- Config I/O via `Codable` with tolerant decoding.

Repo layout: pipeline at root, app under `MorningBriefApp/`, docs in `docs/`.

## 7. Milestones

1. **M1 — Pipeline lock + app scaffold:** lockfile in Python; SPM package
   builds, empty window + menu bar icon, build.sh installs to /Applications.
2. **M2 — Control:** dashboard toggle, schedule picker, Run Now + live output.
3. **M3 — Content management:** subjects & channels CRUD with resolution.
4. **M4 — Polish:** settings editor, log viewer, status parsing, app icon.

## 8. Acceptance (v1 done when)

- Every operation listed in §2 can be performed from the app alone, verified
  against the real LaunchAgent and config.
- A full scheduled run executes correctly with the app closed.
- Killing the app mid-manual-run leaves the pipeline in a consistent state
  (lock released or stale-lock detected on next run).
