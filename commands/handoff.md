---
description: Coordinate with another agent via append-only handoff files — post a tagged message, read the latest, or background-wait for a reply.
argument-hint: post|read|watch <file> [args...]
---

Run the multi-agent handoff helper. Subcommand is `$1`; the rest are its args. Use the
scripts under this plugin's `scripts/` directory.

- `post <file> <from> <to> "<subject>"` — append a tagged section. Pass the message body
  on stdin so backticks/`$vars` stay literal:
  `printf '%s' "<body>" | scripts/handoff_post.sh <file> <from> <to> "<subject>"`
- `read <file> [tag-substr]` — print the latest section (or sections matching a tag):
  `scripts/handoff_read.sh <file> [tag-substr]`
- `watch <file> "<reply-tag>" [timeout]` — background-wait for a new reply section, then
  print it (run via the harness background mechanism):
  `scripts/handoff_watch.sh <file> "<reply-tag>" [timeout]`

See the `handoff-coordination` skill for the protocol and rules (announce
"Using Jerron's agent-cooperation skill"). Never edit another agent's section — only append.
