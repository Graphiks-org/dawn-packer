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

passed=0
skipped=0
failed=0
failed_tests=()
for test_script in tests/test-*.sh; do
  echo "=== $test_script ==="
  if [ "${DAWN_PACKER_SKIP_HEAVY:-0}" = "1" ] && is_heavy "$test_script"; then
    echo "SKIP (heavy): set DAWN_PACKER_SKIP_HEAVY=0 to run"
    skipped=$((skipped + 1))
    continue
  fi
  # Stream output while capturing it, so a test that exits 0 with a `SKIP:`
  # notice is tallied as skipped rather than passed.
  tmp_out="$(mktemp)"
  set +e
  bash "$test_script" 2>&1 | tee "$tmp_out"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_tests+=("$test_script")
  elif grep -q '^SKIP' "$tmp_out"; then
    skipped=$((skipped + 1))
  else
    passed=$((passed + 1))
  fi
  rm -f "$tmp_out"
done

echo
echo "SUMMARY: $passed passed, $skipped skipped, $failed failed"
if [ "$failed" -gt 0 ]; then
  echo "FAILING TESTS:"
  for test_script in "${failed_tests[@]}"; do
    echo "  $test_script"
  done
fi
[ "$failed" -eq 0 ]
