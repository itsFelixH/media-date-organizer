[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$SourcePath = "F:\Bilder\Fotos",

    [Parameter(Mandatory=$false)]
    [string[]]$Extensions = @(".webp", ".jfif", ".heic", ".bmp", ".3gp", ".mov", ".avi"),

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

Write-Host "Scanning for media originals to clean up in $SourcePath..." -ForegroundColor Cyan

# Optimized search for the target extensions
$includePatterns = $Extensions | ForEach-Object { "*$_" }
$originals = Get-ChildItem -Path $SourcePath -Include $includePatterns -Recurse -File
$totalFound = $originals.Count

if ($totalFound -eq 0) {
    Write-Host "No legacy files found matching extensions: $($Extensions -join ', ')" -ForegroundColor Green
    return
}

$deletedCount = 0
$skippedCount = 0

# Grouping for target extension logic
$photoExtensions = @(".webp", ".jfif", ".heic", ".bmp")

foreach ($file in $originals) {
    $ext = $file.Extension.ToLower()
    # Determine if we should look for a .jpg (photo) or .mp4 (video)
    $targetExt = if ($ext -in $photoExtensions) { ".jpg" } else { ".mp4" }
    $targetPath = Join-Path -Path $file.DirectoryName -ChildPath ($file.BaseName + $targetExt)

    if (Test-Path -LiteralPath $targetPath) {
        $targetLabel = $targetExt.ToUpper().TrimStart('.')
        Write-Host "Found $targetLabel for: $($file.Name) - Safe to delete." -ForegroundColor Gray
        
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would delete $($file.FullName)" -ForegroundColor Yellow
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

Write-Host "`n--- Media Cleanup Summary ---" -ForegroundColor Cyan
Write-Host "Originals Found: $totalFound"
Write-Host "Deleted:         $deletedCount" -ForegroundColor Green
Write-Host "Skipped:         $skippedCount" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "This was a DRY RUN. No files were actually deleted." -ForegroundColor Yellow
}