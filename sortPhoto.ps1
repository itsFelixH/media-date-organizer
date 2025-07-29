Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source,
    [string]$dest = (Join-Path -Path $source -ChildPath "Sorted"),
    [string]$format = "yyyy/yyyy-MM/yyyy-MM-dd"
)

# --- Setup ---
# Using a COM object is slow. We can optimize by caching the property indexes.
# This avoids calling the expensive GetDetailsof() in a loop for every file.
$shell = New-Object -ComObject Shell.Application
$datePropertyIndexes = @{
    DateTaken  = -1
    MediaCreated = -1
    OtherDates = [System.Collections.Generic.List[int]]::new()
}

Write-Host "Analyzing metadata properties to find date fields..."
# Use a temporary folder to query property names. The source folder might be huge.
$tempDirForAnalysis = $shell.NameSpace($env:TEMP)
0..287 | ForEach-Object {
    # We query the property NAME, which is slow, but we only do it ONCE here.
    $name = $tempDirForAnalysis.GetDetailsof($null, $_)
    if ($name) {
        # The property name for "Date taken" is consistent across languages in testing, but the fallback is still useful.
        if ($name -eq 'Date taken') {
            $datePropertyIndexes.DateTaken = $_
        }
        elseif ($name -eq 'Media created') {
            $datePropertyIndexes.MediaCreated = $_
        }
        elseif ($name -match 'date' -or $name -match 'created') {
            $datePropertyIndexes.OtherDates.Add($_)
        }
    }
}
$foundCount = 0
if ($datePropertyIndexes.DateTaken -ne -1) { $foundCount++ }
if ($datePropertyIndexes.MediaCreated -ne -1) { $foundCount++ }
$foundCount += $datePropertyIndexes.OtherDates.Count
Write-Host "Analysis complete. Found $foundCount potential date properties."

# --- Functions ---

function Get-File-Date {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileObject
    )

    $dir = $shell.NameSpace($FileObject.Directory.FullName)
    $file = $dir.ParseName($FileObject.Name)
    # Use a list to collect all possible dates to ensure we find the absolute oldest.
    $potentialDates = [System.Collections.Generic.List[datetime]]::new()

    # Check the primary "Date Taken" property (common for photos).
    if ($datePropertyIndexes.DateTaken -ne -1) {
        $date = Get-Date-Property-Value -Dir $dir -File $file -Index $datePropertyIndexes.DateTaken
        if ($null -ne $date) { $potentialDates.Add($date) }
    }

    # Check the "Media Created" property (common for videos).
    if ($datePropertyIndexes.MediaCreated -ne -1) {
        $date = Get-Date-Property-Value -Dir $dir -File $file -Index $datePropertyIndexes.MediaCreated
        if ($null -ne $date) { $potentialDates.Add($date) }
    }

    # Check all other fallback date properties.
    foreach ($index in $datePropertyIndexes.OtherDates) {
        $date = Get-Date-Property-Value -Dir $dir -File $file -Index $index
        if ($null -ne $date) { $potentialDates.Add($date) }
    }

    if ($potentialDates.Count -gt 0) {
        # Sort the dates and return the oldest one (the first in the sorted list).
        $potentialDates.Sort()
        return $potentialDates[0]
    }

    return $null
}

function Get-Date-Property-Value {
    [CmdletBinding()]
    Param (
        $dir,
        $file,
        $index
    )

    try {
        # These LTR/RTL marks can appear in metadata and break date parsing.
        $value = ($dir.GetDetailsof($file, $index) -replace "`u{200e}") -replace "`u{200f}"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }
        # Using Parse() is more flexible than ParseExact("g", ...) as it handles more formats.
        # The COM object returns dates in the system's current culture format.
        return [DateTime]::Parse($value, [System.Globalization.CultureInfo]::CurrentCulture)
    }
    catch {
        # The value was not a recognizable date, so we return null.
        return $null
    }
}

# --- Main Processing ---
$files = Get-ChildItem -Path $source -Recurse -File
$totalFiles = $files.Count
$processedCount = 0

foreach ($fileInfo in $files) {
    $processedCount++
    Write-Host "[$processedCount/$totalFiles] Processing $($fileInfo.FullName)"

    try {
        $date = Get-File-Date -FileObject $fileInfo

        if ($null -eq $date) {
            Write-Warning "Could not determine date for $($fileInfo.Name). Skipping."
            continue # Skip to the next file
        }

        $destinationSubFolder = Get-Date -Date $date -Format $format
        $destinationPath = Join-Path -Path $dest -ChildPath $destinationSubFolder

        # Create the destination directory if it doesn't exist
        if (!(Test-Path -PathType Container -Path $destinationPath)) {
            New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
        }

        # Determine the final destination file path, handling name collisions
        $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $fileInfo.Name

        if ($fileInfo.FullName -eq $finalDestinationFile) {
            Write-Host "Skipping: Source and destination are the same file. $($fileInfo.FullName)"
            continue
        }

        $newNameIndex = 1
        while (Test-Path -LiteralPath $finalDestinationFile) {
            $newName = "$($fileInfo.BaseName)_$($newNameIndex)$($fileInfo.Extension)"
            $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $newName
            $newNameIndex++
        }

        Write-Host "Moving to $finalDestinationFile"
        # Move-Item is more idiomatic PowerShell than robocopy and handles the rename implicitly.
        Move-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile
    }
    catch {
        Write-Error "An unexpected error occurred while processing '$($fileInfo.FullName)': $_"
    }
}

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
# Clean up the variable to prevent accidental reuse
Remove-Variable shell