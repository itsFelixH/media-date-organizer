Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source,
    [string]$dest = (Join-Path -Path $source -ChildPath "Sorted"),
    [string]$format = "yyyy/yyyy-MM/yyyy-MM-dd",
    [switch]$DryRun
)

# --- Configuration ---
# Known Windows Property System IDs for date properties (in priority order)
$knownDateIds = @(
    12,   # System.Photo.DateTaken (Date Taken)
    208,  # System.Media.DateEncoded (Media Created)
    4     # System.DateCreated (Date Created - often reflects file system creation date)
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

    # Check known date properties in priority order
    foreach ($id in $knownDateIds) {
        $dateValue = $dir.GetDetailsof($file, $id)
        if (-not [string]::IsNullOrWhiteSpace($dateValue)) {
            $cleanValue = $dateValue -replace "`u{200e}" -replace "`u{200f}"
            $parsedDate = $null
            if ([DateTime]::TryParse($cleanValue, [ref]$parsedDate)) {
                # Found a valid date for this priority, return it immediately
                return $parsedDate
            }
        }
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
        if ($DryRun) {
            if (!(Test-Path -PathType Container -Path $destinationPath)) {
                Write-Host "[DRY RUN] Would create directory: $destinationPath"
            }
        } elseif (!(Test-Path -PathType Container -Path $destinationPath)) {
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

        if ($DryRun) {
            Write-Host "[DRY RUN] Would move '$($fileInfo.FullName)' to '$finalDestinationFile'"
        } else {
            Write-Host "Moving to $finalDestinationFile"
            Move-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force
        }
    }
    catch {
        Write-Error "Error processing '$($fileInfo.FullName)': $_"
    }
}

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
Remove-Variable shell, namespaceCache