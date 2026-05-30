[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$source,
    [string]$dest = (Join-Path -Path $source -ChildPath "Sorted"),
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
$dateFormat = "yyyy\\yyyy-MM\\yyyy-MM-dd"
$includeExtensions = @()
$excludeExtensions = @()
$conflictStrategy = "rename"
$dateStrategy = "priority"
$requireDateMatch = $false
$logFile = ""

# Load config file if it exists
if (Test-Path -Path $config -PathType Leaf) {
    Write-Verbose "Loading configuration from: $config"
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
                }
            }
            "MetadataProperties" {
                if ($metadataPropertyMap.ContainsKey($line)) {
                    $configDateIds += $metadataPropertyMap[$line]
                }
            }
            "Options" {
                if ($line -match '^(.+?)=(.*)$') {
                    $key = $Matches[1].Trim()
                    $val = $Matches[2].Trim()
                    switch ($key) {
                        "CleanupEmptyDirs" { $cleanupEmptyDirs = $val -eq "true" }
                        "FileAction" {
                            if ($val -in @("move", "copy")) { $fileAction = $val }
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
                        }
                        "DateStrategy" {
                            if ($val -in @("priority", "earliest")) { $dateStrategy = $val }
                        }
                        "RequireDateMatch" { $requireDateMatch = ($val -eq "true") }
                        "LogFile" { $logFile = $val }
                        "DateFormatUnix" {} # Linux/macOS only, ignore silently
                        default { Write-Warning "Unknown option '$key' in config." }
                    }
                }
            }
        }
    }
    if ($configPriority.Count -gt 0) { $priority = $configPriority }
    if ($configDateIds.Count -gt 0) { $knownDateIds = $configDateIds }
}

# --- Setup ---
$source = (Resolve-Path -Path $source).Path
$sourceLeaf = Split-Path -Path $source -Leaf
if (Test-Path -Path $dest) {
    $dest = (Resolve-Path -Path $dest).Path
}

try {
    $null = Get-Date -Format $dateFormat
} catch {
    Write-Error "Invalid DateFormat '$dateFormat' in config."
    return
}

$shell = New-Object -ComObject Shell.Application
$namespaceCache = @{}

if ($logFile -ne "") {
    $logHeader = "Timestamp`tAction`tSource`tDestination`tStrategy"
    if (-not (Test-Path -Path $logFile)) {
        $logHeader | Out-File -FilePath $logFile -Encoding utf8
    }
}

function Write-LogEntry {
    Param([string]$Action, [string]$Source, [string]$Destination, [string]$Strategy)
    if ($logFile -ne "") {
        $safeStrategy = ($Strategy -replace "[\t\r\n]", " ").Trim()
        $entry = "{0}`t{1}`t{2}`t{3}`t{4}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Action, $Source, $Destination, $safeStrategy
        $entry | Out-File -FilePath $logFile -Encoding utf8 -Append
    }
}

function Get-CachedNamespace {
    param([string]$path)
    if (-not $namespaceCache.ContainsKey($path)) {
        $namespaceCache[$path] = $shell.NameSpace($path)
    }
    return $namespaceCache[$path]
}

function Get-DateFromFilename {
    Param ([System.IO.FileInfo]$FileObject)
    if ($FileObject.BaseName -match '(?<!\d)(20\d{2}|19\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])') {
        $dateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
        $parsedDate = [System.DateTime]::MinValue
        if ([DateTime]::TryParse($dateStr, [ref]$parsedDate)) { return $parsedDate }
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
            if ([DateTime]::TryParse($cleanValue, [ref]$parsedDate)) { return $parsedDate }
        }
    }
    return $null
}

function Get-File-Date {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileObject
    )

    if ($dateStrategy -eq "earliest") {
        $candidates = @()
        foreach ($strategy in $priority) {
            $result = switch ($strategy) {
                "filename"   { Get-DateFromFilename -FileObject $FileObject }
                "metadata"   { Get-DateFromMetadata -FileObject $FileObject }
                "filesystem" { $FileObject.CreationTime }
            }
            if ($null -ne $result) { $candidates += @{ Date = $result; Strategy = $strategy } }
        }
        if ($candidates.Count -gt 0) { return $candidates | Sort-Object { $_.Date } | Select-Object -First 1 }
    } else {
        foreach ($strategy in $priority) {
            $result = switch ($strategy) {
                "filename"   { Get-DateFromFilename -FileObject $FileObject }
                "metadata"   { Get-DateFromMetadata -FileObject $FileObject }
                "filesystem" { $FileObject.CreationTime }
            }
            if ($null -ne $result) { return @{ Date = $result; Strategy = $strategy } }
        }
    }

    Write-Warning "All strategies failed for $($FileObject.Name). Using file creation time."
    return @{ Date = $FileObject.CreationTime; Strategy = "filesystem (fallback)" }
}

# --- Main Processing ---
$files = Get-ChildItem -Path $source -File | Where-Object { $_.FullName -notlike "$dest*" }
if ($includeExtensions.Count -gt 0) { $files = $files | Where-Object { $_.Extension.TrimStart('.').ToLower() -in $includeExtensions } }
if ($excludeExtensions.Count -gt 0) { $files = $files | Where-Object { $_.Extension.TrimStart('.').ToLower() -notin $excludeExtensions } }

$totalFiles = @($files).Count
if ($totalFiles -eq 0) { Write-Host "No files found to process."; return }

$processedCount = 0; $movedCount = 0; $skippedCount = 0; $errorCount = 0

foreach ($fileInfo in $files) {
    $processedCount++
    Write-Progress -Activity "Organizing Media" -Status "Processing $($fileInfo.Name)" -PercentComplete ($processedCount/$totalFiles*100)
    Write-Host "[$processedCount/$totalFiles] Processing $($fileInfo.Name)"

    try {
        if ($requireDateMatch) {
            $fnDate = Get-DateFromFilename -FileObject $fileInfo
            $mdDate = Get-DateFromMetadata -FileObject $fileInfo
            if ($null -eq $fnDate -or $null -eq $mdDate -or $fnDate.Date -ne $mdDate.Date) {
                $reason = if ($null -eq $fnDate) { "missing filename date" } 
                          elseif ($null -eq $mdDate) { "missing metadata date" } 
                          else { "dates do not match ($($fnDate.ToString('yyyy-MM-dd')) vs $($mdDate.ToString('yyyy-MM-dd')))" }
                
                Write-Host "Skipping: $($fileInfo.Name) ($reason)" -ForegroundColor Yellow
                Write-LogEntry -Action "SKIP" -Source $fileInfo.FullName -Destination "" -Strategy "RequireDateMatch mismatch/missing"
                $skippedCount++; continue
            }
        }

        $dateResult = Get-File-Date -FileObject $fileInfo
        $date = $dateResult.Date
        $dateStrategy = $dateResult.Strategy
        # Append the folder name with a space instead of a hyphen
        $destinationSubFolder = (Get-Date -Date $date -Format $dateFormat) + " $sourceLeaf"
        $destinationPath = Join-Path -Path $dest -ChildPath $destinationSubFolder

        if (-not $DryRun -and -not (Test-Path -PathType Container -Path $destinationPath)) {
            New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
        }

        $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath $fileInfo.Name
        if (Test-Path -LiteralPath $finalDestinationFile -PathType Leaf) {
            if ($conflictStrategy -eq "skip") { $skippedCount++; continue }
            elseif ($conflictStrategy -eq "rename") {
                $newNameIndex = 1
                while (Test-Path -LiteralPath $finalDestinationFile -PathType Leaf) {
                    $finalDestinationFile = Join-Path -Path $destinationPath -ChildPath ("{0}_{1}{2}" -f $fileInfo.BaseName, $newNameIndex, $fileInfo.Extension)
                    $newNameIndex++
                }
            }
        }

        if ($fileInfo.FullName -eq $finalDestinationFile) { $skippedCount++; continue }

        if ($DryRun) {
            Write-Host "[DRY RUN] Would $fileAction '$($fileInfo.FullName)' to '$finalDestinationFile'"
            Write-LogEntry -Action "DRYRUN" -Source $fileInfo.FullName -Destination $finalDestinationFile -Strategy $dateStrategy
        } else {
            Write-Host "$($fileAction.Substring(0,1).ToUpper() + $fileAction.Substring(1))ing to $finalDestinationFile"
            if ($fileAction -eq "copy") { Copy-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force }
            else { Move-Item -LiteralPath $fileInfo.FullName -Destination $finalDestinationFile -Force }
            Write-LogEntry -Action $fileAction.ToUpper() -Source $fileInfo.FullName -Destination $finalDestinationFile -Strategy $dateStrategy
        }
        $movedCount++
    } catch {
        Write-Error "Error processing '$($fileInfo.FullName)': $_"
        Write-LogEntry -Action "ERROR" -Source $fileInfo.FullName -Destination "" -Strategy "$_"
        $errorCount++
    }
}

if (-not $DryRun -and $cleanupEmptyDirs -and $fileAction -eq "move") {
    Get-ChildItem -Path $source -Recurse -Directory | Where-Object { $_.FullName -notlike "$dest*" } |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            if ((Get-ChildItem -Path $_.FullName -Force).Count -eq 0) { Remove-Item -Path $_.FullName -Force }
        }
}

Write-Host "`n--- Summary ---`nTotal: $totalFiles`nSuccess: $movedCount`nSkipped: $skippedCount`nErrors: $errorCount"
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null