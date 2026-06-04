<#
.SYNOPSIS
    Removes Turkish copy-suffix artifacts from filenames.
.DESCRIPTION
    Scans a directory recursively and removes the Turkish Windows copy-suffix pattern
    ("adl? dosyan?n kopyas?...") that gets appended when files are duplicated in
    Turkish-locale Windows systems.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.PARAMETER DryRun
    Preview changes without renaming any files.
.EXAMPLE
    .\Repair-FileName.ps1 -SourcePath "D:\Photos" -DryRun
.EXAMPLE
    .\Repair-FileName.ps1 -SourcePath "D:\Photos"
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
Write-Host "Scanning for copy-suffix artifacts in $resolvedPath..." -ForegroundColor Cyan

$pattern = '\s+adl.\s+dosyan.n\s+kopyas.*$'
$successCount = 0
$errorCount = 0
$totalChecked = 0

Get-ChildItem -LiteralPath $resolvedPath -File -Recurse | ForEach-Object {
    $totalChecked++
    $newName = $_.Name -replace $pattern, ''

    if ($_.Name -ne $newName) {
        Write-Host "Repairing: $($_.Name) -> $newName"

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would rename to $newName" -ForegroundColor Gray
            $successCount++
            return
        }

        try {
            $_ | Rename-Item -NewName $newName -ErrorAction Stop
            $successCount++
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Scanned:  $totalChecked files"
Write-Host "Repaired: $successCount"
Write-Host "Errors:   $errorCount" -ForegroundColor ($errorCount -gt 0 ? "Red" : "Gray")
if ($DryRun) { Write-Host "(Dry run - no files were actually renamed)" -ForegroundColor Yellow }
