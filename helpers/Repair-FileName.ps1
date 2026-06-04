[cmdletbinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [Alias('Path')]
    [String[]]$BasePath = "$PSScriptRoot"
)

Write-Verbose "Searching in: $BasePath"

# We use -LiteralPath to correctly handle the apostrophe in "BSF'26"
(Get-ChildItem -LiteralPath $BasePath -File -Recurse) | ForEach-Object {
    Write-Verbose "Checking file: $($_.Name)"
    $pattern = '\s+adl.\s+dosyan.n\s+kopyas.*$'
    
    $newName = $_.Name -replace $pattern, ''

    if ($_.Name -ne $newName) {
        Write-Verbose "Found match! Renaming to: $newName"
        $_ | Rename-Item -NewName $newName
    }
}