#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

work="$(mktemp -d)"
tag_file="$root/build/dawn-tag.txt"
rev_file="$root/build/dawn-revision.txt"
tag_backup="$work/dawn-tag.txt"
rev_backup="$work/dawn-revision.txt"
had_tag=0
had_rev=0
if [ -f "$tag_file" ]; then had_tag=1; cp "$tag_file" "$tag_backup"; fi
if [ -f "$rev_file" ]; then had_rev=1; cp "$rev_file" "$rev_backup"; fi
restore() {
  mkdir -p "$root/build"
  if [ "$had_tag" = 1 ]; then cp "$tag_backup" "$tag_file"; else rm -f "$tag_file"; fi
  if [ "$had_rev" = 1 ]; then cp "$rev_backup" "$rev_file"; else rm -f "$rev_file"; fi
  rm -rf "$work"
}
trap restore EXIT
install="$work/install"
mkdir -p "$install/include/webgpu" "$install/lib"
printf '#pragma once\n' > "$install/include/webgpu/webgpu.h"
printf 'fake-archive\n' > "$install/lib/libwebgpu_dawn.a"
touch "$install/.dawn-packer-install"
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
