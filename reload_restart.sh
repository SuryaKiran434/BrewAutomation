#!/bin/bash
PLIST_NAME="com.suryakiran.restart.plist"
SOURCE_PATH="$HOME/BrewAutomation/$PLIST_NAME"
DEST_PATH="/Library/LaunchDaemons/$PLIST_NAME"

echo "Syncing and restarting Restart Automation..."

# Enforce .env permissions (should be readable only by owner)
if [ -f "$HOME/BrewAutomation/.env" ]; then
    chmod 600 "$HOME/BrewAutomation/.env" || {
        echo "ERROR: Failed to set .env permissions. Installation aborted."
        exit 1
    }
    echo "[OK] .env permissions: 600 (owner-only)"
fi

# Unload the old one
sudo launchctl unload "$DEST_PATH" 2>/dev/null || true

# Substitute __HOME__ placeholder with the actual home directory and install
if ! sed "s|__HOME__|$HOME|g" "$SOURCE_PATH" | sudo tee "$DEST_PATH" > /dev/null; then
    echo "ERROR: Failed to install plist."
    exit 1
fi

if ! sudo chown root:wheel "$DEST_PATH"; then
    echo "ERROR: Failed to set plist ownership."
    exit 1
fi

if ! sudo chmod 644 "$DEST_PATH"; then
    echo "ERROR: Failed to set plist permissions."
    exit 1
fi

# Load the new version
if ! sudo launchctl load "$DEST_PATH"; then
    echo "ERROR: Failed to load LaunchDaemon. Check plist syntax:"
    sudo plutil -lint "$DEST_PATH"
    exit 1
fi

echo "✓ LaunchDaemon installed and loaded"
echo "Done! Restart schedule is now active (Tue & Thu at 9:00 AM)."

