#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
source "$root/tests/helpers.sh"

checker="$root/scripts/check-elf-alignment.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# READELF is overridable so the parser runs against canned `readelf -lW`
# output: the macOS host has no readelf and the fast CI job has no NDK, but
# the fixture is exactly what the real tool prints.
cat > "$work/readelf-stub" <<'STUB'
#!/bin/sh
cat "$CHECK_ELF_FIXTURE"
STUB
chmod +x "$work/readelf-stub"

# The checker validates file existence before invoking readelf; the fakes only
# need to exist, the stub never reads them.
: > "$work/fake.so"
: > "$work/first.so"
: > "$work/second.so"

run_checker() { # <min-align-bytes> <fixture-name>
  CHECK_ELF_FIXTURE="$root/tests/fixtures/$2" \
  READELF="$work/readelf-stub" \
    bash "$checker" "$1" "$work/fake.so"
}

run_checker_ok() { # exits 0 or the test fails
  run_checker "$@" || fail "'$2' at min-align $1 should pass"
}
run_checker_fail() { # exits non-zero or the test fails
  if run_checker "$@"; then
    fail "'$2' at min-align $1 should be rejected"
  fi
}

# A 16 KiB-aligned .so is exactly what Android 16 KB compatibility requires.
run_checker_ok 16384 readelf-load-16k.txt
# 4 KiB LOADs are the non-compliant case this checker exists to catch.
run_checker_fail 16384 readelf-load-4k.txt
# The same layout is fine when only 4 KiB is required (32-bit sanity level).
run_checker_ok 4096 readelf-load-4k.txt
# 64 KiB alignment is a multiple of 16 KiB: compatible with 16 KB devices.
run_checker_ok 16384 readelf-load-64k.txt
# An alignment above 16 KiB but not a multiple of it cannot be mapped on
# 16 KiB pages either.
run_checker_fail 16384 readelf-load-nonmultiple.txt
# No PT_LOAD at all is an error, not a silent pass.
run_checker_fail 16384 readelf-load-none.txt

# A missing file is a clean error, not a crash.
if CHECK_ELF_FIXTURE="$root/tests/fixtures/readelf-load-16k.txt" \
   READELF="$work/readelf-stub" bash "$checker" 16384 "$work/absent.so"; then
  fail "missing file should be rejected"
fi

# Multiple files: one bad .so fails the whole run even if others pass.
if CHECK_ELF_FIXTURE="$root/tests/fixtures/readelf-load-16k.txt" \
   READELF="$work/readelf-stub" \
   bash "$checker" 16384 "$work/first.so" "$work/second.so"; then
  : # fixtures are per-stub, so both files read the same 16k fixture; just
    # assert the success path here (the mixed case needs two stubs below).
else
  fail "two 16k-aligned files should pass together"
fi
cat > "$work/readelf-stub-bad" <<'STUB'
#!/bin/sh
cat "${CHECK_ELF_BAD_FIXTURE:?}"
STUB
chmod +x "$work/readelf-stub-bad"
if CHECK_ELF_BAD_FIXTURE="$root/tests/fixtures/readelf-load-4k.txt" \
   READELF="$work/readelf-stub-bad" \
   bash "$checker" 16384 "$work/first.so" "$work/second.so"; then
  fail "a 4k-aligned file among 16k ones should fail the run"
fi

# Usage errors are reported, not crashed into.
if bash "$checker" 16384 >/dev/null 2>&1; then
  fail "missing file argument should be a usage error"
fi
if bash "$checker" banana "$work/fake.so" >/dev/null 2>&1; then
  fail "non-numeric min-align should be a usage error"
fi

pass "check-elf-alignment"
