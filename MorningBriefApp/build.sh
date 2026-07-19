#!/bin/zsh
# Build Morning Brief.app from the Swift package and install to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "error: Xcode toolchain not found — install Xcode (App Store) or Command Line Tools" >&2
    exit 1
fi

swift build -c release

APP="Morning Brief.app"
STAGE="build/$APP"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/MorningBrief "$STAGE/Contents/MacOS/"
cp Info.plist "$STAGE/Contents/"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$STAGE/Contents/Resources/"
codesign --force -s - "$STAGE"

rm -rf "/Applications/$APP"
cp -R "$STAGE" /Applications/
echo "Installed /Applications/$APP"
