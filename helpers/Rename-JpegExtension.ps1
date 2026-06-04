<#
.SYNOPSIS
    Standardizes .jpeg file extensions to .jpg.
.DESCRIPTION
    Recursively finds all .jpeg files and renames them to .jpg.
    Handles case variations (.JPEG, .Jpeg) and filename conflicts at destination.
.PARAMETER SourcePath
    The directory to scan for .jpeg files. Defaults to the current directory.
.PARAMETER DryRun
    Preview changes without renaming any files.
.EXAMPLE
    .\Rename-JpegExtension.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Rename-JpegExtension.ps1 -SourcePath "D:\Photos"
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [Alias('Path')]
    [string]$SourcePath = ".",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$resolvedPath = (Resolve-Path -Path $SourcePath).Path
Write-Host "Scanning for .jpeg files in $resolvedPath..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $resolvedPath -Filter *.jpeg -Recurse -File
$total = $files.Count

if ($total -eq 0) {
    Write-Host "No .jpeg files found." -ForegroundColor Green
    return
}

Write-Host "Found $total files to standardize.`n"

$successCount = 0
$errorCount = 0

foreach ($file in $files) {
    $newName = $file.BaseName + ".jpg"
    $newFullPath = Join-Path -Path $file.DirectoryName -ChildPath $newName

    # Conflict handling: append suffix if target already exists
    if (Test-Path -LiteralPath $newFullPath) {
        $i = 1
        while (Test-Path -LiteralPath $newFullPath) {
            $newName = "$($file.BaseName)_$i.jpg"
            $newFullPath = Join-Path -Path $file.DirectoryName -ChildPath $newName
            $i++
        }
    }

    Write-Host "Renaming: $($file.Name) -> $newName"

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would rename to $newName" -ForegroundColor Gray
        $successCount++
        continue
    }

    try {
        Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
        $successCount++
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Renamed:  $successCount"
Write-Host "Errors:   $errorCount" -ForegroundColor ($errorCount -gt 0 ? "Red" : "Gray")
if ($DryRun) { Write-Host "(Dry run - no files were actually renamed)" -ForegroundColor Yellow }
