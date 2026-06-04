#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# remove-converted-originals.sh - Remove originals after verifying converted files exist
# Safe cleanup step after convert-media-format.sh (only deletes if .jpg/.mp4 exists)
# No external dependencies required.
# =============================================================================

# --- Defaults ---
SOURCE_PATH="."
EXTENSIONS=("webp" "jfif" "heic" "heif" "bmp" "3gp" "mov" "avi")
DRY_RUN=false

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Removes original media files ONLY if a matching converted file (.jpg or .mp4)
exists in the same directory and is non-empty.

Use this after convert-media-format.sh if you didn't use -RemoveOriginal.

Options:
  -source <path>       Directory to scan (default: current directory)
  -extensions <list>   Comma-separated extensions to check (default: webp,jfif,heic,heif,bmp,3gp,mov,avi)
  -DryRun              Preview deletions without removing files
  -h, --help           Show this help message

Example:
  $(basename "$0") -source ~/Pictures -DryRun
  $(basename "$0") -source ~/Pictures
EOF
    exit 1
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -source) SOURCE_PATH="$2"; shift 2 ;;
        -extensions) IFS=',' read -ra EXTENSIONS <<< "$2"; shift 2 ;;
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
echo "Scanning for converted originals to clean up in $SOURCE_PATH..."

photo_extensions=("webp" "jfif" "heic" "heif" "bmp")

# Build find pattern
find_args=()
for ext in "${EXTENSIONS[@]}"; do
    ext="${ext,,}"
    ext="${ext#.}"
    find_args+=(-iname "*.$ext" -o)
done
unset 'find_args[${#find_args[@]}-1]'

mapfile -t files < <(find "$SOURCE_PATH" -type f \( "${find_args[@]}" \) | sort)
total_found=${#files[@]}

if [[ $total_found -eq 0 ]]; then
    echo "No legacy files found matching: ${EXTENSIONS[*]}"
    exit 0
fi

is_photo() {
    local ext="${1,,}"
    ext="${ext#.}"
    for pe in "${photo_extensions[@]}"; do
        [[ "$ext" == "$pe" ]] && return 0
    done
    return 1
}

deleted_count=0
skipped_count=0
error_count=0

for filepath in "${files[@]}"; do
    filename="$(basename "$filepath")"
    dir="$(dirname "$filepath")"
    base="${filename%.*}"
    ext="${filename##*.}"

    if is_photo "$ext"; then
        target_ext="jpg"
    else
        target_ext="mp4"
    fi

    target_path="$dir/${base}.${target_ext}"
    target_label="${target_ext^^}"

    if [[ -f "$target_path" ]]; then
        # Verify converted file is non-empty
        if [[ ! -s "$target_path" ]]; then
            echo "Skipping: $filename - converted file exists but is 0 bytes"
            ((skipped_count++))
            continue
        fi

        echo "Found $target_label for: $filename - Safe to delete."

        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY RUN] Would delete $filepath"
            ((deleted_count++))
        else
            if rm -f "$filepath" 2>/dev/null; then
                ((deleted_count++))
            else
                echo "  Error deleting file: $filepath"
                ((error_count++))
            fi
        fi
    else
        echo "No $target_label found for: $filename - Skipping."
        ((skipped_count++))
    fi
done

echo ""
echo "--- Summary ---"
echo "Originals found: $total_found"
echo "Deleted:         $deleted_count"
echo "Skipped:         $skipped_count"
echo "Errors:          $error_count"
if [[ "$DRY_RUN" == true ]]; then
    echo "(Dry run - no files were actually deleted)"
fi
