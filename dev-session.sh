#!/usr/bin/env bash
# =============================================================================
# dev-session.sh — launch (or attach to) a persistent Go dev tmux session
#
# Usage:
#   ./dev-session.sh [session-name] [project-root]
#   ./dev-session.sh --list
#   ./dev-session.sh --kill [session-name]
#   ./dev-session.sh --kill-all
#   ./dev-session.sh --refresh [session-name] [project-root]
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
  --kill [name]       Kill a session (name resolved like below; default: current folder's)
  --kill-all          Kill all dev sessions ("dev" and "dev-*")
  --refresh [name]    Add any missing layout windows to a running session
                      without touching existing windows or processes
  --help              Show this help message

Arguments:
  session-name        Name of the tmux session (will be prepended with "dev-")
                      Defaults to the project folder's name (e.g. "dev-myapp").
                      If a directory path is passed, names it after that folder
  project-root        Project directory (default: current directory)

Examples:
  dev-session.sh                           # Creates/attaches "dev-<current folder>" in $PWD
  dev-session.sh sasquat                   # Creates/attaches "dev-sasquat" session in $PWD
  dev-session.sh sasquat /code/sasquat     # Creates/attaches "dev-sasquat" session in /code/sasquat
  dev-session.sh /code/sasquat             # Creates/attaches "dev-sasquat" in /code/sasquat
  dev-session.sh --list                    # Lists all tmux sessions
  dev-session.sh --kill sasquat            # Kills the "dev-sasquat" session
  dev-session.sh --kill                    # Kills the current folder's session
  dev-session.sh --kill-all                # Kills "dev" and every "dev-*" session
  dev-session.sh --refresh                 # Adds missing windows (e.g. opencode) to the running session
  dev-session.sh --help                    # Shows this help

EOF
}

list_sessions() {
  if ! tmux list-sessions 2>/dev/null; then
    echo "No tmux sessions available."
    exit 0
  fi
}

# Map a user-supplied name to a session name: "dev", "dev-*" kept, others get "dev-"
resolve_session() {
  case "$1" in
    dev|dev-*) echo "$1" ;;
    *)         echo "dev-$1" ;;
  esac
}

# Session name derived from a directory's basename (tmux disallows "." and ":")
dir_session_name() {
  local base
  base="$(basename "$1")"
  base="${base//[.:]/_}"
  echo "${base:-dev}"
}

kill_session() {
  local target
  target="$(resolve_session "${1:-$(dir_session_name "$PWD")}")"
  if tmux has-session -t "=$target" 2>/dev/null; then
    tmux kill-session -t "=$target"
    echo "Killed session '$target'."
  else
    echo "Session '$target' not found." >&2
    exit 1
  fi
}

kill_all_sessions() {
  local found=0 name
  while IFS= read -r name; do
    if [ "$name" = "dev" ] || [[ "$name" == dev-* ]]; then
      tmux kill-session -t "=$name"
      echo "Killed session '$name'."
      found=1
    fi
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  [ "$found" -eq 1 ] || echo "No dev sessions to kill."
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
  --kill)
    kill_session "${2:-}"
    exit 0
    ;;
  --kill-all)
    kill_all_sessions
    exit 0
    ;;
esac

REFRESH=0
if [ "${1:-}" = "--refresh" ]; then
  REFRESH=1
  shift
fi

# Parse session name and project root
# Logic: if arg1 exists and is a directory, it's the project root
# Otherwise, arg1 is the session name and arg2 (if provided) is the project root
SESSION_NAME="${1:-}"
if [ -n "$SESSION_NAME" ] && [ -d "$SESSION_NAME" ]; then
  # First arg is a directory, so it's the project root (name comes from its folder)
  ROOT="$(cd "$SESSION_NAME" && pwd)"
  SESSION_NAME="$(dir_session_name "$ROOT")"
else
  # First arg is a session name (or omitted)
  ROOT="${2:-$PWD}"  # Second arg is project root, or current directory
  if [ ! -d "$ROOT" ]; then
    echo "Error: project root '$ROOT' is not a directory." >&2
    exit 1
  fi
  ROOT="$(cd "$ROOT" && pwd)"
  [ -n "$SESSION_NAME" ] || SESSION_NAME="$(dir_session_name "$ROOT")"
fi

# Prepend "dev-" to session name (unless it's already "dev" or starts with "dev-")
SESSION="$(resolve_session "$SESSION_NAME")"

# If already inside tmux, switch; otherwise attach or create
tmux_cmd() {
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION"
  elif [ -t 0 ] && [ -t 1 ]; then
    tmux attach-session -t "$SESSION"
  else
    echo "Session '$SESSION' is ready, but this shell isn't an interactive terminal." >&2
    echo "Attach from a real terminal with:  tmux attach -t $SESSION" >&2
    exit 1
  fi
}

# ── Already exists? Attach (or refresh missing windows first) ─────────────────
SESSION_EXISTS=0
tmux has-session -t "=$SESSION" 2>/dev/null && SESSION_EXISTS=1

if [ "$SESSION_EXISTS" -eq 1 ] && [ "$REFRESH" -eq 0 ]; then
  echo "Session '$SESSION' exists — attaching."
  tmux_cmd
  exit 0
fi

window_exists() {
  tmux list-windows -t "=$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$1"
}

# Create window $1 right after the previous layout window (PREV), without
# switching to it. The first window of a brand-new session is made by new-session.
PREV=""
new_win() {
  if [ -z "$PREV" ]; then
    tmux new-window -d -b -t "$SESSION:^" -n "$1" -c "$ROOT"
  else
    tmux new-window -d -a -t "$SESSION:$PREV" -n "$1" -c "$ROOT"
  fi
}

# ── Window: Editor ────────────────────────────────────────────────────────────
#
#  ┌─────────────────────┬────────────────┐
#  │                     │                │
#  │    vim / nvim       │  file explorer │
#  │    (main editor)    │  (lf / nnn /   │
#  │                     │   tree)        │
#  │                     │                │
#  └─────────────────────┴────────────────┘
#
build_editor() {
  # Split right ~25% for file explorer
  tmux split-window -h -l 25% -t "$SESSION:editor" -c "$ROOT"
  tmux send-keys    -t "$SESSION:editor.right" \
    'command -v lf &>/dev/null && lf || command -v nnn &>/dev/null && nnn || watch -n2 tree -L 3' Enter

  # Focus left pane, open vim
  tmux select-pane  -t "$SESSION:editor.left"
  tmux send-keys    -t "$SESSION:editor.left" 'vim .' Enter
}

# ── Window: Claude Code ───────────────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │                                     │
#  │         claude (full width)         │
#  │                                     │
#  └─────────────────────────────────────┘
#
build_claude() {
  tmux send-keys -t "$SESSION:claude" 'claude' Enter
}

# ── Window: GitHub Copilot CLI ────────────────────────────────────────────────
#  brew install copilot-cli   (then /login on first run)
#  ┌─────────────────────────────────────┐
#  │        copilot (full width)         │
#  └─────────────────────────────────────┘
#
build_copilot() {
  tmux send-keys -t "$SESSION:copilot" 'copilot' Enter
}

# ── Window: opencode ──────────────────────────────────────────────────────────
#  brew install opencode   (then `opencode auth login` on first run)
#  ┌─────────────────────────────────────┐
#  │        opencode (full width)        │
#  └─────────────────────────────────────┘
#
build_opencode() {
  tmux send-keys -t "$SESSION:opencode" 'opencode' Enter
}

# ── Window: Shell / go commands ───────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │         go build / test / run       │
#  └────────────────────┬────────────────┘
#  │     go test -v     │  git / misc    │
#  └────────────────────┴────────────────┘
#
build_shell() {
  tmux split-window -v -l 35% -t "$SESSION:shell" -c "$ROOT"
  tmux split-window -h         -t "$SESSION:shell.bottom" -c "$ROOT"

  # Label bottom panes and launch test runner
  tmux select-pane  -t "$SESSION:shell.bottom-left"  -T "test"
  tmux select-pane  -t "$SESSION:shell.bottom-right" -T "git"
  tmux send-keys    -t "$SESSION:shell.bottom-left"  'go test -v ./...' Enter

  # Focus top pane (main shell for go build/run)
  tmux select-pane  -t "$SESSION:shell.top"
}

# ── Window: Debug ─────────────────────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │         delve / dlv dap             │
#  └────────────────────┬────────────────┘
#  │  program output    │  watch / logs  │
#  └────────────────────┴────────────────┘
#
build_debug() {
  tmux split-window -v -l 35% -t "$SESSION:debug" -c "$ROOT"
  tmux split-window -h         -t "$SESSION:debug.bottom" -c "$ROOT"

  tmux select-pane  -t "$SESSION:debug.top"    -T "dlv"
  tmux select-pane  -t "$SESSION:debug.bottom-left"  -T "output"
  tmux select-pane  -t "$SESSION:debug.bottom-right" -T "logs"

  # Start watching test output by default in logs pane
  tmux send-keys    -t "$SESSION:debug.bottom-right" \
    'echo "tail -f app.log  |  or:  go test -v ./... 2>&1 | tee /tmp/gotest.log"' Enter

  tmux select-pane  -t "$SESSION:debug.top"
}

# ── Create the session (or, with --refresh, only the missing windows) ─────────
if [ "$SESSION_EXISTS" -eq 0 ]; then
  tmux new-session -d -s "$SESSION" -n "editor" -c "$ROOT"
  build_editor
  PREV="editor"
else
  echo "Refreshing session '$SESSION' — existing windows are left untouched."
fi

for win in editor claude copilot opencode shell debug; do
  if window_exists "$win"; then
    PREV="$win"
    continue
  fi
  echo "Adding missing window '$win'."
  new_win "$win"
  "build_$win"
  PREV="$win"
done

# ── Land on editor, pane 1 (fresh sessions only) ──────────────────────────────
if [ "$SESSION_EXISTS" -eq 0 ]; then
  tmux select-window -t "$SESSION:editor"
  tmux select-pane   -t "$SESSION:editor.left"
fi

tmux_cmd
