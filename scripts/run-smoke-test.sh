#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:?usage: run-smoke-test.sh <archive.tar.gz> [--link-only]}"
mode="${2:-run}"

# Ruling P2: the library is C++ even though the API is C, so use a C++ linker
# driver. Link flags are OS-specific; Darwin has no libdl and needs frameworks.
cxx="${CXX:-c++}"
case "$(uname -s)" in
  Darwin)
    link_flags=(-lc++ -framework Metal -framework Foundation -framework CoreGraphics \
      -framework QuartzCore -framework IOKit -framework IOSurface)
    ;;
  Linux)
    link_flags=(-lpthread -ldl -lm)
    ;;
  *)
    echo "unsupported OS for smoke test: $(uname -s)" >&2
    exit 1
    ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar xzf "$archive" -C "$work"

lib_dir="$work/lib"
include_dir="$work/include"
static_lib="$(find "$lib_dir" -name '*.a' -print -quit || true)"
shared_lib="$(find "$lib_dir" \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -print -quit || true)"

link_opts=()
if [ -n "$static_lib" ]; then
  link_opts+=("$static_lib")
elif [ -n "$shared_lib" ]; then
  link_opts+=("-L$lib_dir" "-lwebgpu_dawn" "-Wl,-rpath,$lib_dir")
else
  echo "no library found in archive" >&2
  exit 1
fi

# -x c++ / -x none forces C++ for the .c source without treating the archive as
# a source file, and avoids clang's "treating 'c' input as 'c++'" warning.
"$cxx" -I"$include_dir" -x c++ "$root/scripts/smoke-test/link-test.c" -x none \
  "${link_opts[@]}" "${link_flags[@]}" -o "$work/link-test"
echo "link OK"

if [ "$mode" = "--link-only" ]; then
  exit 0
fi
"$work/link-test"
