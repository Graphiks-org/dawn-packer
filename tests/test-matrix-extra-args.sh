#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Finding 2: macosArm64 must carry Kotlin/Native 2.4.20's macOS minimum (12.0)
# via extraCmakeArgs, and must still receive no host protoc (no toolchain file,
# so cross detection is unchanged).
dry="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh macosArm64 static)"
printf '%s\n' "$dry" | grep -q -- '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0' \
  || fail "macosArm64 missing -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
if printf '%s\n' "$dry" | grep -q -- '-DPROTOC_EXECUTABLE='; then
  fail "macosArm64 must not receive -DPROTOC_EXECUTABLE"
fi

# A native target without extraCmakeArgs must not inherit a macOS floor.
linux="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh linuxX64 static)"
if printf '%s\n' "$linux" | grep -q -- 'CMAKE_OSX_DEPLOYMENT_TARGET'; then
  fail "linuxX64 must not receive a macOS deployment target"
fi

pass "matrix-extra-args"
