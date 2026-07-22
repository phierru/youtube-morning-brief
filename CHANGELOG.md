# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

See [docs/ROADMAP.md](docs/ROADMAP.md) — next up: Apple Intelligence backend
(v1.1), bring-your-own-LLM (v1.2).

## [1.0.2] - 2026-07-20

Config robustness.

### Added
- `config.schema.json` (JSON Schema draft-07): editors validate and
  autocomplete `config.json` via its `"$schema"` reference.
- The pipeline validates config structure on startup and exits with
  actionable `FATAL: config.json invalid: …` lines instead of crashing
  mid-run on wrong-shape values.

### Fixed
- The app now reloads `config.json` when it changes on disk (hand-edits
  while the app is open are no longer invisible or overwritten).
- The dashboard's last-run status surfaces FATAL outcomes instead of
  showing the previous day's success.

## [1.0.1] - 2026-07-20

Hardening release addressing all findings of an automated code review.

### Security
- Claude is now invoked non-agentically (`--setting-sources "" 
  --strict-mcp-config --disallowedTools "*" --no-session-persistence`):
  untrusted video content can no longer reach user tools, hooks, or MCP
  servers via prompt injection.
- Channel resolver only fetches YouTube hosts over HTTPS, validates redirect
  targets, and caps response size.

### Fixed
- Seen-state is now keyed per subject — a channel listed in two subjects
  reports in both (legacy state entries still honored).
- State is checkpointed after each subject and same-day appends skip videos
  already in the note: a mid-run crash can no longer duplicate report
  sections.
- Single-instance lock uses `flock` (race-free, PID-reuse safe).
- Transcript timeouts and missing executables no longer abort the whole run;
  they skip the affected video with a log line.
- `/usr/local/bin` added to the app's manual-run PATH (Intel Macs).
- Subject names are sanitized for filesystem/YAML use and validated in the
  app (no `/`, `:`, leading dots, or line breaks).
- Config saves are failable and surfaced in the UI; a malformed config.json
  can no longer be silently overwritten with an empty one.
- `Shell.run` drains pipes concurrently and applies a timeout (no more
  potential deadlock or indefinite hangs).

### Added
- Unit test suite (`tests/`, run with `python -m unittest discover -s tests`).
- `requirements.txt` with a yt-dlp version floor.

## [1.0.0] - 2026-07-19

Initial release.

### Pipeline
- Daily YouTube monitoring via channel RSS feeds (no API key), grouped into
  subjects; one markdown brief per subject per day in an Obsidian vault or
  any markdown folder.
- Transcripts via yt-dlp captions; summaries, key takeaways, and
  product/source links via the Claude CLI; cross-video digest (top themes +
  at-a-glance) at the top of each brief.
- Robustness: seen-video dedup, Shorts filter, deferral of livestreams and
  caption-less fresh uploads, network/Claude retries, PID lockfile against
  overlapping runs.
- Scheduled by a LaunchAgent (`install_agent.sh`, label
  `com.morningbrief.daily`); missed runs execute on wake.

### Mac app (SwiftUI, macOS 14+)
- Dashboard: enable/disable the schedule, change the daily run time, Run Now
  with optional lookback and live output.
- Subjects & channels management: add a channel by pasting any YouTube URL,
  @handle, or channel ID — resolved and verified automatically.
- Settings editor for pipeline tuning; live log viewer.
- Menu bar status item with state-aware icon and quick actions.
- `build.sh` builds an ad-hoc signed Morning Brief.app into /Applications.
