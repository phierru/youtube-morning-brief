# YouTube Morning Brief

Every morning at 07:00 this pipeline checks YouTube channels for new videos,
pulls their transcripts, summarizes each with Claude, and writes one markdown
report **per subject** into the Obsidian vault at
`Claude/YouTube Briefs/<Subject>/YYYY-MM-DD <Subject> Brief.md`.

Subjects (each with its own channel list) are defined in `config.json` —
currently **AI & Tech** and **Geopolitics**.

## How it works

1. **New-video detection** — each channel's public RSS feed
   (`youtube.com/feeds/videos.xml?channel_id=…`), no API key needed.
2. **Transcripts** — `yt-dlp` downloads English (auto-)captions; VTT is
   flattened to plain text.
3. **Summaries** — the `claude` CLI produces per-video summary, key takeaways,
   and products/tools mentioned (links taken from the video description).
4. **Report** — one note per subject per day in the vault, opening with a
   **Digest** (top themes across all videos + at-a-glance list, generated when
   a brief has 2+ videos), followed by the full per-video sections. Shorts
   (< 2 min) are skipped. Live/upcoming streams and fresh uploads whose
   captions aren't ready yet are deferred to the next run (after
   `transcript_defer_hours` without captions, summarized from the description
   instead). Videos already reported are tracked in `state.json` (pruned
   after 30 days).

## Files

- `morning_brief.py` — the whole pipeline
- `config.json` — channels, vault path, lookback window, model
- `state.json` — seen-video state (auto-managed)
- `logs/brief.log` — run log
- LaunchAgent: `~/Library/LaunchAgents/com.francescolardieri.youtube-morning-brief.plist`

## Common operations

Add/remove a channel or subject: edit `config.json` (subjects → channels).
Get a channel ID from its page source (`"externalId":"UC…"`) or ask Claude.

Run manually:

```sh
~/Projects/YouTubeMorningBrief/.venv/bin/python ~/Projects/YouTubeMorningBrief/morning_brief.py
```

Change schedule: edit the plist's `StartCalendarInterval`, then

```sh
launchctl bootout gui/$(id -u)/com.francescolardieri.youtube-morning-brief
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.francescolardieri.youtube-morning-brief.plist
```

Keep `yt-dlp` fresh (YouTube changes break old versions):

```sh
~/Projects/YouTubeMorningBrief/.venv/bin/pip install -U yt-dlp
```
