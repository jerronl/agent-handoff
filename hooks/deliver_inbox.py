#!/usr/bin/env python3
# UserPromptSubmit hook (ALL bots): deliver unread handoff messages straight into
# context on EVERY user prompt — the reliable Layer-1 delivery that does NOT depend
# on a long-lived watcher process or the model arming anything at session start.
#
# Why this exists — two chronic failure modes of the run_in_background watcher:
#   (1) "never armed": the SessionStart arm directive is skipped when the operator's
#       first message grabs attention -> the bot is silently deaf until someone notices.
#   (2) "preset swallow": a keepalive re-arm presets watcher state to current to avoid
#       re-flooding, so a message that landed in the death gap is marked seen and never
#       delivered.
# This hook removes both: it fires on every prompt (no model action, no live process)
# and advances its delivered-offset only AFTER content is emitted into context — never
# presets to current except at genuine first-ever init (so it won't dump full history).
#
# Contract (verified against code.claude.com/docs/en/hooks.md):
#   - UserPromptSubmit fires before Claude processes each prompt.
#   - stdout on exit 0 is injected into the model's context for that turn.
#   - stdin is a JSON object with a `cwd` field.
# We ALWAYS exit 0 (never block the user's prompt). Empty stdout => nothing injected.
#
# Channel source: this bot's `.handoff_channels` (walk up from cwd), the SAME file the
# SessionStart arm hook uses — one `file:tag` watch_handoff pair per line, `#` comments
# allowed; tag may be a regex (e.g. `.*(->|->)me`). Sections are extracted PRECISELY by
# matching header (not a blind line-range tail) so messages addressed to other tags in a
# shared file never leak. State lives in a SEPARATE namespace
# (/tmp/_handoff_delivered_<basename>_<tag>.off) so Layer-2 watchers and this hook never
# clobber each other.
import json
import os
import re
import sys

ANY_HDR = re.compile(r'^## \[')


def find_config(cwd):
    d = cwd or os.getcwd()
    while d and d != '/':
        c = os.path.join(d, '.handoff_channels')
        if os.path.isfile(c):
            return c
        d = os.path.dirname(d)
    return None


def offfile(f, tag):
    return '/tmp/_handoff_delivered_%s_%s.off' % (os.path.basename(f), tag)


def read_offset(off):
    try:
        with open(off) as fh:
            return int(fh.read().split()[0])
    except Exception:
        return 0


def write_offset(off, count):
    try:
        with open(off, 'w') as fh:
            fh.write('%d\n' % count)
    except Exception:
        pass


def new_sections(f, tag):
    """Return (list_of_new_section_texts, count_advanced_to) or (None, None) to skip."""
    try:
        hdr = re.compile(r'^## \[' + tag + r'\]')
    except re.error:
        return None, None
    try:
        with open(f, encoding='utf-8', errors='replace') as fh:
            lines = fh.readlines()
    except Exception:
        return None, None

    matches = [i for i, ln in enumerate(lines) if hdr.match(ln)]
    cur = len(matches)
    off = offfile(f, tag)

    if not os.path.exists(off):
        write_offset(off, cur)            # genuine first-ever init -> preset once, emit nothing
        return None, None

    lc = read_offset(off)
    if cur < lc:                          # file shrank/rotated -> resync, emit nothing
        write_offset(off, cur)
        return None, None
    if cur == lc:
        return None, None

    out = []
    for mi in matches[lc:cur]:            # only the brand-new matching sections
        j = mi + 1
        while j < len(lines) and not ANY_HDR.match(lines[j]):
            j += 1
        out.append(''.join(lines[mi:j]).rstrip('\n'))
    write_offset(off, cur)
    return out, cur


def main():
    raw = sys.stdin.read() if not sys.stdin.isatty() else ''
    try:
        cwd = json.loads(raw).get('cwd', '') if raw else ''
    except Exception:
        cwd = ''
    conf = find_config(cwd)
    if not conf:
        return 0

    blocks = []
    try:
        with open(conf) as fh:
            cfg_lines = fh.readlines()
    except Exception:
        return 0

    for line in cfg_lines:
        line = line.rstrip('\r\n').strip()
        if not line or line.startswith('#'):
            continue
        f = line.split(':', 1)[0]
        tag = line.rsplit(':', 1)[-1]
        if not os.path.isfile(f):
            continue
        secs, cur = new_sections(f, tag)
        if secs:
            blocks.append(
                '### 📨 新 handoff 消息 — %s (频道 tag: %s) — %d 条新 section\n%s'
                % (f, tag, len(secs), '\n\n'.join(secs))
            )

    if not blocks:
        return 0

    sys.stdout.write(
        '📬 你有发往本频道的新 handoff 消息(UserPromptSubmit 自动投递,无需挂 watcher)。'
        '请在回应用户前先读完、按需处理:\n\n' + '\n\n'.join(blocks) + '\n'
    )
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)            # never break the user's prompt
