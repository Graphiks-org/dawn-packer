#!/usr/bin/env python3
"""Build a manifest.json for an installed Dawn tree (stdlib only)."""
import argparse
import datetime
import hashlib
import json
import pathlib
import sys


def sha256_of(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(directory, base, extra_globs):
    files = []
    for pattern in extra_globs:
        files.extend(sorted(pathlib.Path(directory).glob(pattern)))
    unique = {}
    for path in files:
        if path.is_file():
            unique[str(path.relative_to(base))] = path
    return unique


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-dir", required=True)
    parser.add_argument("--kotlin-target", required=True)
    parser.add_argument("--entry-json", required=True, help="one matrix entry as JSON")
    parser.add_argument("--dawn-tag", required=True)
    parser.add_argument("--dawn-revision", required=True)
    parser.add_argument("--linkage", required=True, choices=["static", "shared"])
    parser.add_argument("--packer-version", default="0.1.0")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    install = pathlib.Path(args.install_dir).resolve()
    entry = json.loads(args.entry_json)

    # Headers travel with every archive; libraries are the linkage-specific payload.
    payload = collect(install, install, ["include/**/*.h", "lib/*.a", "lib/*.so*", "lib/*.dylib", "lib/*.dll", "lib/*.lib"])
    artifacts = []
    for relative, path in sorted(payload.items()):
        artifacts.append({"path": relative, "sha256": sha256_of(path), "size": path.stat().st_size})
    if not artifacts:
        print("ERROR: no headers or libraries found in install dir", file=sys.stderr)
        return 1

    manifest = {
        "schemaVersion": 1,
        "packerVersion": args.packer_version,
        "dawn": {"tag": args.dawn_tag, "revision": args.dawn_revision},
        "target": {
            "kotlinTarget": args.kotlin_target,
            "triple": entry["triple"],
            "os": entry["os"],
            "arch": entry["arch"],
        },
        "linkage": args.linkage,
        "backends": entry["backends"],
        "compiler": {},
        "cmake": {"buildType": "Release"},
        "artifacts": artifacts,
        "createdAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    pathlib.Path(args.out).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"manifest: {args.out} ({len(artifacts)} artifacts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
