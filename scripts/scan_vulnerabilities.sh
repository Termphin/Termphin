#!/usr/bin/env bash
# Known vulnerabilities in dependencies, from osv.dev, via osv-scanner.
#
#   scripts/scan_vulnerabilities.sh
#
# Exits non-zero when the app's pubspec.lock has a finding.
#
# Needs osv-scanner on PATH: https://google.github.io/osv-scanner/installation/
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! command -v osv-scanner >/dev/null; then
  echo "osv-scanner is not on PATH." >&2
  echo "Install: https://google.github.io/osv-scanner/installation/" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

echo "== App (pubspec.lock)"
app_status=0
osv-scanner --lockfile=pubspec.lock || app_status=$?

# osv-scanner exits 1 for findings and higher for a scan that could not run;
# either way the app's result is the answer.
exit "$app_status"
