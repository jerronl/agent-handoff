---
name: handoff-coordination
description: Use when coordinating with another agent/Claude — or with your own future sessions — through append-only handoff files. Covers posting exact-tagged messages, point-to-point and broadcast channels, reading the other side's latest message, background-waiting for a single reply, and always-on autonomous listening for any new message via a persistent Monitor. Announces "Using Jerron's agent-cooperation skill".
---

# Jerron's Agent-Cooperation Skill (handoff-coordination)

**Announce at the start of every user-facing interaction while this skill is active:**
`Using Jerron's agent-cooperation skill`

Coordinate multiple agents (or one agent across sessions) by leaving messages in
**append-only** handoff files. No server, no lock — just files + an exact-tag convention.

## When to use
- You need another agent (or your own later session) to pick up / answer something.
- You're waiting on another agent's reply and don't want to busy-wait or ask the human.

## Channels (paths are yours; nothing hardcoded)
- Point-to-point: `handoff_<a>_<b>.md`
- Broadcast / hub: `handoff_<topic>.md` (e.g. a "librarian" that many agents query — an
  example role, not required).

## The protocol (read `references/protocol.md` for the full spec)
1. **Post** a message — append a section headed by an EXACT tag:
   `## [<from>-><to>] <UTC ts> <subject>` (ASCII arrow `->`).
   Use `scripts/handoff_post.sh <file> <from> <to> "<subject>"` with the body on STDIN so
   backticks / `$vars` are stored literally.
2. **Read before you reply** — `scripts/handoff_read.sh <file>` (latest section) or
   `scripts/handoff_read.sh <file> "<tag-substr>"`. NEVER edit/delete another agent's
   section; only append.
3. **Wait for a reply** — `scripts/handoff_watch.sh <file> "<to>-><from>" [timeout]` in the
   background; it fires when a new reply section appears and prints it.

## Two listening modes — pick by how many messages you expect

**Key fact about this harness:** a `run_in_background` task re-invokes the model
only when it **exits**. That single fact splits listening into two cases:

1. **Wait for ONE expected reply, then continue** → `handoff_watch.sh` /
   background-wait. It exits the moment the reply lands (exactly when you want to
   be re-invoked), prints it, done. Correct here.
2. **Always-on inbox — react to ANY message, indefinitely, on your own** → the
   **Monitor tool** running `scripts/monitor_handoff.sh`. Do NOT use
   `run_in_background` for this: a `--loop` watcher never exits, so it never
   notifies; a one-shot watcher that exits-to-notify must be re-armed after every
   message, and the model reliably forgets → silent deafness (the classic
   "are you still listening?" failure).

### Always-on listening (the Monitor tool)
Arm ONE persistent Monitor per agent as a first action each session:

> Monitor tool — `persistent: true`,
> `command: <plugin>/scripts/monitor_handoff.sh <file>:<tag> [<file2>:<tag2> ...]`
> (or no args → reads `./.handoff_channels`).

It emits one event per NEW matching section, **never exits** (no re-arm), and
events arrive autonomously — not gated on the human typing. `<tag>` may be a
regex, e.g. a broadcast inbox `.*(->|→)me` (double-matches `->` and `→`).

**Backstop (bundled, zero model-dependency):** the Monitor still must be armed
once per session by the model. This plugin ships two hooks (in `hooks/`, auto-active
when the plugin is enabled — no settings.json edits) that backstop it:
- `arm_monitor.sh` (**SessionStart**) — injects the "arm the Monitor" directive as a
  first action (a hook can't launch a model-notifying task itself, so it asks the
  model to).
- `deliver_inbox.py` (**UserPromptSubmit**) — scans your channels and injects any
  unread sections on every prompt, with no model action.

Both fire automatically but only on activity (session start / your next prompt), so
they cover "the model forgot to arm" — they do NOT replace the Monitor's idle,
autonomous wake. Both no-op unless a `.handoff_channels` exists up-tree from cwd.

## Rules that bite (see protocol.md)
- Tags are matched EXACTLY by the watcher — keep the `## [from->to]` shape verbatim.
- Append-only: never rewrite history; readers rely on it.
- Quoted-heredoc / stdin bodies: avoid shell expansion footguns in messages.
