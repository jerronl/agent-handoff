#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
P="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_post.sh"
R="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_read.sh"
f="$(mktemp)"
printf 'one\n'   | bash "$P" "$f" a b "s1"
printf 'two\n'   | bash "$P" "$f" b a "s2"
latest="$(bash "$R" "$f")"
assert_contains "$latest" "## [b->a]" "latest section is the last posted"
assert_contains "$latest" "two" "latest body present"
case "$latest" in *"## [a->b]"*) fail "latest should not include earlier section";; *) pass "only latest section";; esac
bytag="$(bash "$R" "$f" "a->b")"
assert_contains "$bytag" "one" "tag filter returns matching section"
rm -f "$f"
