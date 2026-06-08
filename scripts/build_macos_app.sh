#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/MDC Sender.app"

mkdir -p "$BUILD_DIR"
(cd "$ROOT" && env GOCACHE="${GOCACHE:-/private/tmp/mdc-go-cache}" go build -o "$BUILD_DIR/mdc" ./cmd/mdc)

swift build --package-path "$ROOT" -c release --product MDCUI

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/MDCUI" "$APP/Contents/MacOS/MDCUI"
cp "$BUILD_DIR/mdc" "$APP/Contents/Resources/mdc"
cp "$ROOT/macos/MDCUI/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/MDCUI" "$APP/Contents/Resources/mdc"

echo "$APP"
