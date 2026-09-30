#!/usr/bin/env python3
"""Validate targets/matrix.json (stdlib only)."""
import json
import sys

REQUIRED = {"kotlinTarget", "triple", "os", "arch", "runner", "toolchain", "backends", "status"}
ALLOWED_OS = {"linux", "macos", "ios", "tvos", "watchos", "windows", "android"}
ALLOWED_BACKENDS = {"metal", "vulkan", "d3d11", "d3d12", "gles", "desktop_gl", "null"}
ALLOWED_STATUS = {"v1", "spike", "dropped"}
ALLOWED_LINKAGES = {"static", "shared"}
# Each Android target names exactly one NDK ABI, forwarded by
# scripts/build-target.sh as -DCMAKE_ANDROID_ARCH_ABI.
ALLOWED_ANDROID_ABI = {"arm64-v8a", "armeabi-v7a", "x86_64", "x86"}


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
        if entry["os"] == "android":
            if "androidAbi" not in entry:
                problems.append(f"{where}: android entries must set androidAbi")
            elif entry["androidAbi"] not in ALLOWED_ANDROID_ABI:
                problems.append(
                    f"{where}: bad androidAbi {entry['androidAbi']} "
                    f"(allowed: {sorted(ALLOWED_ANDROID_ABI)})"
                )
        elif "androidAbi" in entry:
            problems.append(f"{where}: androidAbi is only allowed for os=android")
        if entry["status"] not in ALLOWED_STATUS:
            problems.append(f"{where}: bad status {entry['status']}")
        # Optional per-target cmake flags (e.g. macosArm64's deployment target).
        # When present it must be a list of strings so build-target.sh can append
        # it verbatim to the configure command.
        extra = entry.get("extraCmakeArgs")
        if extra is not None:
            if not isinstance(extra, list) or not all(isinstance(arg, str) for arg in extra):
                problems.append(f"{where}: extraCmakeArgs must be a list of strings")
        # Optional: the linkages a target actually ships. Absent means both.
        # Windows ships the shared variant only, because an MSVC static library
        # has no C boundary for a GNU consumer to link through.
        linkages = entry.get("linkages")
        if linkages is not None:
            if not isinstance(linkages, list) or not linkages:
                problems.append(f"{where}: linkages must be a non-empty list")
            elif not all(isinstance(value, str) for value in linkages):
                problems.append(f"{where}: linkages must be a list of strings")
            else:
                unknown = [value for value in linkages if value not in ALLOWED_LINKAGES]
                if unknown:
                    problems.append(
                        f"{where}: bad linkage(s) {unknown} "
                        f"(allowed: {sorted(ALLOWED_LINKAGES)})"
                    )
                elif len(set(linkages)) != len(linkages):
                    problems.append(f"{where}: duplicate linkages {linkages}")
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
