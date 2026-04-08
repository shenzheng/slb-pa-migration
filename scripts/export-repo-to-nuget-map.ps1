param(
    [string]$RootPath,
    [string[]]$ProjectGroups = @("Actors", "Shared", "Pipeline"),
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedRoot "doc\repo-to-nuget-map.md"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $resolvedRoot $OutputPath
}

$resolvedOutputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)

if ([string]::IsNullOrWhiteSpace($resolvedOutputDirectory)) {
    throw "OutputPath must include a file name."
}

[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

$excludedDirectoryNames = @(
    ".git",
    ".vs",
    "bin",
    "obj",
    "packages",
    "artifacts",
    "TestResults"
)

function Test-ShouldSkipDirectory {
    param(
        [System.IO.DirectoryInfo]$Directory
    )

    return $excludedDirectoryNames -contains $Directory.Name
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFullPath += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = [System.Uri]::new($baseFullPath)
    $targetUri = [System.Uri]::new($targetFullPath)

    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Get-NuspecMetadata {
    param(
        [string]$NuspecPath
    )

    [xml]$xml = Get-Content -LiteralPath $NuspecPath -Raw -Encoding UTF8
    $idNode = $xml.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='id']")
    $versionNode = $xml.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='version']")

    if ($null -eq $idNode -or [string]::IsNullOrWhiteSpace($idNode.InnerText)) {
        throw "NuGet package id was not found in '$NuspecPath'."
    }

    if ($null -eq $versionNode -or [string]::IsNullOrWhiteSpace($versionNode.InnerText)) {
        throw "NuGet package version was not found in '$NuspecPath'."
    }

    return [PSCustomObject]@{
        PackageId = $idNode.InnerText.Trim()
        Version = $versionNode.InnerText.Trim()
    }
}

function Get-NuspecFiles {
    param(
        [System.IO.DirectoryInfo]$RepositoryDirectory
    )

    $results = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $pending = New-Object System.Collections.Generic.Queue[System.IO.DirectoryInfo]
    $pending.Enqueue($RepositoryDirectory)

    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()

        Get-ChildItem -LiteralPath $current.FullName -File -Filter *.nuspec | ForEach-Object {
            $results.Add($_)
        }

        Get-ChildItem -LiteralPath $current.FullName -Directory | Where-Object {
            -not (Test-ShouldSkipDirectory -Directory $_)
        } | ForEach-Object {
            $pending.Enqueue($_)
        }
    }

    return $results
}

$records = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($projectGroup in $ProjectGroups) {
    $groupPath = Join-Path $resolvedRoot $projectGroup

    if (-not (Test-Path -LiteralPath $groupPath -PathType Container)) {
        $warnings.Add("Skipped project group '$projectGroup' because '$groupPath' does not exist.")
        continue
    }

    Get-ChildItem -LiteralPath $groupPath -Directory | Sort-Object Name | ForEach-Object {
        $repositoryDirectory = $_
        $nuspecFiles = Get-NuspecFiles -RepositoryDirectory $repositoryDirectory

        foreach ($nuspecFile in ($nuspecFiles | Sort-Object FullName)) {
            $metadata = Get-NuspecMetadata -NuspecPath $nuspecFile.FullName

            $records.Add([PSCustomObject]@{
                    ProjectGroup = $projectGroup
                    Repository = $repositoryDirectory.Name
                    PackageId = $metadata.PackageId
                    Version = $metadata.Version
                    NuspecPath = Get-RelativePath -BasePath $resolvedRoot -TargetPath $nuspecFile.FullName
                })
        }
    }
}

$orderedRecords = $records | Sort-Object ProjectGroup, Repository, PackageId, NuspecPath
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("# Repository to NuGet package map")
$lines.Add("")
$lines.Add("Generated at: $generatedAt")
$lines.Add("")

if ($warnings.Count -gt 0) {
    $lines.Add("## Warnings")
    $lines.Add("")

    foreach ($warning in $warnings) {
        $lines.Add("- $warning")
    }

    $lines.Add("")
}

if ($orderedRecords.Count -eq 0) {
    $lines.Add("No `.nuspec` files were found in the scanned repositories.")
}
else {
    $lines.Add("## Packages")
    $lines.Add("")
    $lines.Add("| Project Group | Repository | Package Id | Version | Nuspec Path |")
    $lines.Add("| --- | --- | --- | --- | --- |")

    foreach ($record in $orderedRecords) {
        $lines.Add("| $($record.ProjectGroup) | $($record.Repository) | $($record.PackageId) | $($record.Version) | ``$($record.NuspecPath)`` |")
    }
}

$content = ($lines -join "`r`n") + "`r`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath, $content, $utf8NoBom)

Write-Host ("Scanned {0} packages across {1} repositories." -f $orderedRecords.Count, (($orderedRecords | Select-Object -ExpandProperty Repository -Unique).Count))
Write-Host ("Markdown written to '{0}'." -f $OutputPath)
