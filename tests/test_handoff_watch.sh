#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
D="$(cd "$(dirname "$0")/.." && pwd)/scripts"
f="$(mktemp)"
printf 'q\n' | bash "$D/handoff_post.sh" "$f" agentA agentB "question"   # A asked B
# B replies after 2s
( sleep 2; printf 'answer 42\n' | bash "$D/handoff_post.sh" "$f" agentB agentA "reply" ) &
out="$(bash "$D/handoff_watch.sh" "$f" "agentB->agentA" 15 1)"; rc=$?
assert_eq "$rc" "0" "watch detects reply (rc 0)"
assert_contains "$out" "agentB->agentA" "printed the reply tag"
assert_contains "$out" "answer 42" "printed reply body"
# timeout path: no matching reply
g="$(mktemp)"; printf 'x\n' | bash "$D/handoff_post.sh" "$g" a b s
bash "$D/handoff_watch.sh" "$g" "zzz->none" 2 1; assert_eq "$?" "1" "timeout → rc 1"
rm -f "$f" "$g"
