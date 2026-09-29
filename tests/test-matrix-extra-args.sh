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
for target in macosArm64 iosArm64 tvosArm64 androidNativeX64 mingwX64; do
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

# The backend vocabulary must cover everything Dawn actually builds on Windows.
# Dawn forces D3D11 on for Win32, so the matrix has to be able to name it.
fixture="$(mktemp -d)/matrix.json"
python3 - "$fixture" <<'PY'
import json, sys
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps({
    "schemaVersion": 1,
    "targets": [
        {"kotlinTarget": "mingwX64", "triple": "x86_64-pc-windows-gnu", "os": "windows",
         "arch": "x64", "runner": "windows-2022", "toolchain": "",
         "backends": ["d3d12", "d3d11", "vulkan", "null"], "status": "v1"},
    ],
}))
PY
python3 packaging/validate-matrix.py "$fixture" >/dev/null || fail "d3d11 is not a known backend"

# The Windows target is native (host == target), so it takes no toolchain, no
# host protoc, and it must name every backend Dawn actually builds.
windows="$(DAWN_PACKER_DRY_RUN=1 bash scripts/build-target.sh mingwX64 shared)"
printf '%s\n' "$windows" | grep -q -- '-DDAWN_ENABLE_D3D11=ON' || fail "mingwX64 missing -DDAWN_ENABLE_D3D11=ON"
printf '%s\n' "$windows" | grep -q -- '-DDAWN_ENABLE_VULKAN=ON' || fail "mingwX64 missing -DDAWN_ENABLE_VULKAN=ON"
if printf '%s\n' "$windows" | grep -q -- '-DCMAKE_TOOLCHAIN_FILE'; then
  fail "mingwX64 must not receive a toolchain file"
fi
if printf '%s\n' "$windows" | grep -q -- '-DPROTOC_EXECUTABLE'; then
  fail "mingwX64 must not receive -DPROTOC_EXECUTABLE"
fi

pass "matrix-extra-args"
