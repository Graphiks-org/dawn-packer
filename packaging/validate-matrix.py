#!/usr/bin/env python3
"""Validate targets/matrix.json (stdlib only)."""
import json
import sys

REQUIRED = {"kotlinTarget", "triple", "os", "arch", "runner", "toolchain", "backends", "status"}
ALLOWED_OS = {"linux", "macos", "ios", "tvos", "watchos", "windows", "android"}
ALLOWED_BACKENDS = {"metal", "vulkan", "d3d12", "gles", "desktop_gl", "null"}
ALLOWED_STATUS = {"v1", "spike", "dropped"}


def errors(data):
    problems = []
    if data.get("schemaVersion") != 1:
        problems.append("schemaVersion must be 1")
    targets = data.get("targets")
    if not isinstance(targets, list) or not targets:
        problems.append("targets must be a non-empty list")
        return problems
    seen = set()
    for index, entry in enumerate(targets):
        where = f"targets[{index}]"
        missing = REQUIRED - set(entry)
        if missing:
            problems.append(f"{where}: missing {sorted(missing)}")
            continue
        name = entry["kotlinTarget"]
        if name in seen:
            problems.append(f"{where}: duplicate kotlinTarget {name}")
        seen.add(name)
        if entry["os"] not in ALLOWED_OS:
            problems.append(f"{where}: bad os {entry['os']}")
        if entry["status"] not in ALLOWED_STATUS:
            problems.append(f"{where}: bad status {entry['status']}")
        if not entry["backends"]:
            problems.append(f"{where}: backends must not be empty")
        for backend in entry["backends"]:
            if backend not in ALLOWED_BACKENDS:
                problems.append(f"{where}: bad backend {backend}")
        if "null" not in entry["backends"]:
            problems.append(f"{where}: null backend is mandatory")
    return problems


def main(argv):
    if len(argv) != 2:
        print("usage: validate-matrix.py <matrix.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    problems = errors(data)
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1
    print("matrix OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
