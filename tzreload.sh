#!/bin/bash
# Polls for timezone changes every 5 minutes (via StartInterval in launchd).
# Reloads the brew auto-update LaunchAgent only when the timezone actually changes.

STATEFILE="$HOME/.brewauto_timezone"
PLIST="$HOME/Library/LaunchAgents/com.suryakiran.brewauto.plist"
LOG="$HOME/IdeaProjects/BrewAutomation/system_stdout.log"

current_tz=$(readlink /private/etc/localtime | sed 's|.*/zoneinfo/||')
last_tz=$(cat "$STATEFILE" 2>/dev/null)

if [ "$current_tz" != "$last_tz" ]; then
    echo "$current_tz" > "$STATEFILE"
    if [ -n "$last_tz" ]; then
        # Only reload if we had a previous known timezone (skip first run)
        launchctl unload "$PLIST" 2>/dev/null || true
        launchctl load "$PLIST"
        echo "[$(date)] Timezone changed: $last_tz → $current_tz — reloaded $PLIST" >> "$LOG"
    else
        echo "[$(date)] Timezone initialized: $current_tz" >> "$LOG"
    fi
fi
