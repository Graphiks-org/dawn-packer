#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Cross target must get the flag; native target must not.
cross="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh tvosArm64 static)"
printf '%s\n' "$cross" | grep -q -- '-DPROTOC_EXECUTABLE=' || fail "cross target missing -DPROTOC_EXECUTABLE"
printf '%s\n' "$cross" | grep -q -- '-DCMAKE_TOOLCHAIN_FILE=' || fail "cross target missing toolchain"

native="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh macosArm64 static)"
if printf '%s\n' "$native" | grep -q -- '-DPROTOC_EXECUTABLE='; then
  fail "native target must not receive -DPROTOC_EXECUTABLE"
fi

# The host protoc builder is idempotent and prints an executable path.
path="$(bash scripts/build-host-protoc.sh | tail -n1)"
[ -x "$path" ] || fail "host protoc not executable: $path"
again="$(bash scripts/build-host-protoc.sh | tail -n1)"
assert_eq "$again" "$path"
"$path" --version >/dev/null || fail "protoc does not run"
pass "build-target-protoc"
