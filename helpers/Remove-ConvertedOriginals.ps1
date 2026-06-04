<#
.SYNOPSIS
    Removes original media files after verifying their converted counterparts exist.
.DESCRIPTION
    Scans for legacy-format files (.webp, .jfif, .heic, .heif, .bmp, .3gp, .mov, .avi)
    and deletes them ONLY if a matching converted file (.jpg or .mp4) exists in the same
    directory and is non-empty.

    This is a safe cleanup step to run after Convert-MediaFormat.ps1 when you didn't use
    the -RemoveOriginal flag during conversion (e.g., you wanted to verify results first).

    If you used Convert-MediaFormat.ps1 -RemoveOriginal, you don't need this script.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.PARAMETER Extensions
    File extensions to check for cleanup. Defaults to: .webp, .jfif, .heic, .heif, .bmp, .3gp, .mov, .avi
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
    [string[]]$Extensions = @(".webp", ".jfif", ".heic", ".heif", ".bmp", ".3gp", ".mov", ".avi"),

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

$photoExtensions = @(".webp", ".jfif", ".heic", ".heif", ".bmp")
$deletedCount = 0
$skippedCount = 0
$errorCount = 0

foreach ($file in $originals) {
    $ext = $file.Extension.ToLower()
    $targetExt = if ($ext -in $photoExtensions) { ".jpg" } else { ".mp4" }
    $targetPath = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + $targetExt)

    if (Test-Path -LiteralPath $targetPath) {
        $targetFile = Get-Item -LiteralPath $targetPath

        # Verify the converted file is non-empty (protects against failed conversions)
        if ($targetFile.Length -eq 0) {
            Write-Host "Skipping: $($file.Name) - converted file exists but is 0 bytes" -ForegroundColor DarkYellow
            $skippedCount++
            continue
        }

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
                $errorCount++
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
Write-Host "Errors:          $errorCount" -ForegroundColor ($errorCount -gt 0 ? "Red" : "Gray")
if ($DryRun) { Write-Host "(Dry run - no files were actually deleted)" -ForegroundColor Yellow }
