#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENTITLEMENTS="$REPO_ROOT/SnapTra Translator/Snap Translate.entitlements"

# ─── Resolve signing identity ───
resolve_identity() {
    echo "==> Available signing identities:"
    security find-identity -v -p codesigning
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "ERROR: No Developer ID Application certificate found in keychain"
        exit 1
    fi
    echo "==> Using identity: $SIGNING_IDENTITY"
}

# ─── Command: sign ───
# Signs the .app bundle (must run BEFORE creating DMG)
cmd_sign() {
    local APP_DIR="${1:?Usage: $0 sign <path-to-app>}"
    local bundle_id
    local expanded_entitlements=""
    resolve_identity

    # Sign embedded frameworks first (inside-out order)
    if [ -d "$APP_DIR/Contents/Frameworks" ]; then
        for framework in "$APP_DIR/Contents/Frameworks"/*.framework; do
            if [ -d "$framework" ]; then
                echo "==> Signing embedded framework: $(basename "$framework")"
                # Preserve nested helper signatures inside frameworks such as Sparkle.
                codesign --force --options runtime \
                    --sign "$SIGNING_IDENTITY" \
                    --timestamp \
                    "$framework"
            fi
        done
    fi

    # Sign the main app bundle
    echo "==> Signing main app bundle"
    if [ -f "$ENTITLEMENTS" ]; then
        bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_DIR/Contents/Info.plist")
        expanded_entitlements="$(mktemp /tmp/snaptra-entitlements.XXXXXX)"
        sed "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$bundle_id|g" "$ENTITLEMENTS" > "$expanded_entitlements"

        codesign --force --options runtime \
            --entitlements "$expanded_entitlements" \
            --sign "$SIGNING_IDENTITY" \
            --timestamp \
            "$APP_DIR"

        rm -f "$expanded_entitlements"
    else
        echo "Warning: Entitlements file not found at $ENTITLEMENTS, signing without entitlements"
        codesign --force --options runtime \
            --sign "$SIGNING_IDENTITY" \
            --timestamp \
            "$APP_DIR"
    fi

    # Verify
    echo "==> Verifying signature..."
    codesign --verify --verbose=2 "$APP_DIR"
    echo "==> App bundle signed successfully"
}

# ─── Command: notarize ───
# Signs the DMG, submits for notarization, and staples the ticket
cmd_notarize() {
    local DMG_PATH="${1:?Usage: $0 notarize <path-to-dmg>}"

    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
    : "${APPLE_ID:?APPLE_ID is required}"
    : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

    resolve_identity

    # Sign the DMG
    echo "==> Signing DMG"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

    # Submit for notarization
    echo "==> Submitting for notarization (this may take several minutes)..."
    NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout 30m 2>&1) || true

    echo "$NOTARY_OUTPUT"

    # Extract submission ID and check status
    SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    NOTARY_STATUS=$(echo "$NOTARY_OUTPUT" | grep "status:" | tail -1 | awk '{print $2}')

    if [ "$NOTARY_STATUS" != "Accepted" ]; then
        echo "==> Notarization failed with status: $NOTARY_STATUS"
        if [ -n "$SUBMISSION_ID" ]; then
            echo "==> Fetching notarization log for submission: $SUBMISSION_ID"
            xcrun notarytool log "$SUBMISSION_ID" \
                --apple-id "$APPLE_ID" \
                --password "$APPLE_APP_PASSWORD" \
                --team-id "$APPLE_TEAM_ID" || true
        fi
        exit 1
    fi

    # Staple notarization ticket
    echo "==> Stapling notarization ticket to DMG"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    echo "==> Notarization complete!"
}

# ─── Dispatch ───
COMMAND="${1:?Usage: $0 <sign|notarize> <path>}"
shift
case "$COMMAND" in
    sign)     cmd_sign "$@" ;;
    notarize) cmd_notarize "$@" ;;
    *)        echo "Unknown command: $COMMAND"; exit 1 ;;
esac
