#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
S="$(cd "$(dirname "$0")/.." && pwd)/skills/handoff-coordination"
head -1 "$S/SKILL.md" | grep -q '^---$' && pass "SKILL.md has frontmatter" || fail "no frontmatter"
grep -q '^name: handoff-coordination$' "$S/SKILL.md" && pass "name set" || fail "name missing"
grep -q 'Using Jerron'"'"'s agent-cooperation skill' "$S/SKILL.md" && pass "announcement line present" || fail "no announcement"
grep -qi 'append-only' "$S/SKILL.md" && pass "append-only documented" || fail "append-only missing"
test -f "$S/references/protocol.md" && pass "protocol.md exists" || fail "protocol.md missing"
