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
# A linkage member that is not a string (a nested list, say) must be rejected
# with a clean ERROR line. Testing membership first made an unhashable member
# raise TypeError and print a traceback instead of reporting the bad matrix.
link_err="$(python3 "$root/packaging/validate-matrix.py" \
  "$root/tests/fixtures/matrix-bad-linkages-non-string.json" 2>&1 >/dev/null || true)"
printf '%s\n' "$link_err" \
  | grep -q '^ERROR: targets\[0\]: linkages must be a list of strings$' \
  || fail "non-string linkage must be reported cleanly, got: $link_err"
if printf '%s\n' "$link_err" | grep -q 'Traceback'; then
  fail "non-string linkage must not raise a traceback"
fi
pass "validate-matrix"
