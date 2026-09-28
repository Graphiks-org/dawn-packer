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

# Repartir d'un sous-module propre avant d'appliquer les éventuels patches.
git -C dawn checkout -- .
git -C dawn clean -fd

shopt -s nullglob
patches=(patches/*.patch)
for p in "${patches[@]}"; do
  echo "Applying $p"
  git -C dawn apply "$p"
done

mkdir -p build
printf '%s\n' "$DAWN_TAG" > build/dawn-tag.txt
git -C dawn rev-parse HEAD > build/dawn-revision.txt
echo "Dawn $DAWN_TAG @ $(cat build/dawn-revision.txt)"
