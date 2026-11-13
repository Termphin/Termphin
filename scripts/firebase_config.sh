#!/usr/bin/env bash
# Copies the Firebase config of the termphin-hexeosoft project into the tree.
# The files live outside the repository (~/.config/termphin/firebase, or
# $TERMPHIN_FIREBASE_DIR) and are git-ignored where they land. Without them
# the app builds and runs without Firebase.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${TERMPHIN_FIREBASE_DIR:-$HOME/.config/termphin/firebase}"

if [ ! -d "$SOURCE" ]; then
  echo "No Firebase config in $SOURCE; building without Firebase." >&2
  exit 0
fi

install -m 600 "$SOURCE/google-services.json" "$ROOT/android/app/google-services.json"
install -m 600 "$SOURCE/GoogleService-Info.plist" "$ROOT/ios/Runner/GoogleService-Info.plist"
echo "Firebase config copied from $SOURCE"
