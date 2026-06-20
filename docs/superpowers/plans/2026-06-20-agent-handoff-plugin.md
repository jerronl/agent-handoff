# agent-handoff Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a public Claude Code plugin `agent-handoff` that gives any agent two domain-agnostic capabilities — multi-agent coordination via append-only handoff files, and a generic background-wait pattern.

**Architecture:** A plugin dir with a `plugin.json` manifest, two skills (`handoff-coordination`, `background-wait`), a `/handoff` slash command, and shared POSIX-bash scripts (`bg_wait.sh`, `handoff_post.sh`, `handoff_read.sh`, `handoff_watch.sh`). The command and the handoff skill wrap the scripts; `handoff_watch.sh` reuses `bg_wait.sh` as its poll engine. All logic is in the scripts (testable); skills/command are thin wrappers + instructions.

**Tech Stack:** POSIX bash (no runtime deps), Markdown (SKILL.md/command/README), JSON (manifest). Tests are plain bash (no bats dependency). Build at `/mnt/e/mydoc/git/agent-handoff/`.

**Spec:** `/mnt/e/mydoc/git/agent-handoff/docs/superpowers/specs/2026-06-20-agent-handoff-plugin-design.md`

**Rule #11:** Do NOT auto-commit. `git init` + commits happen only with explicit user approval. The "Commit" steps below are written for completeness; in this environment, pause and ask before running them (or batch at the end).

---

## File Structure

- `/mnt/e/mydoc/git/agent-handoff/.claude-plugin/plugin.json` — plugin manifest.
- `scripts/bg_wait.sh` — generic: poll a condition cmd until success/timeout.
- `scripts/handoff_post.sh` — append a tagged, append-only section (body from stdin, literal).
- `scripts/handoff_read.sh` — print latest section, or sections matching a tag substring.
- `scripts/handoff_watch.sh` — background-wait for a new section with a reply tag (uses bg_wait).
- `skills/handoff-coordination/SKILL.md` + `references/protocol.md` — coordination skill + spec.
- `skills/background-wait/SKILL.md` — background-wait skill.
- `commands/handoff.md` — `/handoff post|read|watch` slash command.
- `tests/assert.sh` — tiny assert helpers. `tests/run.sh` — runs all test files.
- `tests/test_*.sh` — per-component tests.
- `README.md` — what/install/quickstart.

---

### Task 1: Repo skeleton + manifest + test harness

**Files:**
- Create: `.claude-plugin/plugin.json`, `tests/assert.sh`, `tests/run.sh`, `tests/test_manifest.sh`

- [ ] **Step 1: Write the manifest test**

`tests/test_manifest.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -c "import json,sys; d=json.load(open('$ROOT/.claude-plugin/plugin.json'));
assert all(k in d for k in ('name','version','description')), 'missing keys';
assert d['name']=='agent-handoff', 'name'; print('ok')" \
  && pass "plugin.json parses + has required keys" || fail "plugin.json invalid"
```

- [ ] **Step 2: Write the assert helpers + runner**

`tests/assert.sh`:
```bash
# minimal assert helpers for plain-bash tests
_T_FAILED=0
pass(){ echo "PASS: $*"; }
fail(){ echo "FAIL: $*" >&2; _T_FAILED=1; }
assert_eq(){ [ "$1" = "$2" ] && pass "${3:-eq}" || fail "${3:-eq}: '$1' != '$2'"; }
assert_contains(){ case "$1" in *"$2"*) pass "${3:-contains}";; *) fail "${3:-contains}: '$2' not in output";; esac; }
trap '[ "$_T_FAILED" -eq 0 ] || exit 1' EXIT
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -u; cd "$(dirname "$0")"; rc=0
for t in test_*.sh; do echo "== $t =="; bash "$t" || rc=1; done
[ "$rc" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"; exit "$rc"
```

- [ ] **Step 3: Run the manifest test (expect FAIL — no manifest yet)**

Run: `bash tests/test_manifest.sh`
Expected: FAIL (file not found / FAIL line).

- [ ] **Step 4: Write the manifest**

`.claude-plugin/plugin.json`:
```json
{
  "name": "agent-handoff",
  "version": "0.1.0",
  "description": "Multi-agent coordination for Claude: append-only handoff files with exact-tag point-to-point/broadcast channels, plus a generic background-wait pattern.",
  "author": { "name": "Jerron" },
  "license": "MIT"
}
```

- [ ] **Step 5: Run — expect PASS**

Run: `bash tests/run.sh`
Expected: `PASS: plugin.json parses + has required keys` and `ALL TESTS PASSED`.

- [ ] **Step 6: Commit** (ask first — rule #11)
```bash
git init && git add -A && git commit -m "feat: plugin skeleton + manifest + test harness"
```

---

### Task 2: `bg_wait.sh` — generic poll-until-condition

**Files:**
- Create: `scripts/bg_wait.sh`, `tests/test_bg_wait.sh`

- [ ] **Step 1: Write the failing tests**

`tests/test_bg_wait.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
BW="$(cd "$(dirname "$0")/.." && pwd)/scripts/bg_wait.sh"

# success: condition true immediately
bash "$BW" --interval 1 --timeout 5 -- true && pass "succeeds when condition true" || fail "should succeed"

# timeout: condition always false → exit 1 within ~2s
start=$SECONDS
bash "$BW" --interval 1 --timeout 2 -- false; rc=$?
assert_eq "$rc" "1" "times out with rc=1"
[ $((SECONDS - start)) -le 5 ] && pass "timeout bounded" || fail "timeout too slow"

# becomes-true: flag file appears
f="$(mktemp -u)"; ( sleep 2; : > "$f" ) &
bash "$BW" --interval 1 --timeout 10 -- test -f "$f" && pass "detects flag file" || fail "missed flag"
rm -f "$f"
```

- [ ] **Step 2: Run — expect FAIL** (`bash tests/test_bg_wait.sh` → FAIL, script missing)

- [ ] **Step 3: Write `scripts/bg_wait.sh`**
```bash
#!/usr/bin/env bash
# bg_wait.sh — poll a condition command until it succeeds (rc 0) or times out.
# Usage: bg_wait.sh [--interval N] [--timeout N] -- <condition-cmd...>
#   exit 0 = condition met; 1 = timeout; 2 = usage error.
# Pair with the harness's run_in_background so the agent is re-invoked on exit.
set -u
interval=10; timeout=600
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="${2:?}"; shift 2;;
    --timeout)  timeout="${2:?}";  shift 2;;
    --) shift; break;;
    *) echo "usage: bg_wait.sh [--interval N] [--timeout N] -- <cmd...>" >&2; exit 2;;
  esac
done
[ $# -ge 1 ] || { echo "bg_wait: no condition command" >&2; exit 2; }
elapsed=0
while :; do
  if "$@"; then exit 0; fi
  [ "$elapsed" -ge "$timeout" ] && { echo "bg_wait: timeout after ${timeout}s" >&2; exit 1; }
  sleep "$interval"; elapsed=$((elapsed + interval))
done
```

- [ ] **Step 4: Run — expect PASS** (`bash tests/test_bg_wait.sh`)

- [ ] **Step 5: Commit** (ask first)
```bash
git add scripts/bg_wait.sh tests/test_bg_wait.sh && git commit -m "feat: bg_wait.sh generic poll-until-condition"
```

---

### Task 3: `handoff_post.sh` — append-only tagged message

**Files:**
- Create: `scripts/handoff_post.sh`, `tests/test_handoff_post.sh`

- [ ] **Step 1: Write the failing tests**

`tests/test_handoff_post.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
P="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_post.sh"
f="$(mktemp)"; printf 'PRE-EXISTING LINE\n' > "$f"

printf 'hello body\n' | bash "$P" "$f" agentA agentB "first subject"
out="$(cat "$f")"
assert_contains "$out" "PRE-EXISTING LINE" "append-only: prior content kept"
assert_contains "$out" "## [agentA->agentB]" "tag header present"
assert_contains "$out" "first subject" "subject present"
assert_contains "$out" "hello body" "body present"

# safety: backticks and $VARS stored literally (body from stdin, no expansion)
printf 'literal `date` and $HOME stay raw\n' | bash "$P" "$f" agentB agentA "raw"
grep -q 'literal `date` and \$HOME stay raw' "$f" && pass "body stored literally" || fail "body was expanded"
rm -f "$f"

# missing dir → exit 2
printf x | bash "$P" /no/such/dir/x.md a b s; assert_eq "$?" "2" "missing dir → rc 2"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `scripts/handoff_post.sh`**
```bash
#!/usr/bin/env bash
# handoff_post.sh — append a tagged, append-only message section to a handoff file.
# Body is read from STDIN and written LITERALLY (no shell expansion).
# Usage: printf '%s' "<body>" | handoff_post.sh <file> <from> <to> [subject]
#   header: "## [<from>-><to>] <UTC ts> [subject]"   (ASCII '->' so watchers grep it)
set -u
file="${1:?file}"; from="${2:?from}"; to="${3:?to}"; subject="${4:-}"
dir="$(dirname "$file")"
[ -d "$dir" ] || { echo "handoff_post: directory missing: $dir" >&2; exit 2; }
ts="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
body="$(cat)"
{
  printf '\n## [%s->%s] %s %s\n\n' "$from" "$to" "$ts" "$subject"
  printf '%s\n' "$body"
} >> "$file"
echo "posted [$from->$to] -> $file"
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (ask first)
```bash
git add scripts/handoff_post.sh tests/test_handoff_post.sh && git commit -m "feat: handoff_post.sh append-only tagged message"
```

---

### Task 4: `handoff_read.sh` — read latest / by-tag section

**Files:**
- Create: `scripts/handoff_read.sh`, `tests/test_handoff_read.sh`

- [ ] **Step 1: Write the failing tests**

`tests/test_handoff_read.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
P="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_post.sh"
R="$(cd "$(dirname "$0")/.." && pwd)/scripts/handoff_read.sh"
f="$(mktemp)"
printf 'one\n'   | bash "$P" "$f" a b "s1"
printf 'two\n'   | bash "$P" "$f" b a "s2"
latest="$(bash "$R" "$f")"
assert_contains "$latest" "## [b->a]" "latest section is the last posted"
assert_contains "$latest" "two" "latest body present"
case "$latest" in *"## [a->b]"*) fail "latest should not include earlier section";; *) pass "only latest section";; esac
bytag="$(bash "$R" "$f" "a->b")"
assert_contains "$bytag" "one" "tag filter returns matching section"
rm -f "$f"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `scripts/handoff_read.sh`**
```bash
#!/usr/bin/env bash
# handoff_read.sh — print the LATEST tagged section of a handoff file,
# or all sections whose header contains <tag-substr>.
# Usage: handoff_read.sh <file> [tag-substr]
set -u
file="${1:?file}"; tagsub="${2:-}"
[ -f "$file" ] || { echo "handoff_read: no such file: $file" >&2; exit 2; }
if [ -n "$tagsub" ]; then
  awk -v t="$tagsub" '/^## \[/{keep=(index($0,t)>0)} keep' "$file"
else
  awk '/^## \[/{last=NR} {a[NR]=$0} END{for(i=last;i<=NR;i++) print a[i]}' "$file"
fi
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (ask first)
```bash
git add scripts/handoff_read.sh tests/test_handoff_read.sh && git commit -m "feat: handoff_read.sh latest/by-tag section"
```

---

### Task 5: `handoff_watch.sh` — wait for a reply (round-trip)

**Files:**
- Create: `scripts/handoff_watch.sh`, `tests/test_handoff_watch.sh`

- [ ] **Step 1: Write the failing test (round-trip)**

`tests/test_handoff_watch.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
D="$(cd "$(dirname "$0")/.." && pwd)/scripts"
f="$(mktemp)"
printf 'q\n' | bash "$D/handoff_post.sh" "$f" agentA agentB "question"   # A asked B
# B replies after 2s
( sleep 2; printf 'answer 42\n' | bash "$D/handoff_post.sh" "$f" agentB agentA "reply" ) &
out="$(bash "$D/handoff_watch.sh" "$f" "agentB->agentA" 15 1)"; rc=$?
assert_eq "$rc" "0" "watch detects reply (rc 0)"
assert_contains "$out" "agentB->agentA" "printed the reply tag"
assert_contains "$out" "answer 42" "printed reply body"
# timeout path: no matching reply
g="$(mktemp)"; printf 'x\n' | bash "$D/handoff_post.sh" "$g" a b s
bash "$D/handoff_watch.sh" "$g" "zzz->none" 2 1; assert_eq "$?" "1" "timeout → rc 1"
rm -f "$f" "$g"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `scripts/handoff_watch.sh`** (reuses bg_wait.sh)
```bash
#!/usr/bin/env bash
# handoff_watch.sh — background-wait until a NEW section with the given reply tag
# appears, then print it. Engine: bg_wait.sh (the background-wait pattern).
# Usage: handoff_watch.sh <file> <reply-tag> [timeout_sec] [interval_sec]
#   <reply-tag> e.g. "agentB->agentA" (matched in the "## [agentB->agentA] ..." header)
set -u
file="${1:?file}"; tag="${2:?reply-tag}"; timeout="${3:-600}"; interval="${4:-15}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOTE: `grep -c` prints the count AND exits 1 on zero matches, so a `|| echo 0`
# guard would double-print "0\n0" and break the integer compare. Use `|| true`
# (swallow the exit code; count is already on stdout) + `${x:-0}` for the
# file-missing case (grep prints nothing).
base="$(grep -c "^## \[${tag}\]" "$file" 2>/dev/null || true)"; base="${base:-0}"
# Condition: the count of reply-tag sections has grown past the baseline.
if "$here/bg_wait.sh" --interval "$interval" --timeout "$timeout" -- \
     bash -c 'f="$1"; tag="$2"; base="$3";
              n="$(grep -c "^## \[${tag}\]" "$f" 2>/dev/null || true)"; n="${n:-0}";
              [ "$n" -gt "$base" ]' _ "$file" "$tag" "$base"; then
  echo "=== new [${tag}] reply ==="
  awk -v t="[${tag}]" '/^## \[/{last=NR} {a[NR]=$0} END{for(i=last;i<=NR;i++) print a[i]}' "$file"
  exit 0
fi
echo "handoff_watch: timeout — no new [${tag}] within ${timeout}s" >&2
exit 1
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (ask first)
```bash
git add scripts/handoff_watch.sh tests/test_handoff_watch.sh && git commit -m "feat: handoff_watch.sh wait-for-reply (uses bg_wait)"
```

---

### Task 6: `handoff-coordination` skill + protocol reference

**Files:**
- Create: `skills/handoff-coordination/SKILL.md`, `skills/handoff-coordination/references/protocol.md`, `tests/test_skill_handoff.sh`

- [ ] **Step 1: Write the content test**

`tests/test_skill_handoff.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
S="$(cd "$(dirname "$0")/.." && pwd)/skills/handoff-coordination"
head -1 "$S/SKILL.md" | grep -q '^---$' && pass "SKILL.md has frontmatter" || fail "no frontmatter"
grep -q '^name: handoff-coordination$' "$S/SKILL.md" && pass "name set" || fail "name missing"
grep -q 'Using Jerron'"'"'s agent-cooperation skill' "$S/SKILL.md" && pass "announcement line present" || fail "no announcement"
grep -qi 'append-only' "$S/SKILL.md" && pass "append-only documented" || fail "append-only missing"
test -f "$S/references/protocol.md" && pass "protocol.md exists" || fail "protocol.md missing"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `skills/handoff-coordination/SKILL.md`**
```markdown
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
```

- [ ] **Step 4: Write `skills/handoff-coordination/references/protocol.md`**
```markdown
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
```

- [ ] **Step 5: Run — expect PASS** (`bash tests/test_skill_handoff.sh`)

- [ ] **Step 6: Commit** (ask first)
```bash
git add skills/handoff-coordination tests/test_skill_handoff.sh && git commit -m "feat: handoff-coordination skill + protocol reference"
```

---

### Task 7: `background-wait` skill

**Files:**
- Create: `skills/background-wait/SKILL.md`, `tests/test_skill_bgwait.sh`

- [ ] **Step 1: Write the content test**

`tests/test_skill_bgwait.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
S="$(cd "$(dirname "$0")/.." && pwd)/skills/background-wait"
grep -q '^name: background-wait$' "$S/SKILL.md" && pass "name set" || fail "name missing"
grep -qi 'run_in_background' "$S/SKILL.md" && pass "mentions background run" || fail "missing bg run"
grep -qi 'bg_wait.sh' "$S/SKILL.md" && pass "references bg_wait.sh" || fail "no script ref"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `skills/background-wait/SKILL.md`**
```markdown
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
Run `scripts/bg_wait.sh` via the harness's background mechanism:
```
bg_wait.sh [--interval N] [--timeout N] -- <condition-cmd...>
```
- exits 0 the moment `<condition-cmd>` returns 0; exits 1 on timeout.
- Examples:
  - port up: `bg_wait.sh --interval 5 --timeout 300 -- bash -c 'ss -tln | grep -q :7496'`
  - file appears: `bg_wait.sh -- test -f /tmp/done.flag`
  - log marker count grows past N: wrap the grep-count compare in `bash -c '...'`.

`handoff-coordination`'s `handoff_watch.sh` is built on this engine.
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (ask first)
```bash
git add skills/background-wait tests/test_skill_bgwait.sh && git commit -m "feat: background-wait skill"
```

---

### Task 8: `/handoff` slash command

**Files:**
- Create: `commands/handoff.md`, `tests/test_command.sh`

- [ ] **Step 1: Write the content test**

`tests/test_command.sh`:
```bash
#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
C="$(cd "$(dirname "$0")/.." && pwd)/commands/handoff.md"
test -f "$C" && pass "command file exists" || fail "missing command"
for sub in post read watch; do
  grep -q "handoff_${sub}.sh\|/handoff ${sub}\|^### ${sub}\| ${sub} " "$C" \
    && pass "documents $sub" || fail "missing $sub"
done
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Write `commands/handoff.md`**
```markdown
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
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (ask first)
```bash
git add commands/handoff.md tests/test_command.sh && git commit -m "feat: /handoff slash command"
```

---

### Task 9: README + full verification

**Files:**
- Create: `README.md`, `LICENSE`

- [ ] **Step 1: Write `README.md`**
````markdown
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
````

- [ ] **Step 2: Write `LICENSE`** (MIT, author Jerron, year 2026).

- [ ] **Step 3: Make scripts executable**
Run: `chmod +x scripts/*.sh tests/*.sh`

- [ ] **Step 4: Full verification**
Run: `bash tests/run.sh`
Expected: every `test_*.sh` prints PASS lines and the runner ends `ALL TESTS PASSED`.

Run: `python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('manifest ok')"`
Expected: `manifest ok`.

Verify both skills have valid frontmatter:
Run: `for s in skills/*/SKILL.md; do head -1 "$s"; grep '^name:' "$s"; done`
Expected: each starts `---` and shows its `name:`.

- [ ] **Step 5: Commit** (ask first)
```bash
git add README.md LICENSE && git commit -m "docs: README + LICENSE; finalize agent-handoff v0.1.0"
```

---

## Self-Review

- **Spec coverage:** plugin.json (T1) ✓; handoff-coordination skill + protocol + announcement line (T6) ✓; background-wait skill (T7) ✓; shared scripts handoff_watch+bg_wait (T2,T5) + post/read (T3,T4, the command's post/read/watch implemented as testable scripts per spec "command does post|read|watch") ✓; /handoff command (T8) ✓; generalization/no-trade-specifics (neutral `agentA/agentB`, paths as args — enforced across T3–T8) ✓; English-only ✓; tests: round-trip + append-only + post-safety + bg_wait success/timeout + manifest/skill-load (T1–T8) ✓; build location + publish (README T9) ✓.
- **Placeholder scan:** none — every code/test step has full content; commands have expected output.
- **Type/interface consistency:** script names + arg orders consistent across tasks and wrappers — `handoff_post.sh <file> <from> <to> [subject]` (stdin body), `handoff_read.sh <file> [tag-substr]`, `handoff_watch.sh <file> <reply-tag> [timeout] [interval]`, `bg_wait.sh [--interval][--timeout] -- cmd`; the skill/command/README all reference these exact signatures.
- **Rule #11 note:** all "Commit" steps are gated on user approval (no auto-commit); `git init` is in T1 step 6.
