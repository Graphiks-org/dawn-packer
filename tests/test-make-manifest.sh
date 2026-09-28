#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/install/include/webgpu" "$work/install/lib"
printf '#pragma once\n' > "$work/install/include/webgpu/webgpu.h"
printf 'fake-archive\n' > "$work/install/lib/libwebgpu_dawn.a"

entry="$(python3 scripts/matrix.py get linuxX64)"
python3 packaging/make-manifest.py \
  --install-dir "$work/install" \
  --kotlin-target linuxX64 \
  --entry-json "$entry" \
  --dawn-tag chromium/7200 \
  --dawn-revision deadbeefcafe \
  --linkage static \
  --out "$work/manifest.json" >/dev/null

python3 packaging/validate-manifest.py "$work/manifest.json" >/dev/null || fail "manifest should validate"
grep -q '"path": "include/webgpu/webgpu.h"' "$work/manifest.json" || fail "headers missing from manifest"
grep -q '"path": "lib/libwebgpu_dawn.a"' "$work/manifest.json" || fail "library missing from manifest"
pass "make-manifest"
