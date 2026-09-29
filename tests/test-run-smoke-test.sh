#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Derive the host target instead of hardcoding linuxX64.
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

# Stop picking an arbitrary archive. `ls` sorts shared before static, so the
# old `head -n1` silently tested only the shared variant. Test every linkage
# that has an archive, and keep stderr pristine.
tested=0
for linkage in static shared; do
  archive="$(ls dist/"$target"/dawn-*-"$target"-"$linkage".tar.gz 2>/dev/null | head -n1 || true)"
  if [ -z "$archive" ]; then
    echo "SKIP: no $linkage archive built for $target"
    continue
  fi

  err="$(mktemp)"
  # --link-only must compile and link without executing.
  link_only_out="$(bash scripts/run-smoke-test.sh "$archive" --link-only 2>"$err")"
  [ ! -s "$err" ] || { cat "$err" >&2; rm -f "$err"; fail "smoke test wrote to stderr"; }
  printf '%s\n' "$link_only_out"
  printf '%s\n' "$link_only_out" | grep -q '^link OK$' || fail "link-only did not print 'link OK'"
  if printf '%s\n' "$link_only_out" | grep -q 'dawn-packer smoke test OK'; then
    fail "link-only executed the binary"
  fi

  run_out="$(bash scripts/run-smoke-test.sh "$archive" 2>"$err")"
  [ ! -s "$err" ] || { cat "$err" >&2; rm -f "$err"; fail "smoke test wrote to stderr"; }
  rm -f "$err"
  printf '%s\n' "$run_out"
  printf '%s\n' "$run_out" | grep -q '^link OK$' || fail "run did not print 'link OK'"
  printf '%s\n' "$run_out" | grep -q '^dawn-packer smoke test OK$' || fail "run did not print 'dawn-packer smoke test OK'"
  tested=$((tested + 1))
done

if [ "$tested" -eq 0 ]; then
  echo "SKIP: no static/shared archive built for $target"
  exit 0
fi

pass "run-smoke-test"
