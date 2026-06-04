#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# set-media-timestamp.sh - Set filesystem timestamps from EXIF/metadata dates
# Fixes files where filesystem dates are wrong (after copying, unzipping, etc.)
# Requires: exiftool
# =============================================================================

# --- Defaults ---
SOURCE_PATH="."
DRY_RUN=false
INCLUDE_EXTENSIONS=("jpg" "jpeg" "png" "gif" "bmp" "webp" "heic" "heif" "tif" "tiff" "cr2" "cr3" "nef" "arw" "dng" "mp4" "mov" "avi" "mkv" "3gp" "m4v" "mts" "m2ts")

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Sets file system timestamps (modification time) from embedded EXIF/metadata dates.
Only updates files where the metadata date differs from the current filesystem date.

Options:
  -source <path>       Directory to scan (default: current directory)
  -extensions <list>   Comma-separated extensions to process (default: common media types)
  -DryRun              Preview changes without modifying timestamps
  -h, --help           Show this help message

Requires: exiftool (install via 'brew install exiftool' or 'apt install libimage-exiftool-perl')

Example:
  $(basename "$0") -source ~/Pictures -DryRun
  $(basename "$0") -source ~/Pictures/2024
EOF
    exit 1
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -source) SOURCE_PATH="$2"; shift 2 ;;
        -extensions) IFS=',' read -ra INCLUDE_EXTENSIONS <<< "$2"; shift 2 ;;
        -DryRun|-dryrun|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

# --- Dependency Check ---
if ! command -v exiftool &>/dev/null; then
    echo "ERROR: exiftool is required but not installed."
    echo ""
    echo "Install it with:"
    echo "  macOS:  brew install exiftool"
    echo "  Ubuntu: sudo apt install libimage-exiftool-perl"
    echo "  Fedora: sudo dnf install perl-Image-ExifTool"
    echo "  Arch:   sudo pacman -S perl-image-exiftool"
    exit 1
fi

if [[ ! -d "$SOURCE_PATH" ]]; then
    echo "ERROR: Directory '$SOURCE_PATH' does not exist."
    exit 1
fi

SOURCE_PATH="$(cd "$SOURCE_PATH" && pwd)"
echo "Scanning for media files in $SOURCE_PATH..."

# Metadata tags to try (in priority order)
metadata_tags=("DateTimeOriginal" "CreateDate" "MediaCreateDate" "TrackCreateDate" "ModifyDate")

# Build find pattern
find_args=()
for ext in "${INCLUDE_EXTENSIONS[@]}"; do
    ext="${ext,,}"
    ext="${ext#.}"
    find_args+=(-iname "*.$ext" -o)
done
unset 'find_args[${#find_args[@]}-1]'

mapfile -t files < <(find "$SOURCE_PATH" -type f \( "${find_args[@]}" \) | sort)
total=${#files[@]}

if [[ $total -eq 0 ]]; then
    echo "No media files found matching: ${INCLUDE_EXTENSIONS[*]}"
    exit 0
fi

echo "Found $total media files. Checking timestamps..."

updated_count=0
skipped_count=0
error_count=0

get_metadata_date() {
    local filepath="$1"
    for tag in "${metadata_tags[@]}"; do
        local value
        value="$(exiftool -s -s -s -d '%Y-%m-%d %H:%M:%S' "-$tag" "$filepath" 2>/dev/null || true)"
        if [[ -n "$value" && "$value" != "0000:00:00 00:00:00" && "$value" != "0000-00-00 00:00:00" ]]; then
            echo "$value"
            return 0
        fi
    done
    return 1
}

get_file_mtime() {
    local filepath="$1"
    # GNU stat
    if stat -c '%Y' "$filepath" &>/dev/null 2>&1; then
        stat -c '%y' "$filepath" | cut -d'.' -f1
    else
        # BSD stat (macOS)
        stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$filepath"
    fi
}

dates_match() {
    local meta_date="$1"
    local file_date="$2"

    # Compare just the date+time portion (ignore seconds differences up to 2s)
    local meta_epoch file_epoch

    # Try GNU date first, then BSD
    if date -d "$meta_date" '+%s' &>/dev/null 2>&1; then
        meta_epoch="$(date -d "$meta_date" '+%s')"
        file_epoch="$(date -d "$file_date" '+%s')"
    elif date -j -f '%Y-%m-%d %H:%M:%S' "$meta_date" '+%s' &>/dev/null 2>&1; then
        meta_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S' "$meta_date" '+%s')"
        file_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S' "$file_date" '+%s')"
    else
        # Fallback: string comparison (date portion only)
        [[ "${meta_date:0:16}" == "${file_date:0:16}" ]] && return 0 || return 1
    fi

    local diff=$(( meta_epoch - file_epoch ))
    [[ ${diff#-} -lt 2 ]] && return 0 || return 1
}

set_file_timestamp() {
    local filepath="$1"
    local datetime="$2"

    # Format for touch: YYYYMMDDhhmm.ss
    local touch_time
    if date -d "$datetime" '+%Y%m%d%H%M.%S' &>/dev/null 2>&1; then
        # GNU date
        touch_time="$(date -d "$datetime" '+%Y%m%d%H%M.%S')"
    elif date -j -f '%Y-%m-%d %H:%M:%S' "$datetime" '+%Y%m%d%H%M.%S' &>/dev/null 2>&1; then
        # BSD date
        touch_time="$(date -j -f '%Y-%m-%d %H:%M:%S' "$datetime" '+%Y%m%d%H%M.%S')"
    else
        return 1
    fi

    touch -t "$touch_time" "$filepath"
}

for ((i=0; i<total; i++)); do
    filepath="${files[$i]}"
    filename="$(basename "$filepath")"

    # Get metadata date
    meta_date="$(get_metadata_date "$filepath" 2>/dev/null)" || {
        ((skipped_count++))
        continue
    }

    # Get current filesystem modification time
    file_mtime="$(get_file_mtime "$filepath")"

    # Check if already matching
    if dates_match "$meta_date" "$file_mtime"; then
        ((skipped_count++))
        continue
    fi

    echo "[$((i+1))/$total] $filename"
    echo "  Metadata:  $meta_date"
    echo "  Modified:  $file_mtime -> $meta_date"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would update"
        ((updated_count++))
        continue
    fi

    if set_file_timestamp "$filepath" "$meta_date"; then
        ((updated_count++))
    else
        echo "  Error: Failed to set timestamp"
        ((error_count++))
    fi
done

echo ""
echo "--- Summary ---"
echo "Scanned:  $total"
echo "Updated:  $updated_count"
echo "Skipped:  $skipped_count (already correct or no metadata)"
echo "Errors:   $error_count"
if [[ "$DRY_RUN" == true ]]; then
    echo "(Dry run - no timestamps were actually changed)"
fi
