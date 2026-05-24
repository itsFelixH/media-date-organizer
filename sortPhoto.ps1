Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source,
    [string]$dest = (Join-Path -Path $source -ChildPath "Sorted"),
    [string]$format = "yyyy/yyyy-MM/yyyy-MM-dd"
)

# --- Configuration ---
# Known Windows Property System IDs for date properties
$knownDateIds = @(
    12,   # System.Photo.DateTaken (Date Taken)
    208,  # System.Media.DateEncoded (Media Created)
    4,    # System.DateCreated (Date Created)
    15    # System.DateModified (Date Modified)
)

# --- Setup ---
$shell = New-Object -ComObject Shell.Application
$namespaceCache = @{}

# --- Functions ---
function Get-CachedNamespace {
    param([string]$path)
    if (-not $namespaceCache.ContainsKey($path)) {
        $namespaceCache[$path] = $shell.NameSpace($path)
    }
    return $namespaceCache[$path]
}

function Get-File-Date {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileObject
    )

    $dir = Get-CachedNamespace $FileObject.Directory.FullName
    $file = $dir.ParseName($FileObject.Name)
    $potentialDates = [System.Collections.Generic.List[datetime]]::new()

    # Check all known date properties
    foreach ($id in $knownDateIds) {
        $dateValue = $dir.GetDetailsof($file, $id)
        if (-not [string]::IsNullOrWhiteSpace($dateValue)) {
            $cleanValue = $dateValue -replace "`u{200e}" -replace "`u{200f}"
            $parsedDate = $null
            if ([DateTime]::TryParse($cleanValue, [ref]$parsedDate)) {
                $potentialDates.Add($parsedDate)
            }
        }
    }

    if ($potentialDates.Count -gt 0) {
        $potentialDates.Sort()
        return $potentialDates[0]
    }

    # Fallback to file system dates
    Write-Warning "No metadata dates found for $($FileObject.Name). Using file creation time."
    return $FileObject.CreationTime
}

# --- Main Processing ---
$files = Get-ChildItem -Path $source -Recurse -File
$totalFiles = $files.Count
$processedCount = 0

foreach ($fileInfo in $files) {
    $processedCount++
    Write-Progress -Activity "Organizing Media" -Status "Processing $($fileInfo.Name)" -PercentComplete ($processedCount/$totalFiles*100)
    Write-Host "[$processedCount/$totalFiles] Processing $($fileInfo.Name)"

    try {
        $date = Get-File-Date -FileObject $fileInfo
        $destinationSubFolder = Get-Date -Date $date -Format $format
        $destinationPath = Join-Path -Path $dest -ChildPath $destinationSubFolder

        # Create destination directory
        if (!(Test-Path -PathType Container -Path $destinationPath)) {
            New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
        }

        # Handle filename conflicts
        $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $fileInfo.Name
        $newNameIndex = 1
        while (Test-Path -LiteralPath $finalDestinationFile -PathType Leaf) {
            $newName = "{0}_{1}{2}" -f $fileInfo.BaseName, $newNameIndex, $fileInfo.Extension
            $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $newName
            $newNameIndex++
        }

        # Skip if source and destination are same
        if ($fileInfo.FullName -eq $finalDestinationFile) {
            Write-Host "Skipping: Source and destination are identical"
            continue
        }

        # Move file
        Write-Host "Moving to $finalDestinationFile"
        Move-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force
    }
    catch {
        Write-Error "Error processing '$($fileInfo.FullName)': $_"
    }
}

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
Remove-Variable shell, namespaceCache