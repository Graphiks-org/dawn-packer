#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/install/include/webgpu" "$work/install/lib/cmake/Dawn"
printf '#pragma once\n' > "$work/install/include/webgpu/webgpu.h"
printf 'module;\n' > "$work/install/include/webgpu/webgpu.ixx"
printf 'fake-archive\n' > "$work/install/lib/libwebgpu_dawn.a"
printf 'cmake-package\n' > "$work/install/lib/cmake/Dawn/DawnConfig.cmake"

entry="$(python3 scripts/matrix.py get linuxX64)"

# Backward compatibility: without --provenance the legacy empty objects remain.
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
# Finding (minor): the inventory must be exhaustive over what package.sh
# stages: .ixx headers and Dawn's lib/cmake package files included.
grep -q '"path": "include/webgpu/webgpu.ixx"' "$work/manifest.json" || fail ".ixx missing from manifest"
grep -q '"path": "lib/cmake/Dawn/DawnConfig.cmake"' "$work/manifest.json" || fail "lib/cmake missing from manifest"
grep -q '"compiler": {}' "$work/manifest.json" || fail "legacy compiler object changed"

# Finding 4: --provenance populates compiler id/version/flags and cmake flags.
cat > "$work/provenance.json" <<'JSON'
{
  "compiler": { "id": "apple-clang", "version": "17.0.0", "flags": ["-O2"] },
  "cmake": { "buildType": "Release", "flags": ["-DDAWN_PACKER_LINKAGE=STATIC", "-DDAWN_ENABLE_METAL=ON"] }
}
JSON
python3 packaging/make-manifest.py \
  --install-dir "$work/install" \
  --kotlin-target linuxX64 \
  --entry-json "$entry" \
  --dawn-tag chromium/7200 \
  --dawn-revision deadbeefcafe \
  --linkage static \
  --provenance "$work/provenance.json" \
  --out "$work/manifest-prov.json" >/dev/null

python3 packaging/validate-manifest.py "$work/manifest-prov.json" >/dev/null || fail "provenance manifest should validate"
grep -q '"id": "apple-clang"' "$work/manifest-prov.json" || fail "compiler.id missing from manifest"
grep -q '"version": "17.0.0"' "$work/manifest-prov.json" || fail "compiler.version missing from manifest"
grep -q '"flags": \[' "$work/manifest-prov.json" || fail "flags missing from manifest"
grep -q -- '-DDAWN_ENABLE_METAL=ON' "$work/manifest-prov.json" || fail "cmake flags missing from manifest"
pass "make-manifest"
