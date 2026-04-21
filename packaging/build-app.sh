#!/usr/bin/env bash
# Builds "Knowledge Manager.app" into ./dist/
# Usage: ./packaging/build-app.sh [--arch arm64|x64] [--node-version 22.16.0]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$ROOT/packaging"
DIST_DIR="$ROOT/dist"
CACHE_DIR="$DIST_DIR/.cache"

APP_NAME="Knowledge Manager"
APP_PATH="$DIST_DIR/${APP_NAME}.app"
VERSION="1.0.0"

# Defaults — can be overridden via flags.
NODE_VERSION="$(cat "$ROOT/.node-version" 2>/dev/null | tr -d 'v' || echo "22.16.0")"
ARCH_FLAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH_FLAG="$2"; shift 2 ;;
    --node-version) NODE_VERSION="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--arch arm64|x64] [--node-version X.Y.Z]"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

HOST_ARCH="$(uname -m)"
if [ -z "$ARCH_FLAG" ]; then
  case "$HOST_ARCH" in
    arm64) ARCH_FLAG="arm64" ;;
    x86_64) ARCH_FLAG="x64" ;;
    *) echo "Unsupported host arch: $HOST_ARCH" >&2; exit 1 ;;
  esac
fi

case "$ARCH_FLAG" in
  arm64|x64) ;;
  *) echo "Invalid --arch: $ARCH_FLAG (use arm64 or x64)" >&2; exit 1 ;;
esac

NODE_PKG="node-v${NODE_VERSION}-darwin-${ARCH_FLAG}"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_PKG}.tar.gz"

echo "==> Building ${APP_NAME}.app"
echo "    arch:   ${ARCH_FLAG}"
echo "    node:   ${NODE_VERSION}"
echo "    output: ${APP_PATH}"

mkdir -p "$CACHE_DIR"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/app"

# ---------- Node runtime ----------
NODE_TAR="$CACHE_DIR/${NODE_PKG}.tar.gz"
if [ ! -f "$NODE_TAR" ]; then
  echo "==> Downloading Node.js v${NODE_VERSION} (${ARCH_FLAG})"
  curl -fL --progress-bar -o "$NODE_TAR" "$NODE_URL"
fi

echo "==> Extracting Node.js into bundle"
mkdir -p "$APP_PATH/Contents/Resources/node"
tar -xzf "$NODE_TAR" -C "$APP_PATH/Contents/Resources/node" --strip-components=1

# Trim parts we don't need at runtime — saves ~55 MB.
rm -rf "$APP_PATH/Contents/Resources/node/include"
rm -rf "$APP_PATH/Contents/Resources/node/share"
rm -f  "$APP_PATH/Contents/Resources/node/README.md"
rm -f  "$APP_PATH/Contents/Resources/node/CHANGELOG.md"
rm -f  "$APP_PATH/Contents/Resources/node/LICENSE"

# ---------- Quartz source ----------
echo "==> Copying Quartz source"
rsync -a \
  --exclude='/public' \
  --exclude='/dist' \
  --exclude='/.cache' \
  --exclude='/.git' \
  --exclude='/.claude' \
  --exclude='/node_modules' \
  --exclude='/content' \
  --exclude='/packaging' \
  --exclude='.DS_Store' \
  "$ROOT/" "$APP_PATH/Contents/Resources/app/"

# ---------- Launcher ----------
echo "==> Compiling Swift launcher (target: $ARCH_FLAG)"
SWIFT_SRC="$PKG_DIR/src/Launcher.swift"
SWIFT_OUT="$APP_PATH/Contents/MacOS/KnowledgeManager"
case "$ARCH_FLAG" in
  arm64) SWIFT_TARGET="arm64-apple-macos11" ;;
  x64)   SWIFT_TARGET="x86_64-apple-macos11" ;;
esac
if ! swiftc -O -target "$SWIFT_TARGET" "$SWIFT_SRC" -o "$SWIFT_OUT"; then
  echo "  (error) swiftc failed — install Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi
chmod +x "$SWIFT_OUT"

echo "==> Installing bash launcher as resource"
cp "$PKG_DIR/templates/launcher.sh" "$APP_PATH/Contents/Resources/launcher.sh"
chmod +x "$APP_PATH/Contents/Resources/launcher.sh"

# ---------- Info.plist ----------
echo "==> Writing Info.plist"
sed "s/__VERSION__/${VERSION}/g" "$PKG_DIR/templates/Info.plist" > "$APP_PATH/Contents/Info.plist"

# ---------- Icon ----------
ICON_SVG="$PKG_DIR/assets/app-icon.svg"
if [ -f "$ICON_SVG" ]; then
  echo "==> Rasterizing Accion icon (SVG → PNG → icns)"
  ICONSET="$CACHE_DIR/icon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"

  # Use QuickLook to rasterize the SVG (produces <name>.svg.png alongside).
  RASTER_DIR="$CACHE_DIR/icon-raster"
  rm -rf "$RASTER_DIR"
  mkdir -p "$RASTER_DIR"
  qlmanage -t -s 1024 -o "$RASTER_DIR" "$ICON_SVG" >/dev/null 2>&1
  SRC_PNG="$RASTER_DIR/$(basename "$ICON_SVG").png"
  if [ ! -f "$SRC_PNG" ]; then
    echo "  (warning) qlmanage did not produce a PNG — skipping icon" >&2
  else
    for size in 16 32 128 256 512; do
      sips -z $size $size "$SRC_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
      DOUBLE=$((size * 2))
      sips -z $DOUBLE $DOUBLE "$SRC_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/icon.icns"
  fi
fi

# ---------- Clear extended attributes that can trip Gatekeeper ----------
xattr -cr "$APP_PATH" 2>/dev/null || true

echo "==> Done"
echo
echo "App bundle: $APP_PATH"
echo "Size: $(du -sh "$APP_PATH" | cut -f1)"
echo
echo "To test locally:"
echo "  open \"$APP_PATH\""
echo
echo "To distribute, zip the bundle:"
echo "  (cd \"$DIST_DIR\" && zip -qr \"${APP_NAME}-${ARCH_FLAG}.zip\" \"${APP_NAME}.app\")"
