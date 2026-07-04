#!/usr/bin/env bash
# handoff_bots.sh — a pluggable roster for launching / restarting / checking the agents
# in a handoff conversation. The plugin owns the GENERIC parts (roster parsing, liveness
# via pgrep, a handoff-level "is it behind on its inbox" heuristic); the ENVIRONMENT-
# specific part — how to actually spawn an agent (Windows Terminal, tmux, screen, ssh,
# a launcher script…) — is a command YOU register per bot. The plugin cannot know how to
# start a session in an arbitrary environment, so it delegates.
#
# Roster file `.handoff_bots` (walked up from cwd), one bot per line, `#` comments ok:
#   <name> | <pgrep_pattern> | <inbox_file> | <launch_command>
#     name           short id used in commands / headers
#     pgrep_pattern   matches the bot's process (for liveness + restart kill); '-' = skip
#     inbox_file      the bot's inbox handoff file (for the behind-on-inbox heuristic); '-' = skip
#     launch_command  shell command that starts the bot (eval'd); '-' = not launchable here
#   Example:
#     docs | monitor_inbox .*_inbox_docs | /proj/_inbox_docs.md | wt new-tab --title docs bash -lc 'cd /proj && claude'
#
# Commands:
#   handoff_bots.sh list                 roster + alive + inbox-lag, one row per bot
#   handoff_bots.sh status [name]        same as list, or detail for one bot
#   handoff_bots.sh waiting [name]       print bots that look idle/behind (alive + unread inbox)
#   handoff_bots.sh start <name>         run the bot's launch_command
#   handoff_bots.sh restart <name>       pkill the pgrep_pattern, then run launch_command
#
# "Is it waiting for input?" — there is no portable OS signal for "an agent is blocked at a
# prompt". This tool uses a handoff-level PROXY: a bot is flagged when it is alive AND its
# inbox has a section newer than the last section IT sent (i.e. it received something it has
# not answered). That catches "stalled / needs a nudge"; it does not read the terminal.
set -u

find_roster() {
  local d="${1:-$PWD}"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.handoff_bots" ] && { printf '%s' "$d/.handoff_bots"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

ROSTER="$(find_roster || true)"
[ -z "$ROSTER" ] && { echo "handoff_bots: no .handoff_bots roster found up-tree from $PWD" >&2; exit 1; }

# Split "a | b | c | d" into the global fields F_name/F_pat/F_inbox/F_cmd (trimmed).
_parse_line() {
  local IFS='|' ; read -r F_name F_pat F_inbox F_cmd <<EOF
$1
EOF
  F_name="$(printf '%s' "${F_name:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  F_pat="$(printf '%s' "${F_pat:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  F_inbox="$(printf '%s' "${F_inbox:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  F_cmd="$(printf '%s' "${F_cmd:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
}

# Alive? echoes count of matching processes (0 = dead / not-checkable).
_alive() {
  [ "$1" = "-" ] && { echo "-"; return; }
  command -v pgrep >/dev/null 2>&1 || { echo "?"; return; }
  pgrep -fc -- "$1" 2>/dev/null || echo 0
}

# Behind-on-inbox? "yes" if inbox has a section newer (further down the file) than this
# bot's own most-recent outgoing section (`## [<name>->`). Append-only files => file order
# is time order, so "an inbox section after my last reply" = unanswered inbound.
_behind() {
  local name="$1" inbox="$2"
  { [ "$inbox" = "-" ] || [ ! -f "$inbox" ]; } && { echo "-"; return; }
  local last_self last_any
  last_self="$(grep -nE "^## \[$name->" "$inbox" 2>/dev/null | tail -n1 | cut -d: -f1)"
  last_any="$(grep -nE '^## \[' "$inbox" 2>/dev/null | tail -n1 | cut -d: -f1)"
  [ -z "$last_any" ] && { echo "no"; return; }          # empty inbox
  [ -z "$last_self" ] && { echo "yes"; return; }         # never replied but has inbound
  [ "$last_any" -gt "$last_self" ] && echo "yes" || echo "no"
}

_row() {
  _parse_line "$1"
  [ -z "$F_name" ] && return
  printf '%-12s alive=%-3s behind=%-3s %s\n' \
    "$F_name" "$(_alive "$F_pat")" "$(_behind "$F_name" "$F_inbox")" \
    "$([ "$F_cmd" = "-" ] && echo '(no launch cmd)' || echo 'launchable')"
}

_each() { grep -vE '^[[:space:]]*(#|$)' "$ROSTER"; }

_find() {  # echo the raw roster line for <name>, or nothing
  local want="$1" line
  while IFS= read -r line; do
    _parse_line "$line"; [ "$F_name" = "$want" ] && { printf '%s' "$line"; return 0; }
  done < <(_each)
  return 1
}

cmd="${1:-list}"
case "$cmd" in
  list|status)
    if [ -n "${2:-}" ]; then
      line="$(_find "$2")" || { echo "handoff_bots: no bot '$2' in roster" >&2; exit 2; }
      _parse_line "$line"
      echo "name:    $F_name"
      echo "alive:   $(_alive "$F_pat")   (pattern: ${F_pat})"
      echo "behind:  $(_behind "$F_name" "$F_inbox")   (inbox: ${F_inbox})"
      echo "launch:  ${F_cmd}"
    else
      while IFS= read -r line; do _row "$line"; done < <(_each)
    fi
    ;;
  waiting)
    while IFS= read -r line; do
      _parse_line "$line"; [ -z "$F_name" ] && continue
      [ -n "${2:-}" ] && [ "$F_name" != "$2" ] && continue
      a="$(_alive "$F_pat")"; b="$(_behind "$F_name" "$F_inbox")"
      [ "$b" = "yes" ] && { [ "$a" = "0" ] || printf '%-12s alive=%s behind=yes — has unanswered inbox, may be stalled/waiting\n' "$F_name" "$a"; }
    done < <(_each)
    ;;
  start|restart)
    name="${2:?usage: handoff_bots.sh $cmd <name>}"
    line="$(_find "$name")" || { echo "handoff_bots: no bot '$name' in roster" >&2; exit 2; }
    _parse_line "$line"
    [ "$F_cmd" = "-" ] && { echo "handoff_bots: '$name' has no launch_command (not launchable here)" >&2; exit 3; }
    if [ "$cmd" = "restart" ] && [ "$F_pat" != "-" ]; then
      echo "handoff_bots: killing '$name' ($F_pat)"; pkill -f -- "$F_pat" 2>/dev/null || true; sleep 1
    fi
    echo "handoff_bots: launching '$name': $F_cmd"
    eval "$F_cmd"
    ;;
  *)
    echo "usage: handoff_bots.sh {list|status [name]|waiting [name]|start <name>|restart <name>}" >&2
    exit 64
    ;;
esac
