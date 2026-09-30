#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check() {
  local name="$1" line="$2" id="$3" version="$4"
  python3 packaging/provenance.py \
    --compiler-name "$name" --version-line "$line" --cxx-flags " -O2  -DNDEBUG " \
    --out "$work/out.json" -- -DDAWN_PACKER_LINKAGE=SHARED >/dev/null
  python3 - "$work/out.json" "$id" "$version" <<'PY' || fail "provenance mismatch for $id"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["compiler"]["id"] == sys.argv[2], data
assert data["compiler"]["version"] == sys.argv[3], data
assert data["compiler"]["flags"] == ["-O2", "-DNDEBUG"], data
assert data["cmake"]["buildType"] == "Release", data
assert data["cmake"]["flags"] == ["-DDAWN_PACKER_LINKAGE=SHARED"], data
print("ok")
PY
}

check cl.exe "Microsoft (R) C/C++ Optimizing Compiler Version 19.44.35229.0 for x64" msvc "19.44.35229.0"
check clang++ "clang version 18.1.3" clang "18.1.3"
check clang++ "Apple clang version 16.0.0 (clang-1600.0.26.6)" apple-clang "16.0.0"
check g++ "g++ (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0" gcc "13.3.0"
# A version line matching nothing known must still produce a usable identifier.
check cc "some vendor compiler" cc "some vendor compiler"

# MSVC's `cl` rejects `--version`, so the version line arrives empty. The version
# must then come from the CMake cache, while detection still uses the compiler
# name so the identifier stays correct without any version at all.
cat >"$work/CMakeCache.txt" <<'CACHE'
//CXX compiler
CMAKE_CXX_COMPILER:FILEPATH=C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe
CMAKE_CXX_COMPILER_VERSION:INTERNAL=19.44.35229.0
CMAKE_CXX_FLAGS:STRING=/DWIN32 /D_WINDOWS /O2
CACHE
python3 packaging/provenance.py \
  --compiler-name "cl.exe" --version-line "" \
  --cmake-cache "$work/CMakeCache.txt" --cxx-flags " /O2 " \
  --out "$work/cache.json" -- -DDAWN_PACKER_LINKAGE=SHARED >/dev/null
python3 - "$work/cache.json" <<'PY' || fail "cache fallback mismatch"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["compiler"]["id"] == "msvc", data
assert data["compiler"]["version"] == "19.44.35229.0", data
# The cache is the trusted source for flags, so `--cxx-flags` " /O2 " loses.
assert data["compiler"]["flags"] == ["/DWIN32", "/D_WINDOWS", "/O2"], data
assert data["cmake"]["flags"] == ["-DDAWN_PACKER_LINKAGE=SHARED"], data
print("ok")
PY

# A non-empty version line must keep winning over the cache.
python3 packaging/provenance.py \
  --compiler-name "g++" --version-line "g++ (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0" \
  --cmake-cache "$work/CMakeCache.txt" --out "$work/line-wins.json" -- >/dev/null
python3 - "$work/line-wins.json" <<'PY' || fail "version line must win over cache"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["compiler"]["id"] == "gcc", data
assert data["compiler"]["version"] == "13.3.0", data
print("ok")
PY

# MSYS rewrites `/DWIN32` in argv into `C:/Program Files/Git/DWIN32`, so the
# passed `--cxx-flags` cannot be trusted; the cache holds the true string and
# must win whenever it is available.
python3 packaging/provenance.py \
  --compiler-name "cl.exe" \
  --version-line "Microsoft (R) C/C++ Optimizing Compiler Version 19.44.35229.0 for x64" \
  --cmake-cache "$work/CMakeCache.txt" \
  --cxx-flags "C:/Program Files/Git/DWIN32 /D_WINDOWS /O2" \
  --out "$work/mangled.json" -- >/dev/null
python3 - "$work/mangled.json" <<'PY' || fail "flags must come from the cache"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["compiler"]["flags"] == ["/DWIN32", "/D_WINDOWS", "/O2"], data
print("ok")
PY

# A version line that is present but carries no number (MSVC writes a banner
# without a version to stderr) must still fall back to the cache version.
python3 packaging/provenance.py \
  --compiler-name "cl.exe" \
  --version-line "Microsoft (R) C/C++ Optimizing Compiler for x64" \
  --cmake-cache "$work/CMakeCache.txt" \
  --out "$work/no-number.json" -- >/dev/null
python3 - "$work/no-number.json" <<'PY' || fail "version must fall back to the cache"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["compiler"]["id"] == "msvc", data
assert data["compiler"]["version"] == "19.44.35229.0", data
print("ok")
PY

pass "provenance"
