#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# shellcheck disable=SC1091
source ./dawn-pin.env

# NOTE: non-recursive on purpose. Dawn's own submodules (v8, LLVM, SwiftShader,
# ANGLE, ...) are multi-GB and are not needed to pin the revision. Recursively
# initialising them blows the disk budget; build tasks fetch deps explicitly.
git submodule update --init dawn

# Start from a clean submodule before applying any patches.
git -C dawn checkout -- .
git -C dawn clean -fd

shopt -s nullglob
# Iterate the glob directly: with nullglob, no matches means zero iterations.
# Do NOT collect into an array and expand "${patches[@]}": under `set -u`,
# bash 3.2 (macOS /bin/bash, used by the CI Apple jobs) treats an empty array
# expansion as an unbound variable and aborts.
for p in patches/*.patch; do
  echo "Applying $p"
  git -C dawn apply "$p"
done

mkdir -p build
printf '%s\n' "$DAWN_TAG" > build/dawn-tag.txt
git -C dawn rev-parse HEAD > build/dawn-revision.txt
echo "Dawn $DAWN_TAG @ $(cat build/dawn-revision.txt)"
