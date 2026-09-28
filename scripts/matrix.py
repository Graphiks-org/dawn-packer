#!/usr/bin/env python3
"""Read targets/matrix.json."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MATRIX = ROOT / "targets" / "matrix.json"


def load():
    with MATRIX.open(encoding="utf-8") as handle:
        return json.load(handle)


def find(data, kotlin_target):
    for entry in data["targets"]:
        if entry["kotlinTarget"] == kotlin_target:
            return entry
    return None


def main(argv):
    if len(argv) < 2 or argv[1] not in {"list", "get", "backends"}:
        print("usage: matrix.py <list|get|backends> [kotlinTarget]", file=sys.stderr)
        return 2
    command = argv[1]
    data = load()
    if command == "list":
        for entry in data["targets"]:
            print(entry["kotlinTarget"])
        return 0
    if len(argv) < 3:
        print("missing kotlinTarget", file=sys.stderr)
        return 2
    entry = find(data, argv[2])
    if entry is None:
        print(f"unknown target: {argv[2]}", file=sys.stderr)
        return 1
    if command == "get":
        print(json.dumps(entry))
    else:
        print(" ".join(entry["backends"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
