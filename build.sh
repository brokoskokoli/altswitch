#!/usr/bin/env bash
set -euo pipefail

# Configuration
APP_NAME="AltSwitch"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODULE_CACHE="${TMPDIR:-/tmp}/AltSwitchModuleCache"
BUILD_DIR=".build/altswitch"

echo "=== Building ${APP_NAME} for macOS ==="

# 1. Clean previous build artifact
rm -rf "${BUNDLE_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${MODULE_CACHE}"
mkdir -p "${BUILD_DIR}"

# 2. Gather Swift source files
SOURCES=(
    Sources/AltSwitch/Models/*.swift
    Sources/AltSwitch/Services/*.swift
    Sources/AltSwitch/UI/*.swift
    Sources/AltSwitch/App/*.swift
)

# Universal binary (arm64 + x86_64) by default; ARCHS="arm64" builds only one slice.
read -r -a ARCHS <<< "${ARCHS:-arm64 x86_64}"
MIN_MACOS="13.0"
SLICES=()

for ARCH in "${ARCHS[@]}"; do
    echo "-> Compiling Swift sources for ${ARCH} with optimizations..."
    SLICE="${BUILD_DIR}/${APP_NAME}-${ARCH}"
    swiftc -O \
        -parse-as-library \
        -target "${ARCH}-apple-macos${MIN_MACOS}" \
        -module-cache-path "${MODULE_CACHE}" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework Carbon \
        -framework ServiceManagement \
        "${SOURCES[@]}" \
        -o "${SLICE}"
    SLICES+=("${SLICE}")
done

lipo -create "${SLICES[@]}" -output "${MACOS_DIR}/${APP_NAME}"
lipo -info "${MACOS_DIR}/${APP_NAME}"

chmod +x "${MACOS_DIR}/${APP_NAME}"

# 3. Copy Resources
echo "-> Packaging Info.plist and AppIcon..."
if [ -f "Resources/Info.plist" ]; then
    cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo "Warning: Resources/Info.plist not found!"
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4. Code Sign (Ad-Hoc, for local runs; releases are re-signed by tools/package_macos.sh)
echo "-> Applying ad-hoc code signature..."
codesign --force --sign - "${BUNDLE_NAME}"

# 5. Verify Bundle
echo "-> Verifying bundle integrity..."
codesign --verify --deep --strict "${BUNDLE_NAME}"

echo ""
echo "=== Successfully built ${BUNDLE_NAME} ==="
echo "App Bundle: $(pwd)/${BUNDLE_NAME}"
echo "Binary:     ${MACOS_DIR}/${APP_NAME}"
echo ""
echo "To run AltSwitch:"
echo "  open ${BUNDLE_NAME}"
echo "or run directly in background:"
echo "  ./${MACOS_DIR}/${APP_NAME} &"
