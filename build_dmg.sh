#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$PROJECT_ROOT/FlowVision.xcodeproj}"
SCHEME="${SCHEME:-FlowVision}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$PROJECT_ROOT/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist}"
APP_NAME="${APP_NAME:-}"
VOLUME_NAME="${VOLUME_NAME:-FlowVision}"
DMG_NAME="${DMG_NAME:-FlowVision-macOS}"
XCODEBUILD_EXTRA_ARGS="${XCODEBUILD_EXTRA_ARGS:-}"
MPV_FRAMEWORKS_DIR="${MPV_FRAMEWORKS_DIR:-/Applications/IINA.app/Contents/Frameworks}"
INCLUDE_MPV_RUNTIME="${INCLUDE_MPV_RUNTIME:-auto}" # auto, 1, 0

# Optional signing controls
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
ENABLE_CODESIGN="${ENABLE_CODESIGN:-1}" # 1=on, 0=off

echo "[1/4] Building app (scheme=$SCHEME, configuration=$CONFIGURATION)..."
read -r -a EXTRA_ARGS <<< "$XCODEBUILD_EXTRA_ARGS"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  "${EXTRA_ARGS[@]}"

BUILD_PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"

if [[ -n "$APP_NAME" ]]; then
  APP_PATH="$BUILD_PRODUCTS_DIR/$APP_NAME.app"
else
  APP_PATH="$(find "$BUILD_PRODUCTS_DIR" -maxdepth 1 -type d -name "*.app" | head -n 1)"
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: .app not found in $BUILD_PRODUCTS_DIR"
  echo "Tip: set APP_NAME explicitly, e.g. APP_NAME=FlowVisionDbg ./build_dmg.sh"
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"

if [[ "$INCLUDE_MPV_RUNTIME" == "1" || ( "$INCLUDE_MPV_RUNTIME" == "auto" && -f "$MPV_FRAMEWORKS_DIR/libmpv.2.dylib" ) ]]; then
  echo "[2/4] Copying mpv runtime from: $MPV_FRAMEWORKS_DIR"
  mkdir -p "$APP_PATH/Contents/Frameworks"
  rsync -a --delete \
    --include='*.dylib' \
    --exclude='*' \
    "$MPV_FRAMEWORKS_DIR/" \
    "$APP_PATH/Contents/Frameworks/"
elif [[ "$INCLUDE_MPV_RUNTIME" == "1" ]]; then
  echo "ERROR: mpv runtime not found at $MPV_FRAMEWORKS_DIR"
  exit 1
else
  echo "[2/4] Skipping mpv runtime copy."
fi

if [[ "$ENABLE_CODESIGN" == "1" && -n "$APP_SIGN_IDENTITY" ]]; then
  echo "[2/4] Re-signing app with identity: $APP_SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_PATH"
fi

echo "[3/4] Creating DMG..."
mkdir -p "$OUTPUT_DIR"
STAGE_DIR="$(mktemp -d "$PROJECT_ROOT/.dmg_stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_PATH="$OUTPUT_DIR/$DMG_NAME.dmg"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$ENABLE_CODESIGN" == "1" && -n "$DMG_SIGN_IDENTITY" ]]; then
  echo "[4/4] Signing DMG with identity: $DMG_SIGN_IDENTITY"
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
else
  echo "[4/4] Skipping DMG codesign."
fi

echo "DONE: $DMG_PATH"
