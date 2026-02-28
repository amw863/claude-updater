#!/usr/bin/env bash
# uninstall-launchd.sh — Remove macOS launchd scheduled task for claude-updater
set -euo pipefail

PLIST_LABEL="com.wangbang.claude-updater"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# Unload the job
if launchctl list | grep -q "$PLIST_LABEL" 2>/dev/null; then
    echo "Unloading launchd job..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    echo "Job unloaded"
else
    echo "Job not currently loaded"
fi

# Remove plist file
if [[ -f "$PLIST_PATH" ]]; then
    rm "$PLIST_PATH"
    echo "Removed $PLIST_PATH"
else
    echo "Plist file not found (already removed)"
fi

echo ""
echo "Uninstall complete. Log files preserved at ~/.claude/logs/"
