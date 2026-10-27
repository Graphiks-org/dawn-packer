#!/usr/bin/env bash
# Assert that every PT_LOAD segment of an ELF file is aligned to at least
# <min-align> bytes and to a multiple of it. Android 16 KB page size
# compatibility requires this on the 64-bit ABIs (arm64-v8a, x86_64): a .so
# whose LOAD segments are only 4 KiB aligned cannot be loaded on a device
# with 16 KiB pages, and Google Play rejects it for apps targeting
# Android 15+ (see docs/spikes/android.md).
#
# Usage: check-elf-alignment.sh <min-align-bytes> <elf-file>...
# READELF overrides the readelf binary (default: readelf), so tests can feed
# canned `readelf -lW` output.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <min-align-bytes> <elf-file>..." >&2
  exit 2
fi
min_align="$1"
shift

case "$min_align" in
  '' | *[!0-9]*)
    echo "ERROR: min-align must be a positive integer, got '$min_align'" >&2
    exit 2
    ;;
esac

readelf_bin="${READELF:-readelf}"
status=0

for elf in "$@"; do
  if [ ! -f "$elf" ]; then
    echo "ERROR: no such file: $elf" >&2
    status=1
    continue
  fi
  # The last field of each LOAD line is p_align, printed in hex by readelf.
  aligns="$("$readelf_bin" -lW "$elf" 2>/dev/null | awk '$1 == "LOAD" { print $NF }')"
  if [ -z "$aligns" ]; then
    echo "ERROR: $elf: no PT_LOAD segments found (not an ELF?)" >&2
    status=1
    continue
  fi
  bad=0
  while IFS= read -r align; do
    # Bash arithmetic parses 0x-prefixed hex directly.
    value=$((align))
    if [ "$value" -lt "$min_align" ] || [ $((value % min_align)) -ne 0 ]; then
      echo "ERROR: $elf: PT_LOAD alignment $align ($value bytes) is below" \
        "$min_align or not a multiple of it" >&2
      bad=1
    fi
  done <<EOF
$aligns
EOF
  if [ "$bad" -eq 0 ]; then
    echo "OK: $elf: all PT_LOAD segments aligned to a multiple of $min_align"
  else
    status=1
  fi
done

exit "$status"
