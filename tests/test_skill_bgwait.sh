#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
S="$(cd "$(dirname "$0")/.." && pwd)/skills/background-wait"
grep -q '^name: background-wait$' "$S/SKILL.md" && pass "name set" || fail "name missing"
grep -qi 'run_in_background' "$S/SKILL.md" && pass "mentions background run" || fail "missing bg run"
grep -qi 'bg_wait.sh' "$S/SKILL.md" && pass "references bg_wait.sh" || fail "no script ref"
