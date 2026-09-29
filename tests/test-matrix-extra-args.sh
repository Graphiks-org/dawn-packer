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

# The Linux targets must build with Clang. Dawn's dawncpp_module is a C++20
# module target, and CMake 3.28 -- the version on the Ubuntu runners -- can
# only scan the import graph for Clang 16+; with GCC 13 the configure step
# fails with "the compiler does not provide a way to discover the import
# graph". Clang also keeps one compiler family across the whole matrix, since
# Apple and Android targets already build with a Clang derivative.
for target in linuxX64 linuxArm64; do
  run="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh "$target" static)"
  printf '%s\n' "$run" | grep -q -- '-DCMAKE_C_COMPILER=clang' \
    || fail "$target missing -DCMAKE_C_COMPILER=clang"
  printf '%s\n' "$run" | grep -q -- '-DCMAKE_CXX_COMPILER=clang++' \
    || fail "$target missing -DCMAKE_CXX_COMPILER=clang++"
done

# Forcing a host compiler would break the cross targets, whose compiler comes
# from their toolchain file or from Xcode.
for target in macosArm64 iosArm64 tvosArm64 androidNativeX64; do
  run="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh "$target" static)"
  if printf '%s\n' "$run" | grep -q -- 'CMAKE_C_COMPILER'; then
    fail "$target must not receive a forced CMAKE_C_COMPILER"
  fi
done

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
