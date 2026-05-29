<#
.SYNOPSIS
    Analyzes files in the 'examples' folder and generates a Markdown report of all available shell properties.
#>

Param(
    [string]$config = (Join-Path -Path $PSScriptRoot -ChildPath "config.ini")
)

$examplesPath = Join-Path -Path $PSScriptRoot -ChildPath "examples"
$reportTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath "property_report_$reportTimestamp.md"

if (-not (Test-Path -Path $examplesPath)) {
    Write-Error "The directory '$examplesPath' does not exist. Please create it and add sample files."
    return
}

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
        }
    }
    if ($configPriority.Count -gt 0) { $priority = $configPriority }
    if ($configDateIds.Count -gt 0) { $knownDateIds = $configDateIds }
} else {
    Write-Host "No config file found at '$config'. Using defaults."
}

$files = Get-ChildItem -Path $examplesPath -File
if ($files.Count -eq 0) {
    Write-Host "No files found in '$examplesPath' to analyze."
    return
}

$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace($examplesPath)

$mdContent = New-Object System.Collections.Generic.List[string]
$mdContent.Add("# Media Metadata Analysis Report")
$mdContent.Add("Generated on: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
$mdContent.Add("")
$mdContent.Add("## Active Configuration")
$mdContent.Add("- **Priority order:** $($priority -join ' → ')")
$mdContent.Add("- **Metadata properties:** $($knownDateIds -join ', ')")
$mdContent.Add("")
$mdContent.Add("---")
$mdContent.Add("")
$mdContent.Add("This report lists the **Extracted Filename Date** and all date-related Windows Shell properties for files in the ``/examples`` folder.")
$mdContent.Add("")

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

    # Determine winner based on priority order
    foreach ($strategy in $priority) {
        if ($strategyResults.ContainsKey($strategy)) {
            $finalDateSource = $strategy
            $finalDateValue = $strategyResults[$strategy]
            break
        }
    }

    # Ultimate fallback
    if ($finalDateSource -eq "None Found") {
        $finalDateSource = "filesystem (fallback)"
        $finalDateValue = $fileInfo.CreationTime.ToString()
    }

    $mdContent.Add("## File: $($fileInfo.Name)")
    $mdContent.Add("- **Winner:** $finalDateSource → ``$finalDateValue``")
    $mdContent.Add("")
    $mdContent.Add("| Strategy | Result |")
    $mdContent.Add("|---|---|")
    foreach ($strategy in $priority) {
        $val = if ($strategyResults.ContainsKey($strategy)) { $strategyResults[$strategy] } else { "—" }
        $marker = if ($strategy -eq $finalDateSource) { " ✓" } else { "" }
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

$mdContent | Out-File -FilePath $reportPath -Encoding utf8
Write-Host "Success! Property report generated at: $reportPath"

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null