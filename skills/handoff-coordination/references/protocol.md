# Handoff Protocol (full spec)

A minimal convention for multiple agents to coordinate via shared files.

## Message format
Each message is an append-only section:
```
## [<from>-><to>] <YYYY-MM-DD HH:MM:SSZ> <subject>

<body...>
```
- `<from>`/`<to>` are short agent ids you choose (`agentA`, `docs`, `reviewer`, ...).
- The arrow is ASCII `->` (NOT a unicode arrow) so `grep "^## \[from->to\]"` matches.
- Broadcast: `## [<from>-><topic>] ...` to a `handoff_<topic>.md` hub.

## Rules
1. **Append-only.** Only add sections. Never edit or delete another agent's section —
   the watcher and readers assume history is immutable.
2. **Read before reply.** Read the counterpart's latest tag before responding, so you
   answer the current message.
3. **Exact tags.** Watchers `grep -c "^## \[<tag>\]"`; a malformed header is invisible.
4. **Literal bodies.** Post bodies via stdin / a quoted heredoc so backticks and `$vars`
   are stored verbatim (a classic corruption source).
5. **Timestamps** in UTC `YYYY-MM-DD HH:MM:SSZ`.

## Listening: channels & inbox mode
Your `.handoff_channels` (one entry per line, walked up from cwd) tells the Monitor and
the delivery hook which files to watch. Two entry forms:

- **`file:tag`** — tag-routed. `tag` is a regex matched inside the `## [<tag>]` header,
  e.g. `handoff_hub.md:.*(->|→)me` to pull only messages addressed to you out of a shared
  hub. Precise, but the tag must stay in sync with how senders address you.
- **`file`** (bare, no colon) — **inbox mode**: match ANY `## [` section in that file.
  Routing is by filename — you own `<you>_inbox.md` and senders append there, so there is
  no tag to keep in sync. Simpler, and it avoids a footgun: a colon-less line is treated as
  an inbox, never mis-parsed as an unmatchable tag (which would make the watcher silently
  deaf).

Pick tag mode for a shared hub read by many; pick inbox mode when each agent owns its own
inbox file. Both forms can be mixed across lines.

## CC / oversight (optional)
An orchestrator or coordinator often needs to see ALL traffic without being an explicit
recipient of every message. `handoff_post.sh` supports an opt-in CC: the same section is
appended to a CC file in addition to the target. Configure the CC target by either:
- `HANDOFF_CC_FILE=/abs/coordinator_inbox.md` — explicit, per-invocation; or
- a `.handoff_cc` file walked up from the handoff file's directory whose first non-comment
  line is the CC target path — persistent "always CC" for a project.

Unset ⇒ no CC (default). The CC is skipped when it resolves to the target file itself, so
posting directly to the coordinator never double-writes. Point every agent's CC at the same
file and that file becomes the coordinator's firehose of the whole conversation.

## Waiting
`handoff_watch.sh <file> "<reply-tag>" [timeout] [interval]` records the current count of
`<reply-tag>` sections and returns (printing the new section) when it grows — implemented
with the generic `bg_wait.sh` background-wait engine. Run it via the harness's
background mechanism so you're re-invoked the moment a reply lands.

## Example roles (optional)
A "hub"/"librarian" agent owns a broadcast file others post questions to with
`## [<asker>->docs] ...` and answers with `## [docs->...] ...`. This is one usage pattern,
not a requirement.
