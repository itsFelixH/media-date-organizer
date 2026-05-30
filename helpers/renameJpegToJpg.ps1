[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = "F:\Bilder\Fotos",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

if (-not (Test-Path -Path $SourcePath -PathType Container)) {
    Write-Error "Source path '$SourcePath' does not exist."
    return
}

Write-Host "Scanning for .jpeg files in $SourcePath..." -ForegroundColor Cyan

# Find all files with .jpeg extension (handles variations like .JPEG, .Jpeg)
$files = Get-ChildItem -Path $SourcePath -Filter *.jpeg -Recurse -File
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

    # Conflict Handling: If target .jpg already exists, append a suffix
    if (Test-Path -LiteralPath $newFullPath) {
        $i = 1
        while (Test-Path -LiteralPath $newFullPath) {
            $newName = "$($file.BaseName)_$i.jpg"
            $newFullPath = Join-Path -Path $file.DirectoryName -ChildPath $newName
            $i++
        }
    }

    Write-Host "Standardizing: $($file.Name) -> $newName"
    
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would rename to $newName" -ForegroundColor Gray
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

Write-Host "`nSummary: Standardized $successCount files. Errors: $errorCount." -ForegroundColor Cyan
if ($DryRun) { Write-Host "This was a DRY RUN. No changes were made." -ForegroundColor Yellow }