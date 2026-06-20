#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
P="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_post.sh"
f="$(mktemp)"; printf 'PRE-EXISTING LINE\n' > "$f"

printf 'hello body\n' | bash "$P" "$f" agentA agentB "first subject"
out="$(cat "$f")"
assert_contains "$out" "PRE-EXISTING LINE" "append-only: prior content kept"
assert_contains "$out" "## [agentA->agentB]" "tag header present"
assert_contains "$out" "first subject" "subject present"
assert_contains "$out" "hello body" "body present"

# safety: backticks and $VARS stored literally (body from stdin, no expansion)
printf 'literal `date` and $HOME stay raw\n' | bash "$P" "$f" agentB agentA "raw"
grep -q 'literal `date` and \$HOME stay raw' "$f" && pass "body stored literally" || fail "body was expanded"
rm -f "$f"

# missing dir → exit 2
printf x | bash "$P" /no/such/dir/x.md a b s; assert_eq "$?" "2" "missing dir → rc 2"
