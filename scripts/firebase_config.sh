#!/usr/bin/env bash
# Copies the Firebase config of the termphin-hexeosoft project into the tree.
# The files live outside the repository (~/.config/termphin/firebase, or
# $TERMPHIN_FIREBASE_DIR) and are git-ignored where they land. Without them
# the app builds and runs without Firebase.
#
# It also writes ios/Flutter/Firebase.xcconfig with the reversed iOS client
# id, the URL scheme Google sign-in returns through (Info.plist).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${TERMPHIN_FIREBASE_DIR:-$HOME/.config/termphin/firebase}"

if [ ! -d "$SOURCE" ]; then
  echo "No Firebase config in $SOURCE; building without Firebase." >&2
  exit 0
fi

install -m 600 "$SOURCE/google-services.json" "$ROOT/android/app/google-services.json"
install -m 600 "$SOURCE/GoogleService-Info.plist" "$ROOT/ios/Runner/GoogleService-Info.plist"

if [ -f "$SOURCE/dart-defines.json" ]; then
  python3 - "$SOURCE/dart-defines.json" "$ROOT/ios/Flutter/Firebase.xcconfig" <<'PY'
import json
import sys

client = json.load(open(sys.argv[1])).get("FIREBASE_IOS_CLIENT_ID", "")
reversed_id = ".".join(reversed(client.split("."))) if client else ""
with open(sys.argv[2], "w") as out:
    out.write(f"GOOGLE_REVERSED_CLIENT_ID = {reversed_id}\n")
PY
fi
echo "Firebase config copied from $SOURCE"
