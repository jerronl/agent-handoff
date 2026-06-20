#!/usr/bin/env bash
# handoff_watch.sh — background-wait until a NEW section with the given reply tag
# appears, then print it. Engine: bg_wait.sh (the background-wait pattern).
# Usage: handoff_watch.sh <file> <reply-tag> [timeout_sec] [interval_sec]
#   <reply-tag> e.g. "agentB->agentA" (matched in the "## [agentB->agentA] ..." header)
set -u
file="${1:?file}"; tag="${2:?reply-tag}"; timeout="${3:-600}"; interval="${4:-15}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# grep -c prints the count AND exits 1 on zero matches; `|| true` swallows the
# exit code (count already on stdout); `${x:-0}` covers a missing file.
base="$(grep -c "^## \[${tag}\]" "$file" 2>/dev/null || true)"; base="${base:-0}"
if "$here/bg_wait.sh" --interval "$interval" --timeout "$timeout" -- \
     bash -c 'f="$1"; tag="$2"; base="$3";
              n="$(grep -c "^## \[${tag}\]" "$f" 2>/dev/null || true)"; n="${n:-0}";
              [ "$n" -gt "$base" ]' _ "$file" "$tag" "$base"; then
  echo "=== new [${tag}] reply ==="
  awk -v t="[${tag}]" '/^## \[/{last=NR} {a[NR]=$0} END{for(i=last;i<=NR;i++) print a[i]}' "$file"
  exit 0
fi
echo "handoff_watch: timeout — no new [${tag}] within ${timeout}s" >&2
exit 1
