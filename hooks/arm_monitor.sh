#!/usr/bin/env bash
# SessionStart hook (agent-handoff plugin): tell the model to arm THIS agent's
# always-on handoff listener as a first action, so the multi-agent channel never
# silently goes deaf.
#
# Listener = a **persistent Monitor** (Monitor tool, persistent:true) running this
# plugin's monitor_handoff.sh. Monitor emits one notification per new section and
# NEVER exits → no re-arm, no keepalive cron, and events arrive autonomously (not
# gated on the human typing). This hook only EMITS the directive; it cannot launch
# a model-notifying task itself (a hook-spawned background process is detached and
# can't re-invoke the model), so the model must do the actual Monitor call.
#
# Backstop: the UserPromptSubmit hook (deliver_inbox.py) delivers unread on every
# prompt with zero model action — so even if the model skips arming the Monitor,
# nothing is permanently lost.
#
# Channels live in the agent's own `.handoff_channels` (one `file:tag` per line),
# found by walking up from cwd. monitor_handoff.sh reads it at runtime.
#
# Fires for startup + resume; skips 'clear'.
set -u
INPUT=$(cat || true)
_get() { printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('$1',''))
except Exception: print('')" 2>/dev/null; }
SOURCE=$(_get source)
[ "$SOURCE" = "clear" ] && exit 0
CWD=$(_get cwd); [ -z "$CWD" ] && CWD="$PWD"

# Monitor command script — resolve relative to THIS hook (plugin-local), so no
# absolute path is baked in.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." 2>/dev/null && pwd)"; PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$HERE/..}}"
MON="$PLUGIN_ROOT/scripts/monitor_handoff.sh"

# Find this agent's channel config by walking up from cwd.
CONF=""; d="$CWD"
while [ -n "$d" ] && [ "$d" != "/" ]; do
  [ -f "$d/.handoff_channels" ] && { CONF="$d/.handoff_channels"; break; }
  d=$(dirname "$d")
done

if [ -z "$CONF" ]; then
  DIRECTIVE="(SessionStart → agent-handoff) No \`.handoff_channels\` found from your cwd. If you coordinate via handoff files, create one (one entry per line: \`file:tag\` for a tag-routed shared hub, e.g. \`/abs/handoff_hub.md:.*(->|→)me\`, OR a bare \`file\` for inbox mode where you own \`/abs/<you>_inbox.md\` and match any section), then arm an always-on listener: Monitor tool, persistent:true, command \`bash $MON\`. It notifies you per new message, never exits, needs no re-arm."
elif [ "$SOURCE" = "resume" ] || [ "$SOURCE" = "compact" ]; then
  DIRECTIVE="(SessionStart → agent-handoff) resume/compact: your handoff **Monitor** is probably still running. Check TaskList; only if it's gone, re-arm it: Monitor tool, persistent:true, command \`bash $MON\`. Do NOT use run_in_background/--loop or a cron — those don't autonomously notify."
else
  DIRECTIVE="(SessionStart → agent-handoff) FIRST action: arm your always-on handoff listener. Use the **Monitor tool** with persistent:true and command \`bash $MON\` (it reads your \`.handoff_channels\`). It notifies you per new message addressed to your channel, runs the whole session, never exits, and needs NO re-arm — works without the human prompting. (Monitor ≠ run_in_background: the latter only notifies on exit, so a --loop watcher never notifies.) Then answer the user normally."
fi

python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'SessionStart','additionalContext':sys.argv[1]}}))" "$DIRECTIVE"
