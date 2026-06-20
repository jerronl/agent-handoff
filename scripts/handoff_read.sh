#!/usr/bin/env bash
# handoff_read.sh — print the LATEST tagged section of a handoff file,
# or all sections whose header contains <tag-substr>.
# Usage: handoff_read.sh <file> [tag-substr]
set -u
file="${1:?file}"; tagsub="${2:-}"
[ -f "$file" ] || { echo "handoff_read: no such file: $file" >&2; exit 2; }
if [ -n "$tagsub" ]; then
  awk -v t="$tagsub" '/^## \[/{keep=(index($0,t)>0)} keep' "$file"
else
  awk '/^## \[/{last=NR} {a[NR]=$0} END{for(i=last;i<=NR;i++) print a[i]}' "$file"
fi
