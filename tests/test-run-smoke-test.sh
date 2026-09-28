#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Ruling P1: derive the host target instead of hardcoding linuxX64.
host_target() {
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) printf '%s\n' macosArm64 ;;
    Linux/x86_64) printf '%s\n' linuxX64 ;;
    Linux/aarch64 | Linux/arm64) printf '%s\n' linuxArm64 ;;
    *) return 1 ;;
  esac
}

if ! target="$(host_target)"; then
  echo "SKIP: unsupported host $(uname -s)/$(uname -m)"
  exit 0
fi

archive="$(ls dist/"$target"/dawn-*-"$target"-*.tar.gz 2>/dev/null | head -n1 || true)"
[ -n "$archive" ] || { echo "SKIP: archive not built for $target"; exit 0; }

# Ruling P10: --link-only must compile and link without executing.
link_only_out="$(bash scripts/run-smoke-test.sh "$archive" --link-only)"
printf '%s\n' "$link_only_out"
printf '%s\n' "$link_only_out" | grep -q '^link OK$' || fail "link-only did not print 'link OK'"

run_out="$(bash scripts/run-smoke-test.sh "$archive")"
printf '%s\n' "$run_out"
printf '%s\n' "$run_out" | grep -q '^link OK$' || fail "run did not print 'link OK'"
printf '%s\n' "$run_out" | grep -q '^dawn-packer smoke test OK$' || fail "run did not print 'dawn-packer smoke test OK'"

pass "run-smoke-test"
