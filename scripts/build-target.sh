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
# Android serves four ABIs but a single CMake toolchain file cannot pick
# between them, so the ABI lives on the matrix entry and is forwarded here.
android_abi="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("androidAbi", ""))' "$entry")"
# Optional per-target extra configure flags (e.g. macosArm64's
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
    d3d11) backend_flags+=("-DDAWN_ENABLE_D3D11=ON") ;;
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

# Capture the real compiler identity and the exact configure arguments so
# packaging can record provenance instead of empty objects. Written next to the
# install tree; scripts/package.sh picks it up when present and degrades
# gracefully when absent.
provenance="$root/dist/$target/$linkage_lc/packer-provenance.json"
cmake_cache="$build_dir/CMakeCache.txt"
compiler_path="$(sed -n 's/^CMAKE_CXX_COMPILER:[^=]*=//p' "$cmake_cache" | head -n1)"
compiler_flags="$(sed -n 's/^CMAKE_CXX_FLAGS:[^=]*=//p' "$cmake_cache" | head -n1)"
compiler_version=""
if [ -n "$compiler_path" ] && [ -x "$compiler_path" ]; then
  # MSVC's `cl` rejects `--version` and writes its version banner to stderr, so
  # capture both streams; the module falls back to the CMake cache version when
  # the banner (or the empty result) carries no version number.
  compiler_version="$("$compiler_path" --version 2>&1 | head -n1 || true)"
fi
# The literal `--` ends argparse option parsing: every cmake flag starts with
# `-D`, which argparse would otherwise try to read as an option. `--cmake-cache`
# supplies the authoritative compiler flags and the version when `--version` was
# rejected (MSVC's `cl`).
python3 packaging/provenance.py \
  --compiler-name "$(basename "$compiler_path")" \
  --version-line "$compiler_version" \
  --cmake-cache "$cmake_cache" \
  --cxx-flags "$compiler_flags" \
  --out "$provenance" -- \
  "${cmake_args[@]}" "${backend_flags[@]}"

cmake --build "$build_dir" --target dawn_packer
cmake --install "$build_dir" --prefix "$install_dir"
# Windows shared archives must carry the MSVC runtime the library needs, so the
# consumer copies a directory instead of installing a redistributable. Only the
# shared linkage produces a DLL to inspect.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    if [ "$linkage" = "SHARED" ]; then
      dll="$install_dir/bin/webgpu_dawn.dll"
      if [ ! -f "$dll" ]; then
        echo "expected $dll after install" >&2
        exit 1
      fi
      if [ -z "${VCToolsRedistDir:-}" ]; then
        echo "VCToolsRedistDir is unset; enter the MSVC environment first" >&2
        exit 1
      fi
      dumpbin //dependents "$dll" > "$install_dir/dependents.txt"
      python3 packaging/windows-runtime.py \
        --dependents "$install_dir/dependents.txt" \
        --redist-dir "$VCToolsRedistDir" \
        --dest "$install_dir/bin"
      rm -f "$install_dir/dependents.txt"
    fi
    ;;
esac
touch "$install_dir/.dawn-packer-install"
echo "installed: $install_dir"
