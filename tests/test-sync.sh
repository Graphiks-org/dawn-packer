#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"
bash scripts/sync.sh
assert_file "$root/build/dawn-tag.txt"
assert_file "$root/build/dawn-revision.txt"
assert_eq "$(cat "$root/build/dawn-revision.txt")" "$(git -C "$root/dawn" rev-parse HEAD)"
# Every patch must actually land: `git -C dawn` resolves relative paths
# against dawn/, so a relative patch path silently pointed nowhere.
if compgen -G "patches/*.patch" > /dev/null; then
    assert_neq "$(git -C "$root/dawn" status --porcelain)" "" "patches/*.patch were not applied to the dawn submodule"
fi
pass "sync"
