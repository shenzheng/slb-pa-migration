param(
    [string]$RootPath,
    [string]$InputPath,
    [string]$OutputPath,
    [string]$ExceptionPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = "doc\package-versions.md"
}

if (-not [System.IO.Path]::IsPathRooted($InputPath)) {
    $InputPath = Join-Path $resolvedRoot $InputPath
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath) -and -not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $resolvedRoot $OutputPath
}

if ([string]::IsNullOrWhiteSpace($ExceptionPath)) {
    $ExceptionPath = "doc\package-version-conflict-exceptions.md"
}

if (-not [System.IO.Path]::IsPathRooted($ExceptionPath)) {
    $ExceptionPath = Join-Path $resolvedRoot $ExceptionPath
}

function Get-SortableVersionParts {
    param(
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return [PSCustomObject]@{
            Numeric = @(-1)
            Text = ""
        }
    }

    $numeric = New-Object System.Collections.Generic.List[int]

    foreach ($segment in ($Version -split "[^0-9]+")) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        $parsed = 0
        if ([int]::TryParse($segment, [ref]$parsed)) {
            $numeric.Add($parsed)
        }
    }

    if ($numeric.Count -eq 0) {
        $numeric.Add(-1)
    }

    return [PSCustomObject]@{
        Numeric = $numeric.ToArray()
        Text = $Version
    }
}

function Get-VersionSortKey {
    param(
        [string]$Version
    )

    $parts = Get-SortableVersionParts -Version $Version
    $normalized = $parts.Numeric | ForEach-Object { "{0:D8}" -f $_ }

    return "{0}|{1}" -f ($normalized -join "."), $parts.Text
}

function Get-TableCells {
    param(
        [string]$Line
    )

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith("|")) {
        return $null
    }

    $cells = $trimmed.Trim("|").Split("|")
    if ($cells.Count -lt 4) {
        return $null
    }

    return $cells
}

function Get-NormalizedHeaderName {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return ($Value.Trim() -replace '\s+', ' ').ToLowerInvariant()
}

function New-ExceptionRecord {
    param(
        [string]$PackageId
    )

    return [PSCustomObject]@{
        PackageId = $PackageId
        Status = "Planned Exception"
        Classification = "Exception"
        Notes = ""
        Scope = ""
        ReviewOwner = ""
        LastReviewedAt = ""
    }
}

function Get-OrCreateExceptionRecord {
    param(
        [hashtable]$Map,
        [string]$PackageId
    )

    if (-not $Map.ContainsKey($PackageId)) {
        $Map[$PackageId] = New-ExceptionRecord -PackageId $PackageId
    }

    return $Map[$PackageId]
}

function Get-HeaderIndexMap {
    param(
        [string[]]$Cells
    )

    $map = @{}

    for ($index = 0; $index -lt $Cells.Count; $index++) {
        $headerName = Get-NormalizedHeaderName -Value $Cells[$index]
        if ([string]::IsNullOrWhiteSpace($headerName)) {
            continue
        }

        if (-not $map.ContainsKey($headerName)) {
            $map[$headerName] = $index
        }
    }

    return $map
}

function Get-CellValueByHeader {
    param(
        [string[]]$Cells,
        [hashtable]$HeaderIndexMap,
        [string[]]$HeaderNames
    )

    foreach ($headerName in $HeaderNames) {
        $normalizedHeaderName = Get-NormalizedHeaderName -Value $headerName
        if (-not $HeaderIndexMap.ContainsKey($normalizedHeaderName)) {
            continue
        }

        $index = $HeaderIndexMap[$normalizedHeaderName]
        if ($index -lt $Cells.Count) {
            return $Cells[$index].Trim()
        }
    }

    return ""
}

function Read-ConflictExceptionMap {
    param(
        [string]$Path
    )

    $map = @{}

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $map
    }

    $currentTableType = $null
    $currentHeaderIndexMap = $null

    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $currentTableType = $null
            $currentHeaderIndexMap = $null
            continue
        }

        if ($trimmed -match '^#') {
            $currentTableType = $null
            $currentHeaderIndexMap = $null
            continue
        }

        $cells = Get-TableCells -Line $trimmed
        if ($null -eq $cells) {
            $currentTableType = $null
            $currentHeaderIndexMap = $null
            continue
        }

        if ($trimmed -match '^\|\s*-+(\s*\|\s*-+\s*)+\|?$') {
            continue
        }

        if ($null -eq $currentHeaderIndexMap) {
            $headerIndexMap = Get-HeaderIndexMap -Cells $cells

            if ($headerIndexMap.Count -eq 0 -or -not $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Package Id'))) {
                continue
            }

            $currentHeaderIndexMap = $headerIndexMap
            $hasConflictColumns = $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Status')) -and $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Classification')) -and $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Notes'))
            $hasMetadataColumns = $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Scope')) -and $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Review Owner')) -and $headerIndexMap.ContainsKey((Get-NormalizedHeaderName -Value 'Last Reviewed At'))

            if ($hasConflictColumns) {
                $currentTableType = 'ConflictRegister'
            }
            elseif ($hasMetadataColumns) {
                $currentTableType = 'ReviewMetadata'
            }
            else {
                $currentTableType = 'Generic'
            }

            continue
        }

        $packageId = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Package Id')
        if ([string]::IsNullOrWhiteSpace($packageId) -or $packageId -eq "Package Id") {
            continue
        }

        $record = Get-OrCreateExceptionRecord -Map $map -PackageId $packageId

        if ($currentTableType -eq 'ReviewMetadata') {
            $record.Scope = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Scope')
            $record.ReviewOwner = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Review Owner', 'ReviewOwner')
            $record.LastReviewedAt = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Last Reviewed At', 'LastReviewedAt')
            continue
        }

        $status = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Status')
        $classification = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Classification')
        $notes = Get-CellValueByHeader -Cells $cells -HeaderIndexMap $currentHeaderIndexMap -HeaderNames @('Notes')

        if (-not [string]::IsNullOrWhiteSpace($status)) {
            $record.Status = $status
        }

        if (-not [string]::IsNullOrWhiteSpace($classification)) {
            $record.Classification = $classification
        }

        if (-not [string]::IsNullOrWhiteSpace($notes)) {
            $record.Notes = $notes
        }
    }

    return $map
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input markdown was not found at '$InputPath'."
}

$exceptionMap = Read-ConflictExceptionMap -Path $ExceptionPath
$packageMap = @{}
$inDependencyDetails = $false

function Get-OrCreatePackageRecord {
    param(
        [hashtable]$Map,
        [string]$PackageId
    )

    if (-not $Map.ContainsKey($PackageId)) {
        $Map[$PackageId] = [PSCustomObject]@{
            PackageId = $PackageId
            Versions = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            Repositories = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        }
    }

    return $Map[$PackageId]
}

$lines = Get-Content -LiteralPath $InputPath -Encoding UTF8
$currentPackageId = $null
$currentVersion = $null

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^##\s+Package Dependency Details\s*$') {
        $inDependencyDetails = $true
        $currentPackageId = $null
        $currentVersion = $null
        continue
    }

    if (-not $inDependencyDetails) {
        continue
    }

    if ($trimmed -match '^###\s+(.+?)\s*$') {
        $currentPackageId = $matches[1].Trim()
        $currentVersion = $null
        if (-not [string]::IsNullOrWhiteSpace($currentPackageId)) {
            [void](Get-OrCreatePackageRecord -Map $packageMap -PackageId $currentPackageId)
        }

        continue
    }

    if ($trimmed -match '^####\s+Version\s+(.+?)\s*$') {
        if (-not [string]::IsNullOrWhiteSpace($currentPackageId)) {
            $currentVersion = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($currentVersion)) {
                $record = Get-OrCreatePackageRecord -Map $packageMap -PackageId $currentPackageId
                [void]$record.Versions.Add($currentVersion)
            }
        }

        continue
    }

    if ([string]::IsNullOrWhiteSpace($currentPackageId) -or [string]::IsNullOrWhiteSpace($currentVersion)) {
        continue
    }

    if ($trimmed -match '^\|\s*-+\s*(\|\s*-+\s*)+\|$') {
        continue
    }

    $cells = Get-TableCells -Line $trimmed
    if ($null -eq $cells) {
        continue
    }

    $repository = $cells[0].Trim()
    if ([string]::IsNullOrWhiteSpace($repository) -or $repository -eq "Repository" -or $repository -match '^-+$') {
        continue
    }

    $record = Get-OrCreatePackageRecord -Map $packageMap -PackageId $currentPackageId
    [void]$record.Versions.Add($currentVersion)
    [void]$record.Repositories.Add($repository)
}

$conflicts = New-Object System.Collections.Generic.List[object]

foreach ($entry in ($packageMap.GetEnumerator() | Sort-Object Name)) {
    $record = $entry.Value

    if ($record.Versions.Count -le 1) {
        continue
    }

    $versionList = @($record.Versions) | Sort-Object { Get-VersionSortKey -Version $_ }
    $repositoryList = @($record.Repositories) | Sort-Object
    $exception = $null

    if ($exceptionMap.ContainsKey($record.PackageId)) {
        $exception = $exceptionMap[$record.PackageId]
    }

    $conflicts.Add([PSCustomObject]@{
            PackageId = $record.PackageId
            Versions = ($versionList -join ", ")
            RepositoryCount = $repositoryList.Count
            Repositories = ($repositoryList -join ", ")
            Status = if ($null -ne $exception) { $exception.Status } else { "Pending Conflict" }
            Classification = if ($null -ne $exception) { $exception.Classification } else { "Unclassified" }
            Notes = if ($null -ne $exception) { $exception.Notes } else { "" }
        })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$sourceFileDisplay = if ($InputPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    $InputPath.Substring($resolvedRoot.Length).TrimStart('\')
}
else {
    $InputPath
}

$exceptionFileDisplay = if ((Test-Path -LiteralPath $ExceptionPath -PathType Leaf) -and $ExceptionPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    $ExceptionPath.Substring($resolvedRoot.Length).TrimStart('\')
}
elseif (Test-Path -LiteralPath $ExceptionPath -PathType Leaf) {
    $ExceptionPath
}
else {
    $null
}

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# Package Version Conflicts")
$markdown.Add("")
$markdown.Add("Generated at: $generatedAt")
$markdown.Add("")
$markdown.Add("Source document: ``$sourceFileDisplay``")
if ($null -ne $exceptionFileDisplay) {
    $markdown.Add("Exception source: ``$exceptionFileDisplay``")
}
$markdown.Add("")
$markdown.Add("Status / Classification / Notes are reserved for future planned exceptions.")
$markdown.Add("")

if ($conflicts.Count -eq 0) {
    $markdown.Add("No packages currently have multiple versions in the source document.")
}
else {
    $markdown.Add("## Conflicts")
    $markdown.Add("")
    $markdown.Add("| Package Id | Versions | Repository Count | Repositories | Status | Classification | Notes |")
    $markdown.Add("| --- | --- | --- | --- | --- | --- | --- |")

    foreach ($conflict in $conflicts) {
        $markdown.Add("| $($conflict.PackageId) | $($conflict.Versions) | $($conflict.RepositoryCount) | $($conflict.Repositories) | $($conflict.Status) | $($conflict.Classification) | $($conflict.Notes) |")
    }
}

$markdownOutput = ($markdown -join "`r`n") + "`r`n"

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw "OutputPath must include a file name."
    }

    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($OutputPath, $markdownOutput, $utf8NoBom)
}

Write-Output $markdownOutput
Write-Host ("Analyzed {0} packages and found {1} packages with multiple versions." -f $packageMap.Count, $conflicts.Count)
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Host ("Markdown written to '{0}'." -f $OutputPath)
}
