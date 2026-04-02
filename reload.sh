#!/bin/bash
PLIST_NAME="com.suryakiran.brewauto.plist"
SOURCE_PATH="$HOME/IdeaProjects/BrewAutomation/$PLIST_NAME"
DEST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo "Syncing and restarting Brew Automation..."

# Enforce .env permissions (should be readable only by owner)
if [ -f "$HOME/IdeaProjects/BrewAutomation/.env" ]; then
    chmod 600 "$HOME/IdeaProjects/BrewAutomation/.env" || {
        echo "ERROR: Failed to set .env permissions. Installation aborted."
        exit 1
    }
    echo "[OK] .env permissions: 600 (owner-only)"
fi

# Unload the old one
launchctl unload "$DEST_PATH" 2>/dev/null || true

# Substitute __HOME__ placeholder with the actual home directory and install
if ! sed "s|__HOME__|$HOME|g" "$SOURCE_PATH" > "$DEST_PATH"; then
    echo "ERROR: Failed to install plist. Check file permissions."
    exit 1
fi

# Load the new version
if ! launchctl load "$DEST_PATH"; then
    echo "ERROR: Failed to load LaunchAgent. Check plist syntax:"
    plutil -lint "$DEST_PATH"
    exit 1
fi

echo "✓ LaunchAgent installed and loaded"
echo "Done! The new schedule and logic are now active."

