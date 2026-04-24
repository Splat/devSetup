#!/usr/bin/env bash
# =============================================================================
# dev-session.sh — launch (or attach to) a persistent Go dev tmux session
#
# Usage:
#   ./dev-session.sh [project-root]
#
# If a session named "dev" already exists, attaches to it.
# Otherwise creates the full layout from scratch.
# =============================================================================

set -euo pipefail

SESSION="dev"
ROOT="${1:-$HOME/code}"   # override with first arg or set your default here

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
