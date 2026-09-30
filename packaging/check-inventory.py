#!/usr/bin/env python3
"""Prove an archive and its manifest describe the same set of files.

Three ways they can disagree, all of which must fail loudly rather than ship:
a manifest entry the archive lacks, an archive member the manifest lacks, and a
staged file the manifest lacks (the case that let bin/webgpu_dawn.dll vanish).
"""
import argparse
import json
import pathlib
import sys
import tarfile


def portable_path(path):
    """Return a path with forward slashes, whatever the host or path flavour.

    Tar members always use forward slashes, while the manifest and the staged
    tree can be produced on Windows, where str(PureWindowsPath(...)) yields
    backslashes. Normalizing every side keeps the three sets comparable.
    """
    return str(path).replace("\\", "/")


def archive_members(archive):
    with tarfile.open(archive) as handle:
        return {portable_path(m.name) for m in handle.getmembers() if m.isfile()}


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    parser.add_argument("manifest")
    parser.add_argument("staged_dir")
    args = parser.parse_args(argv[1:])

    with open(args.manifest, encoding="utf-8") as handle:
        manifest_paths = {portable_path(a["path"]) for a in json.load(handle)["artifacts"]}
    members = archive_members(args.archive)
    staged = {
        portable_path(path.relative_to(args.staged_dir))
        for path in pathlib.Path(args.staged_dir).rglob("*")
        if path.is_file()
    } - {"manifest.json", ".dawn-packer-install"}

    problems = []
    for path in sorted(manifest_paths - members):
        problems.append(f"manifest lists {path} but the archive lacks it")
    for path in sorted(members - manifest_paths - {"manifest.json"}):
        problems.append(f"archive contains {path} but the manifest lacks it")
    for path in sorted(staged - manifest_paths):
        problems.append(f"staged file {path} is missing from the manifest")
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1
    print(f"inventory OK: {len(manifest_paths)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
