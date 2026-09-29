#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# bsdtar on macOS stores extended attributes as AppleDouble (._*) sidecar
# members by default. They are not artifacts, so suppress them the same way
# scripts/package.sh does, keeping the fixture archives shaped like shipped ones.
export COPYFILE_DISABLE=1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

stage="$work/stage"
mkdir -p "$stage/include" "$stage/bin"
printf 'header\n' > "$stage/include/webgpu.h"
printf 'dll\n' > "$stage/bin/webgpu_dawn.dll"
python3 - "$stage" <<'PY'
import json, sys, pathlib
stage = pathlib.Path(sys.argv[1])
artifacts = sorted(str(p.relative_to(stage)) for p in stage.rglob("*") if p.is_file())
(stage / "manifest.json").write_text(
    json.dumps({"artifacts": [{"path": p} for p in artifacts]}), encoding="utf-8")
PY
tar -czf "$work/good.tar.gz" -C "$stage" bin include manifest.json

python3 packaging/check-inventory.py "$work/good.tar.gz" "$stage/manifest.json" "$stage" >/dev/null \
  || fail "a consistent archive should pass"

# A manifest entry the archive does not contain must fail.
python3 - "$stage/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["artifacts"].append({"path": "lib/never-present.tar"})
json.dump(data, open(path, "w", encoding="utf-8"))
PY
if python3 packaging/check-inventory.py "$work/good.tar.gz" "$stage/manifest.json" "$stage" >/dev/null 2>&1; then
  fail "a manifest entry absent from the archive should be rejected"
fi

# Drop the manufactured entry so the manifest and the archive agree again
# before the next case.
python3 - "$stage/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["artifacts"] = [a for a in data["artifacts"] if a["path"] != "lib/never-present.tar"]
json.dump(data, open(path, "w", encoding="utf-8"))
PY

# An archive member absent from BOTH the manifest and the staged tree must fail
# on the archive/member direction alone. A stray AppleDouble sidecar has this
# shape: it lives only in the archive, so the staged-tree diff cannot catch it.
# The archive is built from a copy of the stage plus one extra file, leaving the
# staged tree and the manifest consistent with each other.
member_stage="$work/member-stage"
mkdir -p "$member_stage"
cp -R "$stage/bin" "$stage/include" "$stage/manifest.json" "$member_stage/"
printf 'ghost\n' > "$member_stage/ghost.txt"
tar -czf "$work/ghost-member.tar.gz" -C "$member_stage" bin include ghost.txt manifest.json
if python3 packaging/check-inventory.py "$work/ghost-member.tar.gz" "$stage/manifest.json" "$stage" >/dev/null 2>&1; then
  fail "an archive member absent from the manifest and staged tree should be rejected"
fi

# An archive member the manifest does not describe must fail. Here the stray
# file is also in the staged tree, so direction 3 fires alongside direction 2.
printf 'stray\n' > "$stage/stray.txt"
tar -czf "$work/extra-member.tar.gz" -C "$stage" bin include stray.txt manifest.json
if python3 packaging/check-inventory.py "$work/extra-member.tar.gz" "$stage/manifest.json" "$stage" >/dev/null 2>&1; then
  fail "an archive member absent from the manifest should be rejected"
fi

# A staged file the manifest does not list must fail.
if python3 packaging/check-inventory.py "$work/good.tar.gz" "$stage/manifest.json" "$stage" >/dev/null 2>&1; then
  fail "a staged file absent from the manifest should be rejected"
fi

pass "check-inventory"
