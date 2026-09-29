#!/usr/bin/env python3
"""Aggregate every manifest.json under a directory into index.json (stdlib only)."""
import json
import pathlib
import sys


def main(argv):
    if len(argv) != 3:
        print("usage: build-index.py <manifests-dir> <out.json>", file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1])
    entries = []
    for manifest_path in sorted(root.rglob("manifest.json")):
        with manifest_path.open(encoding="utf-8") as handle:
            entries.append(json.load(handle))
    pathlib.Path(argv[2]).write_text(json.dumps({"schemaVersion": 1, "manifests": entries}, indent=2) + "\n", encoding="utf-8")
    print(f"index: {len(entries)} manifests")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
