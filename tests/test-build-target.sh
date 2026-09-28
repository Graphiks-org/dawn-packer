#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) host=macosArm64 ;;
  Darwin-x86_64) echo "SKIP: macosX64 is out of scope"; exit 0 ;;
  Linux-x86_64) host=linuxX64 ;;
  Linux-aarch64) host=linuxArm64 ;;
  *) echo "SKIP: unsupported host"; exit 0 ;;
esac

bash scripts/build-target.sh "$host" static
assert_file "dist/$host/static/install/.dawn-packer-install"

lib="$(find "dist/$host/static/install" -name 'libwebgpu_dawn.a' -print -quit)"
[ -n "$lib" ] || fail "libwebgpu_dawn.a not installed"
header="$(find "dist/$host/static/install" -path '*webgpu/webgpu.h' -print -quit)"
[ -n "$header" ] || fail "webgpu/webgpu.h not installed"
pass "build-target $host static"
