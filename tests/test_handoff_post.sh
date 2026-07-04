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

# CC via $HANDOFF_CC_FILE: same section lands in the CC file too
d="$(mktemp -d)"; hub="$d/hub.md"; cc="$d/orch_inbox.md"
printf 'ping\n' | HANDOFF_CC_FILE="$cc" bash "$P" "$hub" agentA agentB "cc-env"
assert_contains "$(cat "$hub")" "cc-env" "primary post written"
assert_contains "$(cat "$cc")" "agentA->agentB" "CC via env: section copied to CC file"
assert_contains "$(cat "$cc")" "cc-env" "CC via env: subject copied"

# CC via .handoff_cc file (walked up from the handoff file's dir)
d2="$(mktemp -d)"; hub2="$d2/hub.md"; cc2="$d2/coord.md"
printf '%s\n' "$cc2" > "$d2/.handoff_cc"
printf 'ping2\n' | bash "$P" "$hub2" a b "cc-file"
assert_contains "$(cat "$cc2")" "cc-file" ".handoff_cc: section copied to CC target"

# CC resolving to the target file itself → not double-posted
d3="$(mktemp -d)"; hub3="$d3/hub.md"
printf '%s\n' "$hub3" > "$d3/.handoff_cc"
printf 'once\n' | bash "$P" "$hub3" a b "self-cc"
n="$(grep -c '## \[a->b\]' "$hub3")"; assert_eq "$n" "1" "CC==target → posted once, not doubled"

rm -rf "$d" "$d2" "$d3"
