#!/usr/bin/env bash
# monitor_handoff.sh — emit ONE stdout line per NEW handoff section matching a
# tag. Designed to be run by the **Monitor tool with persistent:true**: each new
# section becomes a model notification, the loop NEVER exits, so the listener
# needs NO re-arming and reacts autonomously (no user action) for the whole
# session.
#
# Why this AND handoff_watch.sh (they are complementary, not duplicates):
#   `run_in_background` re-invokes the model only when the task EXITS. That is
#   correct for "wait for ONE reply, then continue" (handoff_watch.sh) — but
#   WRONG for an always-on inbox:
#     - a never-exiting `--loop` watcher never exits, so it never notifies;
#     - a one-shot watcher that exits-to-notify must be re-armed after every
#       message, and the model reliably forgets → silent deafness.
#   The Monitor tool emits a notification per stdout line WITHOUT the script
#   exiting, so an always-on listener needs no re-arm. Use:
#     - handoff_watch.sh / background-wait  → block for ONE expected reply
#     - monitor_handoff.sh via Monitor      → continuous always-on listening
#
# Usage (run via the Monitor tool, persistent:true):
#   monitor_handoff.sh <file>:<tag> [<file2>:<tag2> ...]
#   monitor_handoff.sh <file> <tag>              # legacy 2-arg form
#   monitor_handoff.sh                           # no args → read ./.handoff_channels
# <tag> may be a regex, matched inside the "## [<tag>] ..." header, e.g.
#   '.*(->|→)me'  (a broadcast inbox that double-matches ASCII -> and unicode →).
#
# .handoff_channels: one `file:tag` per line ('#' comments allowed) — a per-agent
# config so "which channels I listen to" lives in the agent's dir, not in args.
#
# Test mode: MONITOR_HANDOFF_ONCE=1 → single detection pass (no loop, no sleep);
# re-baselines to 0 so already-present sections count as "new". For tests.
set -u
INTERVAL="${MONITOR_HANDOFF_INTERVAL:-15}"

declare -a FILES TAGS LAST
add_pair() { FILES+=("$1"); TAGS+=("$2"); LAST+=(0); }

if [ "$#" -eq 0 ]; then
  CONF="./.handoff_channels"
  if [ ! -f "$CONF" ]; then
    echo "[monitor_handoff] no args and no ./.handoff_channels — nothing to watch" >&2
    exit 1
  fi
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue;; esac
    add_pair "${line%%:*}" "${line##*:}"
  done < "$CONF"
elif [ "$#" -eq 2 ] && [ "${1#*:}" = "$1" ]; then
  # legacy 2-arg form: <file> <tag>  (only when $1 has no colon)
  add_pair "$1" "$2"
else
  for arg in "$@"; do
    case "$arg" in
      *:*) add_pair "${arg%%:*}" "${arg##*:}";;
      *) echo "[monitor_handoff] arg '$arg' must be <file>:<tag>" >&2; exit 2;;
    esac
  done
fi
[ "${#FILES[@]}" -eq 0 ] && { echo "[monitor_handoff] no file:tag pairs" >&2; exit 1; }

hdr() { printf '^## \\[%s\\]' "$1"; }

# Baseline to current counts so we don't dump history on arm.
for i in "${!FILES[@]}"; do
  LAST[$i]=$(grep -cE "$(hdr "${TAGS[$i]}")" "${FILES[$i]}" 2>/dev/null || echo 0)
done

scan_once() {
  local i f t cur
  for i in "${!FILES[@]}"; do
    f="${FILES[$i]}"; t="${TAGS[$i]}"
    cur=$(grep -cE "$(hdr "$t")" "$f" 2>/dev/null || echo 0)
    if [ "${cur:-0}" -gt "${LAST[$i]:-0}" ]; then
      echo "📨 $((cur - LAST[i])) new [$t] message(s) in $f — read its tail:"
      grep -E "$(hdr "$t")" "$f" 2>/dev/null | tail -n "$((cur - LAST[i]))"
      LAST[$i]="$cur"
    fi
  done
}

if [ "${MONITOR_HANDOFF_ONCE:-0}" = "1" ]; then
  for i in "${!FILES[@]}"; do LAST[$i]=0; done
  scan_once
  exit 0
fi

while true; do
  scan_once
  sleep "$INTERVAL"
done
