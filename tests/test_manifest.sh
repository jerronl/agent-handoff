#!/usr/bin/env bash
set -u; . "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -c "import json,sys; d=json.load(open('$ROOT/.claude-plugin/plugin.json'));
assert all(k in d for k in ('name','version','description')), 'missing keys';
assert d['name']=='agent-handoff', 'name'; print('ok')" \
  && pass "plugin.json parses + has required keys" || fail "plugin.json invalid"
