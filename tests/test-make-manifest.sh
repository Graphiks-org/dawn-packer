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
mkdir -p "$work/install/bin"
printf 'dll\n' > "$work/install/bin/webgpu_dawn.dll"
mkdir -p "$work/install/share/doc"
printf 'readme\n' > "$work/install/share/doc/note.txt"
# The build marker lives in the install tree, so the fixture must carry one for
# the exclusion assertion below to mean anything.
touch "$work/install/.dawn-packer-install"

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
# The inventory must be exhaustive over what package.sh stages: .ixx headers
# and Dawn's lib/cmake package files included.
grep -q '"path": "include/webgpu/webgpu.ixx"' "$work/manifest.json" || fail ".ixx missing from manifest"
grep -q '"path": "lib/cmake/Dawn/DawnConfig.cmake"' "$work/manifest.json" || fail "lib/cmake missing from manifest"

# The inventory enumerates the staged tree, so a directory nobody anticipated
# still reaches the manifest. This is the regression for the Windows DLL, which
# an allowlist of globs dropped in silence.
grep -q '"path": "share/doc/note.txt"' "$work/manifest.json" || fail "unanticipated directory missing from manifest"
grep -q '"path": ".dawn-packer-install"' "$work/manifest.json" && fail "the install marker must not be inventoried"
grep -q '"path": "manifest.json"' "$work/manifest.json" && fail "the manifest must not inventory itself"

grep -q '"path": "bin/webgpu_dawn.dll"' "$work/manifest.json" || fail "bin/ missing from manifest"

grep -q '"compiler": {}' "$work/manifest.json" || fail "legacy compiler object changed"

# --provenance populates compiler id/version/flags and cmake flags.
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

# Manifest paths are a portable, shipped contract: they must use forward slashes
# whatever host produced them. Build a PureWindowsPath explicitly so this fails
# on macOS/Linux too if the conversion regresses.
python3 - <<'PY' || fail "manifest paths must use forward slashes"
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location("make_manifest", "packaging/make-manifest.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

windows = pathlib.PureWindowsPath("include", "webgpu", "webgpu.h")
converted = module.portable_path(windows)
if converted != "include/webgpu/webgpu.h":
    raise SystemExit(f"expected include/webgpu/webgpu.h, got {converted!r}")
PY
pass "make-manifest"
