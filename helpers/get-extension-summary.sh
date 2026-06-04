#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# get-extension-summary.sh - Count and summarize file extensions in a directory
# No external dependencies required.
# =============================================================================

# --- Defaults ---
SOURCE_PATH="."

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Recursively counts files by extension and displays a summary table with sizes.

Options:
  -source <path>    Directory to scan (default: current directory)
  -h, --help        Show this help message

Example:
  $(basename "$0") -source ~/Pictures
EOF
    exit 1
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -source) SOURCE_PATH="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

if [[ ! -d "$SOURCE_PATH" ]]; then
    echo "ERROR: Directory '$SOURCE_PATH' does not exist."
    exit 1
fi

SOURCE_PATH="$(cd "$SOURCE_PATH" && pwd)"
echo "Scanning $SOURCE_PATH..."
echo ""

# Find all files, extract extensions, count and sort
printf "%-12s %8s %10s\n" "Extension" "Count" "Size"
printf "%-12s %8s %10s\n" "---------" "-----" "----"

find "$SOURCE_PATH" -type f -print0 | while IFS= read -r -d '' file; do
    ext="${file##*.}"
    if [[ "$ext" == "$file" || "$ext" == "$(basename "$file")" ]]; then
        ext="(none)"
    else
        ext=".${ext,,}"  # lowercase
    fi
    printf "%s\n" "$ext"
done | sort | uniq -c | sort -rn | while read -r count ext; do
    # Get total size for this extension
    if [[ "$ext" == "(none)" ]]; then
        size_bytes=$(find "$SOURCE_PATH" -type f ! -name "*.*" -print0 | xargs -0 du -cb 2>/dev/null | tail -1 | cut -f1)
    else
        size_bytes=$(find "$SOURCE_PATH" -type f -iname "*${ext}" -print0 | xargs -0 du -cb 2>/dev/null | tail -1 | cut -f1)
    fi
    size_bytes="${size_bytes:-0}"

    # Human-readable size
    if [[ $size_bytes -ge 1073741824 ]]; then
        size="$(echo "scale=1; $size_bytes/1073741824" | bc) GB"
    elif [[ $size_bytes -ge 1048576 ]]; then
        size="$(echo "scale=1; $size_bytes/1048576" | bc) MB"
    elif [[ $size_bytes -ge 1024 ]]; then
        size="$(echo "scale=1; $size_bytes/1024" | bc) KB"
    else
        size="${size_bytes} B"
    fi

    printf "%-12s %8d %10s\n" "$ext" "$count" "$size"
done

echo ""
total_files=$(find "$SOURCE_PATH" -type f | wc -l)
total_bytes=$(find "$SOURCE_PATH" -type f -print0 | xargs -0 du -cb 2>/dev/null | tail -1 | cut -f1)
total_bytes="${total_bytes:-0}"

if [[ $total_bytes -ge 1073741824 ]]; then
    total_size="$(echo "scale=1; $total_bytes/1073741824" | bc) GB"
elif [[ $total_bytes -ge 1048576 ]]; then
    total_size="$(echo "scale=1; $total_bytes/1048576" | bc) MB"
else
    total_size="$(echo "scale=1; $total_bytes/1024" | bc) KB"
fi

total_exts=$(find "$SOURCE_PATH" -type f | sed 's/.*\./\./' | sort -u | wc -l)
echo "Total: $total_files files ($total_size) across $total_exts extensions."
