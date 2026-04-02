#!/bin/bash
# Reloads the brew auto-update LaunchAgent when the system timezone changes.
# Triggered by com.suryakiran.tzwatch via WatchPaths on /private/etc/localtime.

PLIST="$HOME/Library/LaunchAgents/com.suryakiran.brewauto.plist"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "[$(date)] Timezone changed — reloaded $PLIST" >> "$HOME/IdeaProjects/BrewAutomation/system_stdout.log"
