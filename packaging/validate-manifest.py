#!/usr/bin/env python3
"""Validate a dawn-packer manifest (stdlib only)."""
import json
import re
import sys

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def validate(data):
    problems = []

    def require(condition, message):
        if not condition:
            problems.append(message)

    require(data.get("schemaVersion") == 1, "schemaVersion must be 1")
    require(isinstance(data.get("packerVersion"), str) and data["packerVersion"], "packerVersion required")
    dawn = data.get("dawn", {})
    require(isinstance(dawn.get("tag"), str) and dawn["tag"], "dawn.tag required")
    require(isinstance(dawn.get("revision"), str) and len(dawn["revision"]) >= 7, "dawn.revision required")
    target = data.get("target", {})
    for key in ("kotlinTarget", "triple", "os", "arch"):
        require(isinstance(target.get(key), str) and target[key], f"target.{key} required")
    require(data.get("linkage") in {"static", "shared"}, "linkage must be static|shared")
    backends = data.get("backends")
    require(isinstance(backends, list) and len(backends) >= 1, "backends must be non-empty")
    require(isinstance(data.get("compiler"), dict), "compiler must be an object")
    require(isinstance(data.get("cmake"), dict), "cmake must be an object")
    artifacts = data.get("artifacts")
    require(isinstance(artifacts, list) and len(artifacts) >= 1, "artifacts must be non-empty")
    if isinstance(artifacts, list):
        for index, artifact in enumerate(artifacts):
            require(isinstance(artifact.get("path"), str) and artifact["path"], f"artifacts[{index}].path required")
            require(HEX64.match(str(artifact.get("sha256", ""))) is not None, f"artifacts[{index}].sha256 invalid")
            require(isinstance(artifact.get("size"), int) and artifact["size"] >= 0, f"artifacts[{index}].size invalid")
    require(isinstance(data.get("createdAt"), str) and data["createdAt"], "createdAt required")
    return problems


def main(argv):
    if len(argv) != 2:
        print("usage: validate-manifest.py <manifest.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    problems = validate(data)
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1
    print("manifest OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
