# media-date-organizer

Organize your photos and videos into date-based folders automatically. Works with EXIF metadata, filename dates, and file system dates.

## Quick Start

```powershell
.\sortPhotosAndVideos.ps1 -source "C:\Users\You\Pictures"
```

That's it. Your files get sorted into `Pictures\Sorted\2024\2024-06\2024-06-15\` based on when they were taken.

### Preview first (recommended)

```powershell
.\sortPhotosAndVideos.ps1 -source "C:\Users\You\Pictures" -DryRun
```

Shows what would happen without moving anything.

## How It Decides the Date

The script tries multiple strategies in order and uses the first date it finds:

| # | Strategy | What it checks |
|---|----------|----------------|
| 1 | **Metadata** | EXIF DateTaken, DateTimeOriginal, MediaCreated, etc. |
| 2 | **Filename** | Patterns like `IMG_20231025`, `2023-10-25`, `2023_10_25` |
| 3 | **Filesystem** | File creation date (last resort) |

This order works well for most people — metadata is the most reliable source since it survives renames.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-source` | Folder containing your media | *Required* |
| `-dest` | Where sorted files go | `<source>\Sorted` |
| `-config` | Path to config file | `config.ini` next to script |
| `-DryRun` | Preview without moving files | off |

## Configuration (Optional)

The script works out of the box with no config file. If you want to customize behavior:

1. Copy the template:
   ```powershell
   Copy-Item config.ini.template config.ini
   ```

2. Edit `config.ini` to your needs.

### Priority

Controls the order in which date-extraction strategies are tried:

```ini
[Priority]
metadata
filename
filesystem
```

Swap lines to change priority. For example, to trust filenames over metadata:

```ini
[Priority]
filename
metadata
filesystem
```

### Metadata Properties

Controls which metadata fields are checked and in what order:

```ini
[MetadataProperties]
DateTaken
DateTimeOriginal
MediaCreated
MediaCreatedAlt
RecordedDate
ItemDate
DateModified
DateCreated
```

| Name | What it is |
|------|-----------|
| `DateTaken` | EXIF Date Taken (photos) |
| `DateTimeOriginal` | EXIF Date/Time Original |
| `MediaCreated` | Media encoded date (videos) |
| `MediaCreatedAlt` | Same as above, alternate locale ID |
| `RecordedDate` | Recorded date (audio/video) |
| `ItemDate` | General item date |
| `DateModified` | File modified date |
| `DateCreated` | File system creation date |

### Options

```ini
[Options]
# Move or copy files (move/copy)
FileAction=move

# Folder structure date format (.NET format strings)
DateFormat=yyyy\\yyyy-MM\\yyyy-MM-dd

# Only process these extensions (comma-separated, or * for all)
IncludeExtensions=*

# Skip these extensions (comma-separated, or empty for none)
ExcludeExtensions=

# What to do on name collision (rename/skip/overwrite)
ConflictStrategy=rename

# Remove empty directories after moving (true/false)
CleanupEmptyDirs=true

# Path to a log file for auditing (empty to disable)
LogFile=
```

| Option | Values | Default | Notes |
|--------|--------|---------|-------|
| `FileAction` | `move`, `copy` | `move` | Use `copy` to keep originals intact |
| `DateFormat` | .NET date format | `yyyy\\yyyy-MM\\yyyy-MM-dd` | e.g. `yyyy\\MM-MMM` → `2024\04-Apr` |
| `IncludeExtensions` | `*` or comma-separated | `*` | e.g. `jpg,png,mp4,mov` |
| `ExcludeExtensions` | empty or comma-separated | *(empty)* | e.g. `txt,db,ini` |
| `ConflictStrategy` | `rename`, `skip`, `overwrite` | `rename` | `rename` appends `_1`, `_2`, etc. |
| `CleanupEmptyDirs` | `true`, `false` | `true` | Only applies when `FileAction=move` |
| `LogFile` | file path or empty | *(empty)* | TSV log with timestamp, action, source, destination, strategy |

## Diagnostic Tool

Not sure how your files will be sorted? Use `analyzeMedia.ps1` to inspect metadata:

```powershell
.\analyzeMedia.ps1 -source "C:\Users\You\Pictures\SomeFolder"
```

Or just run it against the default `examples/` folder:

```powershell
.\analyzeMedia.ps1
```

The generated `property_report_*.md` shows:
- The active configuration (priority order, metadata properties)
- Which strategy would win for each file
- What every strategy would return (so you can see the effect of reordering)
- All available date-related metadata fields

## Folder Structure Examples

| File | Sorted to |
|------|-----------|
| `DSC02345.jpg` (taken 2023-06-15) | `Sorted\2023\2023-06\2023-06-15\DSC02345.jpg` |
| `VID_20240101_143022.mp4` | `Sorted\2024\2024-01\2024-01-01\VID_20240101_143022.mp4` |
| `IMG_0001.jpg` (no date anywhere) | `Sorted\2019\2019-03\2019-03-22\IMG_0001.jpg` (uses creation date) |

Custom format via config: `DateFormat=yyyy\\MM-MMM` → `2024\04-Apr`

## Good to Know

- **Duplicates** are handled by `ConflictStrategy` (default: auto-rename with `_1`, `_2`, etc.)
- **Windows only** — uses Windows Shell for metadata extraction
- **Network drives** work if mapped; UNC paths may not expose metadata
- **RAW files** (CR3, NEF) need Windows 10+ for metadata support
- **Always test with `-DryRun` first** or use copies
- **Summary** is printed at the end showing moved/copied, skipped, and error counts
- **Empty directories** are cleaned up automatically after moving (configurable)

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- Windows (uses COM Shell.Application for metadata)

## Contributing

PRs, issues, and ideas welcome.
