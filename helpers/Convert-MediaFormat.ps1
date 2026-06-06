<#
.SYNOPSIS
    Converts legacy media formats to standardized formats (JPG/MP4) using ffmpeg.
.DESCRIPTION
    Scans a directory for media files with legacy or non-standard extensions and converts
    them to universally compatible formats:
      - Photos (.webp, .jfif, .heic, .bmp) -> .jpg
      - Videos (.3gp, .mov, .avi) -> .mp4

    Videos already encoded in H.264/H.265 are remuxed (container change only) instead of
    re-encoded, which is significantly faster and lossless.

    Preserves metadata where possible. Handles filename conflicts automatically.
    Originals are kept by default unless -RemoveOriginal is specified.
.PARAMETER SourcePath
    The directory to scan for convertible files. Defaults to the current directory.
.PARAMETER Extensions
    File extensions to convert. Defaults to: .webp, .jfif, .heic, .bmp, .3gp, .mov, .avi
.PARAMETER RemoveOriginal
    Delete the original file after successful conversion. By default originals are kept.
.PARAMETER DryRun
    Preview conversions without executing them.
.EXAMPLE
    .\Convert-MediaFormat.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Convert-MediaFormat.ps1 -SourcePath "D:\Photos" -RemoveOriginal
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
    [switch]$RemoveOriginal,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# --- Dependency Check ---
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found. Please install ffmpeg and add it to your PATH."
    return
}

$hasFFprobe = [bool](Get-Command ffprobe -ErrorAction SilentlyContinue)
if (-not $hasFFprobe) {
    Write-Warning "ffprobe not found. Video codec detection disabled — all videos will be re-encoded."
    Write-Warning "Install ffprobe (usually bundled with ffmpeg) to enable smart remuxing."
    Write-Warning ""
}

# Check HEIC support if needed
$heicExtensions = @(".heic", ".heif")
$needsHeic = ($Extensions | Where-Object { $_ -in $heicExtensions }).Count -gt 0

if ($needsHeic) {
    $decoders = & ffmpeg -decoders 2>&1 | Out-String
    if ($decoders -notmatch 'hevc' -and $decoders -notmatch 'libheif') {
        Write-Warning "Your ffmpeg build may not support HEIC/HEIF decoding (no libheif or hevc decoder found)."
        Write-Warning "HEIC files may fail to convert. Consider installing a build with libheif support."
        Write-Warning ""
    }
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

$photoExtensions = @(".webp", ".jfif", ".heic", ".heif", ".bmp")
$remuxableCodecs = @("h264", "hevc", "h265")
$successCount = 0
$remuxCount = 0
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

    # Determine FFmpeg arguments
    if ($isPhoto) {
        $ffmpegArgs = @("-v", "error", "-n", "-i", $file.FullName, "-map_metadata", "0", "-q:v", "2", $outputFile)
        $mode = "convert"
    } else {
        # Probe video codec to decide: remux or re-encode
        $mode = "convert"
        $videoCodec = ""

        if ($hasFFprobe) {
            $probeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 $file.FullName 2>&1
            $videoCodec = ($probeOutput | Out-String).Trim().ToLower()
        }

        if ($videoCodec -in $remuxableCodecs) {
            # Video codec is MP4-compatible — remux video, re-encode audio to AAC for compatibility
            $ffmpegArgs = @("-v", "error", "-n", "-i", $file.FullName, "-map_metadata", "0", "-c:v", "copy", "-c:a", "aac", $outputFile)
            $mode = "remux"
        } else {
            # Re-encode to H.264 + AAC
            $ffmpegArgs = @("-v", "error", "-n", "-i", $file.FullName, "-map_metadata", "0", "-c:v", "libx264", "-crf", "23", "-c:a", "aac", "-pix_fmt", "yuv420p", $outputFile)
        }
    }

    $modeLabel = if ($mode -eq "remux") { "Remuxing" } else { "Converting" }
    Write-Host "[$i/$total] ${modeLabel}: $($file.Name) -> $(Split-Path $outputFile -Leaf)"

    if ($DryRun) {
        Write-Host "  [DRY RUN] ffmpeg $($ffmpegArgs -join ' ')" -ForegroundColor Gray
        $successCount++
        if ($mode -eq "remux") { $remuxCount++ }
        continue
    }

    # Execute conversion using call operator (safe for special characters in paths)
    & ffmpeg @ffmpegArgs 2>&1 | ForEach-Object { Write-Verbose $_ }

    # Verify output
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputFile)) {
        $newFileInfo = Get-Item -LiteralPath $outputFile
        if ($newFileInfo.Length -gt 0) {
            Write-Host "  Success!" -ForegroundColor Green
            $successCount++
            if ($mode -eq "remux") { $remuxCount++ }

            if ($RemoveOriginal) {
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
if ($remuxCount -gt 0) {
    Write-Host "  (of which $remuxCount remuxed without re-encoding)" -ForegroundColor DarkGray
}
Write-Host "Errors:    $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
if (-not $RemoveOriginal) { Write-Host "Originals kept. Use -RemoveOriginal to delete after conversion." -ForegroundColor DarkGray }
if ($DryRun) { Write-Host "(Dry run - no files were actually converted)" -ForegroundColor Yellow }
