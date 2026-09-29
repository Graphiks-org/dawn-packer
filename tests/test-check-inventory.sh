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

# An archive member the manifest does not describe must fail.
python3 - "$stage/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["artifacts"] = [a for a in data["artifacts"] if a["path"] != "lib/never-present.tar"]
json.dump(data, open(path, "w", encoding="utf-8"))
PY
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
