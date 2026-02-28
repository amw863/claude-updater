# Claude Updater

Auto-update [Claude Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code) and [everything-claude-code](https://github.com/affaan-m/everything-claude-code) on macOS.

## Features

- **Claude Code CLI** — compares local version with npm latest, auto-installs when outdated
- **everything-claude-code** — detects new commits on remote, pulls and re-deploys rules / agents / skills
- **macOS launchd** — optional daily scheduled task (default 10:00 AM)
- **macOS notifications** — system notification on update success/failure
- **Configurable** — all paths via `claude-updater.conf`, no hardcoded values
- **Safe** — `--check` mode for dry-run, detailed logging

## Quick Start

```bash
git clone <this-repo> claude-updater
cd claude-updater
chmod +x *.sh

# 1. Generate config
./claude-updater.sh --init

# 2. Edit config to match your setup
vim claude-updater.conf

# 3. Check for updates (dry-run)
./claude-updater.sh --check

# 4. Run update
./claude-updater.sh

# 5. (Optional) Install daily scheduled task
./install-launchd.sh
```

## Usage

```bash
./claude-updater.sh              # Check and update
./claude-updater.sh --check      # Check only, no changes
./claude-updater.sh --force      # Force update even if already up to date
./claude-updater.sh --init       # Generate default config file
```

## Configuration

Run `./claude-updater.sh --init` to generate `claude-updater.conf`:

```bash
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
```

## What Gets Updated

### Claude Code CLI

1. Get current version via `claude --version`
2. Get latest version via `npm view @anthropic-ai/claude-code version`
3. If different, run `npm install -g @anthropic-ai/claude-code@latest`

### everything-claude-code

1. `git fetch origin` and compare `HEAD` vs `origin/main`
2. If new commits found, `git pull origin main`
3. Re-deploy via `install.sh` (rules to `~/.claude/rules/`)
4. Copy `agents/*.md` to `~/.claude/agents/`
5. Copy `skills/*/` to `~/.claude/skills/`
6. Sync marketplace plugin copy (if configured)

## Scheduled Task (launchd)

```bash
# Install — runs daily at 10:00 AM
./install-launchd.sh

# Verify
launchctl list | grep claude-updater

# Trigger manually
launchctl start com.wangbang.claude-updater

# Uninstall
./uninstall-launchd.sh
```

The plist is installed to `~/Library/LaunchAgents/com.wangbang.claude-updater.plist`.

## Logs

| File | Content |
|------|---------|
| `~/.claude/logs/claude-updater.log` | Update check results and actions |
| `~/.claude/logs/claude-updater-launchd.log` | launchd stdout/stderr |

Example log output:

```
[2026-02-28 10:00:01] ========== Update check started ==========
[2026-02-28 10:00:02] [Claude Code] Already up to date: v2.1.62
[2026-02-28 10:00:05] [ECC] Local: v1.7.0 -> Remote: a3f2c1d feat: add new skill
[2026-02-28 10:00:08] [ECC] Git pull successful
[2026-02-28 10:00:09] [ECC] Rules deployed successfully
[2026-02-28 10:00:09] [ECC] Agents deployed
[2026-02-28 10:00:10] [ECC] Skills deployed
[2026-02-28 10:00:10] [ECC] Update completed: v1.8.0
[2026-02-28 10:00:10] ========== Update check finished ==========
[2026-02-28 10:00:10] Updated: everything-claude-code
```

## Prerequisites

- macOS
- bash 4+
- Node.js & npm (for Claude Code CLI)
- git

## File Structure

```
claude-updater/
├── claude-updater.sh       # Main update script
├── claude-updater.conf     # Config (generated via --init)
├── install-launchd.sh      # Install macOS scheduled task
├── uninstall-launchd.sh    # Remove macOS scheduled task
└── README.md
```

## License

MIT
