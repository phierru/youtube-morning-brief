# Roadmap

## v1.1 — Apple Intelligence backend

Run Morning Brief without a Claude subscription: use Apple's on-device
Foundation Models (macOS 26+, Apple Silicon) as the summarization engine.

- New `summarizer` setting in `config.json`: `"claude"` (default) or
  `"apple"`, with `"auto"` falling back to Apple Intelligence when the
  `claude` CLI is not installed.
- Small Swift helper CLI (`afm-summarize`) bundled with the app build that
  reads a prompt on stdin and prints the model response, so the Python
  pipeline can call it exactly like the `claude` CLI.
- Settings UI: backend picker with availability detection (macOS version,
  Apple Intelligence enabled).
- Honest expectations documented: on-device model is small — summaries will
  be terser than Claude's; digest quality may vary with many videos.

## v1.2 — Bring your own LLM

Support any OpenAI-compatible endpoint, local or remote: Ollama, LM Studio,
vLLM, OpenRouter, llama.cpp server, corporate gateways.

- `summarizer: "openai"` with `endpoint`, `model`, and `api_key_env` (key is
  read from an environment variable, never stored in config).
- Works fully offline with a local server; no vendor lock-in.
- Settings UI: endpoint/model fields with a "Test connection" button.
- Per-call timeout and retry tuning for slow local models.

## Under consideration (no version)

- Per-subject schedules (e.g. tech at 07:00, geopolitics at 12:00)
- Additional delivery channels (e-mail, WhatsApp/messaging bridges)
- Weekly rollup note per subject
- Homebrew formula / prebuilt app releases
