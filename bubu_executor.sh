#!/bin/bash
set -e

# ============================================================================
# BrewAutomation Executor: Updates brew, uv, and Python packages
# ============================================================================

# Parse flags
MANUAL=false
RATE_LIMIT_MINUTES=5
for arg in "$@"; do
    [ "$arg" = "--manual" ] && MANUAL=true
done

# ============================================================================
# SETUP: Paths, Config, Validation
# ============================================================================

BASE_DIR="$HOME/IdeaProjects/BrewAutomation"
TODAY=$(date "+%Y-%m-%d")
TIMESTAMP=$(date)

# Log file selection based on run type
if [ "$MANUAL" = true ]; then
    LOG_FILE="$BASE_DIR/brew_update_manual.log"
    ERROR_LOG="$BASE_DIR/error_manual.log"
    SKIP_LOG=""
    EMAIL_SUBJECT_SUCCESS="Brew Update Manual Run Complete — $TODAY"
    EMAIL_SUBJECT_FAIL="Brew Update Manual Run FAILED — $TODAY"
else
    LOG_FILE="$BASE_DIR/brew_update.log"
    ERROR_LOG="$BASE_DIR/error.log"
    SKIP_LOG="$BASE_DIR/skips.log"
    EMAIL_SUBJECT_SUCCESS="Brew Update Complete — $TODAY"
    EMAIL_SUBJECT_FAIL="Brew Update FAILED — $TODAY"
fi

LOCK_FILE="$BASE_DIR/brew_update.lock"
LOCK_DIR="${LOCK_FILE}.d"
LOCK_TIMEOUT=3600  # 1 hour

# Initialize logging
mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$ERROR_LOG"
chmod 600 "$LOG_FILE" "$ERROR_LOG"
if [ -n "$SKIP_LOG" ]; then
    touch "$SKIP_LOG"
    chmod 600 "$SKIP_LOG"
fi

# ============================================================================
# CONFIGURATION: Parse .env safely (don't expose all env vars)
# ============================================================================

BREW=""
UV=""
SENDER_EMAIL=""
SENDER_APP_PASSWORD=""
RECIPIENT_EMAIL=""

if [ -f "$BASE_DIR/.env" ]; then
    # Parse only needed variables to avoid exposing credentials to all children
    BREW=$(grep "^BREW_PATH=" "$BASE_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    UV=$(grep "^UV_PATH=" "$BASE_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    SENDER_EMAIL=$(grep "^SENDER_EMAIL=" "$BASE_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    SENDER_APP_PASSWORD=$(grep "^SENDER_APP_PASSWORD=" "$BASE_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    RECIPIENT_EMAIL=$(grep "^RECIPIENT_EMAIL=" "$BASE_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
fi

# Apply defaults if not in .env
BREW="${BREW:-/opt/homebrew/bin/brew}"
UV="${UV:-/opt/homebrew/bin/uv}"

# ============================================================================
# VALIDATION: Check tools and Python early (before setting up traps/locking)
# ============================================================================

validate_tools() {
    if [ ! -x "$BREW" ]; then
        echo "[$(date)] ERROR: brew not found at '$BREW'" | tee -a "$ERROR_LOG" >&2
        exit 1
    fi
    if [ ! -x "$UV" ]; then
        echo "[$(date)] ERROR: uv not found at '$UV'" | tee -a "$ERROR_LOG" >&2
        exit 1
    fi
}

find_python() {
    # Try pyenv first, then system python3
    local py
    if command -v pyenv &>/dev/null; then
        py=$(pyenv which python 2>/dev/null || true)
        if [ -n "$py" ] && [ -x "$py" ]; then
            echo "$py"
            return 0
        fi
    fi
    if command -v python3 &>/dev/null; then
        echo "$(command -v python3)"
        return 0
    fi
    return 1
}

validate_tools
PYTHON_PATH=$(find_python || true)

# ============================================================================
# HTML EMAIL GENERATION: Styled templates for success/failure
# ============================================================================

generate_upgrade_summary() {
    local temp_file="$1"

    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        echo "<div style='color: #999; font-style: italic; padding: 15px; text-align: center;'>No packages were updated.</div>"
        return
    fi

    # Extract brew/cask upgrades (lines with "->")
    local brew_upgrades=$(grep -E "[a-zA-Z0-9_-]+ [0-9].*->" "$temp_file" 2>/dev/null || true)

    if [ -z "$brew_upgrades" ]; then
        echo "<div style='color: #999; font-style: italic; padding: 15px; text-align: center;'>No packages were updated.</div>"
        return
    fi

    echo "<table style='width: 100%; border-collapse: collapse; font-size: 13px;'>"
    echo "<tr style='background: #f0f0f0;'><th style='padding: 10px; text-align: left; border-bottom: 2px solid #ddd; font-weight: 600;'>Package</th><th style='padding: 10px; text-align: left; border-bottom: 2px solid #ddd; font-weight: 600;'>Version Change</th></tr>"

    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        local field_count
        field_count=$(echo "$line" | awk '{print NF}')
        [ "$field_count" -lt 4 ] && continue
        local package old_ver new_ver
        package=$(echo "$line" | awk '{print $1}')
        old_ver=$(echo "$line" | awk '{print $2}')
        new_ver=$(echo "$line" | awk '{print $4}')
        [ -z "$old_ver" ] && continue
        [ -z "$new_ver" ] && continue
        # Escape for safe HTML embedding
        package=$(printf '%s' "$package" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g")
        old_ver=$(printf '%s' "$old_ver" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g")
        new_ver=$(printf '%s' "$new_ver" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g")

        echo "<tr style='border-bottom: 1px solid #eee;'>"
        echo "<td style='padding: 10px; font-family: monospace; font-weight: 500;'>$package</td>"
        echo "<td style='padding: 10px; color: #666; font-family: monospace;'>$old_ver → $new_ver</td>"
        echo "</tr>"
    done <<< "$brew_upgrades"

    echo "</table>"
}

generate_html_email() {
    local title="$1"
    local status="$2"
    local upgrade_summary="$3"

    cat <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #333; background: #f5f5f5; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px 20px; text-align: center; }
        .header h1 { margin: 0; font-size: 24px; font-weight: 600; }
        .header p { margin: 8px 0 0 0; font-size: 14px; opacity: 0.9; }
        .status { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; margin-top: 10px; }
        .status.success { background: #d4edda; color: #155724; }
        .status.failed { background: #f8d7da; color: #721c24; }
        .content { padding: 30px 20px; }
        .section { margin-bottom: 20px; }
        .section h2 { font-size: 16px; font-weight: 600; margin: 0 0 12px 0; color: #667eea; border-bottom: 2px solid #667eea; padding-bottom: 8px; }
        .metadata { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; font-size: 13px; background: #f9f9f9; padding: 15px; border-radius: 6px; margin-bottom: 20px; }
        .metadata-item { }
        .metadata-label { color: #666; font-weight: 500; }
        .metadata-value { color: #333; font-family: 'Monaco', 'Courier New', monospace; font-size: 12px; }
        .footer { background: #f9f9f9; padding: 15px 20px; border-top: 1px solid #eee; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>TITLE_PLACEHOLDER</h1>
            <div class="status STATUS_CLASS">STATUS_BADGE</div>
            <p>DATE_PLACEHOLDER</p>
        </div>
        <div class="content">
            <div class="metadata">
                <div class="metadata-item"><div class="metadata-label">Run Type</div><div class="metadata-value">RUN_TYPE_PLACEHOLDER</div></div>
                <div class="metadata-item"><div class="metadata-label">Timestamp</div><div class="metadata-value">TIME_PLACEHOLDER</div></div>
            </div>
            <div class="section">
                <h2>Package Updates</h2>
                UPGRADE_SUMMARY_PLACEHOLDER
            </div>
        </div>
        <div class="footer">
            <p>For detailed logs, see your automation directory.</p>
        </div>
    </div>
</body>
</html>
EOF
}

# ============================================================================


check_lock() {
    if [ ! -f "$LOCK_FILE" ]; then
        return 0  # No lock, safe to proceed
    fi

    # Read PID and timestamp from lock
    read -r PID LOCK_TIME < "$LOCK_FILE" 2>/dev/null || return 0
    CURRENT_TIME=$(date +%s)
    LOCK_AGE=$((CURRENT_TIME - LOCK_TIME))

    # Check if process still running
    if kill -0 "$PID" 2>/dev/null; then
        return 1  # Process running, skip
    fi

    # Check if lock is stale (older than timeout)
    if [ "$LOCK_AGE" -gt "$LOCK_TIMEOUT" ]; then
        rm -f "$LOCK_FILE"
        return 0  # Stale lock removed, safe to proceed
    fi

    return 1  # Lock is valid but process missing (shouldn't happen)
}

# For manual runs, check rate limiting
if [ "$MANUAL" = true ]; then
    if ! check_lock; then
        echo "[$(date)] Skip: Manual trigger already in progress or recently run" >> "$ERROR_LOG"
        exit 0
    fi
fi

# Atomically acquire lock using mkdir to prevent race conditions
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "[$(date)] Skip: Another instance is acquiring the lock" >> "$ERROR_LOG"
    exit 0
fi
echo "$$ $(date +%s)" > "$LOCK_FILE"

# ============================================================================
# ERROR HANDLING: Trap and cleanup on exit
# ============================================================================

FAILED_STEP="initializing"

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    rm -rf "$LOCK_DIR"

    if [ $exit_code -ne 0 ]; then
        local error_msg="[$(date)] ERROR: Failed during '$FAILED_STEP' (exit code $exit_code)"
        if [ "$MANUAL" = false ]; then
            error_msg="$error_msg. Next retry at 12:30 PM tomorrow."
        fi

        echo "$error_msg" | tee -a "$LOG_FILE" "$ERROR_LOG" >&2

        # Send error email with HTML
        if [ -n "$PYTHON_PATH" ] && [ -x "$PYTHON_PATH" ] && [ -n "$SENDER_EMAIL" ] && [ -n "$SENDER_APP_PASSWORD" ] && [ -n "$RECIPIENT_EMAIL" ]; then
            local failed_step_escaped
            failed_step_escaped=$(printf '%s' "$FAILED_STEP" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g")
            local error_body="Brew update failed on $TODAY during step: $FAILED_STEP (exit code $exit_code). See logs for details."
            local error_summary="<div style='color: #333; padding: 15px; background: #f9f9f9; border-left: 3px solid #f8d7da; border-radius: 3px;'><strong>Failed step:</strong> $failed_step_escaped<br><strong>Exit code:</strong> $exit_code<br><strong>See error log for details.</strong></div>"

            local html_error=$(generate_html_email "Brew Update Failed" "failed" "$error_summary")
            html_error="${html_error//TITLE_PLACEHOLDER/Brew Update Failed}"
            html_error="${html_error//STATUS_BADGE/✗ Failed}"
            html_error="${html_error//STATUS_CLASS/failed}"
            local esc_date esc_run_type esc_time
            esc_date=$(printf '%s' "$TODAY" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
            esc_run_type=$([ "$MANUAL" = true ] && echo "Manual" || echo "Automated")
            esc_time=$(date '+%H:%M:%S %Z' | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
            html_error="${html_error//DATE_PLACEHOLDER/$esc_date}"
            html_error="${html_error//RUN_TYPE_PLACEHOLDER/$esc_run_type}"
            html_error="${html_error//TIME_PLACEHOLDER/$esc_time}"
            html_error="${html_error//UPGRADE_SUMMARY_PLACEHOLDER/$error_summary}"

            SENDER_EMAIL="$SENDER_EMAIL" SENDER_APP_PASSWORD="$SENDER_APP_PASSWORD" RECIPIENT_EMAIL="$RECIPIENT_EMAIL" \
            "$PYTHON_PATH" "$BASE_DIR/notify.py" \
                "$EMAIL_SUBJECT_FAIL" \
                "$error_body" \
                "$html_error"
            if [ $? -ne 0 ]; then
                echo "[$(date)] WARNING: Failed to send error email" >> "$ERROR_LOG"
            fi
        fi
    fi
}
trap cleanup EXIT

# ============================================================================
# LOGGING SETUP: Capture stderr
# ============================================================================

echo "" >> "$ERROR_LOG"
echo "=== Run started: $TIMESTAMP ===" >> "$ERROR_LOG"
exec 2> >(tee -a "$ERROR_LOG" >&2)

# ============================================================================
# EXECUTION: Brew, UV, Python upgrades
# ============================================================================

UPGRADE_TEMP=$(mktemp) || { echo "[$(date)] ERROR: Failed to create temp file" >&2; exit 1; }
chmod 600 "$UPGRADE_TEMP"

FAILED_STEP="brew outdated"
echo "--- LOGGING START: $TIMESTAMP ---" >> "$LOG_FILE"
echo "Outdated packages:" >> "$LOG_FILE"
"$BREW" outdated >> "$LOG_FILE" 2>&1 || true

FAILED_STEP="brew update"
echo "--- Updating Homebrew ---"
"$BREW" update 2>&1 | tee -a "$UPGRADE_TEMP" >/dev/null

FAILED_STEP="brew upgrade"
"$BREW" upgrade 2>&1 | tee -a "$UPGRADE_TEMP" >/dev/null

FAILED_STEP="brew upgrade --cask"
"$BREW" upgrade --cask 2>&1 | tee -a "$UPGRADE_TEMP" >/dev/null

FAILED_STEP="uv tool upgrade"
echo "--- Updating UV Tools ---"
"$UV" tool upgrade --all 2>&1 | tee -a "$UPGRADE_TEMP" >/dev/null

# Python pip upgrades (non-fatal if pyenv unavailable)
if [ -n "$PYTHON_PATH" ] && [ -x "$PYTHON_PATH" ]; then
    if command -v pyenv &>/dev/null; then
        PYENV_PYTHON=$(pyenv which python 2>/dev/null || true)
        if [ -n "$PYENV_PYTHON" ] && [ -x "$PYENV_PYTHON" ]; then
            FAILED_STEP="uv pip upgrade"
            echo "--- Updating Python Libs ---"
            PKGS=$("$UV" pip list --python "$PYENV_PYTHON" --format freeze 2>/dev/null | cut -d= -f1 || true)
            if [ -n "$PKGS" ]; then
                echo "$PKGS" | tr '\n' '\0' | xargs -0 "$UV" pip install --upgrade --python "$PYENV_PYTHON" 2>&1 | tee -a "$UPGRADE_TEMP" >/dev/null
            fi
        else
            echo "[$(date)] WARNING: pyenv python not found, skipping pip upgrades" >> "$LOG_FILE"
        fi
    fi
fi

FAILED_STEP="brew cleanup"
"$BREW" cleanup --prune=all >/dev/null 2>&1 || true

# ============================================================================
# SUCCESS: Send email and finalize
# ============================================================================

# ============================================================================
# SUCCESS: Generate HTML email and send notification
# ============================================================================

UPGRADE_SUMMARY=$(generate_upgrade_summary "$UPGRADE_TEMP")

if [ -n "$PYTHON_PATH" ] && [ -x "$PYTHON_PATH" ] && [ -n "$SENDER_EMAIL" ] && [ -n "$SENDER_APP_PASSWORD" ] && [ -n "$RECIPIENT_EMAIL" ]; then
    success_body="Brew update completed successfully on $TODAY at $(date).

$([ "$MANUAL" = true ] && echo "This was a manual run." || echo "")"

    # Generate HTML email from template
    html_body=$(generate_html_email "Brew Update Complete" "success" "$UPGRADE_SUMMARY")
    html_body="${html_body//TITLE_PLACEHOLDER/Brew Update Complete}"
    html_body="${html_body//STATUS_BADGE/✓ Completed Successfully}"
    html_body="${html_body//STATUS_CLASS/success}"
    esc_date=$(printf '%s' "$TODAY" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
    esc_run_type=$([ "$MANUAL" = true ] && echo "Manual" || echo "Automated")
    esc_time=$(date '+%H:%M:%S %Z' | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
    html_body="${html_body//DATE_PLACEHOLDER/$esc_date}"
    html_body="${html_body//RUN_TYPE_PLACEHOLDER/$esc_run_type}"
    html_body="${html_body//TIME_PLACEHOLDER/$esc_time}"
    html_body="${html_body//UPGRADE_SUMMARY_PLACEHOLDER/$UPGRADE_SUMMARY}"

    SENDER_EMAIL="$SENDER_EMAIL" SENDER_APP_PASSWORD="$SENDER_APP_PASSWORD" RECIPIENT_EMAIL="$RECIPIENT_EMAIL" \
    "$PYTHON_PATH" "$BASE_DIR/notify.py" \
        "$EMAIL_SUBJECT_SUCCESS" \
        "$success_body" \
        "$html_body"
    if [ $? -ne 0 ]; then
        echo "[$(date)] WARNING: Failed to send success email" >> "$LOG_FILE"
    fi
fi

rm -f "$UPGRADE_TEMP"

# ============================================================================
# FINALIZATION (automation-only): Completion marker and log rotation
# ============================================================================

if [ "$MANUAL" = false ]; then
    echo "Running bubu has been completed on $TODAY ($(date))" >> "$LOG_FILE"

    # Clear error log on clean run
    > "$ERROR_LOG"

    # Log rotation: keep only the last 30 days of completion markers
    # Use portable date command (try BSD first, then GNU)
    CUTOFF=$(date -v-30d "+%Y-%m-%d" 2>/dev/null || date -d "30 days ago" "+%Y-%m-%d" 2>/dev/null || date "+%Y-%m-%d")

    awk -v cutoff="$CUTOFF" '
        /Running bubu has been completed on [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
            match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)
            if (substr($0, RSTART, RLENGTH) >= cutoff) print
            next
        }
    ' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"

    if [ -n "$SKIP_LOG" ]; then
        tail -n 100 "$SKIP_LOG" > "${SKIP_LOG}.tmp" && mv "${SKIP_LOG}.tmp" "$SKIP_LOG"
    fi
else
    # Manual runs: rotate logs after 50 entries (keep recent runs)
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
        tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi
