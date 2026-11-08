#!/bin/sh
# Runs HeadPointer as its own .app: macOS asks the launching app (the terminal) for Motion access
# otherwise, and kills the process because terminals have no motion usage string.
set -e
cd "$(dirname "$0")"
swift build -c release
app=.build/HeadPointer.app
mkdir -p "$app/Contents/MacOS"
cp .build/release/HeadPointer "$app/Contents/MacOS/"
sed 's#<dict>#<dict><key>CFBundleExecutable</key><string>HeadPointer</string><key>LSUIElement</key><true/>#' \
    Sources/HeadPointer/Info.plist > "$app/Contents/Info.plist"
# Requirement pinned to the bundle id, so the Accessibility grant survives rebuilds (ad-hoc hash changes each build).
codesign --force --sign - --identifier local.headpointer.mac -r='designated => identifier "local.headpointer.mac"' "$app"
# Logs show in this terminal; Ctrl-C stops it.
trap 'pkill -f "$app/Contents/MacOS/HeadPointer"' INT TERM
out=$(tty) || out=/dev/null
open -W -n --stdout "$out" --stderr "$out" "$app" --args "$@"
