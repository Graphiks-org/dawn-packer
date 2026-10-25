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
    # CRLF patches never apply to Dawn's LF-pinned sources: the mingwX64 job
    # failed exactly this way before .gitattributes pinned *.patch to LF.
    for p in patches/*.patch; do
        if grep -q "$(printf '\r')" "$p"; then
            fail "$p contains CR bytes; .gitattributes must pin *.patch text eol=lf"
        fi
    done
fi
pass "sync"
