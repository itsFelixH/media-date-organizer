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
.EXAMPLE
    .\Get-ExtensionSummary.ps1 -SourcePath "." | Format-Table -AutoSize
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
    Select-Object @{Name = "Extension"; Expression = { $_.Name } }, Count |
    Sort-Object Count -Descending

if ($extensionStats.Count -eq 0) {
    Write-Host "No files found." -ForegroundColor Yellow
    return
}

Write-Host "`nFile Extension Summary:" -ForegroundColor Cyan
$extensionStats | Format-Table -AutoSize

Write-Host "Total: $($extensionStats | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) files across $($extensionStats.Count) extensions."
