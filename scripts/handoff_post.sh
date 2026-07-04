#!/usr/bin/env bash
# handoff_post.sh — append a tagged, append-only message section to a handoff file.
# Body is read from STDIN and written LITERALLY (no shell expansion).
# Usage: printf '%s' "<body>" | handoff_post.sh <file> <from> <to> [subject]
#   header: "## [<from>-><to>] <UTC ts> [subject]"   (ASCII '->' so watchers grep it)
#
# Optional CC (opt-in): also append the same section to a CC file so an orchestrator /
# coordinator sees ALL traffic without being an explicit recipient. CC target resolves
# from (first wins):
#   1. $HANDOFF_CC_FILE            — explicit path (per-invocation override)
#   2. a `.handoff_cc` file walked up from the handoff file's directory — its first
#      non-comment line is the CC target path (persistent "always CC" for a project)
# Unset => no CC (default). The CC is skipped when it resolves to the target file itself.
set -u
file="${1:?file}"; from="${2:?from}"; to="${3:?to}"; subject="${4:-}"
dir="$(dirname "$file")"
[ -d "$dir" ] || { echo "handoff_post: directory missing: $dir" >&2; exit 2; }
ts="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
body="$(cat)"

# Build the section once so the primary post and the CC are byte-identical.
section="$(printf '\n## [%s->%s] %s %s\n\n%s\n' "$from" "$to" "$ts" "$subject" "$body")"
printf '%s' "$section" >> "$file"
echo "posted [$from->$to] -> $file"

# Absolute path of an existing-or-creatable file (dir must exist), for de-dup compare.
_abs() { local d; d="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 1; printf '%s/%s' "$d" "$(basename "$1")"; }

# Resolve CC target.
cc="${HANDOFF_CC_FILE:-}"
if [ -z "$cc" ]; then
  d="$dir"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/.handoff_cc" ]; then
      cc="$(grep -vE '^\s*(#|$)' "$d/.handoff_cc" 2>/dev/null | head -n1 | sed 's/[[:space:]]*$//')"
      break
    fi
    d="$(dirname "$d")"
  done
fi

if [ -n "$cc" ]; then
  ccdir="$(dirname "$cc")"
  if [ ! -d "$ccdir" ]; then
    echo "handoff_post: CC directory missing, skipped CC: $ccdir" >&2
  elif [ "$(_abs "$cc" 2>/dev/null)" = "$(_abs "$file" 2>/dev/null)" ]; then
    :   # CC resolves to the target file itself — already posted, skip
  else
    printf '%s' "$section" >> "$cc"
    echo "cc [$from->$to] -> $cc"
  fi
fi
