#!/usr/bin/env bash
# bg_wait.sh — poll a condition command until it succeeds (rc 0) or times out.
# Usage: bg_wait.sh [--interval N] [--timeout N] -- <condition-cmd...>
#   exit 0 = condition met; 1 = timeout; 2 = usage error.
# Pair with the harness's run_in_background so the agent is re-invoked on exit.
set -u
interval=10; timeout=600
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="${2:?}"; shift 2;;
    --timeout)  timeout="${2:?}";  shift 2;;
    --) shift; break;;
    *) echo "usage: bg_wait.sh [--interval N] [--timeout N] -- <cmd...>" >&2; exit 2;;
  esac
done
[ $# -ge 1 ] || { echo "bg_wait: no condition command" >&2; exit 2; }
elapsed=0
while :; do
  if "$@"; then exit 0; fi
  [ "$elapsed" -ge "$timeout" ] && { echo "bg_wait: timeout after ${timeout}s" >&2; exit 1; }
  sleep "$interval"; elapsed=$((elapsed + interval))
done
