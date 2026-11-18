#!/usr/bin/env bash
# =============================================================================
# dev-session-sidebar.sh — task list shown in the left pane of the "ai" window
#
# Usage: dev-session-sidebar <tmux-session> <project-root>
#
# Lists the git worktrees under <repo>/.worktrees (created by `dev-session --task`)
# with their agent and state. Phase 1 is read-only apart from jumping to a
# task's window.
#
#   j / k, arrows   move selection
#   Enter           jump to the selected task's window
#   r               refresh now
#
# State comes from the task window's last output time:
#   working  output within DEV_SESSION_IDLE_SECS (default 20)
#   idle     quiet for longer: finished or waiting on you
#   stopped  worktree exists but its window is gone
# =============================================================================

set -u

SESSION="${1:?usage: dev-session-sidebar <tmux-session> <project-root>}"
START_DIR="${2:?usage: dev-session-sidebar <tmux-session> <project-root>}"
IDLE_SECS="${DEV_SESSION_IDLE_SECS:-20}"
REFRESH_SECS=2

BOLD=$'\e[1m'; DIM=$'\e[90m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; REV=$'\e[7m'; RESET=$'\e[0m'

REPO_ROOT=""
if common="$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  REPO_ROOT="$(dirname "$common")"
fi

RULE='────────────────────────────────────────────────────────────'
sel=0
last_frame=""
NAMES=(); LINES2=()

cleanup() { printf '\e[?25h'; }
trap cleanup EXIT
trap 'last_frame=""' WINCH
printf '\e[?25l'

# Fills NAMES (task names) and LINES2 (second display line per task)
collect() {
  NAMES=(); LINES2=()
  [ -n "$REPO_ROOT" ] || return 0

  local now wins panes line path name win act agent state dirty
  now="$(date +%s)"
  wins="$(tmux list-windows -t "=$SESSION" -F '#{window_name} #{window_activity}' 2>/dev/null)"
  panes="$(tmux list-panes -s -t "=$SESSION" -F '#{window_name} #{pane_title}' 2>/dev/null)"

  while IFS= read -r line; do
    case "$line" in
      "worktree $REPO_ROOT/.worktrees/"*) path="${line#worktree }" ;;
      *) continue ;;
    esac
    name="${path##*/}"
    win="t-${name//[.:]/_}"

    act="$(printf '%s\n' "$wins" | awk -v n="$win" '$1 == n { print $2; exit }')"
    agent="$(printf '%s\n' "$panes" | awk -v n="$win" '$1 == n { print $2; exit }')"
    if [ -z "$act" ]; then
      state="${DIM}○ stopped${RESET}"
    elif [ $((now - act)) -le "$IDLE_SECS" ]; then
      state="${GREEN}● working${RESET}"
    else
      state="${YELLOW}◐ idle${RESET}"
    fi
    dirty=""
    [ -z "$(git -C "$path" status --porcelain 2>/dev/null | head -1)" ] || dirty=" ${YELLOW}*${RESET}"

    NAMES+=("$name")
    LINES2+=("   $state ${DIM}${agent}${RESET}${dirty}")
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)
}

build_frame() {
  local i cols
  cols="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_width}' 2>/dev/null || echo 28)"
  FRAME="${BOLD} AI tasks${RESET}"$'\n'"${DIM}${RULE:0:$((cols - 1))}${RESET}"$'\n'

  if [ -z "$REPO_ROOT" ]; then
    FRAME+="${DIM} not a git repo${RESET}"$'\n'
  elif [ "${#NAMES[@]}" -eq 0 ]; then
    FRAME+="${DIM} no tasks yet${RESET}"$'\n'
    FRAME+="${DIM} dev-session --task <name>${RESET}"$'\n'
  else
    [ "$sel" -lt "${#NAMES[@]}" ] || sel=$((${#NAMES[@]} - 1))
    for i in "${!NAMES[@]}"; do
      local n="${NAMES[$i]}"
      n="${n:0:$((cols - 4))}"
      if [ "$i" -eq "$sel" ]; then
        FRAME+="${REV} ▸ ${n}$(printf '%*s' $((cols - ${#n} - 4)) '')${RESET}"$'\n'
      else
        FRAME+="   ${n}"$'\n'
      fi
      FRAME+="${LINES2[$i]}"$'\n'
    done
  fi

  FRAME+=$'\n'"${DIM} j/k move  ⏎ jump${RESET}"$'\n'
}

# Redraw only when something changed, so an idle sidebar produces no output
# (output would otherwise reset the window's activity time).
draw() {
  [ "$FRAME" != "$last_frame" ] || return 0
  last_frame="$FRAME"
  printf '\e[H'
  while IFS= read -r line; do printf '%s\e[K\n' "$line"; done <<< "$FRAME"
  printf '\e[J'
}

while true; do
  collect
  build_frame
  draw

  key=""
  if IFS= read -rsn1 -t "$REFRESH_SECS" key; then
    action=""
    case "$key" in
      "") action=enter ;;   # Enter arrives as an empty read
      j) action=down ;;
      k) action=up ;;
      r) action=refresh ;;
      $'\e')
        IFS= read -rsn2 -t 1 rest || rest=""
        case "$rest" in
          '[A') action=up ;;
          '[B') action=down ;;
        esac
        ;;
    esac
    case "$action" in
      down) [ "$sel" -lt $((${#NAMES[@]} - 1)) ] && sel=$((sel + 1)) ;;
      up) [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
      refresh) last_frame="" ;;
      enter)
        if [ "${#NAMES[@]}" -gt 0 ]; then
          n="${NAMES[$sel]}"
          tmux select-window -t "=$SESSION:t-${n//[.:]/_}" 2>/dev/null || true
        fi
        ;;
    esac
  fi
done
