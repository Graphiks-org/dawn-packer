#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Heavy tests perform a full native Dawn build (static and shared) or rebuild
# the host protoc. They run by default, as required by the acceptance suite.
# Set DAWN_PACKER_SKIP_HEAVY=1 for a fast feedback loop on the validator,
# fixture and dry-run tests only.
heavy_tests=(
  tests/test-build-target.sh
  tests/test-shared-symbols.sh
  tests/test-build-target-protoc.sh
)

is_heavy() {
  local candidate="$1" heavy
  for heavy in "${heavy_tests[@]}"; do
    if [ "$candidate" = "$heavy" ]; then
      return 0
    fi
  done
  return 1
}

failed=0
for test_script in tests/test-*.sh; do
  echo "=== $test_script ==="
  if [ "${DAWN_PACKER_SKIP_HEAVY:-0}" = "1" ] && is_heavy "$test_script"; then
    echo "SKIP (heavy): set DAWN_PACKER_SKIP_HEAVY=0 to run"
    continue
  fi
  if ! bash "$test_script"; then
    failed=1
  fi
done
exit "$failed"
