#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

assert_file "$root/packaging/validate-manifest.py"

if python3 packaging/validate-manifest.py tests/fixtures/manifest-bad.json >/dev/null 2>&1; then
  fail "incomplete manifest must be rejected"
fi

if python3 packaging/validate-manifest.py tests/fixtures/manifest-missing-cmake.json >/dev/null 2>&1; then
  fail "manifest missing cmake must be rejected"
fi
pass "validate-manifest"
