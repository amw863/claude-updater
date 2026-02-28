#!/usr/bin/env bash
# install-launchd.sh — Install macOS launchd scheduled task for claude-updater
set -euo pipefail

PLIST_LABEL="com.wangbang.claude-updater"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATER_SCRIPT="$SCRIPT_DIR/claude-updater.sh"
LOG_DIR="$HOME/.claude/logs"

# Ensure updater script exists and is executable
if [[ ! -f "$UPDATER_SCRIPT" ]]; then
    echo "Error: $UPDATER_SCRIPT not found" >&2
    exit 1
fi
chmod +x "$UPDATER_SCRIPT"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Ensure LaunchAgents directory exists
mkdir -p "$HOME/Library/LaunchAgents"

# Unload existing job if present
if launchctl list | grep -q "$PLIST_LABEL" 2>/dev/null; then
    echo "Unloading existing job..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

# Generate plist
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$UPDATER_SCRIPT</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>10</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/claude-updater-launchd.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/claude-updater-launchd.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

echo "Plist written to $PLIST_PATH"

# Load the job
launchctl load "$PLIST_PATH"
echo "Launchd job loaded: $PLIST_LABEL"
echo "Scheduled to run daily at 10:00"
echo ""
echo "Verify with: launchctl list | grep claude-updater"
echo "Run now:     launchctl start $PLIST_LABEL"
