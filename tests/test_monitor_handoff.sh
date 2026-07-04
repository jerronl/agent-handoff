#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
D="$(cd "$(dirname "$0")/.." && pwd)/scripts"
f="$(mktemp)"
printf '## [a->me] m1\nx\n\n## [b->ns] notmine\ny\n\n## [c->me] m2\nz\n\n' > "$f"

# file:tag form, broadcast regex tag — match only ->me, not ->ns
out="$(MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh" "$f:.*(->|→)me")"
assert_contains "$out" "a->me" "monitor matches a->me"
assert_contains "$out" "c->me" "monitor matches c->me"
case "$out" in *"b->ns"*) fail "leaked non-matching b->ns";; *) pass "no leak of other tag";; esac

# legacy 2-arg form
out2="$(MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh" "$f" 'b->ns')"
assert_contains "$out2" "b->ns" "legacy 2-arg matches b->ns"

# .handoff_channels fallback (no args)
d="$(mktemp -d)"; cp "$f" "$d/h.md"
printf '%s\n' "$d/h.md:.*(->|→)me" > "$d/.handoff_channels"
out3="$(cd "$d" && MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh")"
assert_contains "$out3" "a->me" ".handoff_channels fallback works"

# inbox mode: bare file arg (no colon) matches ANY section (route by filename)
out4="$(MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh" "$f")"
assert_contains "$out4" "a->me" "inbox mode matches a->me"
assert_contains "$out4" "b->ns" "inbox mode matches b->ns (any tag)"
assert_contains "$out4" "c->me" "inbox mode matches c->me"

# inbox mode via a bare (colon-less) .handoff_channels line
di="$(mktemp -d)"; cp "$f" "$di/inbox.md"
printf '%s\n' "$di/inbox.md" > "$di/.handoff_channels"
out5="$(cd "$di" && MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh")"
assert_contains "$out5" "b->ns" "bare .handoff_channels line = inbox mode (any section)"

# no args + no .handoff_channels → error rc
d2="$(mktemp -d)"; ( cd "$d2" && MONITOR_HANDOFF_ONCE=1 bash "$D/monitor_handoff.sh" ) 2>/dev/null
assert_eq "$?" "1" "no args + no config → rc 1"

rm -rf "$f" "$d" "$d2" "$di"
