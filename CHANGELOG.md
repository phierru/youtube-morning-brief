# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

See [docs/ROADMAP.md](docs/ROADMAP.md) — next up: Apple Intelligence backend
(v1.1), bring-your-own-LLM (v1.2).

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
