#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

target="${1:?usage: build-target.sh <kotlinTarget> [static|shared]}"
linkage_lc="$(printf '%s' "${2:-static}" | tr '[:upper:]' '[:lower:]')"
case "$linkage_lc" in
  static) linkage=STATIC ;;
  shared) linkage=SHARED ;;
  *) echo "linkage must be static or shared" >&2; exit 2 ;;
esac

entry="$(python3 scripts/matrix.py get "$target")"
toolchain="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["toolchain"])' "$entry")"
backends="$(python3 scripts/matrix.py backends "$target")"
# Ruling P14: Android serves four ABIs but a single CMake toolchain file cannot
# pick between them, so the ABI lives on the matrix entry and is forwarded here.
android_abi="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("androidAbi", ""))' "$entry")"
# Finding 2: optional per-target extra configure flags (e.g. macosArm64's
# -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0). These do not touch the toolchain field,
# so native targets still receive no host protoc.
# Read with a `while` loop, NOT `mapfile` (bash 4+): macOS ships /bin/bash 3.2
# and the CI Apple jobs run this script with it.
extra_cmake_args=()
while IFS= read -r arg; do
  if [ -n "$arg" ]; then
    extra_cmake_args+=("$arg")
  fi
done < <(python3 -c 'import json,sys
for arg in json.loads(sys.argv[1]).get("extraCmakeArgs", []):
    print(arg)' "$entry")

backend_flags=()
for backend in $backends; do
  case "$backend" in
    metal) backend_flags+=("-DDAWN_ENABLE_METAL=ON") ;;
    vulkan) backend_flags+=("-DDAWN_ENABLE_VULKAN=ON") ;;
    d3d12) backend_flags+=("-DDAWN_ENABLE_D3D12=ON") ;;
    gles) backend_flags+=("-DDAWN_ENABLE_OPENGLES=ON") ;;
    desktop_gl) backend_flags+=("-DDAWN_ENABLE_DESKTOP_GL=ON") ;;
    null) backend_flags+=("-DDAWN_ENABLE_NULL=ON") ;;
    *) echo "unknown backend: $backend" >&2; exit 2 ;;
  esac
done
# Guard before expanding "${backend_flags[@]}": under `set -u`, bash 3.2
# (macOS /bin/bash) treats an empty array expansion as an unbound variable.
if [ "${#backend_flags[@]}" -eq 0 ]; then
  echo "no backends configured for $target" >&2
  exit 2
fi

build_dir="$root/build/$target/$linkage_lc"
install_dir="$root/dist/$target/$linkage_lc/install"

cmake_args=(
  -S "$root" -B "$build_dir" -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DDAWN_PACKER_LINKAGE="$linkage"
  -DDAWN_EMIT_COVERAGE=OFF
  -DCMAKE_INSTALL_PREFIX="$install_dir"
)
if [ "${#extra_cmake_args[@]}" -gt 0 ]; then
  cmake_args+=("${extra_cmake_args[@]}")
fi
if [ -n "$android_abi" ]; then
  cmake_args+=("-DCMAKE_ANDROID_ARCH_ABI=$android_abi")
fi
if [ -n "$toolchain" ]; then
  cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=$root/$toolchain")
  # Dawn's protobuf.cmake hard-fails when cross-compiling unless a host protoc
  # is supplied. Only cross builds (non-empty toolchain) need it; native targets
  # must not receive the flag.
  if [ "${DAWN_PACKER_DRY_RUN:-0}" = "1" ]; then
    # Dry run must be side-effect free: report the path a real run would pass
    # (the deterministic cache path) without invoking the protoc build.
    protoc_path="$root/build/host-protoc/bin/protoc"
  else
    protoc_path="$(bash scripts/build-host-protoc.sh --print-path)"
  fi
  cmake_args+=("-DPROTOC_EXECUTABLE=$protoc_path")
fi

if [ "${DAWN_PACKER_DRY_RUN:-0}" = "1" ]; then
  printf 'cmake'; printf ' %q' "${cmake_args[@]}" "${backend_flags[@]}"; printf '\n'
  exit 0
fi

rm -rf "$build_dir" "$install_dir"
mkdir -p "$build_dir" "$install_dir"
cmake "${cmake_args[@]}" "${backend_flags[@]}"

# Finding 4: capture the real compiler identity and the exact configure
# arguments so packaging can record provenance (spec section 5.3) instead of empty
# objects. Written next to the install tree; scripts/package.sh picks it up when
# present and degrades gracefully when absent.
provenance="$root/dist/$target/$linkage_lc/packer-provenance.json"
cmake_cache="$build_dir/CMakeCache.txt"
compiler_path="$(sed -n 's/^CMAKE_CXX_COMPILER:[^=]*=//p' "$cmake_cache" | head -n1)"
compiler_flags="$(sed -n 's/^CMAKE_CXX_FLAGS:[^=]*=//p' "$cmake_cache" | head -n1)"
compiler_version=""
if [ -n "$compiler_path" ] && [ -x "$compiler_path" ]; then
  compiler_version="$("$compiler_path" --version 2>/dev/null | head -n1 || true)"
fi
python3 - "$provenance" "$compiler_path" "$compiler_version" "$compiler_flags" -- \
  "${cmake_args[@]}" "${backend_flags[@]}" <<'PY'
import json
import os
import re
import sys

out, compiler_path, compiler_version, compiler_flags = sys.argv[1:5]
flag_start = sys.argv.index("--") + 1
cmake_flags = sys.argv[flag_start:]

version_line = compiler_version.strip()
name = os.path.basename(compiler_path) if compiler_path else ""
haystack = version_line.lower()
if "apple clang" in haystack:
    compiler_id = "apple-clang"
elif "clang" in haystack:
    compiler_id = "clang"
elif "gnu" in haystack or name in {"gcc", "g++"}:
    compiler_id = "gcc"
else:
    compiler_id = name or "unknown"

match = re.search(r"\d+(?:\.\d+)+", version_line)
version = match.group(0) if match else version_line
cxx_flags = [token for token in re.split(r"\s+", compiler_flags.strip()) if token]

provenance = {
    "compiler": {"id": compiler_id, "version": version, "flags": cxx_flags},
    "cmake": {"buildType": "Release", "flags": cmake_flags},
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(provenance, handle, indent=2)
    handle.write("\n")
PY

cmake --build "$build_dir" --target dawn_packer
cmake --install "$build_dir" --prefix "$install_dir"
touch "$install_dir/.dawn-packer-install"
echo "installed: $install_dir"
