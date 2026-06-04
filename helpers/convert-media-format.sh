#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# convert-media-format.sh - Convert legacy media formats to JPG/MP4 using ffmpeg
# Videos already in H.264/H.265 are remuxed (fast, lossless) instead of re-encoded.
# Requires: ffmpeg, ffprobe (optional, for smart remuxing)
# =============================================================================

# --- Defaults ---
SOURCE_PATH="."
EXTENSIONS=("webp" "jfif" "heic" "heif" "bmp" "3gp" "mov" "avi")
REMOVE_ORIGINAL=false
DRY_RUN=false

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Converts legacy media files to standardized formats:
  Photos (.webp, .jfif, .heic, .heif, .bmp) -> .jpg
  Videos (.3gp, .mov, .avi) -> .mp4

Videos already encoded in H.264/H.265 are remuxed without re-encoding.

Options:
  -source <path>       Directory to scan (default: current directory)
  -extensions <list>   Comma-separated extensions to convert (default: webp,jfif,heic,heif,bmp,3gp,mov,avi)
  -RemoveOriginal      Delete originals after successful conversion
  -DryRun              Preview conversions without executing
  -h, --help           Show this help message

Requires: ffmpeg (install via 'brew install ffmpeg' or 'apt install ffmpeg')

Example:
  $(basename "$0") -source ~/Pictures -DryRun
  $(basename "$0") -source ~/Pictures -RemoveOriginal
  $(basename "$0") -source ~/Pictures -extensions "heic,webp"
EOF
    exit 1
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -source) SOURCE_PATH="$2"; shift 2 ;;
        -extensions) IFS=',' read -ra EXTENSIONS <<< "$2"; shift 2 ;;
        -RemoveOriginal|-removeoriginal|--remove-original) REMOVE_ORIGINAL=true; shift ;;
        -DryRun|-dryrun|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

# --- Dependency Check ---
if ! command -v ffmpeg &>/dev/null; then
    echo "ERROR: ffmpeg is required but not installed."
    echo ""
    echo "Install it with:"
    echo "  macOS:  brew install ffmpeg"
    echo "  Ubuntu: sudo apt install ffmpeg"
    echo "  Fedora: sudo dnf install ffmpeg"
    echo "  Arch:   sudo pacman -S ffmpeg"
    exit 1
fi

has_ffprobe=false
if command -v ffprobe &>/dev/null; then
    has_ffprobe=true
else
    echo "WARNING: ffprobe not found. Video codec detection disabled — all videos will be re-encoded."
    echo "         Install ffprobe (usually bundled with ffmpeg) to enable smart remuxing."
    echo ""
fi

# Check HEIC support
needs_heic=false
for ext in "${EXTENSIONS[@]}"; do
    if [[ "${ext,,}" == "heic" || "${ext,,}" == "heif" ]]; then
        needs_heic=true
        break
    fi
done

if [[ "$needs_heic" == true ]]; then
    decoders="$(ffmpeg -decoders 2>&1 || true)"
    if ! echo "$decoders" | grep -qi 'hevc\|libheif'; then
        echo "WARNING: Your ffmpeg build may not support HEIC/HEIF decoding."
        echo "         HEIC files may fail. Consider installing a build with libheif support."
        echo ""
    fi
fi

if [[ ! -d "$SOURCE_PATH" ]]; then
    echo "ERROR: Directory '$SOURCE_PATH' does not exist."
    exit 1
fi

SOURCE_PATH="$(cd "$SOURCE_PATH" && pwd)"

# Photo extensions (everything else is video)
photo_extensions=("webp" "jfif" "heic" "heif" "bmp")
remuxable_codecs=("h264" "hevc" "h265")

# Build find pattern
find_args=()
for ext in "${EXTENSIONS[@]}"; do
    ext="${ext,,}"  # lowercase
    ext="${ext#.}"  # strip leading dot if present
    find_args+=(-iname "*.$ext" -o)
done
# Remove trailing -o
unset 'find_args[${#find_args[@]}-1]'

# Find files
mapfile -t files < <(find "$SOURCE_PATH" -type f \( "${find_args[@]}" \) | sort)
total=${#files[@]}

if [[ $total -eq 0 ]]; then
    echo "No files found matching: ${EXTENSIONS[*]}"
    exit 0
fi

echo "Found $total media files to convert in $SOURCE_PATH."

success_count=0
remux_count=0
error_count=0

is_photo() {
    local ext="${1,,}"
    ext="${ext#.}"
    for pe in "${photo_extensions[@]}"; do
        [[ "$ext" == "$pe" ]] && return 0
    done
    return 1
}

for ((i=0; i<total; i++)); do
    filepath="${files[$i]}"
    filename="$(basename "$filepath")"
    dir="$(dirname "$filepath")"
    base="${filename%.*}"
    ext="${filename##*.}"

    if is_photo "$ext"; then
        target_ext="jpg"
    else
        target_ext="mp4"
    fi

    output_file="$dir/${base}.${target_ext}"

    # Handle filename conflicts
    if [[ -e "$output_file" ]]; then
        n=1
        while [[ -e "$dir/${base}_${n}.${target_ext}" ]]; do
            ((n++))
        done
        output_file="$dir/${base}_${n}.${target_ext}"
    fi

    # Determine conversion mode
    mode="convert"
    if is_photo "$ext"; then
        ffmpeg_args=(-v error -n -i "$filepath" -map_metadata 0 -q:v 2 "$output_file")
    else
        # Probe video codec if ffprobe available
        video_codec=""
        if [[ "$has_ffprobe" == true ]]; then
            video_codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$filepath" 2>/dev/null || true)"
            video_codec="${video_codec,,}"  # lowercase
            video_codec="$(echo "$video_codec" | tr -d '[:space:]')"
        fi

        is_remuxable=false
        for codec in "${remuxable_codecs[@]}"; do
            if [[ "$video_codec" == "$codec" ]]; then
                is_remuxable=true
                break
            fi
        done

        if [[ "$is_remuxable" == true ]]; then
            # Remux: copy video, re-encode audio to AAC for MP4 compatibility
            ffmpeg_args=(-v error -n -i "$filepath" -map_metadata 0 -c:v copy -c:a aac "$output_file")
            mode="remux"
        else
            # Full re-encode to H.264 + AAC
            ffmpeg_args=(-v error -n -i "$filepath" -map_metadata 0 -c:v libx264 -crf 23 -c:a aac -pix_fmt yuv420p "$output_file")
        fi
    fi

    mode_label="Converting"
    [[ "$mode" == "remux" ]] && mode_label="Remuxing"
    echo "[$((i+1))/$total] $mode_label: $filename -> $(basename "$output_file")"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] ffmpeg ${ffmpeg_args[*]}"
        ((success_count++))
        [[ "$mode" == "remux" ]] && ((remux_count++))
        continue
    fi

    # Execute conversion
    if ffmpeg "${ffmpeg_args[@]}" 2>&1 | while IFS= read -r line; do :; done; then
        # Verify output
        if [[ -f "$output_file" && -s "$output_file" ]]; then
            echo "  Success!"
            ((success_count++))
            [[ "$mode" == "remux" ]] && ((remux_count++))

            if [[ "$REMOVE_ORIGINAL" == true ]]; then
                echo "  Deleting original..."
                rm -f "$filepath"
            fi
        else
            echo "  Error: Output file is empty or missing."
            rm -f "$output_file" 2>/dev/null || true
            ((error_count++))
        fi
    else
        echo "  Error: ffmpeg failed to convert this file."
        ((error_count++))
    fi
done

echo ""
echo "--- Summary ---"
echo "Processed: $total"
echo "Success:   $success_count"
if [[ $remux_count -gt 0 ]]; then
    echo "  (of which $remux_count remuxed without re-encoding)"
fi
echo "Errors:    $error_count"
if [[ "$REMOVE_ORIGINAL" == false ]]; then
    echo "Originals kept. Use -RemoveOriginal to delete after conversion."
fi
if [[ "$DRY_RUN" == true ]]; then
    echo "(Dry run - no files were actually converted)"
fi
