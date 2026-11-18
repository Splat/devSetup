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
#   ./dev-session.sh --task <name> [claude|copilot|opencode]
#   ./dev-session.sh --task-done <name>
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
  --task <name> [agent]
                      Create a git worktree (.worktrees/<name>, branch task/<name>,
                      based on the current branch) and open a window for it in the
                      running session with an agent: claude (default), copilot, opencode
  --task-done <name>  Remove that worktree and window (refuses if it has uncommitted
                      changes; the branch is kept)
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
  dev-session.sh --task fix-login          # New worktree + window running claude
  dev-session.sh --task fix-login opencode # Same, with opencode
  dev-session.sh --task-done fix-login     # Remove the worktree and window
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

# ── Task worktrees ────────────────────────────────────────────────────────────
# Sets REPO_ROOT, GIT_COMMON and TASK_SESSION for --task / --task-done.
task_context() {
  GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    echo "Error: not inside a git repository." >&2
    exit 1
  }
  REPO_ROOT="$(dirname "$GIT_COMMON")"
  if [ -n "${TMUX:-}" ]; then
    TASK_SESSION="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{session_name}')"
  else
    TASK_SESSION="$(resolve_session "$(dir_session_name "$REPO_ROOT")")"
  fi
  if ! tmux has-session -t "=$TASK_SESSION" 2>/dev/null; then
    echo "Error: session '$TASK_SESSION' is not running. Start it with dev-session first." >&2
    exit 1
  fi
}

check_task_name() {
  if [[ ! "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: task name must be letters, digits, '.', '_' or '-' (got '${1:-}')." >&2
    exit 1
  fi
}

# tmux treats '.' and ':' specially in targets
task_window_name() { echo "t-${1//[.:]/_}"; }

task_window_id() {
  tmux list-windows -t "=$TASK_SESSION" -F '#{window_id} #{window_name}' |
    awk -v n="$1" '$2 == n { print $1; exit }'
}

start_task() {
  local name="${1:-}" agent="${2:-claude}"
  check_task_name "$name"
  case "$agent" in
    claude|copilot|opencode) ;;
    *) echo "Error: agent must be claude, copilot or opencode (got '$agent')." >&2; exit 1 ;;
  esac
  task_context

  local wt="$REPO_ROOT/.worktrees/$name" branch="task/$name" win existing=0 wid
  win="$(task_window_name "$name")"

  wid="$(task_window_id "$win")"
  if [ -n "$wid" ]; then
    tmux select-window -t "$wid"
    echo "Task '$name' already has a window; selected it."
    return
  fi

  if [ -d "$wt" ]; then
    existing=1
  else
    mkdir -p "$REPO_ROOT/.worktrees" "$GIT_COMMON/info"
    grep -qxF '.worktrees/' "$GIT_COMMON/info/exclude" 2>/dev/null ||
      echo '.worktrees/' >> "$GIT_COMMON/info/exclude"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git worktree add "$wt" "$branch"
    else
      git worktree add -b "$branch" "$wt" HEAD
    fi
  fi

  # A fresh worktree has no conversation to resume
  local cmd="$agent"
  [ "$existing" -eq 1 ] && cmd="$agent --continue"
  [ "$existing" -eq 1 ] && [ "$agent" != "opencode" ] && cmd="$agent --continue || $agent"

  local agent_pane shell_pane
  agent_pane="$(tmux new-window -d -P -F '#{pane_id}' -t "=$TASK_SESSION:" -n "$win" -c "$wt")"
  shell_pane="$(tmux split-window -h -l 30% -P -F '#{pane_id}' -t "$agent_pane" -c "$wt")"
  tmux select-pane -t "$agent_pane" -T "$agent"
  tmux select-pane -t "$shell_pane" -T "shell"
  tmux select-pane -t "$agent_pane"
  tmux set-option -w -t "$agent_pane" monitor-silence "$IDLE_SECS"
  tmux send-keys -t "$agent_pane" "$cmd" Enter

  echo "Task '$name': worktree $wt (branch $branch), window '$win' running $agent."
}

finish_task() {
  local name="${1:-}"
  check_task_name "$name"
  task_context

  local wt="$REPO_ROOT/.worktrees/$name" wid
  if [ ! -d "$wt" ]; then
    echo "Error: no worktree at $wt." >&2
    exit 1
  fi
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    echo "Error: '$name' has uncommitted changes. Commit or discard them first." >&2
    exit 1
  fi

  git worktree remove "$wt"
  echo "Removed worktree $wt. Branch task/$name was kept."

  # Last: this may be the window the command is running in
  wid="$(task_window_id "$(task_window_name "$name")")"
  [ -z "$wid" ] || tmux kill-window -t "$wid"
}

IDLE_SECS="${DEV_SESSION_IDLE_SECS:-20}"   # seconds of silence before an agent window is flagged

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
  --task)
    start_task "${2:-}" "${3:-claude}"
    exit 0
    ;;
  --task-done)
    finish_task "${2:-}"
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
  # Resume this directory's last conversation (e.g. after a reboot); start fresh if none
  tmux send-keys -t "$SESSION:claude" 'claude --continue || claude' Enter
}

# ── Window: GitHub Copilot CLI ────────────────────────────────────────────────
#  brew install copilot-cli   (then /login on first run)
#  ┌─────────────────────────────────────┐
#  │        copilot (full width)         │
#  └─────────────────────────────────────┘
#
build_copilot() {
  # Resume the most recent session (e.g. after a reboot); start fresh if none
  tmux send-keys -t "$SESSION:copilot" 'copilot --continue || copilot' Enter
}

# ── Window: opencode ──────────────────────────────────────────────────────────
#  brew install opencode   (then `opencode auth login` on first run)
#  ┌─────────────────────────────────────┐
#  │        opencode (full width)        │
#  └─────────────────────────────────────┘
#
build_opencode() {
  # Resume the last session (e.g. after a reboot); opencode starts fresh if there is none
  tmux send-keys -t "$SESSION:opencode" 'opencode --continue' Enter
}

# ── Window: Shell / go commands ───────────────────────────────────────────────
#
#  ┌─────────────────────────────────────┐
#  │         go build / test / run       │
#  └────────────────────┬────────────────┘
#  │     go test -v     │    lazygit     │
#  └────────────────────┴────────────────┘
#
build_shell() {
  tmux split-window -v -l 35% -t "$SESSION:shell" -c "$ROOT"
  tmux split-window -h         -t "$SESSION:shell.bottom" -c "$ROOT"

  # Label bottom panes and launch test runner
  tmux select-pane  -t "$SESSION:shell.bottom-left"  -T "test"
  tmux select-pane  -t "$SESSION:shell.bottom-right" -T "git"
  tmux send-keys    -t "$SESSION:shell.bottom-left"  'go test -v ./...' Enter
  tmux send-keys    -t "$SESSION:shell.bottom-right" 'command -v lazygit &>/dev/null && lazygit' Enter

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

# ── Window: AI (task sidebar) ─────────────────────────────────────────────────
#
#  ┌────────┬────────────────────────────┐
#  │ tasks  │                            │
#  │ (list  │   shell (placeholder for   │
#  │  of    │   the selected agent)      │
#  │ worktrees)                          │
#  └────────┴────────────────────────────┘
#
build_ai() {
  local sidebar here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for sidebar in "$here/dev-session-sidebar" "$here/dev-session-sidebar.sh" "$(command -v dev-session-sidebar 2>/dev/null)"; do
    [ -n "$sidebar" ] && [ -x "$sidebar" ] && break
    sidebar=""
  done
  if [ -z "$sidebar" ]; then
    echo "dev-session-sidebar not found; ai window left as a plain shell (run install.sh)." >&2
    return 0
  fi

  local pane
  pane="$(tmux split-window -h -b -l 28 -P -F '#{pane_id}' -t "$SESSION:ai" -c "$ROOT")"
  tmux select-pane -t "$pane" -T "tasks"
  tmux send-keys -t "$pane" "$(printf '%q %q %q' "$sidebar" "$SESSION" "$ROOT")" Enter
  tmux select-pane -t "$SESSION:ai.right"
}

# ── Create the session (or, with --refresh, only the missing windows) ─────────
if [ "$SESSION_EXISTS" -eq 0 ]; then
  tmux new-session -d -s "$SESSION" -n "editor" -c "$ROOT"
  build_editor
  PREV="editor"
else
  echo "Refreshing session '$SESSION' — existing windows are left untouched."
fi

for win in editor claude copilot opencode shell debug ai; do
  if window_exists "$win"; then
    PREV="$win"
    continue
  fi
  echo "Adding missing window '$win'."
  new_win "$win"
  "build_$win"
  PREV="$win"
done

# Flag agent windows in the status bar once they go quiet (finished or waiting on you).
# Applied to existing windows too, so --refresh enables it on running sessions.
for win in claude copilot opencode; do
  window_exists "$win" && tmux set-option -w -t "$SESSION:$win" monitor-silence "$IDLE_SECS"
done

# ── Land on editor, pane 1 (fresh sessions only) ──────────────────────────────
if [ "$SESSION_EXISTS" -eq 0 ]; then
  tmux select-window -t "$SESSION:editor"
  tmux select-pane   -t "$SESSION:editor.left"
fi

tmux_cmd
