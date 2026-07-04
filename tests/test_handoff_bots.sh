#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
B="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_bots.sh"

d="$(mktemp -d)"
# alpha: has an inbound section but never replied → behind=yes
printf '## [beta->alpha] hi\nbody\n\n' > "$d/_inbox_alpha.md"
# gamma: replied AFTER the last inbound → behind=no
printf '## [beta->gamma] hi\nq\n\n## [gamma->beta] answered\na\n\n' > "$d/_inbox_gamma.md"
# roster (pattern '-' = skip liveness so tests don't depend on real processes)
cat > "$d/.handoff_bots" <<EOF
# name | pattern | inbox | cmd
alpha | - | $d/_inbox_alpha.md | -
gamma | - | $d/_inbox_gamma.md | echo launched-gamma
delta | - | - | -
EOF

# list shows every roster bot
out="$(cd "$d" && bash "$B" list)"
assert_contains "$out" "alpha" "list shows alpha"
assert_contains "$out" "gamma" "list shows gamma"
assert_contains "$out" "delta" "list shows delta"

# behind heuristic: alpha unanswered → yes ; gamma answered → no
sa="$(cd "$d" && bash "$B" status alpha)"
assert_contains "$sa" "behind:  yes" "alpha behind=yes (unanswered inbound)"
sg="$(cd "$d" && bash "$B" status gamma)"
assert_contains "$sg" "behind:  no" "gamma behind=no (replied after inbound)"

# waiting lists the behind bot, not the answered one
w="$(cd "$d" && bash "$B" waiting)"
assert_contains "$w" "alpha" "waiting flags alpha"
case "$w" in *gamma*) fail "waiting wrongly flagged gamma";; *) pass "waiting excludes gamma";; esac

# start on a bot with no launch cmd → rc 3
( cd "$d" && bash "$B" start alpha ) >/dev/null 2>&1; assert_eq "$?" "3" "start alpha (no cmd) → rc 3"
# start on a launchable bot runs its command
so="$(cd "$d" && bash "$B" start gamma 2>/dev/null)"
assert_contains "$so" "launched-gamma" "start gamma runs launch_command"
# unknown bot → rc 2
( cd "$d" && bash "$B" status nobody ) >/dev/null 2>&1; assert_eq "$?" "2" "unknown bot → rc 2"
# no roster up-tree → rc 1
d2="$(mktemp -d)"; ( cd "$d2" && bash "$B" list ) >/dev/null 2>&1; assert_eq "$?" "1" "no roster → rc 1"

rm -rf "$d" "$d2"
