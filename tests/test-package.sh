#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
install="$work/install"
mkdir -p "$install/include/webgpu" "$install/lib"
printf '#pragma once\n' > "$install/include/webgpu/webgpu.h"
printf 'fake-archive\n' > "$install/lib/libwebgpu_dawn.a"
mkdir -p build
printf 'chromium/7200\n' > build/dawn-tag.txt
printf 'deadbeefcafe\n' > build/dawn-revision.txt

DAWN_PACKER_INSTALL_DIR="$install" DAWN_PACKER_DIST_DIR="$work/dist" \
  bash scripts/package.sh linuxX64 static

archive="$work/dist/linuxX64/dawn-chromium-7200-linuxX64-static.tar.gz"
assert_file "$archive"
tar tzf "$archive" | grep -q '^include/webgpu/webgpu.h$' || fail "header missing from archive"
tar tzf "$archive" | grep -q '^lib/libwebgpu_dawn.a$' || fail "library missing from archive"
tar tzf "$archive" | grep -q '^manifest.json$' || fail "manifest missing from archive"
pass "package"
