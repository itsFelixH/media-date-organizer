#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# analyzeMedia.sh - Analyze media files and generate a metadata report
# macOS/Linux equivalent of analyzeMedia.ps1
# Requires: exiftool
# =============================================================================

# --- Defaults ---
SOURCE=""
CONFIG=""

PRIORITY=(metadata filename filesystem)
METADATA_PROPERTIES=(DateTaken DateTimeOriginal MediaCreated MediaCreatedAlt RecordedDate ItemDate DateModified DateCreated)

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [-source <path>] [options]

Options:
  -source <path>    Folder containing files to analyze (default: examples/ next to script)
  -config <path>    Path to config file (default: config.ini next to script)

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
            -config) CONFIG="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) echo "Unknown argument: $1"; usage ;;
        esac
    done

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -z "$SOURCE" ]]; then
        SOURCE="$SCRIPT_DIR/examples"
    fi

    if [[ ! -d "$SOURCE" ]]; then
        echo "ERROR: Source directory '$SOURCE' does not exist."
        exit 1
    fi

    SOURCE="$(cd "$SOURCE" && pwd)"

    if [[ -z "$CONFIG" ]]; then
        CONFIG="$SCRIPT_DIR/config.ini"
    fi
}

# --- Parse Config File ---
parse_config() {
    if [[ ! -f "$CONFIG" ]]; then
        echo "No config file found at '$CONFIG'. Using defaults." >&2
        return
    fi

    echo "Loading configuration from: $CONFIG"

    local current_section=""
    local config_priority=()
    local config_metadata=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" || "$line" == \#* ]] && continue

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
        esac
    done < "$CONFIG"

    if [[ ${#config_priority[@]} -gt 0 ]]; then
        PRIORITY=("${config_priority[@]}")
    fi
    if [[ ${#config_metadata[@]} -gt 0 ]]; then
        METADATA_PROPERTIES=("${config_metadata[@]}")
    fi
}

# --- Exiftool Tag Mapping ---
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

# --- Date Extraction ---
get_date_from_filename() {
    local basename="$1"
    if [[ "$basename" =~ (^|[^0-9])(20[0-9]{2}|19[0-9]{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12][0-9]|3[01]) ]]; then
        echo "${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[4]}"
        return 0
    fi
    return 1
}

get_date_from_metadata() {
    local filepath="$1"
    for prop in "${METADATA_PROPERTIES[@]}"; do
        local tag
        tag="$(get_exiftool_tag "$prop")"
        [[ -z "$tag" ]] && continue

        local value
        value="$(exiftool -s -s -s -d '%Y-%m-%d' "-$tag" "$filepath" 2>/dev/null)"

        if [[ -n "$value" && "$value" != "0000:00:00" && "$value" != "0000-00-00" ]]; then
            echo "$value (exif:$tag)"
            return 0
        fi
    done
    return 1
}

get_date_from_filesystem() {
    local filepath="$1"
    if stat -f '%Sm' -t '%Y-%m-%d' "$filepath" &>/dev/null 2>&1; then
        local birth
        birth="$(stat -f '%SB' -t '%Y-%m-%d' "$filepath" 2>/dev/null)"
        if [[ -n "$birth" ]]; then
            echo "$birth"
        else
            stat -f '%Sm' -t '%Y-%m-%d' "$filepath"
        fi
    else
        local birth
        birth="$(stat -c '%w' "$filepath" 2>/dev/null)"
        if [[ -n "$birth" && "$birth" != "-" ]]; then
            echo "$birth" | cut -d' ' -f1
        else
            stat -c '%y' "$filepath" | cut -d' ' -f1
        fi
    fi
}

# =============================================================================
# --- Main ---
# =============================================================================

check_dependencies
parse_args "$@"
parse_config

# Find files
mapfile -t files < <(find "$SOURCE" -maxdepth 1 -type f | sort)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files found in '$SOURCE' to analyze."
    exit 0
fi

# --- Generate Report ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
REPORT_PATH="$SCRIPT_DIR/property_report_${REPORT_TIMESTAMP}.md"

{
    echo "# Media Metadata Analysis Report"
    echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Active Configuration"
    echo "- **Priority order:** $(IFS=' → '; echo "${PRIORITY[*]}")"
    echo "- **Metadata properties:** $(IFS=', '; echo "${METADATA_PROPERTIES[*]}")"
    echo ""
    echo "---"
    echo ""
    echo "This report lists date-extraction results for files in \`$SOURCE\`."
    echo ""

    for filepath in "${files[@]}"; do
        filename="$(basename "$filepath")"
        basename_noext="${filename%.*}"
        echo "Analyzing: $filename..." >&2

        echo "## File: $filename"

        # Evaluate all strategies
        declare -A strategy_results=()

        # Filename
        fname_result="$(get_date_from_filename "$basename_noext" 2>/dev/null)" && strategy_results[filename]="$fname_result" || true

        # Metadata
        meta_result="$(get_date_from_metadata "$filepath" 2>/dev/null)" && strategy_results[metadata]="$meta_result" || true

        # Filesystem
        fs_result="$(get_date_from_filesystem "$filepath" 2>/dev/null)" && strategy_results[filesystem]="$fs_result" || true

        # Determine winner
        winner=""
        winner_value=""
        for strategy in "${PRIORITY[@]}"; do
            if [[ -n "${strategy_results[$strategy]:-}" ]]; then
                winner="$strategy"
                winner_value="${strategy_results[$strategy]}"
                break
            fi
        done

        if [[ -z "$winner" ]]; then
            winner="filesystem (fallback)"
            winner_value="${strategy_results[filesystem]:-unknown}"
        fi

        echo "- **Winner:** $winner → \`$winner_value\`"
        echo ""
        echo "| Strategy | Result |"
        echo "|---|---|"
        for strategy in "${PRIORITY[@]}"; do
            val="${strategy_results[$strategy]:-—}"
            marker=""
            [[ "$strategy" == "$winner" ]] && marker=" ✓"
            echo "| ${strategy}${marker} | $val |"
        done
        echo ""

        # Show all exiftool date fields
        echo "| Tag | Value |"
        echo "|---|---|"
        exif_dates="$(exiftool -s -s -G1 -d '%Y-%m-%d %H:%M:%S' "$filepath" 2>/dev/null | grep -i "date\|time\|created\|modified" || true)"
        if [[ -n "$exif_dates" ]]; then
            while IFS= read -r line; do
                # Format: [Group] TagName : Value
                tag="$(echo "$line" | sed 's/^\[//' | sed 's/\] /|/' | sed 's/ *: */|/')"
                group="${tag%%|*}"
                rest="${tag#*|}"
                tagname="${rest%%|*}"
                value="${rest#*|}"
                echo "| [$group] $tagname | $value |"
            done <<< "$exif_dates"
        else
            echo "| *(no date metadata found)* | |"
        fi
        echo ""

        unset strategy_results
    done
} > "$REPORT_PATH"

echo "Success! Property report generated at: $REPORT_PATH"
