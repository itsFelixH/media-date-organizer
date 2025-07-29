# media-date-organizer

A PowerShell script to organize photos and videos into date-based folders using metadata like **Date Taken** or **Created Date**.

## 📌 Features

- Sorts photos **and** videos by embedded metadata.
- Supports **recursive** folder processing.
- Automatically creates a date-based folder structure:

  ```bash
  yyyy/
      yyyy-MM/
          yyyy-MM-dd/
  ```

- Uses **Date Taken** when available (ideal for photos), falls back to **Created Date**.
- Prevents overwriting existing files by auto-renaming duplicates.
- Moves files using `robocopy` for reliable file transfers.

## 📁 Example

A video taken on *March 12, 2023* will be moved to:

```bash
\2023
    \2023-03
        \2023-03-12\
```

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

## 🔧 Requirements

- Windows
- PowerShell
- `robocopy` (included with Windows)
- File metadata (EXIF or NTFS date fields)

## ⚠ Notes

- Some video files may not have **Date Taken** — the script will fall back to the earliest available date field.
- Uses the Windows Shell COM interface to extract metadata (necessary for Date Taken in Explorer).
- Rename logic ensures files aren’t overwritten when duplicates exist.

## 🙌 Contributions

PRs, ideas, and feedback are welcome!
