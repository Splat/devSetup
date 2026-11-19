#!/usr/bin/env bash
# =============================================================================
# dev-session-sidebar.sh — task list shown in the left pane of the "ai" window
#
# Usage: dev-session-sidebar <tmux-session> <project-root>
#
# Lists the git worktrees under <repo>/.worktrees (created by `dev-session --task`)
# with their agent and state, and creates/ends them by calling `dev-session`.
#
#   j / k, arrows   move selection
#   Enter           show the selected task's agent in the right pane
#   n               new task (asks for a name, then an agent)
#   d               end the selected task (asks to confirm)
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

BOLD=$'\e[1m'; DIM=$'\e[90m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'

REPO_ROOT=""
if common="$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  REPO_ROOT="$(dirname "$common")"
fi

RULE='────────────────────────────────────────────────────────────'
sel=0
last_frame=""
MSG=""
LAST_RC=0
SHOWN=""; SHOWN_PANE=""; PLACEHOLDER=""
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
    if [ -n "$SHOWN_PANE" ] && [ "$name" = "$SHOWN" ]; then
      act="$(printf '%s\n' "$wins" | awk '$1 == "ai" { print $2; exit }')"
      agent="$(tmux display-message -p -t "$SHOWN_PANE" '#{pane_title}' 2>/dev/null)"
    fi
    case "$agent" in GitHub*) agent=copilot ;; esac
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
    LINES2+=("    $state ${DIM}${agent}${RESET}${dirty}")
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)
}

build_frame() {
  local i cols
  cols="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_width}' 2>/dev/null || echo 28)"
  FRAME="  ${BOLD}AI tasks${RESET}"$'\n'"  ${DIM}${RULE:0:$((cols - 4))}${RESET}"$'\n'

  if [ -z "$REPO_ROOT" ]; then
    FRAME+="  ${DIM}not a git repo${RESET}"$'\n'
  elif [ "${#NAMES[@]}" -eq 0 ]; then
    FRAME+="  ${DIM}no tasks yet - press${RESET} ${BOLD}n${RESET}"$'\n'
  else
    [ "$sel" -lt "${#NAMES[@]}" ] || sel=$((${#NAMES[@]} - 1))
    for i in "${!NAMES[@]}"; do
      local n="${NAMES[$i]}"
      n="${n:0:$((cols - 6))}"
      if [ "$i" -eq "$sel" ]; then
        FRAME+="${BOLD}${GREEN}▸ ${n}${RESET}"$'\n'
      else
        FRAME+="  ${n}"$'\n'
      fi
      FRAME+="${LINES2[$i]}"$'\n'
    done
  fi

  if [ -n "$MSG" ]; then
    FRAME+=$'\n'
    while IFS= read -r line; do FRAME+="  ${YELLOW}${line}${RESET}"$'\n'; done < <(printf '%s\n' "$MSG" | fold -s -w $((cols - 4)))
  fi
  FRAME+=$'\n'"  ${DIM}n${RESET} new  ${DIM}d${RESET} end"$'\n'"  ${DIM}j/k${RESET} move  ${DIM}⏎${RESET} open"$'\n'
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

DEV_SESSION="$(dirname "${BASH_SOURCE[0]}")/dev-session"
[ -x "$DEV_SESSION" ] || DEV_SESSION="$(command -v dev-session 2>/dev/null || true)"

# Read a line on the bottom row of the pane (typing is echoed there)
prompt() {
  local rows
  rows="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_height}' 2>/dev/null || echo 24)"
  printf '\e[%d;1H\e[K\e[?25h' "$rows"
  IFS= read -r -e -p "  $1" REPLY || REPLY=""
  printf '\e[?25l'
  last_frame=""
}

run_dev_session() {
  local out
  LAST_RC=0
  out="$(cd "$START_DIR" && "$DEV_SESSION" "$@" 2>&1)" || LAST_RC=$?
  MSG="$(printf '%s\n' "$out" | grep -v '^$' | tail -1)"
}

# The agent shown in the right slot lives in the ai window; its home window
# holds the placeholder shell meanwhile. Swapping back restores both.
unshow() {
  if [ -n "$SHOWN_PANE" ]; then
    tmux swap-pane -d -s "$SHOWN_PANE" -t "$PLACEHOLDER" 2>/dev/null || true
  fi
  SHOWN=""; SHOWN_PANE=""
}

show_task() {
  local n="$1" win agent_pane
  win="t-${n//[.:]/_}"
  if [ "$n" = "$SHOWN" ] && [ -n "$SHOWN_PANE" ]; then
    tmux select-pane -t "$SHOWN_PANE" 2>/dev/null || true
    return 0
  fi
  agent_pane="$(tmux list-panes -t "=$SESSION:$win" -F '#{pane_id}' 2>/dev/null | head -1)"
  if [ -z "$agent_pane" ]; then
    MSG="$n is stopped (no window)"
    return 0
  fi
  if [ -z "$PLACEHOLDER" ]; then
    PLACEHOLDER="$(tmux list-panes -t "=$SESSION:ai" -F '#{pane_id}' 2>/dev/null | grep -vx "${TMUX_PANE:-}" | head -1)"
    [ -n "$PLACEHOLDER" ] || { MSG="no right pane to swap into"; return 0; }
  fi
  unshow
  tmux swap-pane -d -s "$agent_pane" -t "$PLACEHOLDER" && SHOWN="$n" && SHOWN_PANE="$agent_pane"
  tmux select-pane -t "$agent_pane" 2>/dev/null || true
}

new_task() {
  local name agent
  prompt "task name: "; name="$REPLY"
  [ -n "$name" ] || return 0
  prompt "agent (c/p/o, ⏎=claude): "
  case "${REPLY:-claude}" in
    c|claude) agent=claude ;;
    p|g|copilot) agent=copilot ;;
    o|opencode) agent=opencode ;;
    *) MSG="unknown agent '$REPLY' (use c, p or o)"; return 0 ;;
  esac
  MSG="creating $name..."; last_frame=""; build_frame; draw
  run_dev_session --task "$name" "$agent"
  [ "$LAST_RC" -ne 0 ] || MSG="started $name ($agent)"
}

end_task() {
  [ "${#NAMES[@]}" -gt 0 ] || return 0
  local n="${NAMES[$sel]}"
  prompt "end $n? [y/N] "
  case "$REPLY" in
    y|Y|yes) [ "$n" != "$SHOWN" ] || unshow
             run_dev_session --task-done "$n"; [ "$LAST_RC" -ne 0 ] || MSG="ended $n" ;;
    *) MSG="" ;;
  esac
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
      n) action=new ;;
      d) action=end ;;
      $'\e')
        IFS= read -rsn2 -t 1 rest || rest=""
        case "$rest" in
          '[A'|'OA') action=up ;;
          '[B'|'OB') action=down ;;
        esac
        ;;
    esac
    [ "$action" = "" ] || [ "$action" = new ] || [ "$action" = end ] || MSG=""
    case "$action" in
      new) new_task ;;
      end) end_task ;;
      down) [ "$sel" -lt $((${#NAMES[@]} - 1)) ] && sel=$((sel + 1)) ;;
      up) [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
      refresh) last_frame="" ;;
      enter)
        if [ "${#NAMES[@]}" -gt 0 ]; then
          n="${NAMES[$sel]}"
          show_task "$n"
        fi
        ;;
    esac
  fi
done
