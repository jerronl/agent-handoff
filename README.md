# agent-handoff

A Claude Code plugin for **multi-agent coordination**:

- **handoff-coordination** skill — agents (or your own sessions) coordinate via
  append-only handoff files, routed either by **exact tag** (point-to-point / broadcast)
  or by **filename** (a receiver-centric inbox each agent owns), plus a background "wait
  for the other side's reply" helper, plus an always-on autonomous inbox via a persistent
  Monitor. Announces *"Using Jerron's agent-cooperation skill"*.
- **background-wait** skill — a generic "launch in background + poll a condition" pattern.
- `/handoff post|read|watch` command + dependency-free bash scripts in `scripts/` (incl.
  `handoff_bots.sh` — a pluggable roster to launch / restart / check on the other agents).
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
scripts/monitor_handoff.sh "handoff_hub.md:.*(->|→)me"   # tag-routed shared hub
scripts/monitor_handoff.sh agentB_inbox.md               # inbox mode: any section
```

### Channels: `.handoff_channels` (one entry per line)
Each line tells the Monitor and the delivery hook which file to watch. Two forms:
- **`file:tag`** — tag-routed. `tag` is a regex matched inside the `## [<tag>]` header,
  e.g. `handoff_hub.md:.*(->|→)me` — pull only messages addressed to you out of a shared
  hub. Precise, but the tag must stay in sync with how senders address you.
- **`file`** (bare, no colon) — **inbox mode**: match ANY `## [` section in that file.
  Routing is by filename — you own `<you>_inbox.md`, senders append there, no tag to keep
  in sync. It also removes a footgun: a colon-less line is treated as an inbox, never
  mis-parsed as an unmatchable tag (which would make the watcher silently deaf).

Pick tag mode for a shared hub read by many; pick inbox mode when each agent owns its own
inbox file. Both forms can be mixed across lines. Same forms work as direct args to
`monitor_handoff.sh`.

### CC an orchestrator (optional)
Want a coordinator that sees every message without being an explicit recipient? `handoff_post.sh`
appends the same section to a CC file when one is configured — via `HANDOFF_CC_FILE=/abs/orch_inbox.md`
or a `.handoff_cc` file (first line = CC target path) walked up from the handoff file's dir. Point
every agent's CC at the same file and it becomes the orchestrator's firehose. Unset ⇒ no CC (default);
posting directly to the coordinator is never double-written.

### Managing the roster of bots (optional)
An orchestrator often needs to launch, restart, and check on the other agents. `handoff_bots.sh`
is a pluggable roster for exactly that — the plugin owns the generic parts (roster parsing,
liveness via `pgrep`, a handoff-level "behind on its inbox" heuristic); the environment-specific
part — *how to spawn a session* — is a command you register per bot, because the plugin can't
know how to start a session in an arbitrary environment (Windows Terminal, tmux, screen, ssh…).

Roster `.handoff_bots` (walked up from cwd; see `.handoff_bots.example`), one bot per line:
```
# name | pgrep_pattern | inbox_file | launch_command    ('-' skips a field)
docs  | monitor_inbox .*_inbox_docs | /proj/_inbox_docs.md | wt new-tab --title docs bash -lc 'cd /proj && claude'
```
```bash
scripts/handoff_bots.sh list              # roster + alive + inbox-lag, one row per bot
scripts/handoff_bots.sh status docs       # detail for one bot
scripts/handoff_bots.sh waiting           # bots that look stalled (alive + unanswered inbox)
scripts/handoff_bots.sh start docs        # run the bot's launch_command
scripts/handoff_bots.sh restart docs      # pkill the pattern, then relaunch
```
**"Is it waiting for input?"** — there is no portable OS signal for "an agent is blocked at a
prompt", so `waiting`/`behind` use a handoff-level PROXY: a bot is flagged when it is alive AND
its inbox has a section newer than the last one *it* sent (received something it hasn't answered).
That catches "stalled / needs a nudge"; it does not read the terminal.

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
