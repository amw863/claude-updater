#!/usr/bin/env bash
# claude-updater.sh — Auto-update Claude Code CLI and everything-claude-code
#
# Usage:
#   ./claude-updater.sh           # Check and update
#   ./claude-updater.sh --check   # Check only, no updates
#   ./claude-updater.sh --force   # Force update even if versions match
#   ./claude-updater.sh --init    # Generate default config file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/claude-updater.conf"

# --- --init: generate config template ---
if [[ "${1:-}" == "--init" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config already exists: $CONFIG_FILE"
        echo "Delete it first if you want to regenerate."
        exit 1
    fi
    cat > "$CONFIG_FILE" <<'CONF'
# claude-updater.conf — Configuration for claude-updater.sh
#
# Edit the values below to match your local setup.

# Path to the everything-claude-code git repository
ECC_REPO="$HOME/workspace/everything-claude-code"

# Languages to install via ECC install.sh (space-separated)
ECC_LANGUAGES="typescript python golang swift"

# Claude home directory (where rules/, agents/, skills/ live)
CLAUDE_HOME="$HOME/.claude"

# ECC marketplace plugin copy (set empty to skip sync)
ECC_PLUGIN="$CLAUDE_HOME/plugins/marketplaces/everything-claude-code"

# Log directory
LOG_DIR="$CLAUDE_HOME/logs"

# Git remote branch to track
ECC_BRANCH="main"
CONF
    echo "Config generated: $CONFIG_FILE"
    echo "Edit it to match your setup, then run ./claude-updater.sh"
    exit 0
fi

# --- Load config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    echo "Run './claude-updater.sh --init' to generate one." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# --- Resolve paths (config may use $HOME etc.) ---
ECC_REPO="${ECC_REPO:-}"
ECC_LANGUAGES="${ECC_LANGUAGES:-}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
ECC_PLUGIN="${ECC_PLUGIN:-}"
LOG_DIR="${LOG_DIR:-$CLAUDE_HOME/logs}"
ECC_BRANCH="${ECC_BRANCH:-main}"
LOG_FILE="$LOG_DIR/claude-updater.log"

# --- Parse arguments ---
CHECK_ONLY=false
FORCE_UPDATE=false
case "${1:-}" in
    --check) CHECK_ONLY=true ;;
    --force) FORCE_UPDATE=true ;;
esac

# --- Logging ---
mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

# --- Ensure PATH includes npm/node ---
for p in /usr/local/bin /opt/homebrew/bin; do
    [[ -d "$p" ]] && export PATH="$p:$PATH"
done
if [[ -d "$HOME/.nvm/versions/node" ]]; then
    NVM_NODE=$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | sort -V | tail -1)
    [[ -n "$NVM_NODE" ]] && export PATH="$HOME/.nvm/versions/node/$NVM_NODE/bin:$PATH"
fi

log "========== Update check started =========="

# Track overall status
CLAUDE_UPDATED=false
ECC_UPDATED=false
HAD_ERROR=false

# ============================================
# 1. Claude Code CLI update
# ============================================
log "[Claude Code] Checking for updates..."

CURRENT_VERSION=""
LATEST_VERSION=""

if command -v claude &>/dev/null; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
fi

LATEST_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null) || true

if [[ -z "$CURRENT_VERSION" ]]; then
    log "[Claude Code] WARNING: Could not determine current version"
elif [[ -z "$LATEST_VERSION" ]]; then
    log "[Claude Code] WARNING: Could not fetch latest version from npm"
elif [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]] && [[ "$FORCE_UPDATE" == false ]]; then
    log "[Claude Code] Already up to date: v$CURRENT_VERSION"
else
    log "[Claude Code] Current: v${CURRENT_VERSION:-unknown} -> Latest: v$LATEST_VERSION"
    if [[ "$CHECK_ONLY" == true ]]; then
        log "[Claude Code] Update available (check-only mode, skipping install)"
    else
        log "[Claude Code] Installing update..."
        if npm install -g @anthropic-ai/claude-code@latest 2>>"$LOG_FILE"; then
            NEW_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
            log "[Claude Code] Updated successfully: v${CURRENT_VERSION:-unknown} -> v${NEW_VERSION:-unknown}"
            CLAUDE_UPDATED=true
        else
            log "[Claude Code] ERROR: Update failed"
            HAD_ERROR=true
        fi
    fi
fi

# ============================================
# 2. everything-claude-code update
# ============================================
if [[ -z "$ECC_REPO" ]]; then
    log "[ECC] Skipped (ECC_REPO not configured)"
elif [[ ! -d "$ECC_REPO/.git" ]]; then
    log "[ECC] ERROR: Repository not found at $ECC_REPO"
    HAD_ERROR=true
else
    log "[ECC] Checking for updates..."
    cd "$ECC_REPO"

    if ! git fetch origin 2>>"$LOG_FILE"; then
        log "[ECC] ERROR: git fetch failed"
        HAD_ERROR=true
    else
        LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null)
        REMOTE_HEAD=$(git rev-parse "origin/$ECC_BRANCH" 2>/dev/null)

        if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] && [[ "$FORCE_UPDATE" == false ]]; then
            log "[ECC] Already up to date: $(git describe --tags --always 2>/dev/null || echo "$LOCAL_HEAD")"
        else
            LOCAL_DESC=$(git describe --tags --always 2>/dev/null || echo "${LOCAL_HEAD:0:8}")
            REMOTE_DESC=$(git log "origin/$ECC_BRANCH" -1 --format='%h %s' 2>/dev/null || echo "${REMOTE_HEAD:0:8}")
            log "[ECC] Local: $LOCAL_DESC -> Remote: $REMOTE_DESC"

            if [[ "$CHECK_ONLY" == true ]]; then
                log "[ECC] Update available (check-only mode, skipping)"
            else
                log "[ECC] Pulling latest changes..."
                if git pull origin "$ECC_BRANCH" 2>>"$LOG_FILE"; then
                    log "[ECC] Git pull successful"

                    # 2a. Re-deploy rules via install.sh
                    if [[ -n "$ECC_LANGUAGES" ]] && [[ -f "$ECC_REPO/install.sh" ]]; then
                        log "[ECC] Re-deploying rules ($ECC_LANGUAGES)..."
                        if bash "$ECC_REPO/install.sh" $ECC_LANGUAGES 2>>"$LOG_FILE"; then
                            log "[ECC] Rules deployed successfully"
                        else
                            log "[ECC] ERROR: Rules deployment failed"
                            HAD_ERROR=true
                        fi
                    fi

                    # 2b. Copy agents
                    if [[ -d "$ECC_REPO/agents" ]]; then
                        log "[ECC] Deploying agents..."
                        mkdir -p "$CLAUDE_HOME/agents"
                        cp -r "$ECC_REPO/agents/"*.md "$CLAUDE_HOME/agents/" 2>/dev/null || true
                        log "[ECC] Agents deployed"
                    fi

                    # 2c. Copy skills
                    if [[ -d "$ECC_REPO/skills" ]]; then
                        log "[ECC] Deploying skills..."
                        mkdir -p "$CLAUDE_HOME/skills"
                        for skill_dir in "$ECC_REPO/skills"/*/; do
                            skill_name=$(basename "$skill_dir")
                            mkdir -p "$CLAUDE_HOME/skills/$skill_name"
                            cp -r "$skill_dir"* "$CLAUDE_HOME/skills/$skill_name/" 2>/dev/null || true
                        done
                        log "[ECC] Skills deployed"
                    fi

                    # 2d. Sync marketplace plugin copy
                    if [[ -n "$ECC_PLUGIN" ]] && [[ -d "$ECC_PLUGIN/.git" ]]; then
                        log "[ECC] Syncing marketplace plugin copy..."
                        if (cd "$ECC_PLUGIN" && git pull origin "$ECC_BRANCH" 2>>"$LOG_FILE"); then
                            log "[ECC] Marketplace plugin synced"
                        else
                            log "[ECC] WARNING: Marketplace plugin sync failed"
                        fi
                    fi

                    ECC_UPDATED=true
                    log "[ECC] Update completed: $(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)"
                else
                    log "[ECC] ERROR: git pull failed"
                    HAD_ERROR=true
                fi
            fi
        fi
    fi
fi

# ============================================
# 3. Summary and notification
# ============================================
log "========== Update check finished =========="

if [[ "$CHECK_ONLY" == true ]]; then
    log "Mode: check-only (no changes made)"
elif [[ "$CLAUDE_UPDATED" == true ]] || [[ "$ECC_UPDATED" == true ]]; then
    PARTS=()
    [[ "$CLAUDE_UPDATED" == true ]] && PARTS+=("Claude Code CLI")
    [[ "$ECC_UPDATED" == true ]] && PARTS+=("everything-claude-code")
    SUMMARY=$(IFS=", "; echo "${PARTS[*]}")
    log "Updated: $SUMMARY"
    notify "Claude Updater" "Updated: $SUMMARY"
elif [[ "$HAD_ERROR" == true ]]; then
    log "Completed with errors (check log for details)"
    notify "Claude Updater" "Update check completed with errors"
else
    log "Everything is up to date"
fi

exit 0
