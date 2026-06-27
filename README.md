# agent-handoff

A Claude Code plugin for **multi-agent coordination**:

- **handoff-coordination** skill — agents (or your own sessions) coordinate via
  append-only handoff files with exact-tag point-to-point / broadcast channels, plus a
  background "wait for the other side's reply" helper, plus an always-on
  autonomous inbox via a persistent Monitor. Announces
  *"Using Jerron's agent-cooperation skill"*.
- **background-wait** skill — a generic "launch in background + poll a condition" pattern.
- `/handoff post|read|watch` command + dependency-free bash scripts in `scripts/`.
- **Bundled hooks** (`hooks/`, auto-active when enabled): a `SessionStart` hook that
  prompts the model to arm the always-on Monitor listener, and a `UserPromptSubmit`
  hook that delivers unread messages each prompt as a zero-dependency backstop. Both
  no-op unless a `.handoff_channels` file exists up-tree from cwd.

## Install
Add this repo as a plugin marketplace / install with `/plugin` (see Claude Code plugin docs),
or clone into your plugins directory.

## Quickstart
```bash
# A asks B
printf 'please review X\n' | scripts/handoff_post.sh handoff_A_B.md agentA agentB "review request"
# B (or you) read it
scripts/handoff_read.sh handoff_A_B.md
# A waits for B's ONE reply (background; exits when it lands)
scripts/handoff_watch.sh handoff_A_B.md "agentB->agentA" 600

# Always-on inbox: react to ANY new message autonomously (run via the Monitor
# tool, persistent:true — emits per new section, never exits, no re-arm)
scripts/monitor_handoff.sh handoff_A_B.md "agentB->agentA"
scripts/monitor_handoff.sh "handoff_hub.md:.*(->|→)me"   # broadcast inbox
```

### Listening: pick the mode
- **One expected reply, then continue** → `handoff_watch.sh` / background-wait
  (`run_in_background` re-invokes you on EXIT — correct for "wait for one").
- **Continuous, autonomous, never-deaf inbox** → `monitor_handoff.sh` via the
  **Monitor tool** (`persistent:true`). A `--loop` `run_in_background` watcher
  never exits → never notifies; a one-shot needs re-arming you'll forget. Monitor
  emits per event without exiting. See the handoff-coordination skill.

## Tests
`bash tests/run.sh`

## License
MIT
