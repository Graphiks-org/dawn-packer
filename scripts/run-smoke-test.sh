#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:?usage: run-smoke-test.sh <archive.tar.gz> [--link-only]}"
mode="${2:-run}"

# The library is C++ even though the API is C, so use a C++ linker driver (it
# links libc++ itself -- do not add -lc++). Link flags are OS-specific; Darwin
# has no libdl and needs frameworks.
cxx="${CXX:-c++}"
case "$(uname -s)" in
  Darwin)
    link_flags=(-framework Metal -framework Foundation -framework CoreGraphics \
      -framework QuartzCore -framework IOKit -framework IOSurface)
    ;;
  Linux)
    link_flags=(-lpthread -ldl -lm)
    ;;
  MINGW* | MSYS* | CYGWIN*)
    # Windows: link the MSVC import library from the archive and put the DLLs
    # beside the executable, which is the whole deployment story there. The
    # measured probe needed no extra system library.
    link_flags=()
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
import_lib="$(find "$lib_dir" -name '*.lib' -print -quit || true)"
shared_lib="$(find "$lib_dir" \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -print -quit || true)"

link_opts=()
if [ -n "$static_lib" ]; then
  link_opts+=("$static_lib")
elif [ -n "$import_lib" ]; then
  link_opts+=("$import_lib")
elif [ -n "$shared_lib" ]; then
  link_opts+=("-L$lib_dir" "-lwebgpu_dawn" "-Wl,-rpath,$lib_dir")
else
  echo "no library found in archive" >&2
  exit 1
fi

# bin/ holds the library and its runtime on Windows; anywhere else the archive
# has no bin/ and this is a no-op.
if [ -d "$work/bin" ]; then
  cp "$work/bin"/*.dll "$work/" 2>/dev/null || true
fi

# Compile the C source as C++ (Dawn's API is C but the link needs the C++
# runtime) and link it separately. Doing it in two steps avoids both clang
# warnings the one-shot form produced: '-x c++' on a .c file ("treating c input
# as c++") and '-x none' with no later input ("after last input file has no
# effect"). stderr must stay empty.
"$cxx" -I"$include_dir" -x c++ -c "$root/scripts/smoke-test/link-test.c" \
  -o "$work/link-test.o"
"$cxx" "$work/link-test.o" "${link_opts[@]}" ${link_flags[@]+"${link_flags[@]}"} -o "$work/link-test"
echo "link OK"

if [ "$mode" = "--link-only" ]; then
  exit 0
fi
"$work/link-test"
