# agent-handoff

A Claude Code plugin for **multi-agent coordination**:

- **handoff-coordination** skill — agents (or your own sessions) coordinate via
  append-only handoff files with exact-tag point-to-point / broadcast channels, plus a
  background "wait for the other side's reply" helper. Announces
  *"Using Jerron's agent-cooperation skill"*.
- **background-wait** skill — a generic "launch in background + poll a condition" pattern.
- `/handoff post|read|watch` command + dependency-free bash scripts in `scripts/`.

## Install
Add this repo as a plugin marketplace / install with `/plugin` (see Claude Code plugin docs),
or clone into your plugins directory.

## Quickstart
```bash
# A asks B
printf 'please review X\n' | scripts/handoff_post.sh handoff_A_B.md agentA agentB "review request"
# B (or you) read it
scripts/handoff_read.sh handoff_A_B.md
# A waits for B's reply (background)
scripts/handoff_watch.sh handoff_A_B.md "agentB->agentA" 600
```

## Tests
`bash tests/run.sh`

## License
MIT
