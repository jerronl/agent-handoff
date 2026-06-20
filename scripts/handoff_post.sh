#!/usr/bin/env bash
# handoff_post.sh — append a tagged, append-only message section to a handoff file.
# Body is read from STDIN and written LITERALLY (no shell expansion).
# Usage: printf '%s' "<body>" | handoff_post.sh <file> <from> <to> [subject]
#   header: "## [<from>-><to>] <UTC ts> [subject]"   (ASCII '->' so watchers grep it)
set -u
file="${1:?file}"; from="${2:?from}"; to="${3:?to}"; subject="${4:-}"
dir="$(dirname "$file")"
[ -d "$dir" ] || { echo "handoff_post: directory missing: $dir" >&2; exit 2; }
ts="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
body="$(cat)"
{
  printf '\n## [%s->%s] %s %s\n\n' "$from" "$to" "$ts" "$subject"
  printf '%s\n' "$body"
} >> "$file"
echo "posted [$from->$to] -> $file"
