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
DATE_STRATEGY="priority"

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
            Options)
                if [[ "$line" =~ ^(.+)=(.*)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local val="${BASH_REMATCH[2]}"
                    key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    case "$key" in
                        DateStrategy)
                            if [[ "$val" =~ ^(priority|earliest)$ ]]; then
                                DATE_STRATEGY="$val"
                            fi
                            ;;
                    esac
                fi
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
    echo "- **Priority order:** $(IFS=' > '; echo "${PRIORITY[*]}")"
    echo "- **Date strategy:** $DATE_STRATEGY"
    echo "- **Metadata properties:** $(IFS=', '; echo "${METADATA_PROPERTIES[*]}")"
    echo ""
    echo "---"
    echo ""
    echo "This report lists date-extraction results for files in \`$SOURCE\`."
    echo ""

    # --- Tracking variables ---
    total_analyzed=0
    has_filename_date=0
    has_metadata_date=0
    filename_older_count=0
    metadata_older_count=0
    dates_agree_count=0
    no_metadata_files=()
    no_filename_files=()

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

        # --- Track stats ---
        ((total_analyzed++))
        if [[ -n "${strategy_results[filename]:-}" ]]; then
            ((has_filename_date++))
        else
            no_filename_files+=("$filename")
        fi
        if [[ -n "${strategy_results[metadata]:-}" ]]; then
            ((has_metadata_date++))
        else
            no_metadata_files+=("$filename")
        fi

        # Compare filename vs metadata when both exist
        if [[ -n "${strategy_results[filename]:-}" && -n "${strategy_results[metadata]:-}" ]]; then
            fn_date="${strategy_results[filename]:0:10}"
            md_date="${strategy_results[metadata]:0:10}"
            if [[ "$fn_date" == "$md_date" ]]; then
                ((dates_agree_count++))
            elif [[ "$fn_date" < "$md_date" ]]; then
                ((filename_older_count++))
            else
                ((metadata_older_count++))
            fi
        fi

        # Determine winner
        winner=""
        winner_value=""

        if [[ "$DATE_STRATEGY" == "earliest" ]]; then
            # Pick the earliest date across all strategies
            earliest_date=""
            for strategy in "${PRIORITY[@]}"; do
                if [[ -n "${strategy_results[$strategy]:-}" ]]; then
                    date_only="${strategy_results[$strategy]%% *}"
                    # Extract just YYYY-MM-DD portion
                    date_only="${date_only:0:10}"
                    if [[ -z "$earliest_date" || "$date_only" < "$earliest_date" ]]; then
                        earliest_date="$date_only"
                        winner="$strategy"
                        winner_value="${strategy_results[$strategy]}"
                    fi
                fi
            done
        else
            # Priority mode: first match wins
            for strategy in "${PRIORITY[@]}"; do
                if [[ -n "${strategy_results[$strategy]:-}" ]]; then
                    winner="$strategy"
                    winner_value="${strategy_results[$strategy]}"
                    break
                fi
            done
        fi

        if [[ -z "$winner" ]]; then
            winner="filesystem (fallback)"
            winner_value="${strategy_results[filesystem]:-unknown}"
        fi

        echo "- **Winner:** $winner > \`$winner_value\`"
        echo ""
        echo "| Strategy | Result |"
        echo "|---|---|"
        for strategy in "${PRIORITY[@]}"; do
            val="${strategy_results[$strategy]:--}"
            marker=""
            [[ "$strategy" == "$winner" ]] && marker=" *"
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

    # --- Recommendations ---
    echo "---"
    echo ""
    echo "## Recommendations"
    echo ""
    echo "Based on analyzing **$total_analyzed files**:"
    echo ""
    echo "### What was found"
    echo ""
    echo "| Strategy | Files with a date | Files without |"
    echo "|---|---|---|"
    echo "| Filename | $has_filename_date / $total_analyzed | $((total_analyzed - has_filename_date)) |"
    echo "| Metadata | $has_metadata_date / $total_analyzed | $((total_analyzed - has_metadata_date)) |"
    echo "| Filesystem | $total_analyzed / $total_analyzed | 0 (always available) |"
    echo ""

    both_have=$((dates_agree_count + filename_older_count + metadata_older_count))
    if [[ $both_have -gt 0 ]]; then
        echo "### When both filename and metadata have a date ($both_have files)"
        echo ""
        echo "| Result | Count |"
        echo "|---|---|"
        echo "| They agree (same day) | $dates_agree_count |"
        echo "| Filename is older | $filename_older_count |"
        echo "| Metadata is older | $metadata_older_count |"
        echo ""
    fi

    echo "### Suggested settings"
    echo ""

    if [[ $has_metadata_date -eq $total_analyzed && $has_filename_date -eq $total_analyzed ]]; then
        if [[ $dates_agree_count -eq $both_have ]]; then
            echo "All your files have both filename dates and metadata, and they always agree."
            echo "Either priority order works. The default (metadata first) is fine."
        elif [[ $filename_older_count -gt $metadata_older_count ]]; then
            echo "Filename dates are often older than metadata dates. This usually means"
            echo "metadata was modified (e.g. by editing software) while filenames kept the original date."
            echo ""
            echo "**Recommended:**"
            echo "\`\`\`ini"
            echo "[Priority]"
            echo "filename"
            echo "metadata"
            echo "filesystem"
            echo "\`\`\`"
            echo ""
            echo "Or use \`DateStrategy=earliest\` to always pick the oldest date automatically."
        else
            echo "Metadata dates are generally older or equal to filename dates."
            echo "The default priority (metadata first) is a good fit."
        fi
    elif [[ $has_metadata_date -lt $total_analyzed && $has_filename_date -eq $total_analyzed ]]; then
        echo "Some files are missing metadata (likely from WhatsApp, Instagram, or similar apps"
        echo "that strip EXIF data). All files have dates in their filenames."
        echo ""
        echo "**Recommended:**"
        echo "\`\`\`ini"
        echo "[Priority]"
        echo "filename"
        echo "metadata"
        echo "filesystem"
        echo "\`\`\`"
        if [[ ${#no_metadata_files[@]} -le 5 && ${#no_metadata_files[@]} -gt 0 ]]; then
            echo ""
            echo "Files without metadata: $(IFS=', '; echo "${no_metadata_files[*]}")"
        fi
    elif [[ $has_filename_date -lt $total_analyzed && $has_metadata_date -eq $total_analyzed ]]; then
        echo "Some files don't have a recognizable date in their filename,"
        echo "but all files have metadata. The default priority (metadata first) is ideal."
        if [[ ${#no_filename_files[@]} -le 5 && ${#no_filename_files[@]} -gt 0 ]]; then
            echo ""
            echo "Files without filename date: $(IFS=', '; echo "${no_filename_files[*]}")"
        fi
    else
        echo "Your files are a mix - some lack metadata, some lack filename dates."
        echo "Consider using \`DateStrategy=earliest\` to get the best result from whatever is available."
        echo ""
        echo "\`\`\`ini"
        echo "[Options]"
        echo "DateStrategy=earliest"
        echo "\`\`\`"
        if [[ ${#no_metadata_files[@]} -le 5 && ${#no_metadata_files[@]} -gt 0 ]]; then
            echo ""
            echo "Files without metadata: $(IFS=', '; echo "${no_metadata_files[*]}")"
        fi
        if [[ ${#no_filename_files[@]} -le 5 && ${#no_filename_files[@]} -gt 0 ]]; then
            echo ""
            echo "Files without filename date: $(IFS=', '; echo "${no_filename_files[*]}")"
        fi
    fi
    echo ""
} > "$REPORT_PATH"

echo "Success! Property report generated at: $REPORT_PATH"
