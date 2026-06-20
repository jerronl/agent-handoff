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

## Waiting
`handoff_watch.sh <file> "<reply-tag>" [timeout] [interval]` records the current count of
`<reply-tag>` sections and returns (printing the new section) when it grows — implemented
with the generic `bg_wait.sh` background-wait engine. Run it via the harness's
background mechanism so you're re-invoked the moment a reply lands.

## Example roles (optional)
A "hub"/"librarian" agent owns a broadcast file others post questions to with
`## [<asker>->docs] ...` and answers with `## [docs->...] ...`. This is one usage pattern,
not a requirement.
