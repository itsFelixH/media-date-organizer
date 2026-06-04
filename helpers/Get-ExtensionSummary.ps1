# Script to recursively count files by extension in F:\Bilder\Fotos
$sourcePath = "F:\Bilder\Fotos"

if (Test-Path -Path $sourcePath -PathType Container) {
    Write-Host "Scanning $sourcePath..."
    
    $extensionStats = Get-ChildItem -Path $sourcePath -File -Recurse | 
        Group-Object { if ($_.Extension) { $_.Extension.ToLower() } else { "(no extension)" } } | 
        Select-Object @{Name="Extension"; Expression={$_.Name}}, Count | 
        Sort-Object Count -Descending

    Write-Host "`nFile Extension Summary:"
    $extensionStats | Format-Table -AutoSize
} else {
    Write-Error "Path '$sourcePath' does not exist or is not a directory."
}
