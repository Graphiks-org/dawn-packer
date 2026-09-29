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
mapfile -t extra_cmake_args < <(python3 -c 'import json,sys
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
cmake --build "$build_dir" --target dawn_packer
cmake --install "$build_dir" --prefix "$install_dir"
touch "$install_dir/.dawn-packer-install"
echo "installed: $install_dir"
