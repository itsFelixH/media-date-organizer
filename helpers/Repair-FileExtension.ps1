<#
.SYNOPSIS
    Repairs corrupted or mangled file extensions.
.DESCRIPTION
    Scans a directory recursively and fixes common file extension issues:
    - Removes OS copy-suffixes appended after the extension
      (e.g., "photo.jpg - Copy" -> "photo.jpg", "video.mp4 (1)" -> "video.mp4")
    - Removes duplicate extensions (e.g., "photo.jpg.jpg" -> "photo.jpg")
    - Normalizes known extension variants (.jpeg -> .jpg, .tiff -> .tif, .mpeg -> .mpg)

    Only renames files where an issue is detected. Handles conflicts if the
    repaired name already exists.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.PARAMETER DryRun
    Preview changes without renaming any files.
.EXAMPLE
    .\Repair-FileExtension.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Repair-FileExtension.ps1 -SourcePath "D:\Photos"
#>

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [Alias('Path')]
    [string]$SourcePath = ".",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$resolvedPath = (Resolve-Path -Path $SourcePath).Path
Write-Host "Scanning for extension issues in $resolvedPath..." -ForegroundColor Cyan

# Extension normalization map (source -> canonical)
$extensionMap = @{
    ".jpeg" = ".jpg"
    ".tiff" = ".tif"
    ".mpeg" = ".mpg"
}

# Known media extensions for detecting duplicates and suffix corruption
$knownExtensions = @(
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".heic", ".heif",
    ".tif", ".tiff", ".raw", ".cr2", ".cr3", ".nef", ".arw", ".dng",
    ".mp4", ".mov", ".avi", ".mkv", ".wmv", ".flv", ".3gp", ".m4v",
    ".mpg", ".mpeg", ".mts", ".m2ts", ".webm"
)

# Build extension alternation for copy-suffix regex (only match known media extensions)
$extAlternation = ($knownExtensions | ForEach-Object { [regex]::Escape($_) }) -join '|'

# Suffixes appended by OS copy operations (after the real extension)
# macOS pattern matches " 2" through " 99" (single/double digit) to avoid false positives on "DSC 1234.jpg"
$copySuffixPattern = "($extAlternation)(\s*-\s*(Copy|Kopie|copie|copia)(\s*\(\d+\))?|\s*\(\d+\)|\s+adl.\s+dosyan.n\s+kopyas.*|\s+[2-9]\d?)$"

$successCount = 0
$errorCount = 0
$totalChecked = 0

Get-ChildItem -LiteralPath $resolvedPath -File -Recurse | ForEach-Object {
    $totalChecked++
    $originalName = $_.Name
    $newName = $originalName
    $fix = $null

    # --- Fix 1: Remove copy-suffix after extension ---
    # Files like "photo.jpg - Copy" or "video.mp4 (1)" have no valid extension
    # because the OS appended junk after it
    if ($newName -match $copySuffixPattern) {
        $newName = $newName -replace $copySuffixPattern, '$1'
        $fix = "Removed copy-suffix after extension"
    }

    # --- Fix 2: Remove duplicate extension ---
    # e.g., "photo.jpg.jpg" -> "photo.jpg"
    if ($null -eq $fix) {
        $ext = [System.IO.Path]::GetExtension($newName).ToLower()
        if ($ext -in $knownExtensions) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($newName)
            $innerExt = [System.IO.Path]::GetExtension($baseName).ToLower()
            if ($innerExt -eq $ext -or ($extensionMap.ContainsKey($innerExt) -and $extensionMap[$innerExt] -eq $ext)) {
                $newName = [System.IO.Path]::GetFileNameWithoutExtension($baseName) + $ext
                $fix = "Removed duplicate extension"
            }
        }
    }

    # --- Fix 3: Normalize extension variants ---
    if ($null -eq $fix) {
        $ext = [System.IO.Path]::GetExtension($newName).ToLower()
        if ($extensionMap.ContainsKey($ext)) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($newName)
            $newName = $baseName + $extensionMap[$ext]
            $fix = "Normalized $ext -> $($extensionMap[$ext])"
        }
    }

    # Skip if nothing to fix
    if ($null -eq $fix -or $newName -eq $originalName) {
        return
    }

    $newFullPath = Join-Path -Path $_.DirectoryName -ChildPath $newName

    # Handle conflicts
    if (Test-Path -LiteralPath $newFullPath) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($newName)
        $ext = [System.IO.Path]::GetExtension($newName)
        $i = 1
        while (Test-Path -LiteralPath (Join-Path -Path $_.DirectoryName -ChildPath "${baseName}_$i$ext")) {
            $i++
        }
        $newName = "${baseName}_$i$ext"
        $newFullPath = Join-Path -Path $_.DirectoryName -ChildPath $newName
    }

    Write-Host "Repairing: $originalName -> $newName"
    Write-Host "  Fix: $fix" -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would rename" -ForegroundColor Gray
        $successCount++
        return
    }

    try {
        Rename-Item -LiteralPath $_.FullName -NewName $newName -ErrorAction Stop
        $successCount++
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Scanned:  $totalChecked files"
Write-Host "Repaired: $successCount"
Write-Host "Errors:   $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
if ($DryRun) { Write-Host "(Dry run - no files were actually renamed)" -ForegroundColor Yellow }
