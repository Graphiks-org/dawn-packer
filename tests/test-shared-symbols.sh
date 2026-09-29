#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# Derive the host target instead of hardcoding linuxX64.
host_target() {
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) printf '%s\n' macosArm64 ;;
    Linux/x86_64) printf '%s\n' linuxX64 ;;
    Linux/aarch64 | Linux/arm64) printf '%s\n' linuxArm64 ;;
    *) return 1 ;;
  esac
}

if ! target="$(host_target)"; then
  echo "SKIP: unsupported host $(uname -s)/$(uname -m)"
  exit 0
fi

bash scripts/build-target.sh "$target" shared
bash scripts/package.sh "$target" shared

archive="$(ls dist/"$target"/dawn-*-"$target"-shared.tar.gz 2>/dev/null | head -n1 || true)"
[ -n "$archive" ] || fail "shared archive not found"
assert_file "$archive"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar xzf "$archive" -C "$work"

shared_lib="$(find "$work/lib" \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -print -quit)"
[ -n "$shared_lib" ] || fail "shared library missing"

# Symbol inspection is OS-specific. On Darwin the exported ABI lives in the
# Mach-O export trie, not the symbol table: `nm -gU` also reports hidden
# (private-extern) symbols, so it cannot verify visibility. `dyld_info -exports`
# is the Mach-O equivalent of ELF's `nm -D`.
os="$(uname -s)"
case "$os" in
  Darwin)
    defined="$(dyld_info -exports "$shared_lib" | awk '$1 ~ /^0x/ {print $2}')"
    ;;
  Linux)
    defined="$(nm -D --defined-only "$shared_lib" | awk 'NF>=3 {print $3}')"
    ;;
  *)
    echo "SKIP: unsupported OS for symbol inspection: $os"
    exit 0
    ;;
esac
[ -n "$defined" ] || fail "no dynamic symbols found"

# Only the public WebGPU API may be exported. Mach-O names carry a leading
# underscore (_wgpuCreateInstance), ELF names do not, hence the optional `_`.
leaked="$(printf '%s\n' "$defined" | grep -Ev '^_?(wgpu|dawn)' | grep -v '^$' || true)"
if [ -n "$leaked" ]; then
  total="$(printf '%s\n' "$leaked" | wc -l | tr -d ' ')"
  echo "leaked non-wgpu/dawn symbols: $total (first 20):" >&2
  printf '%s\n' "$leaked" | sed -n '1,20p' >&2
  fail "non-wgpu symbols exported"
fi

wgpu_count="$(printf '%s\n' "$defined" | grep -Ec '^_?(wgpu|dawn)' || true)"
echo "exported wgpu/dawn symbols: $wgpu_count"
pass "shared-symbols"
