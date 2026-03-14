#!/usr/bin/env bash

normalize_release_version() {
    local version="$1"
    echo "${version#v}"
}

is_prerelease_version() {
    local version
    version="$(normalize_release_version "$1")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-(alpha|beta|rc)(\.?[0-9]+)?$ ]]
}

compute_sparkle_version() {
    local version
    local base_version
    local prerelease_type
    local prerelease_num
    local offset

    version="$(normalize_release_version "$1")"

    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-(alpha|beta|rc)(\.?([0-9]+))?$ ]]; then
        base_version="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        prerelease_type="${BASH_REMATCH[4]}"
        prerelease_num="${BASH_REMATCH[6]:-0}"

        case "$prerelease_type" in
        alpha) offset=0 ;;
        beta) offset=0 ;;
        rc) offset=90 ;;
        *)
            echo "Unsupported prerelease type: $prerelease_type" >&2
            return 1
            ;;
        esac

        printf "%s%02d\n" "$base_version" $((offset + prerelease_num))
        return 0
    fi

    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        printf "%s%s%s99\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi

    echo "Unsupported release version format: $version" >&2
    return 1
}

appcast_file_for_version() {
    if is_prerelease_version "$1"; then
        echo "docs/appcast-beta.xml"
    else
        echo "docs/appcast.xml"
    fi
}
