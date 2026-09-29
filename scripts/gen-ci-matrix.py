#!/usr/bin/env python3
"""Emit the GitHub Actions build matrix from targets/matrix.json (stdlib only)."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    with (ROOT / "targets" / "matrix.json").open(encoding="utf-8") as handle:
        matrix = json.load(handle)
    include = []
    for entry in matrix["targets"]:
        if entry["status"] == "dropped":
            continue
        for linkage in ("static", "shared"):
            include.append({
                "target": entry["kotlinTarget"],
                "runner": entry["runner"],
                "linkage": linkage,
            })
    json.dump({"include": include}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
