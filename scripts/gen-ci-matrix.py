#!/usr/bin/env python3
"""Emit the GitHub Actions build matrix from targets/matrix.json (stdlib only).

`TARGETS` and `LINKAGES` narrow the matrix for a targeted workflow_dispatch run
(``gh workflow run build.yml -f targets=linuxX64 -f linkages=static``). Both are
comma-separated and empty means "no filter", which is what a push on a version
tag passes. A filter that selects nothing is an error: an empty matrix would
report a green run that built nothing.
"""
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINKAGES = ("static", "shared")


def matrix_path():
    """The shipped matrix, unless a caller overrides it (used by the tests)."""
    override = os.environ.get("MATRIX_FILE")
    return pathlib.Path(override) if override else ROOT / "targets" / "matrix.json"


def selection(variable):
    """Parse a comma-separated filter into a set, or None when unset."""
    raw = os.environ.get(variable, "")
    names = {name.strip() for name in raw.split(",") if name.strip()}
    return names or None


def main():
    with matrix_path().open(encoding="utf-8") as handle:
        matrix = json.load(handle)

    wanted_targets = selection("TARGETS")
    wanted_linkages = selection("LINKAGES")
    if wanted_linkages:
        unknown = wanted_linkages - set(LINKAGES)
        if unknown:
            print(
                f"ERROR: unknown linkage(s) {sorted(unknown)}; expected {list(LINKAGES)}",
                file=sys.stderr,
            )
            return 2

    buildable = [entry for entry in matrix["targets"] if entry["status"] != "dropped"]
    if wanted_targets:
        known = {entry["kotlinTarget"] for entry in buildable}
        unknown = wanted_targets - known
        if unknown:
            print(
                f"ERROR: unknown or dropped target(s) {sorted(unknown)}; "
                f"buildable targets are {sorted(known)}",
                file=sys.stderr,
            )
            return 2
        buildable = [entry for entry in buildable if entry["kotlinTarget"] in wanted_targets]

    include = []
    for entry in buildable:
        # `linkages: null` means "both", the same as omitting the key; the
        # validator already reads it that way, so the generator must too.
        for linkage in entry.get("linkages") or LINKAGES:
            if wanted_linkages and linkage not in wanted_linkages:
                continue
            include.append({
                "target": entry["kotlinTarget"],
                "runner": entry["runner"],
                "linkage": linkage,
            })
    if not include:
        print("ERROR: the requested filters selected no build", file=sys.stderr)
        return 1
    json.dump({"include": include}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
