#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 <output.trace> [duration]" >&2
    echo "Example: $0 /tmp/snaptra-lookup.trace 60s" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 64
fi

output=$1
duration=${2:-60s}

if [[ ! $output == *.trace ]]; then
    echo "Output path must end in .trace: $output" >&2
    exit 64
fi

if [[ ! $duration =~ ^[1-9][0-9]*(ms|s|m|h)$ ]]; then
    echo "Duration must use xctrace syntax such as 500ms, 60s, 2m, or 1h: $duration" >&2
    exit 64
fi

if [[ -e $output ]]; then
    echo "Output already exists; remove it or choose another path: $output" >&2
    exit 73
fi

if ! pgrep -x "SnapTra Translator" >/dev/null; then
    echo "SnapTra Translator is not running." >&2
    exit 69
fi

mkdir -p "$(dirname "$output")"

exec xcrun xctrace record \
    --template Logging \
    --instrument "Points of Interest" \
    --instrument os_signpost \
    --attach "SnapTra Translator" \
    --time-limit "$duration" \
    --output "$output"
