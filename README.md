# media-date-organizer

A PowerShell script to organize photos and videos into date-based folders using metadata.

## 📌 Features

- Supports all common image/video formats
- Metadata priority:\
``Filename Date`` → ``Date Taken`` → ``Media Created`` → ``File Creation Date``
- Auto-renaming for duplicates (IMG_0001.jpg → IMG_0001_1.jpg)
- Preserves file extensions
- Progress reporting

## 🚀 Usage

```powershell
.\media-date-organizer.ps1 -source "C:\Path\To\Your\Media"
```

### Optional Parameters

| Parameter | Description | Default |
|-|-||
| `-source` | Path to the folder containing media files | *Required* |
| `-dest` | Root destination folder | `<source>\Sorted` |
| `-format` | Date format for folder structure | `yyyy/yyyy-MM/yyyy-MM-dd` |

## ⚠ Notes

1. **Network Drives:**\
Metadata extraction requires local files (mapped drives okay)
2. **File Types:**\
RAW camera files (CR3/NEF) require Windows 10+ for metadata
3. **Permissions:**\
Run as Administrator if accessing protected directories
4. **Testing:**\
Always test with copies first!

## 📁 Folder Structure Examples

| Original | Destination |
|-------|-----|
| ``DSC02345.jpg`` (2023-06-15) | ``\Sorted\2023\2023-06\2023-06-15\DSC02345.jpg`` |
| ``VID_20240101.mp4`` | ``\Sorted\2024\2024-01\2024-01-01\VID_20240101.mp4`` |

Custom formats: ``-format "yyyy/MM-MMM"`` → ``2024/04-Apr``

## 🙌 Contributions

PRs, ideas, and feedback are welcome!
