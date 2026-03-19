#!/bin/bash
set -euo pipefail

# Build GregMiner.app with bundled gregcoind and create a DMG
# Usage: ./scripts/build-dmg.sh [--skip-gregcoind] [--output DIR] [--gregcoind-bin PATH]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/dist"
APP_NAME="GregMiner"
BUNDLE_ID="com.gregcoin.gregminer"
VERSION="2.0.0"
SKIP_GREGCOIND=false
GREGCOIND_BIN=""
GREGCOIN_REPO="https://github.com/chartractegg/gregcoin.git"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --skip-gregcoind) SKIP_GREGCOIND=true; shift ;;
        --gregcoind-bin) GREGCOIND_BIN="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# ── Step 1: Build gregcoind from source ─────────────────────────────────────
GREGCOIND_FINAL=""

if [[ -n "$GREGCOIND_BIN" ]]; then
    echo "==> Using provided gregcoind binary: $GREGCOIND_BIN"
    GREGCOIND_FINAL="$GREGCOIND_BIN"
elif [[ "$SKIP_GREGCOIND" == true ]]; then
    echo "==> Skipping gregcoind build (--skip-gregcoind)"
else
    GREGCOIN_BUILD_DIR="${OUTPUT_DIR}/gregcoin-build"
    echo "==> Building gregcoind from source..."

    if [[ -d "$GREGCOIN_BUILD_DIR" ]]; then
        echo "    Updating existing clone..."
        cd "$GREGCOIN_BUILD_DIR"
        git pull --ff-only || true
    else
        echo "    Cloning ${GREGCOIN_REPO}..."
        git clone --depth 1 "$GREGCOIN_REPO" "$GREGCOIN_BUILD_DIR"
    fi

    cd "$GREGCOIN_BUILD_DIR"

    # Install build dependencies if needed (macOS)
    if ! command -v cmake &>/dev/null; then
        echo "    Installing cmake via Homebrew..."
        brew install cmake
    fi

    # Check for required deps — install common ones
    for dep in automake libtool boost libevent; do
        if ! brew list "$dep" &>/dev/null; then
            echo "    Installing $dep..."
            brew install "$dep"
        fi
    done

    echo "    Running cmake..."
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DWITH_ZMQ=OFF \
        -DWITH_MINIUPNPC=OFF \
        2>&1 | tail -5

    echo "    Compiling (this may take a few minutes)..."
    cmake --build build -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -5

    # Find the gregcoind binary
    if [[ -f "build/bin/gregcoind" ]]; then
        GREGCOIND_FINAL="build/bin/gregcoind"
    elif [[ -f "build/src/gregcoind" ]]; then
        GREGCOIND_FINAL="build/src/gregcoind"
    else
        GREGCOIND_FINAL="$(find build -name 'gregcoind' -type f | head -1)"
    fi

    if [[ -z "$GREGCOIND_FINAL" || ! -f "$GREGCOIND_FINAL" ]]; then
        echo "ERROR: gregcoind binary not found after build"
        echo "       Build directory contents:"
        find build -name 'gregcoin*' -type f 2>/dev/null || true
        exit 1
    fi

    GREGCOIND_FINAL="$(cd "$(dirname "$GREGCOIND_FINAL")" && pwd)/$(basename "$GREGCOIND_FINAL")"
    echo "    Built: $GREGCOIND_FINAL"
    echo "    Size:  $(du -h "$GREGCOIND_FINAL" | cut -f1)"
fi

cd "$PROJECT_DIR"

# ── Step 2: Build GregMiner (Swift) ─────────────────────────────────────────
echo "==> Building ${APP_NAME} (release)..."
swift build -c release 2>&1 | tail -3

BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "    Binary: $BINARY"

# ── Step 3: Create .app bundle ──────────────────────────────────────────────
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
echo "==> Creating ${APP_NAME}.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy GregMiner binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Bundle gregcoind inside Resources
if [[ -n "$GREGCOIND_FINAL" && -f "$GREGCOIND_FINAL" ]]; then
    cp "$GREGCOIND_FINAL" "$APP_DIR/Contents/Resources/gregcoind"
    chmod +x "$APP_DIR/Contents/Resources/gregcoind"
    echo "    Bundled gregcoind ($(du -h "$APP_DIR/Contents/Resources/gregcoind" | cut -f1))"
else
    echo "    WARNING: No gregcoind binary bundled — app will need manual configuration"
fi

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Copy icon if available
ICON_SRC="${PROJECT_DIR}/../build/icon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "    Icon copied"
fi

echo "    App bundle: $APP_DIR"
echo "    Total size: $(du -sh "$APP_DIR" | cut -f1)"

# ── Step 4: Create DMG ──────────────────────────────────────────────────────
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}-macOS.dmg"
echo "==> Creating DMG..."
rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "${APP_NAME}" \
        --volicon "$APP_DIR/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 175 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$APP_DIR" \
    || {
        echo "    create-dmg failed, falling back to hdiutil..."
        hdiutil create -volname "${APP_NAME}" \
            -srcfolder "$APP_DIR" \
            -ov -format UDZO \
            "$DMG_PATH"
    }
else
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$APP_DIR" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "==> Done!"
echo "    App:  $APP_DIR"
echo "    DMG:  $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
