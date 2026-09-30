#!/usr/bin/env python3
"""Copy the MSVC runtime DLLs a Windows build actually depends on.

The list is derived from the built binary rather than hardcoded, and the
redistributable directory is globbed because its name carries the toolset
version. A runtime DLL that cannot be found is a hard failure: shipping the
library without it produces an archive that fails to load with an unhelpful
message.
"""
import argparse
import pathlib
import re
import shutil
import sys

# The C++ runtime, in the naming MSVC gives it. Everything else a Windows binary
# imports -- kernel32, user32, the api-ms-win-* API sets -- is part of Windows.
RUNTIME_PATTERN = re.compile(r"^(msvcp\d+.*|vcruntime\d+.*|concrt\d+.*)\.dll$", re.I)


def dependents(path):
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            name = raw.strip()
            if name.lower().endswith(".dll"):
                yield name


def redist_dir(root):
    # %VCToolsRedistDir% already ends at the toolset version, so on a real
    # install the CRT sits directly at <root>/x64/Microsoft.VC*.CRT. Accept an
    # intermediate version directory too, so the lookup does not depend on which
    # of the two layouts the host uses.
    base = pathlib.Path(root)
    for pattern in ("x64/Microsoft.VC*.CRT", "*/x64/Microsoft.VC*.CRT"):
        candidates = sorted(base.glob(pattern))
        if candidates:
            return candidates[-1]
    print(f"ERROR: no x64/Microsoft.VC*.CRT under {root}", file=sys.stderr)
    return None


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dependents", required=True)
    parser.add_argument("--redist-dir", required=True)
    parser.add_argument("--dest", required=True)
    args = parser.parse_args(argv[1:])

    source = redist_dir(args.redist_dir)
    if source is None:
        return 1

    # dumpbin reports the imports in upper case while the MSVC redistributable
    # ships lower-case file names; canonicalize so the lookup behaves the same
    # on a case-sensitive host.
    wanted = sorted({name.lower() for name in dependents(args.dependents) if RUNTIME_PATTERN.match(name)})
    if not wanted:
        print("ERROR: the binary imports no MSVC runtime DLL", file=sys.stderr)
        return 1

    destination = pathlib.Path(args.dest)
    destination.mkdir(parents=True, exist_ok=True)
    for name in wanted:
        candidate = source / name
        if not candidate.is_file():
            print(f"ERROR: {name} is not in {source}", file=sys.stderr)
            return 1
        shutil.copy2(candidate, destination / name)
        print(f"runtime: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
