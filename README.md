# BrewAutomation

Automated Homebrew, uv, and Python package updates on macOS with **hardened security**, error handling, and email notifications. Includes both automated scheduling and manual triggers.

## Features

- ✅ **Daily package updates** (brew, casks, uv tools, Python libraries)
- ✅ **Scheduled system restarts** (Tuesday & Thursday 9:00 AM)
- ✅ **HTML email notifications** (success & failure with package details)
- ✅ **Secure credential storage** (encrypted env vars, restricted permissions)
- ✅ **Robust error handling** (visible failures, detailed logs, retry detection)
- ✅ **Duplicate prevention** (lock files with timestamp-based expiration)
- ✅ **Graceful degradation** (iTerm2 fallback to background execution)
- ✅ **Manual triggers** (immediate updates/restarts with separate logging)
- ✅ **Log rotation** (automatic 30-day retention for automation logs)

---

## How It Works

### Brew Updates
```
LaunchAgent (plist, daily at 12:30 PM)
    └─> brew_autoupdate.sh       (guard: skip if already ran today)
            ├─> Lock file check  (stale detection + rate limiting)
            └─> bubu_executor.sh (runs in iTerm2, falls back to background)
                    ├── brew update / upgrade / upgrade --cask
                    ├── uv tool upgrade --all
                    └── uv pip install --upgrade (pyenv Python)
```

**Automated:** Runs daily at 12:30 PM; only executes once per calendar day (duplicate guard prevents multiple runs).

**Manual:** `bubu_executor.sh --manual` triggers an immediate run with separate logging.

### System Restarts
```
LaunchDaemon (plist, Tue & Thu at 9:00 AM)
    └─> restart_script.sh (with 3-second confirmation prompt)
            └─> sudo shutdown -r now
```

**Automated:** Scheduled for Tuesday and Thursday mornings (no confirmation).

**Manual:** `restart_script.sh --manual` triggers a restart after 3-second confirmation. Pass `--force` to skip the confirmation.

---

## Security & Reliability

### Credential Management
- ✅ `.env` file permissions enforced to `600` (owner-only readable)
- ✅ Email credentials **never exposed** to child processes (`set -a` removed)
- ✅ Credentials passed via **scoped environment variables** to subprocess — invisible to `ps`/`/proc`
- ✅ `notify.py` strips surrounding quotes from `.env` values before use
- ✅ SMTP error messages don't leak credentials or sensitive info

### Error Handling
- ✅ `set -e` halts scripts on any error (fail-fast)
- ✅ Trap handlers clean up resources on failure
- ✅ Email notifications sent on both success and failure
- ✅ Visible errors in LaunchAgent logs (`restart_stdout.log`, `restart_stderr.log`)
- ✅ Proper exit codes from `notify.py` (0=success, 1=config error, 2=network error)

### Lock File Safety
- ✅ Lock files include timestamp-based expiration (1-hour timeout)
- ✅ PID verification (prevent stale process detection)
- ✅ Atomic lock creation via `mkdir` (race-condition-free)
- ✅ Rate limiting for manual triggers (prevents duplicate execution)
- ✅ Clock skew protection (negative lock age clamped to zero)

### Tool Validation
- ✅ Brew and uv paths validated early (before traps/logging)
- ✅ Python path resolution standardized (pyenv preferred, system fallback)
- ✅ Missing tools produce clear error messages (not silent failures)
- ✅ iTerm2 fallback to background execution if missing

### Log Management
- ✅ Automated logs rotate to keep last 30 days (completion markers only)
- ✅ Manual logs rotate to keep last 500 lines (separate from automation)
- ✅ Error logs cleared on successful automation runs
- ✅ All log files created with `600` permissions (owner-only readable)
- ✅ Temporary files created with `600` permissions
- ✅ All timestamps recorded for audit trail

---

## Email Notifications

Both automations send **styled HTML emails** on success and failure with:

- **Status badge** (✓ Success / ✗ Failed) with visual indicators
- **Metadata** (Run type, date, timestamp, duration)
- **Package upgrade table** (package name, old version → new version)
- **Plain text fallback** for email clients that don't support HTML
- **Fully HTML-escaped output** (all 5 special chars including `'`) — no injection possible
- **Proper error messages** without credential leakage

### Success Example
```
Subject: Brew Update Complete — 2026-04-01

Brew update completed successfully on 2026-04-01 at Wed Apr 1 12:30:45 CDT 2026.
```

### Failure Example
```
Subject: Brew Update FAILED — 2026-04-01

Brew update failed on 2026-04-01.

Failed step: brew upgrade
Exit code: 1

See ~/IdeaProjects/BrewAutomation/error.log for details.

Next retry at 12:30 PM tomorrow.
```

---

## Setup

### 1. Clone/Copy to Home Directory
```bash
git clone <repo> ~/IdeaProjects/BrewAutomation
cd ~/IdeaProjects/BrewAutomation
chmod +x *.sh  # Make scripts executable
```

### 2. Configure Gmail Credentials

Edit `.env` with your Gmail App Password:
```bash
SENDER_EMAIL=your-email@gmail.com
SENDER_APP_PASSWORD="xxxx xxxx xxxx xxxx"
RECIPIENT_EMAIL=your-email@gmail.com
BREW_PATH=/opt/homebrew/bin/brew
UV_PATH=/opt/homebrew/bin/uv
```

**To get a Gmail App Password:**
1. Enable 2-Step Verification: https://myaccount.google.com/security
2. Generate App Password: https://myaccount.google.com/apppasswords (select "Other (custom name)")
3. Copy the 16-character password (with spaces) into `.env`

**Security reminder:** `.env` contains plaintext credentials. The setup script enforces `chmod 600` (readable only by owner). Keep your app password secret and never commit `.env` to version control.

### 3. Install LaunchAgents
```bash
bash reload.sh                    # Install brew automation (user-level)
bash reload_restart.sh            # Install restart automation (system-level, needs sudo)
```

Output should show:
```
✓ LaunchAgent installed and loaded
✓ .env permissions: 600 (owner-only)
```

### 4. Verify Installation
```bash
launchctl list | grep suryakiran
```

Should show:
- `com.suryakiran.brewauto` (LaunchAgent, user-level)
- `com.suryakiran.restart` (LaunchDaemon, system-level)

---

## Manual Triggers

### Trigger Brew Update
```bash
~/IdeaProjects/BrewAutomation/bubu_executor.sh --manual
```
- Runs immediately in iTerm2 (or background if iTerm2 unavailable)
- Logs to separate `brew_update_manual.log` and `error_manual.log`
- Sends success/failure email
- Does NOT write completion marker (doesn't affect daily automation guard)
- Does NOT skip if already ran today (manual runs always execute)

### Trigger System Restart
```bash
bash ~/IdeaProjects/BrewAutomation/restart_script.sh --manual
```
- Prompts: "System restart will occur in 3 seconds. Press Ctrl+C to cancel."
- Logs to separate `restart_history_manual.log`
- Sends email notification
- **Use `--force` to skip the confirmation prompt:**
  ```bash
  bash ~/IdeaProjects/BrewAutomation/restart_script.sh --manual --force
  ```

---

## Monitoring

### Check Logs
```bash
# Automated brew run
tail -f ~/IdeaProjects/BrewAutomation/brew_update.log

# Manual brew run
tail -f ~/IdeaProjects/BrewAutomation/brew_update_manual.log

# Errors (automated)
tail -f ~/IdeaProjects/BrewAutomation/error.log

# Errors (manual)
tail -f ~/IdeaProjects/BrewAutomation/error_manual.log

# Skipped runs
tail -f ~/IdeaProjects/BrewAutomation/skips.log

# Restart history (automated)
cat ~/IdeaProjects/BrewAutomation/restart_history.log

# Restart history (manual)
cat ~/IdeaProjects/BrewAutomation/restart_history_manual.log

# LaunchAgent system output
tail -f ~/IdeaProjects/BrewAutomation/system_stderr.log
tail -f ~/IdeaProjects/BrewAutomation/system_stdout.log

# LaunchDaemon system output (restart)
tail -f ~/IdeaProjects/BrewAutomation/restart_stdout.log
tail -f ~/IdeaProjects/BrewAutomation/restart_stderr.log
```

### Check LaunchAgent Status
```bash
# View current state
launchctl list com.suryakiran.brewauto
launchctl list com.suryakiran.restart

# View next scheduled time
launchctl list | grep suryakiran
```

### Health Check
A healthy system shows:
- ✅ Completion marker in `brew_update.log` once per day
- ✅ Email received on success/failure
- ✅ No errors in `error.log` (or cleared after success)
- ✅ Lock file removed after run completes
- ✅ No stale locks older than 1 hour

---

## Log Rotation & Retention

| Log File | Rotation Policy | Retention |
|---|---|---|
| `brew_update.log` | Date-based (completion markers only) | Last 30 days |
| `brew_update_manual.log` | Line-based (last 500 lines) | Latest 500 lines (~50 runs) |
| `error.log` | Cleared on success, preserved on failure | Current failure or empty |
| `error_manual.log` | Line-based (last 500 lines) | Latest 500 lines (~50 runs) |
| `skips.log` | Line-based (last 100 lines) | Latest 100 lines (~30-50 days) |
| `brew_update_background.log` | iTerm2 fallback output (no rotation) | Unbounded |
| `system_stderr.log` | LaunchAgent output (no rotation) | Unbounded |
| `system_stdout.log` | LaunchAgent output (no rotation) | Unbounded |
| `restart_stdout.log` | LaunchDaemon output (no rotation) | Unbounded |
| `restart_stderr.log` | LaunchDaemon output (no rotation) | Unbounded |

All log files are created with `600` permissions (owner-only readable).

---

## File Reference

| File | Purpose |
|---|---|
| `brew_autoupdate.sh` | Guard script — checks for duplicates, manages lock file, launches executor |
| `bubu_executor.sh` | Executor script — runs all upgrades (brew, uv, python) with error handling |
| `restart_script.sh` | System restart — logs and sends email notification, with confirmation prompt |
| `tzreload.sh` | Timezone watcher — reloads LaunchAgent when system timezone changes |
| `notify.py` | Email sender — sends HTML/plain text emails via Gmail SMTP |
| `com.suryakiran.brewauto.plist` | LaunchAgent definition (brew updates, daily 12:30 PM) |
| `com.suryakiran.restart.plist` | LaunchDaemon definition (restart, Tue/Thu 9:00 AM) |
| `com.suryakiran.tzwatch.plist` | LaunchAgent definition (timezone watcher, polls every 5 min) |
| `reload.sh` | Installer — deploys brew LaunchAgent and tzwatch, enforces permissions |
| `reload_restart.sh` | Installer — deploys restart LaunchDaemon, enforces permissions |
| `.env` | Credentials (gitignored) — Gmail & tool paths |
| `.gitignore` | Git exclusions — credentials, logs, lock directory, IDE files |
| `README.md` | This file |

---

## Troubleshooting

### Brew automation not running
**Symptoms:** No logs updated, no emails received, missing completion marker

**Debug steps:**
1. Check LaunchAgent is loaded: `launchctl list com.suryakiran.brewauto`
   - Should show `0` (loaded) or `1` (exited successfully)
2. Check for errors: `tail ~/IdeaProjects/BrewAutomation/system_stderr.log`
3. Check LaunchAgent environment: `launchctl getenv PATH` (verify it includes brew path)
4. Reload the agent: `bash reload.sh`
5. Test manually: `bash ~/IdeaProjects/BrewAutomation/bubu_executor.sh --manual`

### Emails not sending
**Symptoms:** No email received on success/failure

**Debug steps:**
1. Verify `.env` has all credentials:
   ```bash
   grep "^SENDER_EMAIL\|^SENDER_APP_PASSWORD\|^RECIPIENT_EMAIL" ~/.BrewAutomation/.env
   ```
2. Verify app password is correct (not Gmail login password): https://myaccount.google.com/apppasswords
3. Verify 2-Step Verification is enabled: https://myaccount.google.com/security
4. Check for SMTP errors:
   ```bash
   tail -50 ~/IdeaProjects/BrewAutomation/error.log | grep -i "smtp\|auth\|network"
   ```
5. Test email sending (credentials loaded from `.env` automatically):
   ```bash
   cd ~/IdeaProjects/BrewAutomation && python3 notify.py "Test Email" "This is a test." ""
   ```

### Tools not found (brew, uv, python)
**Symptoms:** Error log shows "brew not found at..." / "uv not found at..."

**Debug steps:**
1. Find actual paths:
   ```bash
   which brew
   which uv
   which python3
   ```
2. Update `.env` with correct paths:
   ```bash
   BREW_PATH=$(which brew)
   UV_PATH=$(which uv)
   ```
3. Reload: `bash reload.sh`

### Manual run already in progress
**Symptoms:** Manual trigger returns immediately without running

**Debug steps:**
1. Check if lock file exists: `ls -la ~/IdeaProjects/BrewAutomation/brew_update.lock`
2. If it does, check the PID: `cat ~/IdeaProjects/BrewAutomation/brew_update.lock`
3. If that process doesn't exist, remove the stale lock and lock directory:
   ```bash
   rm -f ~/IdeaProjects/BrewAutomation/brew_update.lock
   rm -rf ~/IdeaProjects/BrewAutomation/brew_update.lock.d
   ```

### System restart confirmation appears even on scheduled run
**Symptoms:** 3-second countdown appears during scheduled 12:30 PM run

**This shouldn't happen** (no confirmation on automated runs), but if it does:
1. Check if `restart_script.sh --manual` was called instead of scheduled run
2. Check the scheduled time in plist: `cat ~/Library/LaunchDaemons/com.suryakiran.restart.plist | grep -A 5 StartCalendarInterval`

---

## Uninstalling

To disable and remove automations:

```bash
# Unload brew automation and timezone watcher
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.suryakiran.brewauto.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.suryakiran.tzwatch.plist

# Unload restart automation (needs sudo for LaunchDaemon)
sudo launchctl bootout system /Library/LaunchDaemons/com.suryakiran.restart.plist

# Remove the project directory (optional)
rm -rf ~/IdeaProjects/BrewAutomation
```

---

## Requirements

- macOS 10.14+ with Homebrew installed
- Python 3 (for email notifications)
- **Optional:** pyenv (for Python package upgrades via uv pip)
- **Optional:** iTerm2 (falls back to background execution if missing)

---

## Environment

This project uses `$HOME` for all paths — works on any macOS user account after installation. The plist templates contain `__HOME__` placeholders which are substituted during `reload.sh` installation.

---

## Version History

### v3.0 (Current — Comprehensive Security Hardening)
- ✅ Credentials passed via scoped env vars — no longer visible in `ps` output
- ✅ Fixed `notify.py` quote-stripping bug (SMTP auth was failing when loaded from `.env`)
- ✅ Fixed missing `error_body` variable (error emails had blank plain-text body)
- ✅ Fixed `/bin/bash` missing from restart LaunchDaemon plist (restarts were silently failing)
- ✅ Fixed `notify.py` argument order in `restart_script.sh` (sender/password were shifted)
- ✅ Full HTML escaping on all email output including single-quote (`&#39;`)
- ✅ HTML-escaped date, time, and run-type fields in email templates
- ✅ Atomic lock acquisition via `mkdir` (race-condition-free)
- ✅ Atomic timezone state file write via `tmp → mv`
- ✅ Timezone string format validated before use
- ✅ `|| true` error handling on all `.env` grep calls in `restart_script.sh`
- ✅ `xargs -0` with null-delimited input for pip package names
- ✅ All log files created with `600` permissions (owner-only)
- ✅ Clock skew protection in lock age calculation
- ✅ `mktemp` result validated before use
- ✅ `awk` field count guard before package name extraction
- ✅ `$BASE_DIR` path escaped before osascript heredoc embedding
- ✅ Background fallback logs to `brew_update_background.log` instead of `/dev/null`
- ✅ `set -e` added to `brew_autoupdate.sh`, `reload.sh`, `reload_restart.sh`
- ✅ Restart log files pre-created at `600` in `reload_restart.sh`
- ✅ `brew_update.lock.d/` added to `.gitignore`
- ✅ Deprecated `launchctl unload` replaced with `bootout` throughout

### v2.0 (Security & Hardening Release)
- ✅ Added confirmation prompt to system restarts (prevent accidental data loss)
- ✅ Fixed credential exposure (no more `set -a`)
- ✅ Added stdout/stderr logging to LaunchDaemon
- ✅ Fixed silent email failures (proper exit codes)
- ✅ Enforced `.env` permissions (`chmod 600`)
- ✅ Fixed command injection risks (proper quoting)
- ✅ Added iTerm2 fallback (background execution)
- ✅ Improved lock file safety (timestamp-based expiration)
- ✅ Standardized Python resolution
- ✅ Added LaunchAgent validation (exit code checks)
- ✅ Manual log rotation for long-term retention
- ✅ Detailed troubleshooting guide

### v1.0 (Initial Release)
- Basic brew/uv/python automation
- Email notifications
- LaunchAgent scheduling
- Manual triggers

---

## License

Personal automation project. No license specified.
