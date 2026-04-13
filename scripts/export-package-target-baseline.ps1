param(
    [string]$RootPath,
    [string]$PackageVersionsPath,
    [string]$TaskPath,
    [string]$OutputPath,
    [string[]]$ExcludedRepositories
)

$ErrorActionPreference = "Stop"

function Resolve-WorkspacePath {
    param(
        [string]$BasePath,
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
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

function Escape-MarkdownCell {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function Get-ExcludedRepositoriesFromTask {
    param(
        [string]$TaskFilePath
    )

    $results = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $inExcludedSection = $false
    $sawAnyHeading = $false
    $repoPattern = '^\s*-\s+([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)\s*$'

    if (-not (Test-Path -LiteralPath $TaskFilePath -PathType Leaf)) {
        return $results
    }

    foreach ($line in (Get-Content -LiteralPath $TaskFilePath -Encoding UTF8)) {
        if ($line -match '^##\s+') {
            $sawAnyHeading = $true
            $inExcludedSection = $line -match '^##\s+.*不进行改造的工程'
            continue
        }

        if ($inExcludedSection -and $line -match $repoPattern) {
            [void]$results.Add($matches[1].Trim())
        }
    }

    if ($results.Count -gt 0 -or -not $sawAnyHeading) {
        return $results
    }

    # Fallback for legacy task documents whose heading text is already mojibake in the file:
    # collect the first level-2 section that contains repository bullets.
    $inFirstRepositorySection = $false
    $fallbackResults = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in (Get-Content -LiteralPath $TaskFilePath -Encoding UTF8)) {
        if ($line -match '^##\s+') {
            if ($inFirstRepositorySection -and $fallbackResults.Count -gt 0) {
                break
            }

            $inFirstRepositorySection = $true
            continue
        }

        if (-not $inFirstRepositorySection) {
            continue
        }

        if ($line -match $repoPattern) {
            [void]$fallbackResults.Add($matches[1].Trim())
        }
    }

    if ($fallbackResults.Count -gt 0) {
        return $fallbackResults
    }

    return $results
}

function Get-PackageInventory {
    param(
        [string]$PackageVersionsFilePath
    )

    $packages = @{}
    $inDependencySection = $false
    $currentPackageId = $null
    $currentVersion = $null
    $inDependencyTable = $false

    foreach ($line in (Get-Content -LiteralPath $PackageVersionsFilePath -Encoding UTF8)) {
        if ($line -match '^##\s+Package Dependency Details\s*$') {
            $inDependencySection = $true
            $currentPackageId = $null
            $currentVersion = $null
            $inDependencyTable = $false
            continue
        }

        if (-not $inDependencySection) {
            continue
        }

        if ($line -match '^###\s+(.+?)\s*$') {
            $heading = $matches[1].Trim()

            if ($heading -notmatch '^Version\s+') {
                $currentPackageId = $heading
                $currentVersion = $null
                $inDependencyTable = $false

                if (-not $packages.ContainsKey($currentPackageId)) {
                    $packages[$currentPackageId] = [PSCustomObject]@{
                        PackageId = $currentPackageId
                        Versions = @{}
                        Repositories = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
                    }
                }
            }

            continue
        }

        if ($line -match '^####\s+Version\s+(.+?)\s*$') {
            $currentVersion = $matches[1].Trim()
            $inDependencyTable = $false

            if (-not [string]::IsNullOrWhiteSpace($currentPackageId)) {
                $package = $packages[$currentPackageId]

                if (-not $package.Versions.ContainsKey($currentVersion)) {
                    $package.Versions[$currentVersion] = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
                }
            }

            continue
        }

        if ($line -match '^\|\s*Repository\s+\|\s*Project\s+\|\s*Reference Type\s+\|\s*Path\s+\|') {
            $inDependencyTable = $true
            continue
        }

        if (-not $inDependencyTable) {
            continue
        }

        if ($line -notmatch '^\|') {
            if ([string]::IsNullOrWhiteSpace($line)) {
                $inDependencyTable = $false
            }

            continue
        }

        if ($line -match '^\|\s*-+\s*\|\s*-+\s*\|\s*-+\s*\|\s*-+\s*\|') {
            continue
        }

        $cells = $line.Trim().Trim('|').Split('|')
        if ($cells.Count -lt 4) {
            continue
        }

        $repository = $cells[0].Trim()
        if ([string]::IsNullOrWhiteSpace($repository) -or [string]::IsNullOrWhiteSpace($currentPackageId) -or [string]::IsNullOrWhiteSpace($currentVersion)) {
            continue
        }

        $package = $packages[$currentPackageId]
        [void]$package.Repositories.Add($repository)
        [void]$package.Versions[$currentVersion].Add($repository)
    }

    return $packages.Values
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
else {
    $RootPath = [System.IO.Path]::GetFullPath($RootPath)
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($PackageVersionsPath)) {
    $PackageVersionsPath = Join-Path $resolvedRoot "doc\package-versions.md"
}
else {
    $PackageVersionsPath = Resolve-WorkspacePath -BasePath $resolvedRoot -PathValue $PackageVersionsPath
}

if ([string]::IsNullOrWhiteSpace($TaskPath)) {
    $TaskPath = Join-Path $resolvedRoot 'tasks\task-5-uni-pkg-version.md'
}
else {
    $TaskPath = Resolve-WorkspacePath -BasePath $resolvedRoot -PathValue $TaskPath
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedRoot "tasks\uni-pkg-version-target-baseline.md"
}
else {
    $OutputPath = Resolve-WorkspacePath -BasePath $resolvedRoot -PathValue $OutputPath
}

foreach ($requiredPath in @($PackageVersionsPath, $TaskPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file not found: '$requiredPath'."
    }
}

$resolvedOutputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if ([string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
    throw "OutputPath must include a file name."
}

[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

$excludedRepositorySet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($repository in (Get-ExcludedRepositoriesFromTask -TaskFilePath $TaskPath)) {
    [void]$excludedRepositorySet.Add($repository)
}

if ($null -ne $ExcludedRepositories) {
    foreach ($repository in $ExcludedRepositories) {
        if ([string]::IsNullOrWhiteSpace($repository)) {
            continue
        }

        [void]$excludedRepositorySet.Add($repository.Trim())
    }
}

$packages = Get-PackageInventory -PackageVersionsFilePath $PackageVersionsPath
$records = New-Object System.Collections.Generic.List[object]

foreach ($package in ($packages | Sort-Object PackageId)) {
    $currentVersions = @()
    if ($package.Versions.Count -gt 0) {
        $currentVersions = @($package.Versions.Keys | Sort-Object { Get-VersionSortKey -Version $_ } -Descending)
    }

    $targetVersion = if ($currentVersions.Count -gt 0) { $currentVersions[0] } else { "" }
    $allRepositories = @()
    if ($package.Repositories.Count -gt 0) {
        $allRepositories = $package.Repositories | Sort-Object
    }

    $inScopeRepositories = @($allRepositories | Where-Object { -not $excludedRepositorySet.Contains($_) })
    $outOfScopeRepositories = @($allRepositories | Where-Object { $excludedRepositorySet.Contains($_) })
    $inScope = $inScopeRepositories.Count -gt 0
    $inScopeVersions = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    if ($inScope) {
        foreach ($version in $currentVersions) {
            $versionRepos = $package.Versions[$version]
            if ($null -eq $versionRepos) {
                continue
            }

            if (($versionRepos | Where-Object { -not $excludedRepositorySet.Contains($_) }).Count -gt 0) {
                [void]$inScopeVersions.Add($version)
            }
        }
    }

    $strategy = "Unified upgrade"
    $exceptionReason = "-"

    if (-not $inScope) {
        $strategy = "Recommend removal"
        $exceptionReason = "Only appears in repositories excluded by task-5"
    }
    elseif (($outOfScopeRepositories.Count -gt 0) -and ($currentVersions.Count -gt 1) -and ($inScopeVersions.Count -le 1)) {
        $strategy = "Keep divergence"
        $exceptionReason = "Out-of-scope repositories still use different versions"
    }

    $records.Add([PSCustomObject]@{
            PackageId = $package.PackageId
            CurrentVersions = ($currentVersions | ForEach-Object { Escape-MarkdownCell -Value $_ }) -join ", "
            TargetVersion = Escape-MarkdownCell -Value $targetVersion
            SourceRepositories = ($allRepositories | ForEach-Object { Escape-MarkdownCell -Value $_ }) -join ", "
            InScope = if ($inScope) { "Yes" } else { "No" }
            Strategy = $strategy
            ExceptionReason = $exceptionReason
        })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("# Unified Package Version Target Baseline")
$lines.Add("")
$lines.Add("Generated at: $generatedAt")
$lines.Add("")
$lines.Add('Source: doc/package-versions.md')
$lines.Add("Excluded repositories: $((($excludedRepositorySet | Sort-Object) -join ', '))")
$lines.Add("")
$lines.Add("## Rules")
$lines.Add("")
$lines.Add('- Target Version is the highest version already present in doc/package-versions.md.')
$lines.Add('- In Scope is derived from task-5 exclusions, plus any repositories passed through -ExcludedRepositories.')
$lines.Add('- Strategy is generated from current workspace coverage and scope boundaries.')
$lines.Add("")
$lines.Add("## Baseline")
$lines.Add("")
$lines.Add("| Package Id | Current Versions | Target Version | Source Repositories | In Scope | Strategy | Exception Reason |")
$lines.Add("| --- | --- | --- | --- | --- | --- | --- |")

foreach ($record in $records) {
    $lines.Add("| $($record.PackageId) | $($record.CurrentVersions) | $($record.TargetVersion) | $($record.SourceRepositories) | $($record.InScope) | $($record.Strategy) | $($record.ExceptionReason) |")
}

$content = ($lines -join "`r`n") + "`r`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath, $content, $utf8NoBom)

Write-Host ("Scanned {0} packages from '{1}'." -f $records.Count, $PackageVersionsPath)
Write-Host ("Excluded {0} repositories from task scope." -f $excludedRepositorySet.Count)
Write-Host ("Markdown written to '{0}'." -f $OutputPath)
