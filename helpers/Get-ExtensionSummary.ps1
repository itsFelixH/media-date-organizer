<#
.SYNOPSIS
    Recursively counts and summarizes file extensions in a directory.
.DESCRIPTION
    Scans a folder tree and displays a table of all file extensions with their counts,
    sorted by frequency. Useful for auditing media collections before processing.
.PARAMETER SourcePath
    The directory to scan. Defaults to the current directory.
.EXAMPLE
    .\Get-ExtensionSummary.ps1 -SourcePath "D:\Photos"
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [Alias('Path')]
    [string]$SourcePath = "."
)

$resolvedPath = (Resolve-Path -Path $SourcePath).Path
Write-Host "Scanning $resolvedPath..." -ForegroundColor Cyan

$extensionStats = Get-ChildItem -Path $resolvedPath -File -Recurse |
    Group-Object { if ($_.Extension) { $_.Extension.ToLower() } else { "(no extension)" } } |
    Select-Object @{Name = "Extension"; Expression = { $_.Name } },
                  Count,
                  @{Name = "Size"; Expression = {
                      $bytes = ($_.Group | Measure-Object -Property Length -Sum).Sum
                      if ($bytes -ge 1GB) { "{0:N1} GB" -f ($bytes / 1GB) }
                      elseif ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) }
                      elseif ($bytes -ge 1KB) { "{0:N1} KB" -f ($bytes / 1KB) }
                      else { "$bytes B" }
                  }} |
    Sort-Object Count -Descending

if ($extensionStats.Count -eq 0) {
    Write-Host "No files found." -ForegroundColor Yellow
    return
}

Write-Host "`nFile Extension Summary:" -ForegroundColor Cyan
$extensionStats | Format-Table -AutoSize

$totalFiles = ($extensionStats | Measure-Object -Property Count -Sum).Sum
$totalBytes = Get-ChildItem -Path $resolvedPath -File -Recurse | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum
$totalSize = if ($totalBytes -ge 1GB) { "{0:N1} GB" -f ($totalBytes / 1GB) }
             elseif ($totalBytes -ge 1MB) { "{0:N1} MB" -f ($totalBytes / 1MB) }
             else { "{0:N1} KB" -f ($totalBytes / 1KB) }

Write-Host "Total: $totalFiles files ($totalSize) across $($extensionStats.Count) extensions."
