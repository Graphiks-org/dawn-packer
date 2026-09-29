#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"
cd "$root"

# This test builds every non-dropped target, which is only possible in CI where
# each platform has a matching runner (Linux, Android NDK, Xcode). A developer
# host cannot build targets whose toolchain is absent, so the test is opt-in and
# must skip cleanly (exit 0) otherwise.
if [ "${RUN_ALL_TARGETS:-0}" != "1" ]; then
  echo "SKIP: set RUN_ALL_TARGETS=1 to build every target (CI only)"
  exit 0
fi

# The only target whose binary runs on this host; every other target is
# link-only.
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) host_target=macosArm64 ;;
  Darwin-x86_64) host_target=macosX64 ;;
  Linux-x86_64) host_target=linuxX64 ;;
  Linux-aarch64) host_target=linuxArm64 ;;
  *) host_target= ;;
esac

while read -r target; do
  status="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["status"])' "$(python3 scripts/matrix.py get "$target")")"
  [ "$status" = "dropped" ] && continue
  bash scripts/build-target.sh "$target" static
  bash scripts/package.sh "$target" static
  # Glob the tag slug: the Dawn tag is dynamic and must never be hardcoded.
  archive="$(ls dist/"$target"/dawn-*-"$target"-static.tar.gz | head -n1)"
  if [ "$target" = "$host_target" ]; then
    bash scripts/run-smoke-test.sh "$archive"
  else
    bash scripts/run-smoke-test.sh "$archive" --link-only
  fi
  pass "built $target"
done < <(python3 scripts/matrix.py list)
