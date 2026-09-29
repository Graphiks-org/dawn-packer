#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Cold-cache dry run must be side-effect free: it must still print the flag
# without building protoc or creating the cache.
rm -rf build/host-protoc
cold="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh tvosArm64 static)"
printf '%s\n' "$cold" | grep -q -- '-DPROTOC_EXECUTABLE=' || fail "cold dry-run missing -DPROTOC_EXECUTABLE"
[ ! -e build/host-protoc ] || fail "cold dry-run created the protoc cache"

# Cross target must get the flag; native target must not.
cross="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh tvosArm64 static)"
printf '%s\n' "$cross" | grep -q -- '-DPROTOC_EXECUTABLE=' || fail "cross target missing -DPROTOC_EXECUTABLE"
printf '%s\n' "$cross" | grep -q -- '-DCMAKE_TOOLCHAIN_FILE=' || fail "cross target missing toolchain"

native="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh macosArm64 static)"
if printf '%s\n' "$native" | grep -q -- '-DPROTOC_EXECUTABLE='; then
  fail "native target must not receive -DPROTOC_EXECUTABLE"
fi

# linuxArm64 produces no artifacts on this macOS host, so only its wiring is
# verifiable here. It is a host-native target on its own Linux runner: it must
# receive neither a toolchain file nor a host protoc.
linux_arm64="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh linuxArm64 static)"
if printf '%s\n' "$linux_arm64" | grep -q -- '-DCMAKE_TOOLCHAIN_FILE='; then
  fail "linuxArm64 must not receive -DCMAKE_TOOLCHAIN_FILE"
fi
if printf '%s\n' "$linux_arm64" | grep -q -- '-DPROTOC_EXECUTABLE='; then
  fail "linuxArm64 must not receive -DPROTOC_EXECUTABLE"
fi

# Android targets forward their matrix entry's ABI as
# -DCMAKE_ANDROID_ARCH_ABI; native targets must not.
android="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh androidNativeArm64 static)"
printf '%s\n' "$android" | grep -q -- '-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a' \
  || fail "android target missing -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
if printf '%s\n' "$native" | grep -q -- '-DCMAKE_ANDROID_ARCH_ABI'; then
  fail "native target must not receive -DCMAKE_ANDROID_ARCH_ABI"
fi

# The host protoc builder is idempotent and prints an executable path.
path="$(bash scripts/build-host-protoc.sh --print-path)"
[ -x "$path" ] || fail "host protoc not executable: $path"
again="$(bash scripts/build-host-protoc.sh --print-path)"
assert_eq "$again" "$path"
"$path" --version >/dev/null || fail "protoc does not run"
pass "build-target-protoc"
