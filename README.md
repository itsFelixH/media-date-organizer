# media-date-organizer

A collection of PowerShell scripts to analyze and organize photos and videos into date-based folders using filename patterns and Windows Shell metadata.

## 📌 Features

- Supports all common image/video formats
- Metadata priority:\
``Filename Date`` → ``Date Taken (EXIF)`` → ``Media Created (Encoded)`` → ``General Item Date`` → ``File System Date``
- Auto-renaming for duplicates (IMG_0001.jpg → IMG_0001_1.jpg)
- **Dry Run mode** to preview changes without moving files
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
| `-DryRun` | Preview the organization without creating folders or moving files | `$false` |

## 🔍 Diagnostic Tool (`analyzeMedia.ps1`)

Before running the main script, you can use `analyzeMedia.ps1` to see exactly how your files will be processed.

1. Place sample files in the `\examples` folder.
2. Run the script:
   ```powershell
   .\analyzeMedia.ps1
   ```
3. Review `property_report.md` to see:
   - The **Script Decision** (which date source was chosen).
   - A list of all date-related Windows Shell properties found.
   - Specific markers showing which properties are considered **(Priority)**.

## ⚠ Notes

1. **Filename Logic:**\
The script prioritizes dates found in filenames (e.g., `IMG_20231025_...`) as these are often preserved when metadata is stripped by messaging apps.
2. **Invisible Characters:**\
Windows often adds hidden Unicode markers (BiDi) to date strings. Both scripts automatically strip these to ensure valid parsing.
3. **Network Drives:**\
Metadata extraction requires local files (mapped drives okay)
4. **File Types:**\
RAW camera files (CR3/NEF) require Windows 10+ for metadata
5. **Permissions:**\
Run as Administrator if accessing protected directories
6. **Testing:**\
Always test with copies first!

## 📁 Folder Structure Examples

| Original | Destination |
|-------|-----|
| ``DSC02345.jpg`` (2023-06-15) | ``\Sorted\2023\2023-06\2023-06-15\DSC02345.jpg`` |
| ``VID_20240101.mp4`` | ``\Sorted\2024\2024-01\2024-01-01\VID_20240101.mp4`` |

Custom formats: ``-format "yyyy/MM-MMM"`` → ``2024/04-Apr``

## 🙌 Contributions

PRs, ideas, and feedback are welcome!
