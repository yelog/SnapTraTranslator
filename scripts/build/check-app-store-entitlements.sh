#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/build/check-app-store-entitlements.sh <path-to-app>

Checks the signed App Store app for the sandbox entitlements required by SnapTra.
USAGE
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" || "$APP_PATH" != *.app ]]; then
    echo "ERROR: Input must be an existing .app bundle: $APP_PATH" >&2
    exit 2
fi

if ! ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)"; then
    echo "ERROR: Unable to read signed entitlements from: $APP_PATH" >&2
    exit 2
fi

entitlement_value() {
    local key="$1"
    local key_path="${key//./\\.}"
    printf '%s' "$ENTITLEMENTS" | plutil -extract "$key_path" raw -o - - 2>/dev/null || true
}

require_true_entitlement() {
    local key="$1"
    local value
    value="$(entitlement_value "$key")"

    if [ "$value" != "true" ]; then
        echo "ERROR: Required entitlement is missing or disabled: $key" >&2
        exit 1
    fi
}

require_true_entitlement "com.apple.security.app-sandbox"
require_true_entitlement "com.apple.security.network.client"
require_true_entitlement "com.apple.security.files.user-selected.read-write"

if [ "$(entitlement_value "com.apple.security.files.user-selected.read-only")" = "true" ]; then
    echo "ERROR: Read-only user-selected file entitlement must not replace read/write access." >&2
    exit 1
fi

echo "App Store sandbox entitlements are valid."
