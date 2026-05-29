<#
.SYNOPSIS
    Analyzes files in a folder and generates a Markdown report of all available shell properties.
#>

Param(
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source = (Join-Path -Path $PSScriptRoot -ChildPath "examples"),
    [string]$config = (Join-Path -Path $PSScriptRoot -ChildPath "config.ini")
)

$reportTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath "property_report_$reportTimestamp.md"

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
$dateStrategy = "priority"

# Load config file if it exists
if (Test-Path -Path $config -PathType Leaf) {
    Write-Host "Loading configuration from: $config"
    $currentSection = $null
    $configPriority = @()
    $configDateIds = @()

    foreach ($line in Get-Content -Path $config) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $Matches[1]
            continue
        }
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
                if ($line -match '^(.+?)=(.*)$') {
                    $key = $Matches[1].Trim()
                    $val = $Matches[2].Trim()
                    switch ($key) {
                        "DateStrategy" {
                            if ($val -in @("priority", "earliest")) { $dateStrategy = $val }
                        }
                    }
                }
            }
        }
    }
    if ($configPriority.Count -gt 0) { $priority = $configPriority }
    if ($configDateIds.Count -gt 0) { $knownDateIds = $configDateIds }
} else {
    Write-Host "No config file found at '$config'. Using defaults."
}

$files = Get-ChildItem -Path $source -File
if ($files.Count -eq 0) {
    Write-Host "No files found in '$source' to analyze."
    return
}

$shell = New-Object -ComObject Shell.Application
$absoluteSource = (Resolve-Path -Path $source).Path
$folder = $shell.NameSpace($absoluteSource)

$mdContent = New-Object System.Collections.Generic.List[string]
$mdContent.Add("# Media Metadata Analysis Report")
$mdContent.Add("Generated on: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
$mdContent.Add("")
$mdContent.Add("## Active Configuration")
$mdContent.Add("- **Priority order:** $($priority -join ' > ')")
$mdContent.Add("- **Date strategy:** $dateStrategy")
$mdContent.Add("- **Metadata properties:** $($knownDateIds -join ', ')")
$mdContent.Add("")
$mdContent.Add("---")
$mdContent.Add("")
$mdContent.Add("This report lists the **Extracted Filename Date** and all date-related Windows Shell properties for files in ``$source``.")
$mdContent.Add("")

# --- Tracking for recommendations ---
$totalAnalyzed = 0
$hasFilenameDate = 0
$hasMetadataDate = 0
$filenameOlderCount = 0
$metadataOlderCount = 0
$datesAgreeCount = 0
$noMetadataFiles = @()
$noFilenameFiles = @()

foreach ($fileInfo in $files) {
    Write-Host "Analyzing: $($fileInfo.Name)..."
    $item = $folder.ParseName($fileInfo.Name)

    # --- Decision Waterfall (uses configured priority) ---
    $strategyResults = @{}
    $finalDateSource = "None Found"
    $finalDateValue = "N/A"

    # Evaluate ALL strategies to show what each would return
    # Filename
    if ($fileInfo.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $strategyResults["filename"] = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }
    # Metadata
    foreach ($id in $knownDateIds) {
        $rawVal = $folder.GetDetailsOf($item, $id)
        if (-not [string]::IsNullOrWhiteSpace($rawVal)) {
            $cleanVal = $rawVal -replace "[\u200e\u200f\u202a-\u202e]", ""
            $tempDate = [System.DateTime]::MinValue
            if ([DateTime]::TryParse($cleanVal, [ref]$tempDate)) {
                $strategyResults["metadata"] = "$cleanVal (ID $id - $($folder.GetDetailsOf($null, $id)))"
                break
            }
        }
    }
    # Filesystem
    $strategyResults["filesystem"] = $fileInfo.CreationTime.ToString()

    # --- Track stats for recommendations ---
    $totalAnalyzed++
    $hasFilenameDateBool = $strategyResults.ContainsKey("filename")
    $hasMetadataDateBool = $strategyResults.ContainsKey("metadata")

    if ($hasFilenameDateBool) { $hasFilenameDate++ } else { $noFilenameFiles += $fileInfo.Name }
    if ($hasMetadataDateBool) { $hasMetadataDate++ } else { $noMetadataFiles += $fileInfo.Name }

    # Compare filename vs metadata dates when both exist
    if ($hasFilenameDateBool -and $hasMetadataDateBool) {
        $fnDate = [System.DateTime]::MinValue
        $mdDate = [System.DateTime]::MinValue
        $fnParsed = [DateTime]::TryParse($strategyResults["filename"], [ref]$fnDate)
        $mdDatePart = ($strategyResults["metadata"] -split '\(')[0].Trim()
        $mdParsed = [DateTime]::TryParse($mdDatePart, [ref]$mdDate)

        if ($fnParsed -and $mdParsed) {
            if ($fnDate.Date -eq $mdDate.Date) {
                $datesAgreeCount++
            } elseif ($fnDate -lt $mdDate) {
                $filenameOlderCount++
            } else {
                $metadataOlderCount++
            }
        }
    }

    # Determine winner based on date strategy
    if ($dateStrategy -eq "earliest") {
        # Parse dates from results and pick earliest
        $earliestDate = $null
        $finalDateSource = "None Found"
        $finalDateValue = "N/A"
        foreach ($strategy in $priority) {
            if ($strategyResults.ContainsKey($strategy)) {
                $valStr = $strategyResults[$strategy]
                $parsedDate = [System.DateTime]::MinValue
                # Try to parse the date portion (before any parenthetical info)
                $datePart = ($valStr -split '\(')[0].Trim()
                if ([DateTime]::TryParse($datePart, [ref]$parsedDate)) {
                    if ($null -eq $earliestDate -or $parsedDate -lt $earliestDate) {
                        $earliestDate = $parsedDate
                        $finalDateSource = $strategy
                        $finalDateValue = $strategyResults[$strategy]
                    }
                }
            }
        }
    } else {
        # Priority mode: first match wins
        foreach ($strategy in $priority) {
            if ($strategyResults.ContainsKey($strategy)) {
                $finalDateSource = $strategy
                $finalDateValue = $strategyResults[$strategy]
                break
            }
        }
    }

    # Ultimate fallback
    if ($finalDateSource -eq "None Found") {
        $finalDateSource = "filesystem (fallback)"
        $finalDateValue = $fileInfo.CreationTime.ToString()
    }

    $mdContent.Add("## File: $($fileInfo.Name)")
    $mdContent.Add("- **Winner:** $finalDateSource > ``$finalDateValue``")
    $mdContent.Add("")
    $mdContent.Add("| Strategy | Result |")
    $mdContent.Add("|---|---|")
    foreach ($strategy in $priority) {
        $val = if ($strategyResults.ContainsKey($strategy)) { $strategyResults[$strategy] } else { "-" }
        $marker = if ($strategy -eq $finalDateSource) { " *" } else { "" }
        $mdContent.Add("| $strategy$marker | $val |")
    }
    $mdContent.Add("")
    $mdContent.Add("| ID | Property Name | Value |")
    $mdContent.Add("|---|---|---|")

    # Iterate through potential Shell property IDs (0-350 covers standard and extended metadata)
    for ($i = 0; $i -le 350; $i++) {
        $name = $folder.GetDetailsOf($null, $i)
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        # Filter: Include if matches keywords OR is part of the priority list
        if ($name -notmatch "date|datum|erstellt|encoded|taken|recorded|zeit" -and $knownDateIds -notcontains $i) {
            continue
        }

        $value = $folder.GetDetailsOf($item, $i)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $priorityTag = if ($knownDateIds -contains $i) { " **(Priority)**" } else { "" }
            # Remove invisible Unicode control characters (BiDi markers) and escape pipes for Markdown
            $cleanValue = ($value -replace "[\u200e\u200f\u202a-\u202e]", "").Replace("|", "\|")
            $mdContent.Add("| $i | $name$priorityTag | $cleanValue |")
        }
    }
    $mdContent.Add("")
}

# --- Recommendations ---
$mdContent.Add("---")
$mdContent.Add("")
$mdContent.Add("## Recommendations")
$mdContent.Add("")
$mdContent.Add("Based on analyzing **$totalAnalyzed files**:")
$mdContent.Add("")

# Coverage stats
$mdContent.Add("### What was found")
$mdContent.Add("")
$mdContent.Add("| Strategy | Files with a date | Files without |")
$mdContent.Add("|---|---|---|")
$mdContent.Add("| Filename | $hasFilenameDate / $totalAnalyzed | $($totalAnalyzed - $hasFilenameDate) |")
$mdContent.Add("| Metadata | $hasMetadataDate / $totalAnalyzed | $($totalAnalyzed - $hasMetadataDate) |")
$mdContent.Add("| Filesystem | $totalAnalyzed / $totalAnalyzed | 0 (always available) |")
$mdContent.Add("")

# Agreement analysis
$bothHaveDate = $datesAgreeCount + $filenameOlderCount + $metadataOlderCount
if ($bothHaveDate -gt 0) {
    $mdContent.Add("### When both filename and metadata have a date ($bothHaveDate files)")
    $mdContent.Add("")
    $mdContent.Add("| Result | Count |")
    $mdContent.Add("|---|---|")
    $mdContent.Add("| They agree (same day) | $datesAgreeCount |")
    $mdContent.Add("| Filename is older | $filenameOlderCount |")
    $mdContent.Add("| Metadata is older | $metadataOlderCount |")
    $mdContent.Add("")
}

# Suggested settings
$mdContent.Add("### Suggested settings")
$mdContent.Add("")

if ($hasMetadataDate -eq $totalAnalyzed -and $hasFilenameDate -eq $totalAnalyzed) {
    # Both always available
    if ($datesAgreeCount -eq $bothHaveDate) {
        $mdContent.Add("All your files have both filename dates and metadata, and they always agree.")
        $mdContent.Add("Either priority order works. The default (metadata first) is fine.")
    } elseif ($filenameOlderCount -gt $metadataOlderCount) {
        $mdContent.Add("Filename dates are often older than metadata dates. This usually means")
        $mdContent.Add("metadata was modified (e.g. by editing software) while filenames kept the original date.")
        $mdContent.Add("")
        $mdContent.Add("**Recommended:**")
        $mdContent.Add("``````ini")
        $mdContent.Add("[Priority]")
        $mdContent.Add("filename")
        $mdContent.Add("metadata")
        $mdContent.Add("filesystem")
        $mdContent.Add("``````")
        $mdContent.Add("")
        $mdContent.Add("Or use ``DateStrategy=earliest`` to always pick the oldest date automatically.")
    } else {
        $mdContent.Add("Metadata dates are generally older or equal to filename dates.")
        $mdContent.Add("The default priority (metadata first) is a good fit.")
    }
} elseif ($hasMetadataDate -lt $totalAnalyzed -and $hasFilenameDate -eq $totalAnalyzed) {
    # Filename always available, metadata sometimes missing
    $mdContent.Add("Some files are missing metadata (likely from WhatsApp, Instagram, or similar apps")
    $mdContent.Add("that strip EXIF data). All files have dates in their filenames.")
    $mdContent.Add("")
    $mdContent.Add("**Recommended:**")
    $mdContent.Add("``````ini")
    $mdContent.Add("[Priority]")
    $mdContent.Add("filename")
    $mdContent.Add("metadata")
    $mdContent.Add("filesystem")
    $mdContent.Add("``````")
    if ($noMetadataFiles.Count -le 5) {
        $mdContent.Add("")
        $mdContent.Add("Files without metadata: $($noMetadataFiles -join ', ')")
    }
} elseif ($hasFilenameDate -lt $totalAnalyzed -and $hasMetadataDate -eq $totalAnalyzed) {
    # Metadata always available, filename sometimes missing
    $mdContent.Add("Some files don't have a recognizable date in their filename,")
    $mdContent.Add("but all files have metadata. The default priority (metadata first) is ideal.")
    if ($noFilenameFiles.Count -le 5) {
        $mdContent.Add("")
        $mdContent.Add("Files without filename date: $($noFilenameFiles -join ', ')")
    }
} else {
    # Mixed - some missing from both
    $mdContent.Add("Your files are a mix - some lack metadata, some lack filename dates.")
    $mdContent.Add("Consider using ``DateStrategy=earliest`` to get the best result from whatever is available.")
    $mdContent.Add("")
    $mdContent.Add("``````ini")
    $mdContent.Add("[Options]")
    $mdContent.Add("DateStrategy=earliest")
    $mdContent.Add("``````")
    if ($noMetadataFiles.Count -le 5 -and $noMetadataFiles.Count -gt 0) {
        $mdContent.Add("")
        $mdContent.Add("Files without metadata: $($noMetadataFiles -join ', ')")
    }
    if ($noFilenameFiles.Count -le 5 -and $noFilenameFiles.Count -gt 0) {
        $mdContent.Add("")
        $mdContent.Add("Files without filename date: $($noFilenameFiles -join ', ')")
    }
}

$mdContent.Add("")

$mdContent | Out-File -FilePath $reportPath -Encoding utf8
Write-Host "Success! Property report generated at: $reportPath"

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null