# media-date-organizer

Automatically sort your photos and videos into date-based folders. Works on Windows, macOS, and Linux.

```
Before:                          After:
📁 Unsorted/                     📁 Sorted/
├── IMG_20240615_143022.jpg      ├── 2024/
├── DSC02345.jpg                 │   ├── 2024-06/
├── VID_20240101.mp4             │   │   └── 2024-06-15/
├── random_photo.png             │   │       ├── IMG_20240615_143022.jpg
└── ...                          │   │       └── DSC02345.jpg
                                 │   └── 2024-01/
                                 │       └── 2024-01-01/
                                 │           └── VID_20240101.mp4
                                 └── ...
```

---

## Quick Start

### Windows (PowerShell)

```powershell
# Preview what would happen (recommended first run)
.\sortPhotosAndVideos.ps1 -source "C:\Users\You\Pictures" -DryRun

# Do it for real
.\sortPhotosAndVideos.ps1 -source "C:\Users\You\Pictures"
```

### macOS / Linux (Bash)

```bash
# Install exiftool first (one-time)
brew install exiftool          # macOS
sudo apt install libimage-exiftool-perl  # Ubuntu/Debian

# Preview what would happen
./sortPhotosAndVideos.sh -source ~/Pictures -DryRun

# Do it for real
./sortPhotosAndVideos.sh -source ~/Pictures
```

That's it. Files are sorted into `<source>/Sorted/` by date.

---

## How It Decides the Date

The script tries multiple strategies in order and uses the first date it finds:

| # | Strategy | What it checks |
|---|----------|----------------|
| 1 | **Metadata** | EXIF DateTaken, DateTimeOriginal, MediaCreated, etc. |
| 2 | **Filename** | Patterns like `IMG_20231025`, `2023-10-25`, `2023_10_25` |
| 3 | **Filesystem** | File creation date (last resort) |

This order is configurable. See [Configuration](#configuration-optional) below.

---

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-source` | Folder containing your media | *Required* |
| `-dest` | Where sorted files go | `<source>/Sorted` |
| `-config` | Path to config file | `config.ini` next to script |
| `-DryRun` | Preview without moving files | off |

---

## Configuration (Optional)

The scripts work out of the box with no config file. To customize:

```bash
# Copy the template
cp config.ini.template config.ini   # macOS/Linux
Copy-Item config.ini.template config.ini  # Windows
```

Then edit `config.ini`. It's heavily commented with examples — open it and you'll see what's available.

### At a Glance

| Setting | What it does | Default |
|---------|-------------|---------|
| **[Priority]** | Order of date-extraction strategies | metadata → filename → filesystem |
| **[MetadataProperties]** | Which metadata fields to check | All (DateTaken first) |
| **FileAction** | Move or copy files | `move` |
| **DateFormat** | Folder structure (Windows, .NET format) | `yyyy\yyyy-MM\yyyy-MM-dd` |
| **DateFormatUnix** | Folder structure (macOS/Linux, strftime) | `%Y/%Y-%m/%Y-%m-%d` |
| **IncludeExtensions** | Only process these file types | `*` (all) |
| **ExcludeExtensions** | Skip these file types | *(none)* |
| **ConflictStrategy** | Name collision handling | `rename` (_1, _2, ...) |
| **CleanupEmptyDirs** | Remove empty folders after moving | `true` |
| **LogFile** | TSV audit log path | *(disabled)* |

### Example: Phone Photos Setup

```ini
[Priority]
filename
metadata
filesystem

[Options]
IncludeExtensions=jpg,jpeg,heic,mp4,mov
ExcludeExtensions=thm,aae
```

### Example: Backup Mode (Keep Originals)

```ini
[Options]
FileAction=copy
ConflictStrategy=skip
```

---

## Diagnostic Tool

Not sure how your files will be sorted? Analyze them first:

```powershell
# Windows
.\analyzeMedia.ps1 -source "C:\Users\You\Pictures\SomeFolder"
```

```bash
# macOS/Linux
./analyzeMedia.sh -source ~/Pictures/SomeFolder
```

Generates a `property_report_*.md` showing:
- Which strategy wins for each file
- What every strategy *would* return (helps you tune priority order)
- All available date metadata

---

## Good to Know

- **Always test with `-DryRun` first** — see exactly what will happen before committing
- **Duplicates** are handled by `ConflictStrategy` (default: auto-rename with `_1`, `_2`)
- **Empty directories** are cleaned up automatically after moving (configurable)
- **Summary** is printed at the end: moved/copied, skipped, errors
- **Log file** records every action as TSV for auditing (also logs during dry runs)
- **Network drives** work if mapped; UNC paths may not expose metadata (Windows)
- **RAW files** (CR3, NEF) — Windows needs 10+ for metadata; exiftool handles them everywhere

---

## Cross-Platform Reference

| | Windows | macOS/Linux |
|---|---------|-------------|
| Sort script | `sortPhotosAndVideos.ps1` | `sortPhotosAndVideos.sh` |
| Analyze script | `analyzeMedia.ps1` | `analyzeMedia.sh` |
| Metadata engine | Windows Shell COM | exiftool |
| Config file | Shared `config.ini` | Shared `config.ini` |
| Date format option | `DateFormat` (.NET) | `DateFormatUnix` (strftime) |
| Requirements | PowerShell 5.1+ | Bash 4+, exiftool |

---

## Contributing

PRs, issues, and ideas welcome.
