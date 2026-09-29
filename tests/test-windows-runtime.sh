#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
redist="$work/redist"
# The toolset directory name varies with the compiler version, so the lookup
# must glob rather than assume VC143.
mkdir -p "$redist/14.99.1234/x64/Microsoft.VC144.CRT"
for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
  printf 'runtime\n' > "$redist/14.99.1234/x64/Microsoft.VC144.CRT/$dll"
done

cat > "$work/dependents.txt" <<'TXT'
    KERNEL32.dll
    USER32.dll
    MSVCP140.dll
    VCRUNTIME140.dll
    VCRUNTIME140_1.dll
    api-ms-win-core-errorhandling-l1-1-0.dll
TXT

dest="$work/dest"
mkdir -p "$dest"
python3 packaging/windows-runtime.py --dependents "$work/dependents.txt" --redist-dir "$redist" --dest "$dest" >/dev/null \
  || fail "runtime resolution failed"
# Only the MSVC runtime travels: system and API-set DLLs must be left alone.
for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
  assert_file "$dest/$dll"
done
for unwanted in kernel32.dll user32.dll api-ms-win-core-errorhandling-l1-1-0.dll; do
  [ -e "$dest/$unwanted" ] && fail "$unwanted must not be shipped"
done

# A runtime DLL the redistributable directory does not hold must fail loudly.
rm "$redist/14.99.1234/x64/Microsoft.VC144.CRT/vcruntime140_1.dll"
if python3 packaging/windows-runtime.py --dependents "$work/dependents.txt" --redist-dir "$redist" --dest "$dest" >/dev/null 2>&1; then
  fail "a missing runtime DLL should fail"
fi

# On a real install %VCToolsRedistDir% already ends at the toolset version, so
# the CRT sits directly under it, without a version directory in between.
direct="$work/direct"
mkdir -p "$direct/x64/Microsoft.VC143.CRT"
for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
  printf 'runtime\n' > "$direct/x64/Microsoft.VC143.CRT/$dll"
done
direct_dest="$work/direct-dest"
mkdir -p "$direct_dest"
python3 packaging/windows-runtime.py --dependents "$work/dependents.txt" --redist-dir "$direct" --dest "$direct_dest" >/dev/null \
  || fail "runtime resolution failed for the direct layout"
for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
  assert_file "$direct_dest/$dll"
done

pass "windows-runtime"
