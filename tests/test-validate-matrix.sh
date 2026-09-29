#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

python3 "$root/packaging/validate-matrix.py" "$root/targets/matrix.json" >/dev/null || fail "real matrix should be valid"
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad.json" >/dev/null 2>&1; then
  fail "bad matrix should be rejected"
fi
# Ruling P14: android entries must name a valid NDK ABI...
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad-android-abi.json" >/dev/null 2>&1; then
  fail "wrong androidAbi should be rejected"
fi
# ...and non-android entries must not carry one.
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad-extra-android-abi.json" >/dev/null 2>&1; then
  fail "androidAbi on a non-android entry should be rejected"
fi
python3 "$root/scripts/matrix.py" get linuxX64 | grep -q '"triple": "x86_64-unknown-linux-gnu"' || fail "matrix.py get failed"
pass "validate-matrix"
