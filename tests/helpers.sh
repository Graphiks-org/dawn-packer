#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }
