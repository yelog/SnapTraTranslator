#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="SnapTra Translator"
BUNDLE_ID="com.yelog.snaptra-translator"
SCHEME="SnapTra Translator"
PROJECT="$REPO_ROOT/SnapTra Translator.xcodeproj"

source "$SCRIPT_DIR/sparkle-release-utils.sh"

# Determine version from git tag, fallback to "0.0.0-dev"
VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")}"
VERSION="${VERSION#v}"  # strip leading 'v'

echo "==> Building $APP_NAME $VERSION"

# Step 1: Clean build directory
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Step 2: Build Release version
# Disable code signing during build - we'll sign with Developer ID after build
echo "==> Building with xcodebuild"
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DIST_DIR/DerivedData" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    clean build

# Step 3: Locate the built app
BUILD_DIR="$DIST_DIR/DerivedData/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Built app not found at $APP_PATH"
    exit 1
fi

echo "==> Built app found at $APP_PATH"

# Step 4: Inject GitHub release metadata before signing
if [ "${DISTRIBUTION_CHANNEL:-}" = "github" ]; then
    SPARKLE_VERSION="$(compute_sparkle_version "$VERSION")"
    echo "==> Setting Sparkle bundle version to $SPARKLE_VERSION for GitHub distribution"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SPARKLE_VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $SPARKLE_VERSION" "$APP_PATH/Contents/Info.plist"

    echo "==> Adding GitHub distribution marker to Info.plist"
    /usr/libexec/PlistBuddy -c "Add :DISTRIBUTION_CHANNEL string 'github'" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :DISTRIBUTION_CHANNEL 'github'" "$APP_PATH/Contents/Info.plist"

    echo "==> Validating Sparkle sandbox settings for GitHub distribution"
    SPARKLE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
    INSTALLER_LAUNCHER_ENABLED=$(/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)

    if [ -z "$SPARKLE_PUBLIC_KEY" ]; then
        echo "ERROR: SUPublicEDKey is missing from $APP_PATH/Contents/Info.plist"
        exit 1
    fi

    if [ "$INSTALLER_LAUNCHER_ENABLED" != "true" ]; then
        echo "ERROR: SUEnableInstallerLauncherService must be true for sandboxed GitHub builds"
        exit 1
    fi
fi

# Step 5: Code sign the .app bundle (CI only, must happen BEFORE creating DMG)
if [ "${CODESIGN_ENABLED:-}" = "1" ]; then
    echo "==> Running code signing on .app bundle..."
    bash "$SCRIPT_DIR/codesign-and-notarize.sh" sign "$APP_PATH"
else
    echo "==> Skipping code signing (set CODESIGN_ENABLED=1 to enable)"
fi

# Step 6: Package as .dmg (from the signed .app)
DMG_NAME="SnapTra-Translator-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_STAGING="$DIST_DIR/.dmg-staging"

rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Stage .app and /Applications symlink for drag-to-install
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating $DMG_NAME"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo "==> DMG created at: $DMG_PATH"

# Step 7: Sign DMG and notarize (CI only)
if [ "${CODESIGN_ENABLED:-}" = "1" ]; then
    echo "==> Signing DMG and submitting for notarization..."
    bash "$SCRIPT_DIR/codesign-and-notarize.sh" notarize "$DMG_PATH"
fi

# Step 8: Compute SHA-256 (must be after signing, since stapler modifies the DMG)
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$DIST_DIR/$DMG_NAME.sha256"
echo "==> SHA-256: $SHA256"

echo ""
echo "Done! Output:"
echo "  $DMG_PATH"
echo "  $DIST_DIR/$DMG_NAME.sha256"
