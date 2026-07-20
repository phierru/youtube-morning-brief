# Code Review 1.0.0

## Review findings

1. **High — Untrusted video content reaches an agentic CLI with tools enabled.** Titles, descriptions, and transcripts are inserted directly into a prompt, then passed to `claude -p` without disabling tools, settings, hooks, plugins, or session persistence. A malicious transcript could prompt-inject Claude into reading local files or invoking tools, depending on the user’s permission configuration. The installed CLI also states that `-p` skips workspace trust. See [`morning_brief.py:212`](morning_brief.py#L212) and [`morning_brief.py:232`](morning_brief.py#L232). Use a non-agentic API or invoke Claude with at least `--tools ""`, `--safe-mode`, and `--no-session-persistence`.

2. **High — Global deduplication drops videos from later subjects.** Seen state is keyed only by video ID. If a channel appears under two subjects, processing the first subject marks its videos seen and the second subject silently omits them. See [`morning_brief.py:292`](morning_brief.py#L292), [`morning_brief.py:301`](morning_brief.py#L301), and [`morning_brief.py:340`](morning_brief.py#L340). Key state by stable subject ID plus video ID.

3. **High — A late failure can duplicate already-written reports.** Reports are written one subject at a time, but state is persisted only after all subjects complete. If a later subject crashes, earlier reports remain while their seen state is lost; the next run appends those videos again. Same-day writes explicitly append without checking video IDs. See [`morning_brief.py:255`](morning_brief.py#L255), [`morning_brief.py:342`](morning_brief.py#L342), and [`morning_brief.py:349`](morning_brief.py#L349). Make report generation idempotent and checkpoint state atomically per subject.

4. **Medium — The single-instance lock has a race condition.** Two processes can both observe no lock before either writes it, allowing overlapping runs despite the documented guarantee. PID reuse can also make a stale lock look active. See [`morning_brief.py:94`](morning_brief.py#L94). Hold an OS advisory lock such as `flock` for the process lifetime.

5. **Medium — Expected subprocess failures terminate the entire run.** `fetch_transcript` does not catch its 300-second timeout, and `run_claude` does not catch `FileNotFoundError` or other `OSError`s. Targeted probes confirmed both exceptions escape. This is particularly relevant on Intel Macs because the app’s manual-run `PATH` omits `/usr/local/bin`. See [`morning_brief.py:183`](morning_brief.py#L183), [`morning_brief.py:212`](morning_brief.py#L212), and [`PipelineRunner.swift:35`](MorningBriefApp/Sources/MorningBrief/Services/PipelineRunner.swift#L35). Handle timeouts and executable failures per video and report actionable diagnostics.

6. **Medium — Subject names are used as filesystem paths and YAML without validation.** The app accepts names such as `..`, newlines, and path separators. `..` writes the report one directory above `report_dir`; newlines can corrupt or inject frontmatter. See [`ConfigStore.swift:77`](MorningBriefApp/Sources/MorningBrief/Models/ConfigStore.swift#L77) and [`morning_brief.py:255`](morning_brief.py#L255). Separate display names from sanitized directory slugs and verify resolved paths remain under the configured base.

7. **Medium — Configuration writes can fail while the UI reports success.** `save()` records an error but returns nothing; `addSubject` and `addChannel` still return `true`, and Settings displays “Saved” immediately. Loading a valid JSON value with the wrong shape also silently becomes an empty configuration that can later overwrite existing data. See [`ConfigStore.swift:26`](MorningBriefApp/Sources/MorningBrief/Models/ConfigStore.swift#L26), [`ConfigStore.swift:43`](MorningBriefApp/Sources/MorningBrief/Models/ConfigStore.swift#L43), and [`SettingsView.swift:43`](MorningBriefApp/Sources/MorningBrief/Views/SettingsView.swift#L43). Make persistence throwing or failable and validate with a typed `Codable` schema before replacing in-memory state.

8. **Low — Channel resolution permits arbitrary HTTP requests.** Any supplied `http://` or `https://` URL is fetched, redirects are followed, and the full response is loaded into memory. This creates a local SSRF/GET-CSRF and memory-exhaustion surface. See [`ChannelResolver.swift:53`](MorningBriefApp/Sources/MorningBrief/Services/ChannelResolver.swift#L53) and [`ChannelResolver.swift:89`](MorningBriefApp/Sources/MorningBrief/Services/ChannelResolver.swift#L89). Restrict hosts to known YouTube domains, require HTTPS, validate redirects, and cap response size.

9. **Low — Synchronous process handling can freeze or deadlock the app.** `Shell.run` waits for process exit before draining stdout and stderr pipes. A sufficiently verbose child can fill a pipe and block forever; all current calls also occur on the main actor. See [`Paths.swift:33`](MorningBriefApp/Sources/MorningBrief/Services/Paths.swift#L33) and [`LaunchAgentManager.swift:22`](MorningBriefApp/Sources/MorningBrief/Services/LaunchAgentManager.swift#L22). Drain output concurrently, impose a timeout, and execute off the UI actor.

## Verification

- Swift debug build: passed.
- Python, shell, plist, and example-JSON syntax: passed.
- Targeted timeout and missing-executable probes: confirmed the uncaught exceptions.
- Swift tests: none found.
- Python tests: 0 discovered.
- Dependency versions are not pinned; `yt-dlp` is installed directly from the latest release via README instructions.
- The worktree was clean before this review file was added; no source files were modified.
