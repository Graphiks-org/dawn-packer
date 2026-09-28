#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

target="${1:?usage: package.sh <kotlinTarget> <static|shared>}"
linkage="$(printf '%s' "${2:?linkage required}" | tr '[:upper:]' '[:lower:]')"
case "$linkage" in static|shared) ;; *) echo "linkage must be static or shared" >&2; exit 2 ;; esac

install_dir="${DAWN_PACKER_INSTALL_DIR:-$root/dist/$target/$linkage/install}"
# DAWN_PACKER_DIST_DIR overrides the dist root; the per-target directory is
# always appended, so archives land in dist/<target>/dawn-...tar.gz.
out_root="${DAWN_PACKER_DIST_DIR:-$root/dist}/$target"

# The marker is dropped by scripts/build-target.sh when it installs a target.
[ -f "$install_dir/.dawn-packer-install" ] || { echo "missing install tree: $install_dir" >&2; exit 1; }
[ -f build/dawn-tag.txt ] || { echo "missing build/dawn-tag.txt (run scripts/sync.sh)" >&2; exit 1; }
[ -f build/dawn-revision.txt ] || { echo "missing build/dawn-revision.txt (run scripts/sync.sh)" >&2; exit 1; }

dawn_tag="$(cat build/dawn-tag.txt)"
dawn_revision="$(cat build/dawn-revision.txt)"
tag_slug="${dawn_tag//\//-}"
entry="$(python3 scripts/matrix.py get "$target")"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$install_dir/include" "$stage/include"
cp -R "$install_dir/lib" "$stage/lib"

python3 packaging/make-manifest.py \
  --install-dir "$stage" \
  --kotlin-target "$target" \
  --entry-json "$entry" \
  --dawn-tag "$dawn_tag" \
  --dawn-revision "$dawn_revision" \
  --linkage "$linkage" \
  --out "$stage/manifest.json" >/dev/null

python3 packaging/validate-manifest.py "$stage/manifest.json" >/dev/null

mkdir -p "$out_root"
archive="$out_root/dawn-$tag_slug-$target-$linkage.tar.gz"
# Archive without a leading ./ so entries are include/..., lib/..., manifest.json.
tar -czf "$archive" -C "$stage" include lib manifest.json
echo "archive: $archive"
