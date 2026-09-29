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
non_dropped = [t for t in matrix["targets"] if t["status"] != "dropped"]
expected = {t["kotlinTarget"] for t in non_dropped}
dropped = {t["kotlinTarget"] for t in matrix["targets"] if t["status"] == "dropped"}
runners = {t["kotlinTarget"]: t["runner"] for t in non_dropped}

# The top-level object must be exactly {"include": [...]}.
assert set(data) == {"include"}, f"unexpected top-level keys: {sorted(data)}"

# Every entry must carry exactly the CI matrix keys, with a known linkage,
# and the runner declared for that target in the matrix.
for entry in data["include"]:
    assert set(entry) == {"target", "runner", "linkage"}, f"unexpected entry keys: {entry}"
    assert entry["linkage"] in ("static", "shared"), f"bad linkage: {entry}"
    assert entry["runner"] == runners.get(entry["target"]), f"runner mismatch: {entry}"

pairs = [(entry["target"], entry["linkage"]) for entry in data["include"]]
assert len(pairs) == len(set(pairs)), f"duplicate (target, linkage) entries: {pairs}"

included = {entry["target"] for entry in data["include"]}
missing = expected - included
assert not missing, f"missing from CI matrix: {missing}"

# Dropped targets must never reach CI.
leaked = dropped & included
assert not leaked, f"dropped targets leaked into CI matrix: {leaked}"

# Exactly one entry per non-dropped target per linkage, and every linkage present.
linkages = {entry["linkage"] for entry in data["include"]}
assert linkages == {"static", "shared"}, f"expected both linkages, got: {sorted(linkages)}"
expected_pairs = {(t, l) for t in expected for l in ("static", "shared")}
assert set(pairs) == expected_pairs, f"target/linkage coverage mismatch: {expected_pairs ^ set(pairs)}"
print("ci matrix covers", len(included), "targets,", len(data["include"]), "entries")
PY
pass "gen-ci-matrix"
