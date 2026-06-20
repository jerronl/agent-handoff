---
name: handoff-coordination
description: Use when coordinating with another agent/Claude — or with your own future sessions — through append-only handoff files. Covers posting exact-tagged messages, point-to-point and broadcast channels, reading the other side's latest message, and background-waiting for a reply. Announces "Using Jerron's agent-cooperation skill".
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

## Rules that bite (see protocol.md)
- Tags are matched EXACTLY by the watcher — keep the `## [from->to]` shape verbatim.
- Append-only: never rewrite history; readers rely on it.
- Quoted-heredoc / stdin bodies: avoid shell expansion footguns in messages.
