# minimal assert helpers for plain-bash tests
_T_FAILED=0
pass(){ echo "PASS: $*"; }
fail(){ echo "FAIL: $*" >&2; _T_FAILED=1; }
assert_eq(){ [ "$1" = "$2" ] && pass "${3:-eq}" || fail "${3:-eq}: '$1' != '$2'"; }
assert_contains(){ case "$1" in *"$2"*) pass "${3:-contains}";; *) fail "${3:-contains}: '$2' not in output";; esac; }
trap '[ "$_T_FAILED" -eq 0 ] || exit 1' EXIT
