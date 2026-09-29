#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

python3 "$root/packaging/validate-matrix.py" "$root/targets/matrix.json" >/dev/null || fail "real matrix should be valid"
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad.json" >/dev/null 2>&1; then
  fail "bad matrix should be rejected"
fi
# android entries must name a valid NDK ABI...
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad-android-abi.json" >/dev/null 2>&1; then
  fail "wrong androidAbi should be rejected"
fi
# ...and non-android entries must not carry one.
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad-extra-android-abi.json" >/dev/null 2>&1; then
  fail "androidAbi on a non-android entry should be rejected"
fi
# extraCmakeArgs, when present, must be a list of strings.
if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/matrix-bad-extra-cmake-args.json" >/dev/null 2>&1; then
  fail "non-list extraCmakeArgs should be rejected"
fi
python3 "$root/scripts/matrix.py" get linuxX64 | grep -q '"triple": "x86_64-unknown-linux-gnu"' || fail "matrix.py get failed"
# linkages, when present, must be a non-empty subset of static/shared.
for fixture in matrix-bad-linkages-empty matrix-bad-linkages-unknown; do
  if python3 "$root/packaging/validate-matrix.py" "$root/tests/fixtures/$fixture.json" >/dev/null 2>&1; then
    fail "$fixture should be rejected"
  fi
done
pass "validate-matrix"
