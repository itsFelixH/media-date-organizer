Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source,
    [string]$dest = (Join-Path -Path $source -ChildPath "Sorted"),
    [string]$format = "yyyy\\yyyy-MM\\yyyy-MM-dd",
    [string]$config = (Join-Path -Path $PSScriptRoot -ChildPath "config.ini"),
    [switch]$DryRun
)

# --- Configuration ---
# Map of friendly names to Windows Shell property IDs
$metadataPropertyMap = @{
    "DateTaken"        = 12     # System.Photo.DateTaken
    "DateTimeOriginal" = 36879  # System.Photo.DateTimeOriginal (EXIF)
    "MediaCreated"     = 208    # System.Media.DateEncoded
    "MediaCreatedAlt"  = 209    # System.Media.DateEncoded (alternate locale ID)
    "RecordedDate"     = 17     # System.RecordedDate
    "ItemDate"         = 3      # System.ItemDate
    "DateModified"     = 15     # System.DateModified
    "DateCreated"      = 4      # System.DateCreated (file system)
}

# Defaults
$priority = @("metadata", "filename", "filesystem")
$knownDateIds = @(12, 36879, 208, 209, 17, 3, 15, 4)
$cleanupEmptyDirs = $true
$fileAction = "move"
$dateFormat = $format
$includeExtensions = @()
$excludeExtensions = @()
$conflictStrategy = "rename"

# Load config file if it exists
if (Test-Path -Path $config -PathType Leaf) {
    Write-Verbose "Loading configuration from: $config"
    $currentSection = $null
    $configPriority = @()
    $configDateIds = @()

    foreach ($line in Get-Content -Path $config) {
        $line = $line.Trim()
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        # Section header
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $Matches[1]
            continue
        }
        # Values under sections
        switch ($currentSection) {
            "Priority" {
                if ($line -in @("filename", "metadata", "filesystem")) {
                    $configPriority += $line
                } else {
                    Write-Warning "Unknown priority strategy '$line' in config. Available: filename, metadata, filesystem"
                }
            }
            "MetadataProperties" {
                if ($metadataPropertyMap.ContainsKey($line)) {
                    $configDateIds += $metadataPropertyMap[$line]
                } else {
                    Write-Warning "Unknown metadata property '$line' in config. Available: $($metadataPropertyMap.Keys -join ', ')"
                }
            }
            "Options" {
                if ($line -match '^(.+?)=(.+)$') {
                    $key = $Matches[1].Trim()
                    $val = $Matches[2].Trim()
                    switch ($key) {
                        "CleanupEmptyDirs" { $cleanupEmptyDirs = $val -eq "true" }
                        "FileAction" {
                            if ($val -in @("move", "copy")) { $fileAction = $val }
                            else { Write-Warning "Invalid FileAction '$val'. Available: move, copy" }
                        }
                        "DateFormat" { $dateFormat = $val }
                        "IncludeExtensions" {
                            if ($val -ne "*" -and $val -ne "") {
                                $includeExtensions = $val.Split(',') | ForEach-Object { $_.Trim().TrimStart('.').ToLower() }
                            }
                        }
                        "ExcludeExtensions" {
                            if ($val -ne "") {
                                $excludeExtensions = $val.Split(',') | ForEach-Object { $_.Trim().TrimStart('.').ToLower() }
                            }
                        }
                        "ConflictStrategy" {
                            if ($val -in @("rename", "skip", "overwrite")) { $conflictStrategy = $val }
                            else { Write-Warning "Invalid ConflictStrategy '$val'. Available: rename, skip, overwrite" }
                        }
                        default { Write-Warning "Unknown option '$key' in config." }
                    }
                }
            }
        }
    }
    # Override defaults only if config had entries
    if ($configPriority.Count -gt 0) { $priority = $configPriority }
    if ($configDateIds.Count -gt 0) { $knownDateIds = $configDateIds }
} else {
    Write-Verbose "No config file found at '$config'. Using defaults."
}


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

function Get-DateFromFilename {
    Param ([System.IO.FileInfo]$FileObject)
    # Matches YYYYMMDD, YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD
    if ($FileObject.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $dateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
        $parsedDate = [System.DateTime]::MinValue
        if ([DateTime]::TryParse($dateStr, [ref]$parsedDate)) {
            return $parsedDate
        }
    }
    return $null
}

function Get-DateFromMetadata {
    Param ([System.IO.FileInfo]$FileObject)
    $dir = Get-CachedNamespace $FileObject.Directory.FullName
    $file = $dir.ParseName($FileObject.Name)

    foreach ($id in $knownDateIds) {
        $dateValue = $dir.GetDetailsof($file, $id)
        if (-not [string]::IsNullOrWhiteSpace($dateValue)) {
            $cleanValue = $dateValue -replace "[\u200e\u200f\u202a-\u202e]", ""
            $parsedDate = [System.DateTime]::MinValue
            if ([DateTime]::TryParse($cleanValue, [ref]$parsedDate)) {
                return $parsedDate
            }
        }
    }
    return $null
}

function Get-DateFromFilesystem {
    Param ([System.IO.FileInfo]$FileObject)
    return $FileObject.CreationTime
}

function Get-File-Date {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileObject
    )

    foreach ($strategy in $priority) {
        $result = switch ($strategy) {
            "filename"   { Get-DateFromFilename -FileObject $FileObject }
            "metadata"   { Get-DateFromMetadata -FileObject $FileObject }
            "filesystem" { Get-DateFromFilesystem -FileObject $FileObject }
            default      { Write-Warning "Unknown priority strategy: $strategy"; $null }
        }
        if ($null -ne $result) {
            return $result
        }
    }

    # Ultimate fallback if all configured strategies fail
    Write-Warning "All strategies failed for $($FileObject.Name). Using file creation time."
    return $FileObject.CreationTime
}

# --- Main Processing ---
$files = Get-ChildItem -Path $source -Recurse -File | Where-Object { $_.FullName -notlike "$dest*" }

# Apply extension filters
if ($includeExtensions.Count -gt 0) {
    $files = $files | Where-Object { $_.Extension.TrimStart('.').ToLower() -in $includeExtensions }
}
if ($excludeExtensions.Count -gt 0) {
    $files = $files | Where-Object { $_.Extension.TrimStart('.').ToLower() -notin $excludeExtensions }
}

$totalFiles = @($files).Count

if ($totalFiles -eq 0) {
    Write-Host "No files found to process in '$source'."
    return
}

$processedCount = 0
$movedCount = 0
$skippedCount = 0
$errorCount = 0

foreach ($fileInfo in $files) {
    $processedCount++
    Write-Progress -Activity "Organizing Media" -Status "Processing $($fileInfo.Name)" -PercentComplete ($processedCount/$totalFiles*100)
    Write-Host "[$processedCount/$totalFiles] Processing $($fileInfo.Name)"

    try {
        $date = Get-File-Date -FileObject $fileInfo
        $destinationSubFolder = Get-Date -Date $date -Format $dateFormat
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
        if (Test-Path -LiteralPath $finalDestinationFile -PathType Leaf) {
            switch ($conflictStrategy) {
                "skip" {
                    Write-Host "Skipping (conflict): $($fileInfo.Name) already exists at destination"
                    $skippedCount++
                    continue
                }
                "overwrite" {
                    # Keep the same path, -Force will overwrite
                }
                "rename" {
                    $newNameIndex = 1
                    while (Test-Path -LiteralPath $finalDestinationFile -PathType Leaf) {
                        $newName = "{0}_{1}{2}" -f $fileInfo.BaseName, $newNameIndex, $fileInfo.Extension
                        $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $newName
                        $newNameIndex++
                    }
                }
            }
        }

        # Skip if source and destination are same
        if ($fileInfo.FullName -eq $finalDestinationFile) {
            Write-Host "Skipping: Source and destination are identical"
            $skippedCount++
            continue
        }

        if ($DryRun) {
            Write-Host "[DRY RUN] Would $fileAction '$($fileInfo.FullName)' to '$finalDestinationFile'"
        } else {
            Write-Host "$($fileAction.Substring(0,1).ToUpper() + $fileAction.Substring(1))ing to $finalDestinationFile"
            if ($fileAction -eq "copy") {
                Copy-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force
            } else {
                Move-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force
            }
        }
        $movedCount++
    }
    catch {
        Write-Error "Error processing '$($fileInfo.FullName)': $_"
        $errorCount++
    }
}

# --- Cleanup empty directories ---
if (-not $DryRun -and $cleanupEmptyDirs -and $fileAction -eq "move") {
    Get-ChildItem -Path $source -Recurse -Directory |
        Where-Object { $_.FullName -notlike "$dest*" } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if ((Get-ChildItem -Path $_.FullName -Force).Count -eq 0) {
                Write-Verbose "Removing empty directory: $($_.FullName)"
                Remove-Item -Path $_.FullName -Force
            }
        }
}

# --- Summary ---
$actionLabel = if ($fileAction -eq "copy") { "Copied" } else { "Moved" }
Write-Host ""
Write-Host "--- Summary ---"
Write-Host "Total files:  $totalFiles"
Write-Host "${actionLabel}:      $movedCount"
Write-Host "Skipped:      $skippedCount"
Write-Host "Errors:       $errorCount"
if ($DryRun) { Write-Host "(Dry run - no files were actually $($fileAction)d)" }

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
Remove-Variable shell, namespaceCache