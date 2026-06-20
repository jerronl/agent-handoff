#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
BW="$(cd "$(dirname "$0")/.." && pwd)/scripts/bg_wait.sh"

# success: condition true immediately
bash "$BW" --interval 1 --timeout 5 -- true && pass "succeeds when condition true" || fail "should succeed"

# timeout: condition always false → exit 1 within ~2s
start=$SECONDS
bash "$BW" --interval 1 --timeout 2 -- false; rc=$?
assert_eq "$rc" "1" "times out with rc=1"
[ $((SECONDS - start)) -le 5 ] && pass "timeout bounded" || fail "timeout too slow"

# becomes-true: flag file appears
f="$(mktemp -u)"; ( sleep 2; : > "$f" ) &
bash "$BW" --interval 1 --timeout 10 -- test -f "$f" && pass "detects flag file" || fail "missed flag"
rm -f "$f"
