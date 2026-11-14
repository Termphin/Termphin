#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-android}"
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [android|ios]" >&2
  exit 1
fi

case "$TARGET" in
  android|ios)
    ;;
  *)
    echo "Usage: $0 [android|ios]" >&2
    exit 1
    ;;
esac

if [ "$TARGET" = "ios" ]; then
  if [ "$(uname)" != "Darwin" ]; then
    echo "Building for iOS requires macOS." >&2
    exit 1
  fi
fi

VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}')"

FIREBASE_DIR="${TERMPHIN_FIREBASE_DIR:-$HOME/.config/termphin/firebase}"
if [ -n "${FIREBASE_CONFIG_BASE64:-}" ]; then
  FIREBASE_DIR="$(mktemp -d)"
  trap 'rm -rf "$FIREBASE_DIR"' EXIT
  printf '%s' "$FIREBASE_CONFIG_BASE64" | base64 -d | tar -xz -C "$FIREBASE_DIR"
fi
FIREBASE_ARGS=()
if [ -f "$FIREBASE_DIR/dart-defines.json" ]; then
  TERMPHIN_FIREBASE_DIR="$FIREBASE_DIR" "$ROOT/scripts/firebase_config.sh"
  FIREBASE_ARGS=(--dart-define-from-file="$FIREBASE_DIR/dart-defines.json")
else
  echo "Warning: no Firebase config in $FIREBASE_DIR. Analytics, crash reports, accounts and push will be off in this build." >&2
fi

if [ "$TARGET" = "android" ]; then
  echo "Building app-release.aab and app-release.apk for $VERSION..."
  (
    cd "$ROOT"
    flutter build appbundle "${FIREBASE_ARGS[@]}"
    flutter build apk "${FIREBASE_ARGS[@]}"
  )

  echo
  echo "Built: build/app/outputs/bundle/release/app-release.aab"
  echo "Built: build/app/outputs/flutter-apk/app-release.apk"
else
  APP_STORE_ID="${APP_STORE_ID:-}"
  if [ -z "$APP_STORE_ID" ]; then
    echo "Warning: APP_STORE_ID is unset or empty. The \"Rate Termphin\" row will be hidden in this build. The numeric id comes from App Store Connect." >&2
  fi

  echo "Building ipa for $VERSION..."

  BUILD_ARGS=(--dart-define=APP_STORE_ID="$APP_STORE_ID" "${FIREBASE_ARGS[@]}")
  if [ -n "${EXPORT_OPTIONS_PLIST:-}" ]; then
    BUILD_ARGS+=(--export-options-plist="$EXPORT_OPTIONS_PLIST")
  fi
  (
    cd "$ROOT"
    flutter build ipa "${BUILD_ARGS[@]}"
  )

  echo
  echo "Built: build/ios/ipa"
fi
