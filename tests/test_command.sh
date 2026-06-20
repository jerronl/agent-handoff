#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
C="$(cd "$(dirname "$0")/.." && pwd)/commands/handoff.md"
test -f "$C" && pass "command file exists" || fail "missing command"
for sub in post read watch; do
  grep -q "handoff_${sub}.sh\|/handoff ${sub}\|^### ${sub}\| ${sub} " "$C" \
    && pass "documents $sub" || fail "missing $sub"
done
