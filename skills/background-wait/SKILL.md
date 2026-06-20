---
name: background-wait
description: Use when you launch something long (a build, deploy, remote job) or must wait on an external condition the harness can't notify you about — wait by polling a condition in the background instead of foreground-sleeping or asking the human to ping you.
---

# background-wait

When you must wait on an external condition, launch a poll loop in the background (the
harness re-invokes you when it exits) rather than blocking on a foreground `sleep` or
asking the human to remind you.

## Use it for
- A log file's marker/line-count growing.
- A process exiting, a TCP port starting to listen, a file appearing.
- Any shell-checkable condition.

## Do NOT use it for
- Work the harness already tracks (a tracked background task / subagent) — you're
  re-invoked automatically when those finish; polling them is wasted.

## How
Run `scripts/bg_wait.sh` via the harness's `run_in_background` mechanism:
```
bg_wait.sh [--interval N] [--timeout N] -- <condition-cmd...>
```
- exits 0 the moment `<condition-cmd>` returns 0; exits 1 on timeout.
- Examples:
  - port up: `bg_wait.sh --interval 5 --timeout 300 -- bash -c 'ss -tln | grep -q :7496'`
  - file appears: `bg_wait.sh -- test -f /tmp/done.flag`
  - log marker count grows past N: wrap the grep-count compare in `bash -c '...'`.

`handoff-coordination`'s `handoff_watch.sh` is built on this engine.
