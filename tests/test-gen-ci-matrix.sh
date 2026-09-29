#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

out="$(python3 scripts/gen-ci-matrix.py)"
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["include"], "empty"; [print(e["target"]) for e in data["include"]]' "$out" >/dev/null || fail "invalid CI matrix JSON"

python3 - "$out" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
matrix = json.load(open("targets/matrix.json"))
expected = {t["kotlinTarget"] for t in matrix["targets"] if t["status"] != "dropped"}
dropped = {t["kotlinTarget"] for t in matrix["targets"] if t["status"] == "dropped"}

# Every entry must carry exactly the CI matrix keys, with a known linkage.
for entry in data["include"]:
    assert set(entry) == {"target", "runner", "linkage"}, f"unexpected entry keys: {entry}"
    assert entry["linkage"] in ("static", "shared"), f"bad linkage: {entry}"

included = {entry["target"] for entry in data["include"]}
missing = expected - included
assert not missing, f"missing from CI matrix: {missing}"

# Ruling: dropped targets must never reach CI.
leaked = dropped & included
assert not leaked, f"dropped targets leaked into CI matrix: {leaked}"

# One entry per non-dropped target per linkage.
assert len(data["include"]) == 2 * len(expected), "expected static+shared for each target"
print("ci matrix covers", len(included), "targets,", len(data["include"]), "entries")
PY
pass "gen-ci-matrix"
