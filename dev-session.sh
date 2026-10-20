#!/usr/bin/env bash
# =============================================================================
# dev-session.sh — launch (or attach to) a persistent Go dev tmux session
#
# Usage:
#   ./dev-session.sh [session-name] [project-root]
#   ./dev-session.sh --list
#   ./dev-session.sh --help
#
# If a session already exists, attaches to it.
# Otherwise creates the full layout from scratch.
# =============================================================================

set -euo pipefail

# ── Helper functions ──────────────────────────────────────────────────────────
show_help() {
  cat << 'EOF'
Usage: dev-session.sh [OPTIONS] [session-name] [project-root]

Options:
  --list              List all available tmux sessions
  --help              Show this help message

Arguments:
  session-name        Name of the tmux session (will be prepended with "dev-")
                      If a directory path is passed, uses "dev" session in that directory
  project-root        Project directory (default: current directory)

Examples:
  dev-session.sh                           # Creates/attaches "dev" session in $PWD
  dev-session.sh sasquat                   # Creates/attaches "dev-sasquat" session in $PWD
  dev-session.sh sasquat /code/sasquat     # Creates/attaches "dev-sasquat" session in /code/sasquat
  dev-session.sh /code/sasquat             # Creates/attaches "dev" session in /code/sasquat
  dev-session.sh --list                    # Lists all tmux sessions
  dev-session.sh --help                    # Shows this help

EOF
}

list_sessions() {
  if ! tmux list-sessions 2>/dev/null; then
    echo "No tmux sessions available."
    exit 0
  fi
}

# ── Parse arguments ───────────────────────────────────────────────────────────
case "${1:-}" in
  --help)
    show_help
    exit 0
    ;;
  --list)
    list_sessions
    exit 0
    ;;
esac

# Parse session name and project root
# Logic: if arg1 exists and is a directory, it's the project root
# Otherwise, arg1 is the session name and arg2 (if provided) is the project root
SESSION_NAME="${1:-dev}"
if [ -d "$SESSION_NAME" ]; then
  # First arg is a directory, so it's the project root (using default session name)
  SESSION_NAME="dev"
  ROOT="$SESSION_NAME"
else
  # First arg is a session name
  ROOT="${2:-$PWD}"  # Second arg is project root, or current directory
fi

# Prepend "dev-" to session name (unless it's already "dev" or starts with "dev-")
if [ "$SESSION_NAME" = "dev" ]; then
  SESSION="dev"
elif [[ "$SESSION_NAME" == dev-* ]]; then
  SESSION="$SESSION_NAME"  # Already has dev- prefix
else
  SESSION="dev-$SESSION_NAME"
fi

# If already inside tmux, switch; otherwise attach or create
tmux_cmd() {
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION"
  else
    tmux attach-session -t "$SESSION"
  fi
}

# ── Already exists? Just attach ───────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' exists — attaching."
  tmux_cmd
  exit 0
fi

# ── Create session with window 1: Editor ──────────────────────────────────────
#
#  ┌─────────────────────┬────────────────┐
#  │                     │                │
#  │    vim / nvim       │  file explorer │
#  │    (main editor)    │  (lf / nnn /   │
#  │                     │   tree)        │
#  │                     │                │
#  └─────────────────────┴────────────────┘
#
tmux new-session  -d -s "$SESSION" -n "editor" -c "$ROOT"

# Split right ~25% for file explorer
tmux split-window -h -l 25% -t "$SESSION:editor" -c "$ROOT"
tmux send-keys    -t "$SESSION:editor.right" \
  'command -v lf &>/dev/null && lf || command -v nnn &>/dev/null && nnn || watch -n2 tree -L 3' Enter

# Focus left pane, open vim
tmux select-pane  -t "$SESSION:editor.left"
tmux send-keys    -t "$SESSION:editor.left" 'vim .' Enter

# ── Window 2: Claude Code ─────────────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │                                     │
#  │         claude (full width)         │
#  │                                     │
#  └─────────────────────────────────────┘
#
tmux new-window   -t "$SESSION" -n "claude" -c "$ROOT"
tmux send-keys    -t "$SESSION:claude" 'claude' Enter

# ── Window 3: GitHub Copilot CLI ──────────────────────────────────────────────
#  brew install copilot-cli   (then /login on first run)
#  ┌─────────────────────────────────────┐
#  │        copilot (full width)         │
#  └─────────────────────────────────────┘
#
tmux new-window -t "$SESSION" -n "copilot" -c "$ROOT"
tmux send-keys -t "$SESSION:copilot" 'copilot' Enter

# ── Window 4: Shell / go commands ─────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │         go build / test / run       │
#  └────────────────────┬────────────────┘
#  │     go test -v     │  git / misc    │
#  └────────────────────┴────────────────┘
#
tmux new-window   -t "$SESSION" -n "shell" -c "$ROOT"
tmux split-window -v -l 35% -t "$SESSION:shell" -c "$ROOT"
tmux split-window -h         -t "$SESSION:shell.bottom" -c "$ROOT"

# Label bottom panes and launch test runner
tmux select-pane  -t "$SESSION:shell.bottom-left"  -T "test"
tmux select-pane  -t "$SESSION:shell.bottom-right" -T "git"
tmux send-keys    -t "$SESSION:shell.bottom-left"  'go test -v ./...' Enter

# Focus top pane (main shell for go build/run)
tmux select-pane  -t "$SESSION:shell.top"

# ── Window 5: Debug ───────────────────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │         delve / dlv dap             │
#  └────────────────────┬────────────────┘
#  │  program output    │  watch / logs  │
#  └────────────────────┴────────────────┘
#
tmux new-window   -t "$SESSION" -n "debug" -c "$ROOT"
tmux split-window -v -l 35% -t "$SESSION:debug" -c "$ROOT"
tmux split-window -h         -t "$SESSION:debug.bottom" -c "$ROOT"

tmux select-pane  -t "$SESSION:debug.top"    -T "dlv"
tmux select-pane  -t "$SESSION:debug.bottom-left"  -T "output"
tmux select-pane  -t "$SESSION:debug.bottom-right" -T "logs"

# Start watching test output by default in logs pane
tmux send-keys    -t "$SESSION:debug.bottom-right" \
  'echo "tail -f app.log  |  or:  go test -v ./... 2>&1 | tee /tmp/gotest.log"' Enter

tmux select-pane  -t "$SESSION:debug.top"

# ── Land on editor, pane 1 ────────────────────────────────────────────────────
tmux select-window -t "$SESSION:editor"
tmux select-pane   -t "$SESSION:editor.left"

tmux_cmd
