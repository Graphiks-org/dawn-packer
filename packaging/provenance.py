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
CMAKE_CXX_FLAGS = "CMAKE_CXX_FLAGS"


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


def _numeric_version(text):
    match = re.search(r"\d+(?:\.\d+)+", text)
    return match.group(0) if match else ""


def compiler_version(version_line, cache_version=""):
    # `cl` writes its banner to stderr and rejects `--version`, so the line can
    # be empty or carry no number at all. Fall back to the cache whenever no
    # number was extracted, not only when the line is empty, rather than ship a
    # version that is really the banner text.
    line = version_line.strip()
    cached = cache_version.strip()
    return _numeric_version(line) or _numeric_version(cached) or cached or line


def compiler_flags(cxx_flags, cache_flags=""):
    # MSYS rewrites `/DWIN32` in argv into `C:/Program Files/Git/DWIN32`, so the
    # cache is the only trustworthy source when present; `--cxx-flags` stays the
    # fallback for a caller that has no cache.
    source = cache_flags.strip() or cxx_flags.strip()
    return [token for token in re.split(r"\s+", source) if token]


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
    cache_flags = cmake_cache_value(args.cmake_cache, CMAKE_CXX_FLAGS)
    provenance = {
        "compiler": {
            "id": compiler_id(args.version_line, args.compiler_name),
            "version": compiler_version(args.version_line, cache_version),
            "flags": compiler_flags(args.cxx_flags, cache_flags),
        },
        "cmake": {"buildType": "Release", "flags": list(args.cmake_flags)},
    }
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(provenance, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
