#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# repair-file-extension.sh - Fix corrupted/mangled file extensions
# Removes OS copy-suffixes, duplicate extensions, and normalizes variants.
# No external dependencies required.
# =============================================================================

# --- Defaults ---
SOURCE_PATH="."
DRY_RUN=false

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Repairs common file extension issues:
  - Removes OS copy-suffixes appended after the extension
    (e.g., "photo.jpg - Copy" -> "photo.jpg", "video.mp4 (1)" -> "video.mp4")
  - Removes duplicate extensions (e.g., "photo.jpg.jpg" -> "photo.jpg")
  - Normalizes variants (.jpeg -> .jpg, .tiff -> .tif, .mpeg -> .mpg)

Options:
  -source <path>    Directory to scan (default: current directory)
  -DryRun           Preview changes without renaming
  -h, --help        Show this help message

Example:
  $(basename "$0") -source ~/Pictures -DryRun
EOF
    exit 1
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -source) SOURCE_PATH="$2"; shift 2 ;;
        -DryRun|-dryrun|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

if [[ ! -d "$SOURCE_PATH" ]]; then
    echo "ERROR: Directory '$SOURCE_PATH' does not exist."
    exit 1
fi

SOURCE_PATH="$(cd "$SOURCE_PATH" && pwd)"
echo "Scanning for extension issues in $SOURCE_PATH..."

# Known media extensions
known_extensions="jpg|jpeg|png|gif|bmp|webp|heic|heif|tif|tiff|raw|cr2|cr3|nef|arw|dng|mp4|mov|avi|mkv|wmv|flv|3gp|m4v|mpg|mpeg|mts|m2ts|webm"

# Extension normalization
normalize_ext() {
    case "$1" in
        .jpeg) echo ".jpg" ;;
        .tiff) echo ".tif" ;;
        .mpeg) echo ".mpg" ;;
        *) echo "" ;;
    esac
}

success_count=0
error_count=0
total_checked=0

while IFS= read -r -d '' filepath; do
    ((total_checked++))
    filename="$(basename "$filepath")"
    dir="$(dirname "$filepath")"
    new_name="$filename"
    fix=""

    # --- Fix 1: Remove copy-suffix after extension ---
    # Match: known_ext + copy suffix (case insensitive for suffix keywords)
    if [[ "$new_name" =~ ^(.+\.($known_extensions))(\ *-\ *(Copy|Kopie|copie|copia)(\ *\([0-9]+\))?|\ *\([0-9]+\)|\ +[2-9][0-9]?)$ ]]; then
        new_name="${BASH_REMATCH[1]}"
        fix="Removed copy-suffix after extension"
    fi

    # --- Fix 2: Remove duplicate extension ---
    if [[ -z "$fix" ]]; then
        ext="${new_name##*.}"
        ext_lower="${ext,,}"
        base="${new_name%.*}"
        inner_ext="${base##*.}"
        inner_ext_lower="${inner_ext,,}"

        if [[ "$ext_lower" =~ ^($known_extensions)$ ]]; then
            if [[ "$inner_ext_lower" == "$ext_lower" ]]; then
                new_name="${base%.*}.$ext_lower"
                fix="Removed duplicate extension"
            elif [[ "$(normalize_ext ".$inner_ext_lower")" == ".$ext_lower" ]]; then
                new_name="${base%.*}.$ext_lower"
                fix="Removed duplicate extension (variant)"
            fi
        fi
    fi

    # --- Fix 3: Normalize extension variants ---
    if [[ -z "$fix" ]]; then
        ext="${new_name##*.}"
        ext_lower="${ext,,}"
        normalized="$(normalize_ext ".$ext_lower")"
        if [[ -n "$normalized" ]]; then
            base="${new_name%.*}"
            new_name="${base}${normalized}"
            fix="Normalized .$ext_lower -> $normalized"
        fi
    fi

    # Skip if nothing changed
    if [[ -z "$fix" || "$new_name" == "$filename" ]]; then
        continue
    fi

    new_path="$dir/$new_name"

    # Handle conflicts
    if [[ -e "$new_path" ]]; then
        base="${new_name%.*}"
        ext="${new_name##*.}"
        i=1
        while [[ -e "$dir/${base}_${i}.${ext}" ]]; do
            ((i++))
        done
        new_name="${base}_${i}.${ext}"
        new_path="$dir/$new_name"
    fi

    echo "Repairing: $filename -> $new_name"
    echo "  Fix: $fix"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would rename"
        ((success_count++))
        continue
    fi

    if mv "$filepath" "$new_path" 2>/dev/null; then
        ((success_count++))
    else
        echo "  Error: Failed to rename"
        ((error_count++))
    fi

done < <(find "$SOURCE_PATH" -type f -print0 | sort -z)

echo ""
echo "--- Summary ---"
echo "Scanned:  $total_checked files"
echo "Repaired: $success_count"
echo "Errors:   $error_count"
if [[ "$DRY_RUN" == true ]]; then
    echo "(Dry run - no files were actually renamed)"
fi
