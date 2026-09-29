#!/usr/bin/env python3
"""Assemble the compiler and cmake provenance recorded in a manifest.

Kept as a module rather than an inline script so the mapping can be tested for a
compiler the test host cannot run, MSVC included.
"""
import argparse
import json
import re
import sys

CMAKE_CXX_COMPILER_VERSION = "CMAKE_CXX_COMPILER_VERSION"


def compiler_id(version_line, compiler_name):
    haystack = version_line.lower()
    name = compiler_name.lower()
    if "apple clang" in haystack:
        return "apple-clang"
    if "clang" in haystack:
        return "clang"
    if "microsoft" in haystack or name in {"cl", "cl.exe"}:
        return "msvc"
    if "gnu" in haystack or name in {"gcc", "g++"}:
        return "gcc"
    return compiler_name or "unknown"


def compiler_version(version_line, cache_version=""):
    # `cl` rejects `--version`, so MSVC leaves the line empty; fall back to the
    # version CMake recorded in its cache rather than shipping no version at all.
    source = version_line.strip() or cache_version.strip()
    match = re.search(r"\d+(?:\.\d+)+", source)
    return match.group(0) if match else source


def cmake_cache_value(cache_path, key):
    """Read `KEY:<type>=value` from a CMake cache, or "" when absent."""
    if not cache_path:
        return ""
    pattern = re.compile(r"^" + re.escape(key) + r":[^=]*=(.*)$")
    with open(cache_path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = pattern.match(line.strip())
            if match:
                return match.group(1).strip()
    return ""


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler-name", required=True)
    parser.add_argument("--version-line", required=True)
    parser.add_argument("--cmake-cache", default="")
    parser.add_argument("--cxx-flags", default="")
    parser.add_argument("--out", required=True)
    parser.add_argument("cmake_flags", nargs="*")
    args = parser.parse_args(argv[1:])

    cache_version = cmake_cache_value(args.cmake_cache, CMAKE_CXX_COMPILER_VERSION)
    provenance = {
        "compiler": {
            "id": compiler_id(args.version_line, args.compiler_name),
            "version": compiler_version(args.version_line, cache_version),
            "flags": [token for token in re.split(r"\s+", args.cxx_flags.strip()) if token],
        },
        "cmake": {"buildType": "Release", "flags": list(args.cmake_flags)},
    }
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(provenance, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
