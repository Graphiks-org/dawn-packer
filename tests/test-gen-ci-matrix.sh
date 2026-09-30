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

# Exactly one entry per non-dropped target per linkage it declares, and both
# linkages present somewhere. A target may ship only one linkage: mingwX64 ships
# shared only, since an MSVC static library needs the MSVC/SDK import libraries.
def declared_linkages(entry):
    return entry.get("linkages") or ["static", "shared"]

linkages = {entry["linkage"] for entry in data["include"]}
assert linkages == {"static", "shared"}, f"expected both linkages, got: {sorted(linkages)}"
expected_pairs = {
    (t["kotlinTarget"], linkage)
    for t in non_dropped
    for linkage in declared_linkages(t)
}
assert set(pairs) == expected_pairs, f"target/linkage coverage mismatch: {expected_pairs ^ set(pairs)}"
print("ci matrix covers", len(included), "targets,", len(data["include"]), "entries")
PY

# Targeted runs: the `targets` / `LINKAGES` environment variables narrow the
# matrix so a single job can be dispatched while iterating on a build fix.
python3 - <<'PY'
import json, os, pathlib, subprocess, sys, tempfile

def run(targets="", linkages=""):
    env = dict(os.environ, TARGETS=targets, LINKAGES=linkages)
    # Pin MATRIX_FILE so an exported value in a developer shell or CI job cannot
    # silently redirect the shipped-matrix run at whatever fixture it names.
    env.pop("MATRIX_FILE", None)
    return subprocess.run(
        [sys.executable, "scripts/gen-ci-matrix.py"],
        env=env, capture_output=True, text=True,
    )

def entries(result):
    return json.loads(result.stdout)["include"]

# Regression: `run()` must ignore an ambient MATRIX_FILE. Point it at a fixture
# with a different entry count; if the guard leaked, the count below would read
# that fixture instead of the shipped matrix and fail.
ambient = pathlib.Path(tempfile.mkdtemp()) / "ambient-matrix.json"
ambient.write_text(json.dumps({
    "schemaVersion": 1,
    "targets": [
        {"kotlinTarget": "linuxX64", "triple": "x86_64-unknown-linux-gnu", "os": "linux",
         "arch": "x64", "runner": "ubuntu-24.04", "toolchain": "",
         "backends": ["null"], "status": "v1"},
    ],
}), encoding="utf-8")
os.environ["MATRIX_FILE"] = str(ambient)
try:
    full = entries(run())
finally:
    del os.environ["MATRIX_FILE"]
assert len(full) == 25, f"expected 25 entries unfiltered, got {len(full)}"

# The generator reads MATRIX_FILE, which lets a test describe a target without
# touching the shipped matrix.
fixture = pathlib.Path(tempfile.mkdtemp()) / "matrix.json"
fixture.write_text(json.dumps({
    "schemaVersion": 1,
    "targets": [
        {"kotlinTarget": "linuxX64", "triple": "x86_64-unknown-linux-gnu", "os": "linux",
         "arch": "x64", "runner": "ubuntu-24.04", "toolchain": "",
         "backends": ["null"], "status": "v1"},
        {"kotlinTarget": "mingwX64", "triple": "x86_64-pc-windows-gnu", "os": "windows",
         "arch": "x64", "runner": "windows-2022", "toolchain": "",
         "linkages": ["shared"], "backends": ["d3d12", "null"], "status": "v1"},
    ],
}), encoding="utf-8")

def run_fixture(targets="", linkages=""):
    env = dict(os.environ, TARGETS=targets, LINKAGES=linkages, MATRIX_FILE=str(fixture))
    return subprocess.run([sys.executable, "scripts/gen-ci-matrix.py"],
                          env=env, capture_output=True, text=True)

# A target that declares one linkage yields one entry for it.
declared = entries(run_fixture())
assert [(e["target"], e["linkage"]) for e in declared] == [
    ("linuxX64", "static"), ("linuxX64", "shared"), ("mingwX64", "shared"),
], declared

# The caller filter still applies on top of the declaration.
filtered = entries(run_fixture(linkages="static"))
assert [(e["target"], e["linkage"]) for e in filtered] == [
    ("linuxX64", "static"),
], filtered

# One target, both linkages.
only_linux = entries(run(targets="linuxX64"))
assert [(e["target"], e["linkage"]) for e in only_linux] == [
    ("linuxX64", "static"), ("linuxX64", "shared"),
], only_linux
assert {e["runner"] for e in only_linux} == {"ubuntu-24.04"}, only_linux

# Several targets and a single linkage, tolerating spaces after the commas.
pair = entries(run(targets="linuxX64, macosArm64", linkages="static"))
assert [(e["target"], e["linkage"]) for e in pair] == [
    ("linuxX64", "static"), ("macosArm64", "static"),
], pair
assert {e["runner"] for e in pair} == {"ubuntu-24.04", "macos-15"}, pair

# A dropped target stays unreachable even when asked for by name.
for bad in ("nosuchtarget", "watchosDeviceArm64", "watchosArm64"):
    result = run(targets=bad)
    assert result.returncode != 0, f"{bad} should have been rejected"
    assert "error" in result.stderr.lower(), result.stderr

# An unknown linkage must fail loudly: an empty matrix would report a green run
# that built nothing.
for bad_linkage in ("bogus", "static,bogus"):
    result = run(linkages=bad_linkage)
    assert result.returncode != 0, f"linkage {bad_linkage!r} should have been rejected"
    assert "error" in result.stderr.lower(), result.stderr

# An explicit null `linkages` means "both", exactly as the validator reads it
# (absent and null are the same). The generator used to do `for linkage in
# None` and crash on a matrix the validator had just blessed.
null_fixture = pathlib.Path(tempfile.mkdtemp()) / "matrix.json"
null_fixture.write_text(json.dumps({
    "schemaVersion": 1,
    "targets": [
        {"kotlinTarget": "linuxX64", "triple": "x86_64-unknown-linux-gnu", "os": "linux",
         "arch": "x64", "runner": "ubuntu-24.04", "toolchain": "",
         "linkages": None, "backends": ["null"], "status": "v1"},
    ],
}), encoding="utf-8")

validated = subprocess.run(
    [sys.executable, "packaging/validate-matrix.py", str(null_fixture)],
    capture_output=True, text=True,
)
assert validated.returncode == 0, validated.stderr

# Pin TARGETS/LINKAGES so an exported filter cannot narrow the fixture. Ambient
# values are set here and must not leak into the run: without the pin the
# unknown target below would be rejected before the null-linkages path is read.
os.environ["TARGETS"] = "macosArm64"
os.environ["LINKAGES"] = "static"
try:
    env = dict(os.environ, MATRIX_FILE=str(null_fixture), TARGETS="", LINKAGES="")
    result = subprocess.run([sys.executable, "scripts/gen-ci-matrix.py"],
                            env=env, capture_output=True, text=True)
finally:
    del os.environ["TARGETS"]
    del os.environ["LINKAGES"]
assert result.returncode == 0, result.stderr
assert [(e["target"], e["linkage"]) for e in entries(result)] == [
    ("linuxX64", "static"), ("linuxX64", "shared"),
], result.stdout

print("ci matrix filtering OK")
PY
pass "gen-ci-matrix"
