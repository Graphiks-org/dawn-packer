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
entry_json="$(python3 scripts/matrix.py get "$target")"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
# Stage every top-level entry of the install tree except the marker the build
# writes, so whatever Dawn's install learns to emit is carried into the archive
# (bin/ for the Windows DLL and its runtime, for one). Staging a fixed list of
# directories is what used to drop bin/ in silence.
members=()
for entry in "$install_dir"/*; do
  name="$(basename "$entry")"
  if [ "$name" = ".dawn-packer-install" ]; then
    continue
  fi
  cp -R "$entry" "$stage/$name"
  members+=("$name")
done
if [ "${#members[@]}" -eq 0 ]; then
  echo "empty install tree: $install_dir" >&2
  exit 1
fi

# build-target.sh drops provenance next to the install tree. Pass it through
# when present; make-manifest.py keeps its legacy output otherwise.
provenance="$(dirname "$install_dir")/packer-provenance.json"
provenance_args=()
if [ -f "$provenance" ]; then
  provenance_args=(--provenance "$provenance")
fi

python3 packaging/make-manifest.py \
  --install-dir "$stage" \
  --kotlin-target "$target" \
  --entry-json "$entry_json" \
  --dawn-tag "$dawn_tag" \
  --dawn-revision "$dawn_revision" \
  --linkage "$linkage" \
  ${provenance_args[@]+"${provenance_args[@]}"} \
  --out "$stage/manifest.json" >/dev/null

python3 packaging/validate-manifest.py "$stage/manifest.json" >/dev/null

mkdir -p "$out_root"
archive="$out_root/dawn-$tag_slug-$target-$linkage.tar.gz"
members+=(manifest.json)
# Archive without a leading ./ so entries are include/..., lib/..., manifest.json.
# COPYFILE_DISABLE stops bsdtar on macOS from adding AppleDouble (._*) sidecar
# members for extended attributes, which are not artifacts and would otherwise
# leave the archive stating files the manifest does not describe.
COPYFILE_DISABLE=1 tar -czf "$archive" -C "$stage" "${members[@]}"
python3 packaging/check-inventory.py "$archive" "$stage/manifest.json" "$stage" >/dev/null
echo "archive: $archive"
