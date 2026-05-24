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
    12,    # System.Photo.DateTaken (Date Taken - common for photos)
    36879, # System.Photo.DateTimeOriginal (EXIF Date/Time Original - most reliable for photos)
    208,   # System.Media.DateEncoded (Media Created - common for videos)
    17,    # System.RecordedDate (Recorded Date - often for audio/video)
    3,     # System.ItemDate (General Item Date - good fallback for any media type)
    15,    # System.DateModified (Date Modified - useful if EXIF is missing)
    4      # System.DateCreated (File System Creation Date - least reliable, last resort fallback)
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

    # 1. Try extracting date from filename (Highest Priority)
    # Matches YYYYMMDD, YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD
    if ($FileObject.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $dateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
        $parsedDate = $null
        if ([DateTime]::TryParse($dateStr, [ref]$parsedDate)) {
            return $parsedDate
        }
    }

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
$files = Get-ChildItem -Path $source -Recurse -File | Where-Object { $_.FullName -notlike "$dest*" }
$totalFiles = $files.Count

if ($totalFiles -eq 0) {
    Write-Host "No files found to process in '$source'."
    return
}

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