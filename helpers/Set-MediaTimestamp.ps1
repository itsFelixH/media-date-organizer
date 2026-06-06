<#
.SYNOPSIS
    Sets file system timestamps (CreationTime, LastWriteTime) from EXIF/metadata dates.
.DESCRIPTION
    Scans a directory for media files and updates their file system timestamps to match
    the embedded metadata date (e.g., EXIF DateTaken, DateTimeOriginal).

    This fixes files where the filesystem date is wrong — common after copying between
    drives, extracting from archives, downloading from cloud services, or restoring backups.

    Uses the same metadata property priority as the main Sort-Media.ps1 script.
    Only updates files where the metadata date differs from the current filesystem date.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.PARAMETER IncludeExtensions
    Only process files with these extensions (comma-separated). Default: common media types.
.PARAMETER DryRun
    Preview changes without modifying any timestamps.
.EXAMPLE
    .\Set-MediaTimestamp.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Set-MediaTimestamp.ps1 -SourcePath "D:\Photos\2024"
.EXAMPLE
    .\Set-MediaTimestamp.ps1 -SourcePath "." -IncludeExtensions @(".jpg", ".mp4")
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [Alias('Path')]
    [string]$SourcePath = ".",

    [Parameter(Mandatory = $false)]
    [string[]]$IncludeExtensions = @(
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".heic", ".heif",
        ".tif", ".tiff", ".cr2", ".cr3", ".nef", ".arw", ".dng",
        ".mp4", ".mov", ".avi", ".mkv", ".3gp", ".m4v", ".mts", ".m2ts"
    ),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$resolvedPath = (Resolve-Path -Path $SourcePath).Path
Write-Host "Scanning for media files in $resolvedPath..." -ForegroundColor Cyan

# --- Windows Shell metadata property IDs (date-related, in priority order) ---
$metadataPropertyIds = @(
    12,     # System.Photo.DateTaken
    36879,  # System.Photo.DateTimeOriginal (EXIF)
    208,    # System.Media.DateEncoded
    209,    # System.Media.DateEncoded (alternate locale)
    17,     # System.RecordedDate
    3       # System.ItemDate
)

$shell = New-Object -ComObject Shell.Application
$namespaceCache = @{}

function Get-CachedNamespace {
    param([string]$path)
    if (-not $namespaceCache.ContainsKey($path)) {
        $namespaceCache[$path] = $shell.NameSpace($path)
    }
    return $namespaceCache[$path]
}

function Get-MetadataDate {
    param([System.IO.FileInfo]$FileObject)

    $dir = Get-CachedNamespace $FileObject.Directory.FullName
    if ($null -eq $dir) { return $null }

    $item = $dir.ParseName($FileObject.Name)
    if ($null -eq $item) { return $null }

    foreach ($id in $metadataPropertyIds) {
        $dateValue = $dir.GetDetailsOf($item, $id)
        if (-not [string]::IsNullOrWhiteSpace($dateValue)) {
            # Remove invisible Unicode BiDi markers
            $cleanValue = $dateValue -replace "[\u200e\u200f\u202a-\u202e]", ""
            $parsedDate = [System.DateTime]::MinValue
            if ([DateTime]::TryParse($cleanValue, [ref]$parsedDate)) {
                return $parsedDate
            }
        }
    }
    return $null
}

# Find matching files
$includePatterns = $IncludeExtensions | ForEach-Object { "*$_" }
$files = Get-ChildItem -Path $resolvedPath -Include $includePatterns -Recurse -File
$total = $files.Count

if ($total -eq 0) {
    Write-Host "No media files found matching: $($IncludeExtensions -join ', ')" -ForegroundColor Yellow
    return
}

Write-Host "Found $total media files. Checking timestamps..." -ForegroundColor Cyan

$updatedCount = 0
$skippedCount = 0
$errorCount = 0
$i = 0

foreach ($file in $files) {
    $i++
    Write-Progress -Activity "Checking Timestamps" -Status "$($file.Name)" -PercentComplete ($i / $total * 100)

    $metadataDate = Get-MetadataDate -FileObject $file

    if ($null -eq $metadataDate) {
        $skippedCount++
        continue
    }

    # Check if filesystem dates already match (within 1 second tolerance)
    $creationMatch = [Math]::Abs(($file.CreationTime - $metadataDate).TotalSeconds) -lt 2
    $writeMatch = [Math]::Abs(($file.LastWriteTime - $metadataDate).TotalSeconds) -lt 2

    if ($creationMatch -and $writeMatch) {
        $skippedCount++
        continue
    }

    Write-Host "[$i/$total] $($file.Name)"
    Write-Host "  Metadata:  $($metadataDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
    if (-not $creationMatch) {
        Write-Host "  Created:   $($file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')) -> $($metadataDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    }
    if (-not $writeMatch) {
        Write-Host "  Modified:  $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -> $($metadataDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would update" -ForegroundColor Gray
        $updatedCount++
        continue
    }

    try {
        if (-not $creationMatch) {
            $file.CreationTime = $metadataDate
        }
        if (-not $writeMatch) {
            $file.LastWriteTime = $metadataDate
        }
        $updatedCount++
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Progress -Activity "Checking Timestamps" -Completed

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
Remove-Variable shell, namespaceCache

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Scanned:  $total"
Write-Host "Updated:  $updatedCount" -ForegroundColor Green
Write-Host "Skipped:  $skippedCount (already correct or no metadata)" -ForegroundColor DarkGray
Write-Host "Errors:   $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
if ($DryRun) { Write-Host "(Dry run - no timestamps were actually changed)" -ForegroundColor Yellow }
