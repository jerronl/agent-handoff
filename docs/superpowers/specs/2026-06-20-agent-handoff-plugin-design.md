# agent-handoff — Plugin Design

**Date:** 2026-06-20
**Status:** approved (user 2026-06-20), pending spec review → writing-plans
**Type:** public Claude Code plugin (standalone repo, not part of the trade system)
**Language:** the entire plugin (SKILL.md, references, README, code comments) is written in English.

## Purpose

Package the generic, reusable parts of a home-grown multi-agent toolkit into a public
plugin so anyone can install it. Two capabilities, both domain-agnostic:

1. **handoff-coordination** — let multiple Claude/agents (or one agent across sessions)
   coordinate by leaving messages in append-only handoff files, with exact-tag channels
   and a background "wait for the other side's reply" helper.
2. **background-wait** — the generic "launch in background + poll a condition" pattern
   (wait on a log marker, a process exit, a port, a file) instead of foreground sleep or
   asking the human to ping the agent.

All trade-specific details (hardcoded `/mnt/...` paths, `ns`/`xlsw`/`pyvol`/`lib` tags,
the librarian role, TWS/bt/Excel hooks) are stripped — only the patterns remain.

## Why a plugin (not a bare skill)

A plugin is the distributable wrapper that can bundle multiple skills **and** a slash
command. We ship two skills + one `/handoff` command, so a plugin is the right unit
(a bare skill cannot carry a slash command or a sibling skill). Install via marketplace /
git `/plugin install`.

## Structure

```
agent-handoff/
  .claude-plugin/plugin.json          # manifest: name, version, description, author
  README.md                           # what it is, install, quickstart
  skills/
    handoff-coordination/
      SKILL.md                        # when + how to coordinate via handoff files
      references/protocol.md          # full protocol spec (tags, append-only, channels, traps)
    background-wait/
      SKILL.md                        # the bg-wait pattern
  scripts/
    handoff_watch.sh                  # generic watcher: bg-wait for a peer's reply tag
    bg_wait.sh                        # generic: run a condition cmd in a poll loop until true/timeout
  commands/
    handoff.md                        # /handoff post|read|watch convenience command
  docs/superpowers/specs/             # this design doc
```

Scripts live at the plugin root `scripts/` and are referenced by both skills + the command
via the plugin path, so they are shared (not duplicated per skill).

## Component 1 — skill `handoff-coordination`

**SKILL.md** (description triggers on: coordinating with another agent / leaving a message
for another Claude / waiting on another agent's reply / multi-session handoff).

Protocol (generalized):
- **Channel files** chosen by the user/caller — point-to-point `handoff_<a>_<b>.md` or
  broadcast `handoff_<topic>.md`. Paths are arguments, never hardcoded.
- **Append-only** messages. Each message is a section headed by an EXACT tag:
  `## [<from>-><to>] <timestamp> <subject>` using an ASCII arrow `->` so watchers can
  grep the tag exactly. Broadcast variant: `## [<from>-><topic>] ...`.
- **Read before reply**: read the other side's latest tag first; **never edit or delete
  another agent's section** — only append.
- **Append safely**: use a quoted heredoc (`<<'EOF'`) so backticks / `$` in the message
  aren't expanded (a real footgun).
- **Wait for a reply**: run `scripts/handoff_watch.sh <file> "<reply-tag>" [timeout]` in
  the background; it records the current count of `<reply-tag>` sections and fires when a
  new one appears, printing it.
- Optional **roles** (e.g. a "librarian"/broadcast hub) are documented as an *example
  pattern*, not a requirement.
- **Announcement convention**: while this skill is active, the agent begins each
  user-facing interaction with the exact line `Using Jerron's agent-cooperation skill`
  (confirmed wording, grammar-corrected from the user's "use Jerron's agents corporating
  skill"), mirroring how skills self-announce — signaling multi-agent coordination is in
  effect.

**references/protocol.md** — the complete spec (the generic distillation of the original
HANDOFF_PROTOCOL): tag exact-match rule, append-only, point-to-point vs broadcast, the
heredoc trap, timestamp format, watcher contract, and the read-before-reply discipline.

## Component 2 — skill `background-wait`

**SKILL.md**: when you launch something long (a build, a deploy, a remote job) or must wait
on an external condition the harness can't notify you about, **don't** foreground-`sleep`
or ask the human to ping you — launch a background poll loop that exits the moment a
condition holds, so the harness re-invokes you. Conditions: a log marker's count grows, a
process exits, a TCP port starts listening, a file appears. Caveat: don't poll for
harness-tracked background work (you're already re-invoked when it finishes).

## Component 3 — `/handoff` command

`commands/handoff.md` wires the protocol + watcher into three subcommands:
- `/handoff post <file> <from> <to> "<msg>"` — append a correctly-tagged section (quoted-heredoc safe).
- `/handoff read <file>` — print the latest tagged section(s).
- `/handoff watch <file> "<reply-tag>" [timeout]` — background-wait for a reply.

## Scripts (generic, parameterized)

- **handoff_watch.sh** `<file> <reply_tag> [timeout_sec] [interval_sec]`: baseline =
  `grep -c "^## \[<reply_tag>\]" file`; poll every interval until count increases or
  timeout; on success print the new section(s); exit 0 (found) / nonzero (timeout). No
  hardcoded paths or tags.
- **bg_wait.sh** `[--interval N] [--timeout N] -- <condition-cmd...>`: run the condition
  command each interval; exit 0 when it succeeds (rc 0), nonzero on timeout. Used by the
  background-wait skill and as the engine under handoff_watch.

## Generalization checklist (public-readiness)

- No `/mnt/...` / `G:\...` absolute paths — all paths are arguments.
- No project tags (`ns`, `xlsw`, `pyvol`, `lib`, ...) — `from`/`to`/`topic` are parameters.
- No domain assumptions (trading, Excel, TWS) anywhere in text or scripts.
- Examples use neutral names (`agentA`, `agentB`, `docs`).

## Error handling

- Watcher: clear timeout message + the file's tail; missing file → explicit error (don't
  create silently — a typo'd path shouldn't spawn a bogus channel).
- post: refuse if `<file>` dir doesn't exist; warn (don't block) if the tag already exists
  verbatim (possible duplicate).
- bg_wait: bounded by timeout; never infinite.

## Testing

- handoff round-trip: post A->B, start watch for `B->A`, append a `B->A` section, assert the
  watcher detects + prints it; assert append-only (existing sections untouched).
- post safety: a message containing backticks / `$VAR` is stored literally.
- bg_wait: succeeds when the condition becomes true; times out cleanly otherwise.
- plugin.json parses; `/plugin` can discover the plugin; both skills load.

## Build location & publishing

- Standalone repo at `/mnt/e/mydoc/git/agent-handoff/` (NOT inside the trade repo).
- `plugin.json` manifest; README with install + quickstart.
- Publish: push to a public GitHub repo; users add it as a marketplace / install via
  `/plugin`. (Submitting to an official marketplace is a follow-up, out of scope here.)

## Out of scope (YAGNI)

- The protected-files edit-guard hook (different theme → a separate plugin later).
- Any trade/Excel/TWS-specific helper.
- A networked message bus / locking — append-only files + exact tags are enough.
