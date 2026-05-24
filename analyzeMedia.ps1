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

    # 1. Try extracting date from filename (matches logic in sortPhoto.ps1)
    $filenameDate = "No date found"
    if ($fileInfo.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $filenameDate = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }

    $mdContent.Add("## File: $($fileInfo.Name)")
    $mdContent.Add("- **Extracted Filename Date:** ``$filenameDate``")
    $mdContent.Add("")
    $mdContent.Add("| ID | Property Name | Value |")
    $mdContent.Add("|---|---|---|")

    $item = $folder.ParseName($fileInfo.Name)

    # Iterate through potential Shell property IDs (0-350 covers standard and extended metadata)
    for ($i = 0; $i -le 350; $i++) {
        $name = $folder.GetDetailsOf($null, $i)
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        # Filter: Only include properties that contain date-related keywords
        if ($name -notmatch "date|datum|erstellt|encoded|taken|recorded|zeit") {
            continue
        }

        $value = $folder.GetDetailsOf($item, $i)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            # Remove invisible Unicode control characters (BiDi markers) and escape pipes for Markdown
            $cleanValue = ($value -replace "[\u200e\u200f\u202a-\u202e]", "").Replace("|", "\|")
            $mdContent.Add("| $i | $name | $cleanValue |")
        }
    }
    $mdContent.Add("")
}

$mdContent | Out-File -FilePath $reportPath -Encoding utf8
Write-Host "Success! Property report generated at: $reportPath"

# Cleanup COM object
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null