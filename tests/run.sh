#!/usr/bin/env bash
set -u; cd "$(dirname "$0")"; rc=0
for t in test_*.sh; do echo "== $t =="; bash "$t" || rc=1; done
[ "$rc" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"; exit "$rc"
