<#
.SYNOPSIS
    Removes original media files after verifying their converted counterparts exist.
.DESCRIPTION
    Scans for legacy-format files (.webp, .jfif, .heic, .bmp, .3gp, .mov, .avi) and
    deletes them ONLY if a matching converted file (.jpg or .mp4) exists in the same
    directory. This is a safe cleanup step to run after Convert-MediaFormat.ps1.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.PARAMETER Extensions
    File extensions to check for cleanup. Defaults to: .webp, .jfif, .heic, .bmp, .3gp, .mov, .avi
.PARAMETER DryRun
    Preview deletions without actually removing files.
.EXAMPLE
    .\Remove-ConvertedOriginals.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Remove-ConvertedOriginals.ps1 -SourcePath "D:\Photos"
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [Alias('Path')]
    [string]$SourcePath = ".",

    [Parameter(Mandatory = $false)]
    [string[]]$Extensions = @(".webp", ".jfif", ".heic", ".bmp", ".3gp", ".mov", ".avi"),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$resolvedPath = (Resolve-Path -Path $SourcePath).Path
Write-Host "Scanning for converted originals to clean up in $resolvedPath..." -ForegroundColor Cyan

# Find files matching the target extensions
$includePatterns = $Extensions | ForEach-Object { "*$_" }
$originals = Get-ChildItem -Path $resolvedPath -Include $includePatterns -Recurse -File
$totalFound = $originals.Count

if ($totalFound -eq 0) {
    Write-Host "No legacy files found matching extensions: $($Extensions -join ', ')" -ForegroundColor Green
    return
}

$photoExtensions = @(".webp", ".jfif", ".heic", ".bmp")
$deletedCount = 0
$skippedCount = 0

foreach ($file in $originals) {
    $ext = $file.Extension.ToLower()
    $targetExt = if ($ext -in $photoExtensions) { ".jpg" } else { ".mp4" }
    $targetPath = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + $targetExt)

    if (Test-Path -LiteralPath $targetPath) {
        $targetLabel = $targetExt.ToUpper().TrimStart('.')
        Write-Host "Found $targetLabel for: $($file.Name) - Safe to delete." -ForegroundColor Gray

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would delete $($file.FullName)" -ForegroundColor Yellow
            $deletedCount++
        } else {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deletedCount++
            } catch {
                Write-Host "  Error deleting file: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        $targetLabel = $targetExt.ToUpper().TrimStart('.')
        Write-Host "No $targetLabel found for: $($file.Name) - Skipping." -ForegroundColor DarkYellow
        $skippedCount++
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Originals found: $totalFound"
Write-Host "Deleted:         $deletedCount" -ForegroundColor Green
Write-Host "Skipped:         $skippedCount" -ForegroundColor Yellow
if ($DryRun) { Write-Host "(Dry run - no files were actually deleted)" -ForegroundColor Yellow }
