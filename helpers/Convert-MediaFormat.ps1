<#
.SYNOPSIS
    Converts legacy media formats to standardized formats (JPG/MP4) using ffmpeg.
.DESCRIPTION
    Scans a directory for media files with legacy or non-standard extensions and converts
    them to universally compatible formats:
      - Photos (.webp, .jfif, .heic, .bmp) -> .jpg
      - Videos (.3gp, .mov, .avi) -> .mp4

    Preserves metadata where possible. Handles filename conflicts automatically.
.PARAMETER SourcePath
    The directory to scan for convertible files. Defaults to the current directory.
.PARAMETER Extensions
    File extensions to convert. Defaults to: .webp, .jfif, .heic, .bmp, .3gp, .mov, .avi
.PARAMETER KeepOriginal
    Keep the original file after successful conversion instead of deleting it.
.PARAMETER DryRun
    Preview conversions without executing them.
.EXAMPLE
    .\Convert-MediaFormat.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Convert-MediaFormat.ps1 -SourcePath "D:\Photos" -KeepOriginal
.EXAMPLE
    .\Convert-MediaFormat.ps1 -SourcePath "D:\Photos" -Extensions @(".heic", ".webp")
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
    [switch]$KeepOriginal,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# --- Dependency Check ---
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found. Please install ffmpeg and add it to your PATH."
    return
}

$resolvedPath = (Resolve-Path -Path $SourcePath).Path

# Find files matching the target extensions
$includePatterns = $Extensions | ForEach-Object { "*$_" }
$filesToConvert = Get-ChildItem -Path $resolvedPath -Include $includePatterns -Recurse -File
$total = $filesToConvert.Count

if ($total -eq 0) {
    Write-Host "No files found matching: $($Extensions -join ', ')" -ForegroundColor Cyan
    return
}

Write-Host "Found $total media files to convert in $resolvedPath." -ForegroundColor Cyan

$photoExtensions = @(".webp", ".jfif", ".heic", ".bmp")
$successCount = 0
$errorCount = 0
$i = 0

foreach ($file in $filesToConvert) {
    $i++
    Write-Progress -Activity "Converting Media" -Status "Processing $($file.Name)" -PercentComplete ($i / $total * 100)

    $ext = $file.Extension.ToLower()
    $isPhoto = $ext -in $photoExtensions
    $targetExt = if ($isPhoto) { ".jpg" } else { ".mp4" }

    $outputFile = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + $targetExt)

    # Handle filename conflicts
    if (Test-Path -LiteralPath $outputFile) {
        $n = 1
        while (Test-Path -LiteralPath (Join-Path -Path $file.DirectoryName -ChildPath "$($file.BaseName)_$n$targetExt")) {
            $n++
        }
        $outputFile = Join-Path -Path $file.DirectoryName -ChildPath "$($file.BaseName)_$n$targetExt"
    }

    Write-Host "[$i/$total] Converting: $($file.Name) -> $(Split-Path $outputFile -Leaf)"

    # Determine FFmpeg arguments
    if ($isPhoto) {
        $ffmpegArgs = "-v error -i `"$($file.FullName)`" -map_metadata 0 -q:v 2 `"$outputFile`""
    } else {
        $ffmpegArgs = "-v error -i `"$($file.FullName)`" -map_metadata 0 -c:v libx264 -crf 23 -c:a aac -pix_fmt yuv420p `"$outputFile`""
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] ffmpeg $ffmpegArgs" -ForegroundColor Gray
        $successCount++
        continue
    }

    # Execute conversion
    Invoke-Expression "ffmpeg $ffmpegArgs"

    # Verify output
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputFile)) {
        $newFileInfo = Get-Item -LiteralPath $outputFile
        if ($newFileInfo.Length -gt 0) {
            Write-Host "  Success!" -ForegroundColor Green
            $successCount++

            if (-not $KeepOriginal) {
                Write-Host "  Deleting original..." -ForegroundColor DarkGray
                Remove-Item -LiteralPath $file.FullName -Force
            }
        } else {
            Write-Host "  Error: Output file is 0 bytes." -ForegroundColor Red
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
            $errorCount++
        }
    } else {
        Write-Host "  Error: ffmpeg failed to convert this file." -ForegroundColor Red
        $errorCount++
    }
}

Write-Progress -Activity "Converting Media" -Completed

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Processed: $total"
Write-Host "Success:   $successCount" -ForegroundColor Green
Write-Host "Errors:    $errorCount" -ForegroundColor ($errorCount -gt 0 ? "Red" : "Gray")
if ($DryRun) { Write-Host "(Dry run - no files were actually converted)" -ForegroundColor Yellow }
