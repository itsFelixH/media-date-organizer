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
| `-format` | Folder structure format | `yyyy\yyyy-MM\yyyy-MM-dd` |
| `-config` | Path to config file | `config.ini` next to script |
| `-DryRun` | Preview without moving files | off |

## Configuration (Optional)

The script works out of the box with no config file. If you want to customize the priority order:

1. Copy the template:
   ```powershell
   Copy-Item config.ini.template config.ini
   ```

2. Edit `config.ini`:
   ```ini
   # Swap order to trust filenames over metadata:
   [Priority]
   filename
   metadata
   filesystem

   # Only check these metadata fields:
   [MetadataProperties]
   DateTaken
   DateTimeOriginal
   MediaCreated
   ```

### Available strategies

- `filename` — extracts date from filename patterns (e.g. `20231025`, `2023-10-25`)
- `metadata` — reads Windows Shell properties (EXIF, media encoded dates)
- `filesystem` — uses file creation time

### Available metadata properties

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

## Diagnostic Tool

Not sure how your files will be sorted? Use `analyzeMedia.ps1` to inspect metadata:

1. Put sample files in the `examples/` folder
2. Run:
   ```powershell
   .\analyzeMedia.ps1
   ```
3. Check the generated `property_report_*.md` — shows which date source would be chosen for each file and all available metadata

## Folder Structure Examples

| File | Sorted to |
|------|-----------|
| `DSC02345.jpg` (taken 2023-06-15) | `Sorted\2023\2023-06\2023-06-15\DSC02345.jpg` |
| `VID_20240101_143022.mp4` | `Sorted\2024\2024-01\2024-01-01\VID_20240101_143022.mp4` |
| `IMG_0001.jpg` (no date anywhere) | `Sorted\2019\2019-03\2019-03-22\IMG_0001.jpg` (uses creation date) |

Custom format: `-format "yyyy\\MM-MMM"` → `2024\04-Apr`

## Good to Know

- **Duplicates** are auto-renamed (`IMG_0001.jpg` → `IMG_0001_1.jpg`)
- **Windows only** — uses Windows Shell for metadata extraction
- **Network drives** work if mapped; UNC paths may not expose metadata
- **RAW files** (CR3, NEF) need Windows 10+ for metadata support
- **Always test with `-DryRun` first** or use copies

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- Windows (uses COM Shell.Application for metadata)

## Contributing

PRs, issues, and ideas welcome.
