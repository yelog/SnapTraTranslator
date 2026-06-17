#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/build/check-app-store-symbols.sh <path-to-app-or-executable>

Checks the app executable for App Store-risk private Dictionary Services symbols.
USAGE
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

INPUT_PATH="$1"
EXECUTABLE_PATH="$INPUT_PATH"

if [ -d "$INPUT_PATH" ]; then
    if [[ "$INPUT_PATH" == *.app ]]; then
        INFO_PLIST="$INPUT_PATH/Contents/Info.plist"
        EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST")
        EXECUTABLE_PATH="$INPUT_PATH/Contents/MacOS/$EXECUTABLE_NAME"
    else
        echo "ERROR: Directory input must be a .app bundle: $INPUT_PATH" >&2
        exit 2
    fi
fi

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "ERROR: Executable not found: $EXECUTABLE_PATH" >&2
    exit 2
fi

FORBIDDEN_PATTERN='_(DCSCopyAvailableDictionaries|DCSDictionaryGetName|DCSCopyActiveDictionaries|DCSCopyRecordsWithHeadword|DCSDictionaryGetLanguages|DCSDictionaryGetParentDictionary)'
MATCHES="$(nm -u "$EXECUTABLE_PATH" | rg "$FORBIDDEN_PATTERN" || true)"

if [ -n "$MATCHES" ]; then
    echo "ERROR: App Store-risk private Dictionary Services symbols found in:" >&2
    echo "  $EXECUTABLE_PATH" >&2
    echo "$MATCHES" >&2
    exit 1
fi

echo "No App Store-risk private Dictionary Services symbols found."
