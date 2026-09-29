#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# macosArm64 must carry Kotlin/Native 2.4.20's macOS minimum (12.0) via
# extraCmakeArgs, and must still receive no host protoc (no toolchain file, so
# cross detection is unchanged).
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

# Regression: macOS /bin/bash is 3.2, which has no `mapfile`. The CI Apple jobs
# run this script with that interpreter, so a dry run under /bin/bash must work
# and must still carry the extra cmake args.
if [ -x /bin/bash ]; then
  bashed="$(DAWN_PACKER_DRY_RUN=1 /bin/bash scripts/build-target.sh macosArm64 static)" \
    || fail "build-target.sh failed under /bin/bash (bash 3.2 compatibility)"
  printf '%s\n' "$bashed" | grep -q -- '-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0' \
    || fail "/bin/bash run lost the extra cmake args"
fi

pass "matrix-extra-args"
