#!/usr/bin/env bash
set -euo pipefail

# Packages a built Flutter Linux release bundle into an AppImage.
# Usage: linux/packaging/build_appimage.sh [bundle_dir] [output_appimage]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="${1:-$ROOT_DIR/build/linux/x64/release/bundle}"
OUT_APPIMAGE="${2:-$ROOT_DIR/Termphin-x86_64.AppImage}"
APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
ARCH="${ARCH:-x86_64}"

if [ ! -x "$BUNDLE_DIR/termphin" ]; then
  echo "Linux release bundle not found at $BUNDLE_DIR" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_DIR="$WORK_DIR/Termphin.AppDir"

mkdir -p \
  "$APP_DIR/usr/bin" \
  "$APP_DIR/usr/share/applications" \
  "$APP_DIR/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE_DIR"/. "$APP_DIR/usr/bin/"

cat > "$APP_DIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/termphin" "$@"
EOF
chmod 0755 "$APP_DIR/AppRun"

DESKTOP_SRC="$ROOT_DIR/linux/packaging/dev.termphin.termphin.desktop"
cp "$DESKTOP_SRC" "$APP_DIR/dev.termphin.termphin.desktop"
cp "$DESKTOP_SRC" "$APP_DIR/usr/share/applications/dev.termphin.termphin.desktop"

ICON_SRC="$ROOT_DIR/assets/icons/termphin_icon.png"
cp "$ICON_SRC" "$APP_DIR/termphin.png"
cp "$ICON_SRC" "$APP_DIR/.DirIcon"
cp "$ICON_SRC" "$APP_DIR/usr/share/icons/hicolor/512x512/apps/termphin.png"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APP_DIR/dev.termphin.termphin.desktop"
fi

ARGS=()
if [ -n "${APPIMAGE_UPDATE_INFO:-}" ]; then
  ARGS+=(-u "$APPIMAGE_UPDATE_INFO")
fi

# --appimage-extract-and-run lets appimagetool run in containers without FUSE.
ARCH="$ARCH" "$APPIMAGETOOL" --appimage-extract-and-run "${ARGS[@]}" "$APP_DIR" "$OUT_APPIMAGE"
chmod 0755 "$OUT_APPIMAGE"
