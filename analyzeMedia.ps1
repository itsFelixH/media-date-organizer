<#
.SYNOPSIS
    Analyzes files in the 'examples' folder and generates a Markdown report of all available shell properties.
#>

$examplesPath = Join-Path -Path $PSScriptRoot -ChildPath "examples"
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath "property_report.md"

if (-not (Test-Path -Path $examplesPath)) {
    Write-Error "The directory '$examplesPath' does not exist. Please create it and add sample files."
    return
}

# Known Windows Property System IDs for date properties (sync with sortPhoto.ps1)
$knownDateIds = @(
    12,    # System.Photo.DateTaken
    36879, # System.Photo.DateTimeOriginal
    208,   # System.Media.DateEncoded
    209,   # System.Media.DateEncoded (Alt)
    17,    # System.RecordedDate
    3,     # System.ItemDate
    15,    # System.DateModified
    4      # System.DateCreated
)

$files = Get-ChildItem -Path $examplesPath -File
if ($files.Count -eq 0) {
    Write-Host "No files found in '$examplesPath' to analyze."
    return
}

$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace($examplesPath)

$mdContent = New-Object System.Collections.Generic.List[string]
$mdContent.Add("# Media Metadata Analysis Report")
$mdContent.Add("Generated on: $(Get-Date)")
$mdContent.Add("")
$mdContent.Add("This report lists the **Extracted Filename Date** and all date-related Windows Shell properties for files in the ``/examples`` folder.")
$mdContent.Add("")

foreach ($fileInfo in $files) {
    Write-Host "Analyzing: $($fileInfo.Name)..."
    $item = $folder.ParseName($fileInfo.Name)

    # --- Decision Waterfall (Same logic as sortPhoto.ps1) ---
    $finalDateSource = "None Found"
    $finalDateValue = "N/A"

    # 1. Filename Extraction
    if ($fileInfo.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $finalDateSource = "Filename Regex"
        $finalDateValue = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }

    # 2. Metadata Waterfall (Simulation)
    if ($finalDateSource -eq "None Found") {
        foreach ($id in $knownDateIds) {
            $rawVal = $folder.GetDetailsOf($item, $id)
            if (-not [string]::IsNullOrWhiteSpace($rawVal)) {
                $cleanVal = $rawVal -replace "[\u200e\u200f\u202a-\u202e]", ""
                if ([DateTime]::TryParse($cleanVal, [ref]$null)) {
                    $finalDateSource = "Metadata ID $id ($($folder.GetDetailsOf($null, $id)))"
                    $finalDateValue = $cleanVal
                    break
                }
            }
        }
    }

    # 3. Fallback
    if ($finalDateSource -eq "None Found") {
        $finalDateSource = "File System (CreationTime)"
        $finalDateValue = $fileInfo.CreationTime.ToString()
    }

    $mdContent.Add("## File: $($fileInfo.Name)")
    $mdContent.Add("- **Script Decision:** $finalDateSource")
    $mdContent.Add("- **Resulting Date:** ``$finalDateValue``")
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