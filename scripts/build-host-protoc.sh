#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cache="$root/build/host-protoc"
protoc="$cache/bin/protoc"
if [ -x "$protoc" ]; then
  echo "$protoc"
  exit 0
fi

# Dawn's pinned protobuf is dawn/third_party/protobuf (protobuf 7.36.0). It has
# no cmake/CMakeLists.txt: the project root is dawn/third_party/protobuf, and a
# standalone configure would fall back to fetching Abseil from GitHub. Dawn's
# own CI (dawn/.github/workflows/ci.yml) instead configures the Dawn tree with
# DAWN_BUILD_PROTOBUF=ON and builds the `protoc` target, which wires Abseil
# from dawn/third_party/abseil-cpp. Match that recipe here.
cmake -S dawn -B "$cache" -G Ninja \
  -DDAWN_BUILD_PROTOBUF=ON \
  -DDAWN_BUILD_SAMPLES=OFF \
  -DDAWN_BUILD_NODE=OFF \
  -DDAWN_ENABLE_VULKAN=OFF \
  -DDAWN_ENABLE_METAL=OFF \
  -DDAWN_ENABLE_D3D12=OFF \
  -DDAWN_ENABLE_D3D11=OFF \
  -DDAWN_ENABLE_OPENGLES=OFF \
  -DDAWN_ENABLE_DESKTOP_GL=OFF \
  -DDAWN_ENABLE_NULL=OFF \
  -DDAWN_USE_X11=OFF \
  -DDAWN_USE_WAYLAND=OFF \
  -DDAWN_USE_GLFW=OFF \
  -DDAWN_BUILD_TESTS=OFF \
  -DTINT_BUILD_CMD_TOOLS=OFF \
  -DTINT_BUILD_DOCS=OFF \
  -DTINT_BUILD_TESTS=OFF \
  -DTINT_BUILD_WGSL_READER=OFF \
  -DTINT_BUILD_WGSL_WRITER=OFF \
  -DTINT_BUILD_GLSL_VALIDATOR=OFF \
  -DTINT_BUILD_IR_BINARY=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$cache" --target protoc

# CMake names the executable `protoc` or, because protoc.cmake sets a VERSION,
# `protoc-<major>.<minor>` (observed: protoc-36.0.0 at the build root). Search
# for whichever the pinned revision produced.
built=""
while IFS= read -r candidate; do
  if [ -x "$candidate" ]; then
    built="$candidate"
    break
  fi
done < <(find "$cache" -type f -name 'protoc*' ! -name 'protoc-gen-*' 2>/dev/null)
[ -n "$built" ] || { echo "protoc was not produced under $cache" >&2; exit 1; }
mkdir -p "$cache/bin"
cp "$built" "$protoc"

echo "$protoc"
