#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$ROOT"

# hooks.json parses and registers the two events
python3 - "$ROOT/hooks/hooks.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
ev=d["hooks"]
assert "SessionStart" in ev and "UserPromptSubmit" in ev, "missing events"
print("ok")
PY
assert_eq "$?" "0" "hooks.json parses + has SessionStart & UserPromptSubmit"

# both hook scripts exist and are executable
[ -x "$ROOT/hooks/arm_monitor.sh" ] && pass "arm_monitor.sh executable" || fail "arm_monitor.sh not executable"
[ -x "$ROOT/hooks/deliver_inbox.py" ] && pass "deliver_inbox.py executable" || fail "deliver_inbox.py not executable"

# SessionStart hook emits a Monitor-arming directive that points at monitor_handoff.sh
out="$(printf '{"source":"startup","cwd":"/tmp"}' | bash "$ROOT/hooks/arm_monitor.sh")"
assert_contains "$out" "monitor_handoff.sh" "arm hook directive references monitor_handoff.sh"
assert_contains "$out" "Monitor" "arm hook directive says use the Monitor tool"

# clear source → silent (no output)
out2="$(printf '{"source":"clear","cwd":"/tmp"}' | bash "$ROOT/hooks/arm_monitor.sh")"
assert_eq "$out2" "" "arm hook silent on source=clear"

# UserPromptSubmit backstop: with a .handoff_channels + a new section, it injects it;
# with none, it stays silent (exit 0).
d="$(mktemp -d)"; printf '## [x->me] hi\nbody\n\n' > "$d/h.md"
printf '%s:%s\n' "$d/h.md" '.*(->|→)me' > "$d/.handoff_channels"
# first run = baseline (silent); then add a section; second run = deliver it
printf '{"cwd":"%s"}' "$d" | python3 "$ROOT/hooks/deliver_inbox.py" >/dev/null
printf '## [y->me] second\nb2\n\n' >> "$d/h.md"
out3="$(printf '{"cwd":"%s"}' "$d" | python3 "$ROOT/hooks/deliver_inbox.py")"
assert_contains "$out3" "y->me" "deliver hook injects the new section on next prompt"
case "$out3" in *"x->me"*) fail "deliver re-sent already-baselined section";; *) pass "deliver does not re-send baselined";; esac
rm -rf "$d"

# deliver hook inbox mode: a bare (colon-less) .handoff_channels line matches ANY section
di="$(mktemp -d)"; printf '## [p->anyone] hello\nbody\n\n' > "$di/inbox.md"
printf '%s\n' "$di/inbox.md" > "$di/.handoff_channels"
printf '{"cwd":"%s"}' "$di" | python3 "$ROOT/hooks/deliver_inbox.py" >/dev/null   # baseline
printf '## [q->anyone] second\nb2\n\n' >> "$di/inbox.md"
outI="$(printf '{"cwd":"%s"}' "$di" | python3 "$ROOT/hooks/deliver_inbox.py")"
assert_contains "$outI" "q->anyone" "deliver inbox mode delivers a new section with no tag"
rm -rf "$di"
