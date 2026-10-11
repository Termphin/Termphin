#!/usr/bin/env bash
# Real process memory for a running Termphin, straight from Android.
#
# What the process actually costs, including the Flutter engine, graphics
# and the platform's own overhead.
#
#   scripts/measure_memory.sh              # one reading
#   scripts/measure_memory.sh --watch 5    # a reading every 5 seconds
#
# Build with --profile or --release. A debug build carries the VM service and
# unoptimised code, and its numbers say nothing about what users will see.
set -euo pipefail

PACKAGE="${TERMPHIN_PACKAGE:-dev.termphin.termphin}"
INTERVAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch) INTERVAL="${2:-5}"; shift 2 ;;
    --package) PACKAGE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! command -v adb >/dev/null; then
  echo "adb is not on PATH." >&2
  exit 1
fi

if [[ -z "$(adb devices | awk 'NR>1 && $2=="device"')" ]]; then
  echo "No device. Connect a phone with USB debugging enabled." >&2
  exit 1
fi

reading() {
  local dump
  if ! dump="$(adb shell dumpsys meminfo "$PACKAGE" 2>/dev/null)"; then
    echo "Could not read meminfo for $PACKAGE." >&2
    return 1
  fi
  if grep -q "No process found" <<<"$dump"; then
    echo "$PACKAGE is not running. Start it first." >&2
    return 1
  fi

  # PSS is the number to watch: private memory plus this process's share of
  # what it maps with others, which is what Android weighs when deciding who
  # to kill. Labels in the table are two words wide, so the Pss column is $3
  # for those rows and $2 for the single-word ones.
  awk -v ts="$(date +%H:%M:%S)" '
    /^ *Native Heap/  { native = $3 }
    /^ *Dalvik Heap/  { dalvik = $3 }
    /^ *Gfx dev/      { gfx    = $3 }
    /^ *EGL mtrack/   { egl    = $3 }
    /^ *TOTAL /       { if (total == "") total = $2 }
    END {
      printf "%s  total %6.1f MB | native %5.1f  dalvik %5.1f  gfx %5.1f  egl %5.1f\n",
        ts, total/1024, native/1024, dalvik/1024, gfx/1024, egl/1024
    }
  ' <<<"$dump"
}

echo "package: $PACKAGE"
if [[ -z "$INTERVAL" ]]; then
  reading
else
  echo "Sampling every ${INTERVAL}s. Ctrl-C to stop."
  while true; do
    reading || exit 1
    sleep "$INTERVAL"
  done
fi
