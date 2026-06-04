[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$SourcePath = "F:\Bilder\Fotos",
    [string[]]$Extensions = @(".webp", ".jfif", ".heic", ".bmp", ".3gp", ".mov", ".avi"),
    [switch]$KeepOriginal,
    [switch]$DryRun
)

# Check for ffmpeg dependency
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found. Please install ffmpeg and add it to your PATH."
    return
}

# Find files matching the target extensions (optimized search)
$includePatterns = $Extensions | ForEach-Object { "*$_" }
$filesToConvert = Get-ChildItem -Path $SourcePath -Include $includePatterns -Recurse -File
$total = $filesToConvert.Count

if ($total -eq 0) {
    Write-Host "No files found matching: $($Extensions -join ', ')" -ForegroundColor Cyan
    return
}

Write-Host "Found $total media files to standardize." -ForegroundColor Cyan

$successCount = 0
$i = 0
$errorCount = 0

foreach ($file in $filesToConvert) {
    $i++
    Write-Progress -Activity "Converting Media" -Status "Processing $($file.Name)" -PercentComplete ($i / $total * 100)
    
    $ext = $file.Extension.ToLower()
    $isPhoto = $ext -in @(".webp", ".jfif", ".heic", ".bmp")
    $targetExt = if ($isPhoto) { ".jpg" } else { ".mp4" }
    
    $outputFile = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + $targetExt)

    # Handle potential name conflict
    if (Test-Path -LiteralPath $outputFile) {
        $n = 1
        while (Test-Path -LiteralPath (Join-Path -Path $file.DirectoryName -ChildPath "$($file.BaseName)_$n$targetExt")) {
            $n++
        }
        $outputFile = Join-Path -Path $file.DirectoryName -ChildPath "$($file.BaseName)_$n$targetExt"
    }

    Write-Host "[$i/$total] Converting: $($file.Name) -> $(Split-Path $outputFile -Leaf)"

    # Determine FFmpeg arguments based on type
    if ($isPhoto) {
        # High quality JPEG output
        $ffmpegArgs = "-v error -i `"$($file.FullName)`" -map_metadata 0 -q:v 2 `"$outputFile`""
    } else {
        # H.264 video + AAC audio for universal compatibility
        $ffmpegArgs = "-v error -i `"$($file.FullName)`" -map_metadata 0 -c:v libx264 -crf 23 -c:a aac -pix_fmt yuv420p `"$outputFile`""
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] ffmpeg $ffmpegArgs" -ForegroundColor Gray
        continue
    }

    # Execute conversion
    Invoke-Expression "ffmpeg $ffmpegArgs"

    # --- Verification ---
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputFile)) {
        $newFileInfo = Get-Item -LiteralPath $outputFile
        if ($newFileInfo.Length -gt 0) {
            Write-Host "  Success!" -ForegroundColor Green
            $successCount++

            if (-not $KeepOriginal) {
                if ($DryRun) {
                    Write-Host "  [DRY RUN] Would delete original: $($file.Name)" -ForegroundColor Yellow
                } else {
                    Write-Host "  Deleting original..." -ForegroundColor DarkGray
                    Remove-Item -LiteralPath $file.FullName -Force
                }
            }
        } else {
            Write-Host "  Error: Output file is 0 bytes." -ForegroundColor Red
            $errorCount++
        }
    } else {
        Write-Host "  Error: ffmpeg failed to convert this file." -ForegroundColor Red
        $errorCount++
    }
}

Write-Progress -Activity "Converting Media" -Completed
Write-Host "`n--- Conversion Summary ---" -ForegroundColor Cyan
Write-Host "Processed: $total"
Write-Host "Success:   $successCount" -ForegroundColor Green
Write-Host "Errors:    $errorCount" -ForegroundColor ($errorCount -gt 0 ? "Red" : "Gray")

if ($DryRun) {
    Write-Host "This was a DRY RUN. No files were actually converted." -ForegroundColor Yellow
}