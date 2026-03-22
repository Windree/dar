#!/usr/bin/env bash
set -Eeuo pipefail

function create() {
    local source="/source"
    local target="/data"
    local temp="$target/$1"
    shift
    
    mkdir -p "$temp"
    
    local last_dar=$(find "$target" -maxdepth 1 -type f -name "*.*.dar" -printf '%T@\t%p\n' | sort -n | tail -1 | cut -f2-)
    
    if [ -z "$last_dar" ]; then
        local name="full"
        echo "Creating an archive: '$name'"
        if ! dar --create "$temp/$name" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null; then
            echo "Failed to create an archive: '$name'"
            exit 1
        fi
    else
        local last_ref="${last_dar%.*.*}"
        local name="incremental-$(date +%Y%m%d-%H%M%S)"
        echo "Creating an incremental archive '$name' based on '$last_ref'."
        if ! dar --create "$temp/$name" --ref "$last_ref" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null; then
            echo "Failed to create an incremental archive"
            exit 1
        fi
    fi
    
    local size=$(du --total --bytes "$temp" | tail -n 1 | cut -f 1)
    local count=$(find "$temp" -type f | wc -l)
    echo "Size: $size bytes."
    echo "Files: $count."
}

function verify() {
    local data="/data"
    local index=0
    local total=$(get_archives "$data" | wc -l)
    
    if [ $total -eq 0 ]; then
        echo "Failed to find files to verify!"
        exit 2
    fi

    while IFS="" read -r archive_basename || [ -n "$archive_basename" ]; do
        index=$((index + 1))
        
        echo "[$index/$total] Verification of the file: $archive_basename"
        if ! dar --test "$data/$archive_basename" -Q --quiet "$@"; then
            echo "[$index/$total] The file verification failed: '$archive_basename'!"
            exit 1
        fi
    done < <(get_archives "$data")
}

function extract() {
    local data="/data"
    local target="/target"
    local archives="$(get_archives "$data")"
    local count=$(get_archives "$data" | wc -l)
    local index=0
    
    while IFS="" read -r archive_basename || [ -n "$archive_basename" ]; do
        index=$((index + 1))
        echo "[$index/$count] Restoring an archive: '$archive_basename'"
        if ! dar -x "$data/$archive_basename" "$@" --fs-root="$target" -Q --quiet -w -ae; then
            echo "[$index/$count] Failed restore: '$archive_basename'"
            exit 1
        fi
    done < <(get_archives "$data")
}

function get_archives() {
    find "$1" -maxdepth 1 -type f -name "*.*.dar" | grep -oP '[^/]+(?=\.\d+\.dar)' | sort | uniq
}

if [ $# -lt 1 ]; then
    echo "Usage: $0 {create|extract|verify} [args]"
    exit 1
fi

action=$1
shift
case "$action" in
    "create") create "$@" ;;
    "extract") extract "$@" ;;
    "verify") verify "$@" ;;

    *)
        echo "Unsupported action '$action'"
        exit 1
        ;;
esac