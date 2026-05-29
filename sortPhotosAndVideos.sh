#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# sortPhotosAndVideos.sh - Organize media files into date-based folders
# macOS/Linux equivalent of sortPhotosAndVideos.ps1
# Requires: exiftool
# =============================================================================

# --- Defaults ---
SOURCE=""
DEST=""
CONFIG=""
DRY_RUN=false

PRIORITY=(metadata filename filesystem)
METADATA_PROPERTIES=(DateTaken DateTimeOriginal MediaCreated MediaCreatedAlt RecordedDate ItemDate DateModified DateCreated)
FILE_ACTION="move"
DATE_FORMAT_UNIX="%Y/%Y-%m/%Y-%m-%d"
INCLUDE_EXTENSIONS=()
EXCLUDE_EXTENSIONS=()
CONFLICT_STRATEGY="rename"
CLEANUP_EMPTY_DIRS=true
LOG_FILE=""

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") -source <path> [options]

Options:
  -source <path>    Folder containing your media (required)
  -dest <path>      Where sorted files go (default: <source>/Sorted)
  -config <path>    Path to config file (default: config.ini next to script)
  -DryRun           Preview without moving files

Requires: exiftool (install via 'brew install exiftool' or 'apt install libimage-exiftool-perl')
EOF
    exit 1
}

# --- Dependency Check ---
check_dependencies() {
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
}

# --- Parse CLI Arguments ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -source) SOURCE="$2"; shift 2 ;;
            -dest) DEST="$2"; shift 2 ;;
            -config) CONFIG="$2"; shift 2 ;;
            -DryRun|-dryrun|--dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage ;;
            *) echo "Unknown argument: $1"; usage ;;
        esac
    done

    if [[ -z "$SOURCE" ]]; then
        echo "ERROR: -source is required."
        usage
    fi

    if [[ ! -d "$SOURCE" ]]; then
        echo "ERROR: Source directory '$SOURCE' does not exist."
        exit 1
    fi

    # Resolve to absolute path
    SOURCE="$(cd "$SOURCE" && pwd)"

    if [[ -z "$DEST" ]]; then
        DEST="$SOURCE/Sorted"
    fi

    if [[ -z "$CONFIG" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        CONFIG="$SCRIPT_DIR/config.ini"
    fi
}

# --- Parse Config File ---
parse_config() {
    if [[ ! -f "$CONFIG" ]]; then
        echo "No config file found at '$CONFIG'. Using defaults." >&2
        return
    fi

    local current_section=""
    local config_priority=()
    local config_metadata=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim whitespace
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        case "$current_section" in
            Priority)
                if [[ "$line" =~ ^(filename|metadata|filesystem)$ ]]; then
                    config_priority+=("$line")
                else
                    echo "WARNING: Unknown priority strategy '$line' in config." >&2
                fi
                ;;
            MetadataProperties)
                case "$line" in
                    DateTaken|DateTimeOriginal|MediaCreated|MediaCreatedAlt|RecordedDate|ItemDate|DateModified|DateCreated)
                        config_metadata+=("$line")
                        ;;
                    *)
                        echo "WARNING: Unknown metadata property '$line' in config." >&2
                        ;;
                esac
                ;;
            Options)
                if [[ "$line" =~ ^(.+)=(.*)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local val="${BASH_REMATCH[2]}"
                    # Trim
                    key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

                    case "$key" in
                        FileAction)
                            if [[ "$val" == "move" || "$val" == "copy" ]]; then
                                FILE_ACTION="$val"
                            else
                                echo "WARNING: Invalid FileAction '$val'. Available: move, copy" >&2
                            fi
                            ;;
                        DateFormatUnix)
                            [[ -n "$val" ]] && DATE_FORMAT_UNIX="$val"
                            ;;
                        IncludeExtensions)
                            if [[ -n "$val" && "$val" != "*" ]]; then
                                IFS=',' read -ra INCLUDE_EXTENSIONS <<< "$val"
                                INCLUDE_EXTENSIONS=("${INCLUDE_EXTENSIONS[@]// /}")
                            fi
                            ;;
                        ExcludeExtensions)
                            if [[ -n "$val" ]]; then
                                IFS=',' read -ra EXCLUDE_EXTENSIONS <<< "$val"
                                EXCLUDE_EXTENSIONS=("${EXCLUDE_EXTENSIONS[@]// /}")
                            fi
                            ;;
                        ConflictStrategy)
                            if [[ "$val" =~ ^(rename|skip|overwrite)$ ]]; then
                                CONFLICT_STRATEGY="$val"
                            else
                                echo "WARNING: Invalid ConflictStrategy '$val'. Available: rename, skip, overwrite" >&2
                            fi
                            ;;
                        CleanupEmptyDirs)
                            [[ "$val" == "true" ]] && CLEANUP_EMPTY_DIRS=true || CLEANUP_EMPTY_DIRS=false
                            ;;
                        LogFile)
                            LOG_FILE="$val"
                            ;;
                        DateFormat)
                            ;; # Windows-only, ignore silently
                        *)
                            echo "WARNING: Unknown option '$key' in config." >&2
                            ;;
                    esac
                fi
                ;;
        esac
    done < "$CONFIG"

    # Override defaults if config had entries
    if [[ ${#config_priority[@]} -gt 0 ]]; then
        PRIORITY=("${config_priority[@]}")
    fi
    if [[ ${#config_metadata[@]} -gt 0 ]]; then
        METADATA_PROPERTIES=("${config_metadata[@]}")
    fi
}

# --- Logging ---
write_log() {
    local action="$1" source_path="$2" dest_path="$3" strategy="$4"
    if [[ -n "$LOG_FILE" ]]; then
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        # Sanitize strategy (remove tabs/newlines)
        strategy="$(echo "$strategy" | tr '\t\n\r' '   ')"
        printf '%s\t%s\t%s\t%s\t%s\n' "$timestamp" "$action" "$source_path" "$dest_path" "$strategy" >> "$LOG_FILE"
    fi
}

init_log() {
    if [[ -n "$LOG_FILE" && ! -f "$LOG_FILE" ]]; then
        printf 'Timestamp\tAction\tSource\tDestination\tStrategy\n' > "$LOG_FILE"
    fi
}

# --- Date Extraction ---
# Map friendly names to exiftool tags
get_exiftool_tag() {
    case "$1" in
        DateTaken)         echo "DateTimeOriginal" ;;
        DateTimeOriginal)  echo "DateTimeOriginal" ;;
        MediaCreated)      echo "MediaCreateDate" ;;
        MediaCreatedAlt)   echo "CreateDate" ;;
        RecordedDate)      echo "TrackCreateDate" ;;
        ItemDate)          echo "CreateDate" ;;
        DateModified)      echo "ModifyDate" ;;
        DateCreated)       echo "FileCreateDate" ;;
        *)                 echo "" ;;
    esac
}

get_date_from_filename() {
    local basename="$1"
    # Match YYYYMMDD, YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD
    if [[ "$basename" =~ (^|[^0-9])(20[0-9]{2}|19[0-9]{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12][0-9]|3[01]) ]]; then
        local year="${BASH_REMATCH[2]}"
        local month="${BASH_REMATCH[3]}"
        local day="${BASH_REMATCH[4]}"
        # Validate date
        if date -d "$year-$month-$day" &>/dev/null 2>&1; then
            echo "$year-$month-$day"
            return 0
        elif date -j -f "%Y-%m-%d" "$year-$month-$day" &>/dev/null 2>&1; then
            # macOS date validation
            echo "$year-$month-$day"
            return 0
        fi
        # If date command fails, still return it (basic validation passed via regex)
        echo "$year-$month-$day"
        return 0
    fi
    return 1
}

get_date_from_metadata() {
    local filepath="$1"

    # Build exiftool tag list
    local tags=()
    for prop in "${METADATA_PROPERTIES[@]}"; do
        local tag
        tag="$(get_exiftool_tag "$prop")"
        [[ -n "$tag" ]] && tags+=("-$tag")
    done

    # Query exiftool for all relevant tags at once
    local exif_output
    exif_output="$(exiftool -s -s -s -d '%Y-%m-%d %H:%M:%S' "${tags[@]}" "$filepath" 2>/dev/null)"

    # Try each property in priority order
    for prop in "${METADATA_PROPERTIES[@]}"; do
        local tag
        tag="$(get_exiftool_tag "$prop")"
        [[ -z "$tag" ]] && continue

        local value
        value="$(exiftool -s -s -s -d '%Y-%m-%d' "-$tag" "$filepath" 2>/dev/null)"

        if [[ -n "$value" && "$value" != "0000:00:00" && "$value" != "0000-00-00" ]]; then
            echo "$value"
            return 0
        fi
    done
    return 1
}

get_date_from_filesystem() {
    local filepath="$1"
    # macOS uses -f with stat, Linux uses -c
    if stat -f '%Sm' -t '%Y-%m-%d' "$filepath" &>/dev/null 2>&1; then
        # macOS (BSD stat) - use birth time if available, else modification time
        local birth
        birth="$(stat -f '%SB' -t '%Y-%m-%d' "$filepath" 2>/dev/null)"
        if [[ -n "$birth" && "$birth" != "" ]]; then
            echo "$birth"
        else
            stat -f '%Sm' -t '%Y-%m-%d' "$filepath"
        fi
    else
        # Linux (GNU stat) - use birth time if available, else modification time
        local birth
        birth="$(stat -c '%w' "$filepath" 2>/dev/null)"
        if [[ -n "$birth" && "$birth" != "-" ]]; then
            echo "$birth" | cut -d' ' -f1
        else
            stat -c '%y' "$filepath" | cut -d' ' -f1
        fi
    fi
}

get_file_date() {
    local filepath="$1"
    local basename
    basename="$(basename "$filepath")"
    basename="${basename%.*}"

    for strategy in "${PRIORITY[@]}"; do
        local result=""
        case "$strategy" in
            filename)
                result="$(get_date_from_filename "$basename")" && { echo "$result|$strategy"; return 0; }
                ;;
            metadata)
                result="$(get_date_from_metadata "$filepath")" && { echo "$result|$strategy"; return 0; }
                ;;
            filesystem)
                result="$(get_date_from_filesystem "$filepath")" && { echo "$result|$strategy"; return 0; }
                ;;
            *)
                echo "WARNING: Unknown priority strategy: $strategy" >&2
                ;;
        esac
    done

    # Ultimate fallback
    echo "WARNING: All strategies failed for $(basename "$filepath"). Using filesystem date." >&2
    local fallback
    fallback="$(get_date_from_filesystem "$filepath")"
    echo "$fallback|filesystem (fallback)"
}

# --- Extension Filtering ---
should_process_file() {
    local filepath="$1"
    local ext="${filepath##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

    # Check include filter
    if [[ ${#INCLUDE_EXTENSIONS[@]} -gt 0 ]]; then
        local found=false
        for inc_ext in "${INCLUDE_EXTENSIONS[@]}"; do
            inc_ext="$(echo "$inc_ext" | tr '[:upper:]' '[:lower:]' | sed 's/^\.//')"
            [[ "$ext" == "$inc_ext" ]] && { found=true; break; }
        done
        [[ "$found" == false ]] && return 1
    fi

    # Check exclude filter
    if [[ ${#EXCLUDE_EXTENSIONS[@]} -gt 0 ]]; then
        for exc_ext in "${EXCLUDE_EXTENSIONS[@]}"; do
            exc_ext="$(echo "$exc_ext" | tr '[:upper:]' '[:lower:]' | sed 's/^\.//')"
            [[ "$ext" == "$exc_ext" ]] && return 1
        done
    fi

    return 0
}

# --- Format Date into Folder Path ---
format_date_path() {
    local date_str="$1"
    local year="${date_str:0:4}"
    local month="${date_str:5:2}"
    local day="${date_str:8:2}"

    # Use date command to format
    if date -d "$date_str" &>/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "$date_str" +"$DATE_FORMAT_UNIX"
    elif date -j -f "%Y-%m-%d" "$date_str" &>/dev/null 2>&1; then
        # BSD date (macOS)
        date -j -f "%Y-%m-%d" "$date_str" +"$DATE_FORMAT_UNIX"
    else
        # Fallback: manual substitution for basic formats
        echo "$DATE_FORMAT_UNIX" | sed \
            -e "s/%Y/$year/g" \
            -e "s/%m/$month/g" \
            -e "s/%d/$day/g"
    fi
}

# --- Resolve Conflict ---
resolve_conflict() {
    local dest_file="$1"
    local base="${dest_file%.*}"
    local ext="${dest_file##*.}"

    # If no extension (base == dest_file), handle it
    if [[ "$base" == "$dest_file" ]]; then
        ext=""
    fi

    case "$CONFLICT_STRATEGY" in
        skip)
            echo ""
            return 1
            ;;
        overwrite)
            echo "$dest_file"
            return 0
            ;;
        rename)
            local index=1
            local new_file
            while true; do
                if [[ -n "$ext" && "$base" != "$dest_file" ]]; then
                    new_file="${base}_${index}.${ext}"
                else
                    new_file="${dest_file}_${index}"
                fi
                [[ ! -e "$new_file" ]] && break
                ((index++))
            done
            echo "$new_file"
            return 0
            ;;
    esac
}

# =============================================================================
# --- Main Processing ---
# =============================================================================

check_dependencies
parse_args "$@"
parse_config
init_log

# Validate date format
if ! format_date_path "2024-01-15" &>/dev/null; then
    echo "ERROR: Invalid DateFormatUnix '$DATE_FORMAT_UNIX'."
    exit 1
fi

# Find files (exclude destination directory)
mapfile -t files < <(find "$SOURCE" -type f ! -path "$DEST/*" | sort)

total_files=${#files[@]}

if [[ $total_files -eq 0 ]]; then
    echo "No files found to process in '$SOURCE'."
    exit 0
fi

moved_count=0
skipped_count=0
error_count=0
processed_count=0

for filepath in "${files[@]}"; do
    ((processed_count++))

    # Extension filter
    if ! should_process_file "$filepath"; then
        continue
    fi

    filename="$(basename "$filepath")"
    echo "[$processed_count/$total_files] Processing $filename"

    # Get date
    date_output="$(get_file_date "$filepath")"
    file_date="${date_output%%|*}"
    date_strategy="${date_output##*|}"

    if [[ -z "$file_date" ]]; then
        echo "ERROR: Could not determine date for '$filepath'" >&2
        write_log "ERROR" "$filepath" "" "no date found"
        ((error_count++))
        continue
    fi

    # Build destination path
    subfolder="$(format_date_path "$file_date")"
    dest_dir="$DEST/$subfolder"
    dest_file="$dest_dir/$filename"

    # Create destination directory
    if [[ "$DRY_RUN" == true ]]; then
        [[ ! -d "$dest_dir" ]] && echo "[DRY RUN] Would create directory: $dest_dir"
    else
        mkdir -p "$dest_dir"
    fi

    # Handle conflicts
    if [[ -e "$dest_file" ]]; then
        if [[ "$CONFLICT_STRATEGY" == "skip" ]]; then
            echo "Skipping (conflict): $filename already exists at destination"
            write_log "SKIP" "$filepath" "$dest_file" "$date_strategy"
            ((skipped_count++))
            continue
        fi
        resolved="$(resolve_conflict "$dest_file")"
        if [[ -n "$resolved" ]]; then
            dest_file="$resolved"
        fi
    fi

    # Skip if source and destination are the same
    if [[ "$(realpath "$filepath")" == "$(realpath "$dest_file" 2>/dev/null || echo "")" ]]; then
        echo "Skipping: Source and destination are identical"
        write_log "SKIP" "$filepath" "$dest_file" "$date_strategy"
        ((skipped_count++))
        continue
    fi

    # Perform action
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would $FILE_ACTION '$filepath' to '$dest_file'"
        write_log "DRYRUN" "$filepath" "$dest_file" "$date_strategy"
    else
        action_label="$(echo "$FILE_ACTION" | sed 's/./\U&/')"
        echo "${action_label}ing to $dest_file"
        if [[ "$FILE_ACTION" == "copy" ]]; then
            cp "$filepath" "$dest_file"
        else
            mv "$filepath" "$dest_file"
        fi
        write_log "${FILE_ACTION^^}" "$filepath" "$dest_file" "$date_strategy"
    fi
    ((moved_count++))
done

# --- Cleanup empty directories ---
if [[ "$DRY_RUN" == false && "$CLEANUP_EMPTY_DIRS" == true && "$FILE_ACTION" == "move" ]]; then
    find "$SOURCE" -type d -empty ! -path "$DEST/*" -delete 2>/dev/null || true
fi

# --- Summary ---
if [[ "$FILE_ACTION" == "copy" ]]; then
    action_label="Copied"
else
    action_label="Moved"
fi

echo ""
echo "--- Summary ---"
echo "Total files:  $total_files"
echo "$action_label:      $moved_count"
echo "Skipped:      $skipped_count"
echo "Errors:       $error_count"
if [[ "$DRY_RUN" == true ]]; then
    echo "(Dry run - no files were actually ${FILE_ACTION}d)"
fi
