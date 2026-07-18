#!/bin/zsh
# Install (or reinstall) the Morning Brief LaunchAgent for the current
# checkout location and user. Usage: ./install_agent.sh [HOUR [MINUTE]]
set -euo pipefail
cd "$(dirname "$0")"

HOUR="${1:-7}"
MINUTE="${2:-0}"
LABEL="com.morningbrief.daily"
PROJECT_DIR="$(pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -x "$PROJECT_DIR/.venv/bin/python" ]]; then
    echo "error: no venv found — run: python3 -m venv .venv && .venv/bin/pip install yt-dlp" >&2
    exit 1
fi
mkdir -p "$PROJECT_DIR/logs"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PROJECT_DIR/.venv/bin/python</string>
        <string>$PROJECT_DIR/morning_brief.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>$MINUTE</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$PROJECT_DIR/logs/brief.log</string>
    <key>StandardErrorPath</key>
    <string>$PROJECT_DIR/logs/brief.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed and loaded $LABEL (daily at $(printf '%02d:%02d' "$HOUR" "$MINUTE"))"
