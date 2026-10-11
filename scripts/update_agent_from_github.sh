#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/assets/termphin-agent"
REPO="Termphin/termphin-agent"
TAG="${1:-latest}"

if [[ "$TAG" == "latest" ]]; then
  TAG="$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName')"
  if [[ -z "$TAG" ]]; then
    echo "no releases found in $REPO" >&2
    exit 1
  fi
fi

mkdir -p "$ASSETS"
gh release download "$TAG" --repo "$REPO" --dir "$ASSETS" --clobber \
  --pattern 'termphin-agent-*' --pattern 'manifest.properties'

for key in x86_64 aarch64 windows_x86_64 macos_x86_64 macos_aarch64; do
  file="$(awk -F= -v k="$key.file" '$1 == k { print $2 }' "$ASSETS/manifest.properties")"
  sha="$(awk -F= -v k="$key.sha256" '$1 == k { print $2 }' "$ASSETS/manifest.properties")"
  [[ -n "$file" && -n "$sha" ]] || continue
  echo "$sha  $ASSETS/$file" | sha256sum -c -
done

# Ship them gzipped. App Store validation refuses a Mach-O anywhere in the app
# bundle, and it rejected the two macOS helpers by name - even though nothing
# here runs on the device, it is bytes on their way to the user's own server.
# The digests above stay the helper's own, so the app checks what it uploads
# rather than what it unpacks from.
for key in x86_64 aarch64 windows_x86_64 macos_x86_64 macos_aarch64; do
  file="$(awk -F= -v k="$key.file" '$1 == k { print $2 }' "$ASSETS/manifest.properties")"
  [[ -n "$file" && "$file" != *.gz ]] || continue
  gzip -9 -f "$ASSETS/$file"
  sed -i.bak "s|^$key.file=$file$|$key.file=$file.gz|" "$ASSETS/manifest.properties"
  rm -f "$ASSETS/manifest.properties.bak"
done

VERSION="$(awk -F= '$1 == "version" { print $2 }' "$ASSETS/manifest.properties")"
printf 'Fetched termphin-agent %s (%s), helpers gzipped\n' "$TAG" "$VERSION"
