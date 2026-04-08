param(
    [string]$RootPath,
    [string[]]$ProjectGroups = @("Actors", "Shared"),
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedRoot "doc\package-versions.md"
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

$projectExtensions = @(".csproj", ".fsproj", ".vbproj", ".sfproj")

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

    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace("/", "\")
}

function Get-XmlDocument {
    param(
        [string]$Path
    )

    [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
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

function Resolve-PropertyValue {
    param(
        [string]$Value,
        [hashtable]$Properties,
        [System.Collections.Generic.HashSet[string]]$Visited
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    return [System.Text.RegularExpressions.Regex]::Replace(
        $Value,
        "\$\(([A-Za-z0-9_.-]+)\)",
        {
            param($match)

            $propertyName = $match.Groups[1].Value

            if ($Visited.Contains($propertyName)) {
                return $match.Value
            }

            if (-not $Properties.ContainsKey($propertyName)) {
                return $match.Value
            }

            $Visited.Add($propertyName) | Out-Null
            $resolved = Resolve-PropertyValue -Value $Properties[$propertyName] -Properties $Properties -Visited $Visited
            $Visited.Remove($propertyName) | Out-Null

            return $resolved
        }
    )
}

function Get-DirectoryAncestorProps {
    param(
        [string]$ProjectDirectory,
        [string]$RootBoundary
    )

    $files = New-Object System.Collections.Generic.List[string]
    $current = [System.IO.Path]::GetFullPath($ProjectDirectory)
    $boundary = [System.IO.Path]::GetFullPath($RootBoundary)

    while ($true) {
        foreach ($propsFileName in @("Directory.Build.props", "Directory.Packages.props")) {
            $candidate = Join-Path $current $propsFileName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $files.Add($candidate)
            }
        }

        if ($current -eq $boundary) {
            break
        }

        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent) {
            break
        }

        $current = $parent.FullName
    }

    $orderedFiles = $files.ToArray()
    [array]::Reverse($orderedFiles)
    return $orderedFiles
}

function Get-ProjectEvaluationContext {
    param(
        [string]$ProjectPath,
        [string]$RootBoundary
    )

    $projectDirectory = Split-Path -Parent $ProjectPath
    $propertyFiles = Get-DirectoryAncestorProps -ProjectDirectory $projectDirectory -RootBoundary $RootBoundary
    $propertyMap = @{}
    $packageVersionMap = @{}

    foreach ($propertyFile in $propertyFiles) {
        $xml = Get-XmlDocument -Path $propertyFile

        foreach ($propertyGroup in $xml.SelectNodes("/*[local-name()='Project']/*[local-name()='PropertyGroup']")) {
            foreach ($propertyNode in $propertyGroup.ChildNodes) {
                if ($propertyNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                    continue
                }

                $propertyText = ""
                if ($null -ne $propertyNode.InnerText) {
                    $propertyText = $propertyNode.InnerText
                }

                $propertyMap[$propertyNode.LocalName] = $propertyText.Trim()
            }
        }

        foreach ($packageVersionNode in $xml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageVersion']")) {
            $packageId = $packageVersionNode.GetAttribute("Include")
            if ([string]::IsNullOrWhiteSpace($packageId)) {
                $packageId = $packageVersionNode.GetAttribute("Update")
            }

            if ([string]::IsNullOrWhiteSpace($packageId)) {
                continue
            }

            $version = $packageVersionNode.GetAttribute("Version")
            if ([string]::IsNullOrWhiteSpace($version)) {
                $versionNode = $packageVersionNode.SelectSingleNode("*[local-name()='Version']")
                if ($null -ne $versionNode) {
                    $version = $versionNode.InnerText
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($version)) {
                $packageVersionMap[$packageId.Trim()] = $version.Trim()
            }
        }
    }

    $projectXml = Get-XmlDocument -Path $ProjectPath

    foreach ($propertyGroup in $projectXml.SelectNodes("/*[local-name()='Project']/*[local-name()='PropertyGroup']")) {
        foreach ($propertyNode in $propertyGroup.ChildNodes) {
            if ($propertyNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                continue
            }

            $propertyText = ""
            if ($null -ne $propertyNode.InnerText) {
                $propertyText = $propertyNode.InnerText
            }

            $propertyMap[$propertyNode.LocalName] = $propertyText.Trim()
        }
    }

    foreach ($packageVersionNode in $projectXml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageVersion']")) {
        $packageId = $packageVersionNode.GetAttribute("Include")
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            $packageId = $packageVersionNode.GetAttribute("Update")
        }

        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $version = $packageVersionNode.GetAttribute("Version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            $versionNode = $packageVersionNode.SelectSingleNode("*[local-name()='Version']")
            if ($null -ne $versionNode) {
                $version = $versionNode.InnerText
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $packageVersionMap[$packageId.Trim()] = $version.Trim()
        }
    }

    $assemblyName = $propertyMap["AssemblyName"]
    if ([string]::IsNullOrWhiteSpace($assemblyName)) {
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
    }

    return [PSCustomObject]@{
        ProjectXml = $projectXml
        Properties = $propertyMap
        PackageVersions = $packageVersionMap
        ProjectName = $assemblyName
    }
}

function Resolve-VersionText {
    param(
        [string]$Value,
        [hashtable]$Properties
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return (Resolve-PropertyValue -Value $Value.Trim() -Properties $Properties -Visited ([System.Collections.Generic.HashSet[string]]::new())).Trim()
}

function Get-PackageReferencesFromProject {
    param(
        [string]$ProjectPath,
        [string]$RootBoundary
    )

    $context = Get-ProjectEvaluationContext -ProjectPath $ProjectPath -RootBoundary $RootBoundary
    $references = New-Object System.Collections.Generic.List[object]

    foreach ($packageReferenceNode in $context.ProjectXml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageReference']")) {
        $packageId = $packageReferenceNode.GetAttribute("Include")
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            $packageId = $packageReferenceNode.GetAttribute("Update")
        }

        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $version = $packageReferenceNode.GetAttribute("Version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            $versionNode = $packageReferenceNode.SelectSingleNode("*[local-name()='Version']")
            if ($null -ne $versionNode) {
                $version = $versionNode.InnerText
            }
        }

        if ([string]::IsNullOrWhiteSpace($version) -and $context.PackageVersions.ContainsKey($packageId.Trim())) {
            $version = $context.PackageVersions[$packageId.Trim()]
        }

        $resolvedVersion = Resolve-VersionText -Value $version -Properties $context.Properties
        if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
            $resolvedVersion = "(unspecified)"
        }

        $references.Add([PSCustomObject]@{
                ProjectName = $context.ProjectName
                PackageId = $packageId.Trim()
                Version = $resolvedVersion
                DeclaredVersion = $version
                ReferenceType = "PackageReference"
            })
    }

    return $references
}

function Get-PackageReferencesFromPackagesConfig {
    param(
        [string]$PackagesConfigPath
    )

    $references = New-Object System.Collections.Generic.List[object]
    $xml = Get-XmlDocument -Path $PackagesConfigPath
    $projectDirectory = Split-Path -Parent $PackagesConfigPath
    $owningProject = Get-ChildItem -LiteralPath $projectDirectory -File | Where-Object {
        $projectExtensions -contains $_.Extension
    } | Sort-Object Name | Select-Object -First 1

    $projectName = if ($null -ne $owningProject) {
        [System.IO.Path]::GetFileNameWithoutExtension($owningProject.Name)
    }
    else {
        Split-Path -Leaf $projectDirectory
    }

    foreach ($packageNode in $xml.SelectNodes("/*[local-name()='packages']/*[local-name()='package']")) {
        $packageId = $packageNode.GetAttribute("id")
        $version = $packageNode.GetAttribute("version")

        if ([string]::IsNullOrWhiteSpace($packageId) -or [string]::IsNullOrWhiteSpace($version)) {
            continue
        }

        $references.Add([PSCustomObject]@{
                ProjectName = $projectName
                PackageId = $packageId.Trim()
                Version = $version.Trim()
                DeclaredVersion = $version.Trim()
                ReferenceType = "packages.config"
            })
    }

    return $references
}

function Get-NuspecPackageMap {
    param(
        [string]$RepositoryPath
    )

    $records = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Queue[System.IO.DirectoryInfo]
    $pending.Enqueue((Get-Item -LiteralPath $RepositoryPath))

    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()

        Get-ChildItem -LiteralPath $current.FullName -File -Filter *.nuspec | ForEach-Object {
            $xml = Get-XmlDocument -Path $_.FullName
            $idNode = $xml.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='id']")

            if ($null -eq $idNode -or [string]::IsNullOrWhiteSpace($idNode.InnerText)) {
                return
            }

            $records.Add([PSCustomObject]@{
                    PackageId = $idNode.InnerText.Trim()
                    NuspecPath = $_.FullName
                })
        }

        Get-ChildItem -LiteralPath $current.FullName -Directory | Where-Object {
            -not (Test-ShouldSkipDirectory -Directory $_)
        } | ForEach-Object {
            $pending.Enqueue($_)
        }
    }

    return $records
}

$allReferences = New-Object System.Collections.Generic.List[object]
$internalPackageSources = @{}
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($projectGroup in $ProjectGroups) {
    $groupPath = Join-Path $resolvedRoot $projectGroup

    if (-not (Test-Path -LiteralPath $groupPath -PathType Container)) {
        $warnings.Add("Skipped project group '$projectGroup' because '$groupPath' does not exist.")
        continue
    }

    Get-ChildItem -LiteralPath $groupPath -Directory | Sort-Object Name | ForEach-Object {
        $repositoryDirectory = $_
        $repositoryName = $repositoryDirectory.Name

        foreach ($packageRecord in (Get-NuspecPackageMap -RepositoryPath $repositoryDirectory.FullName)) {
            if (-not $internalPackageSources.ContainsKey($packageRecord.PackageId)) {
                $internalPackageSources[$packageRecord.PackageId] = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            }

            $internalPackageSources[$packageRecord.PackageId].Add($repositoryName) | Out-Null
        }

        $pending = New-Object System.Collections.Generic.Queue[System.IO.DirectoryInfo]
        $pending.Enqueue($repositoryDirectory)

        while ($pending.Count -gt 0) {
            $current = $pending.Dequeue()

            Get-ChildItem -LiteralPath $current.FullName -File | ForEach-Object {
                $file = $_
                $extension = $file.Extension.ToLowerInvariant()

                if ($projectExtensions -contains $extension) {
                    foreach ($reference in (Get-PackageReferencesFromProject -ProjectPath $file.FullName -RootBoundary $repositoryDirectory.FullName)) {
                        $allReferences.Add([PSCustomObject]@{
                                ProjectGroup = $projectGroup
                                Repository = $repositoryName
                                ProjectName = $reference.ProjectName
                                ProjectPath = Get-RelativePath -BasePath $resolvedRoot -TargetPath $file.FullName
                                PackageId = $reference.PackageId
                                Version = $reference.Version
                                DeclaredVersion = $reference.DeclaredVersion
                                ReferenceType = $reference.ReferenceType
                            })
                    }
                }
                elseif ($file.Name -ieq "packages.config") {
                    foreach ($reference in (Get-PackageReferencesFromPackagesConfig -PackagesConfigPath $file.FullName)) {
                        $allReferences.Add([PSCustomObject]@{
                                ProjectGroup = $projectGroup
                                Repository = $repositoryName
                                ProjectName = $reference.ProjectName
                                ProjectPath = Get-RelativePath -BasePath $resolvedRoot -TargetPath $file.FullName
                                PackageId = $reference.PackageId
                                Version = $reference.Version
                                DeclaredVersion = $reference.DeclaredVersion
                                ReferenceType = $reference.ReferenceType
                            })
                    }
                }
            }

            Get-ChildItem -LiteralPath $current.FullName -Directory | Where-Object {
                -not (Test-ShouldSkipDirectory -Directory $_)
            } | ForEach-Object {
                $pending.Enqueue($_)
            }
        }
    }
}

$orderedReferences = $allReferences | Sort-Object PackageId, @{ Expression = { Get-VersionSortKey -Version $_.Version } }, Repository, ProjectName, ProjectPath
$partOneRows = $orderedReferences | Group-Object PackageId, Version | ForEach-Object {
    $sample = $_.Group | Select-Object -First 1
    $sourceText = if ($internalPackageSources.ContainsKey($sample.PackageId)) {
        (($internalPackageSources[$sample.PackageId] | Sort-Object) -join ", ")
    }
    else {
        "External"
    }

    [PSCustomObject]@{
        PackageId = $sample.PackageId
        Version = $sample.Version
        Source = $sourceText
    }
} | Sort-Object PackageId, @{ Expression = { Get-VersionSortKey -Version $_.Version } }

$groupedByPackage = $orderedReferences | Group-Object PackageId | Sort-Object Name
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("# Package Versions and Dependencies")
$lines.Add("")
$lines.Add("Generated at: $generatedAt")
$lines.Add("")
$lines.Add("Scanned project groups: $($ProjectGroups -join ", ")")
$lines.Add("")

if ($warnings.Count -gt 0) {
    $lines.Add("## Warnings")
    $lines.Add("")

    foreach ($warning in $warnings) {
        $lines.Add("- $warning")
    }

    $lines.Add("")
}

$lines.Add("## Package Version Summary")
$lines.Add("")

if ($partOneRows.Count -eq 0) {
    $lines.Add("No package dependencies were found.")
    $lines.Add("")
}
else {
    $lines.Add("| Package Name | Version | Source |")
    $lines.Add("| --- | --- | --- |")

    foreach ($row in $partOneRows) {
        $lines.Add("| $($row.PackageId) | $($row.Version) | $($row.Source) |")
    }

    $lines.Add("")
}

$lines.Add("## Package Dependency Details")
$lines.Add("")

if ($groupedByPackage.Count -eq 0) {
    $lines.Add("No package dependency details are available.")
}
else {
    foreach ($packageGroup in $groupedByPackage) {
        $packageId = $packageGroup.Name
        $lines.Add("### $packageId")
        $lines.Add("")

        $versionGroups = $packageGroup.Group | Group-Object Version | Sort-Object @{ Expression = { Get-VersionSortKey -Version $_.Name } }

        foreach ($versionGroup in $versionGroups) {
            $lines.Add("#### Version $($versionGroup.Name)")
            $lines.Add("")
            $lines.Add("| Repository | Project | Reference Type | Path |")
            $lines.Add("| --- | --- | --- | --- |")

            foreach ($reference in ($versionGroup.Group | Sort-Object Repository, ProjectName, ProjectPath)) {
                $lines.Add("| $($reference.Repository) | $($reference.ProjectName) | $($reference.ReferenceType) | ``$($reference.ProjectPath)`` |")
            }

            $lines.Add("")
        }
    }
}

$content = ($lines -join "`r`n") + "`r`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath, $content, $utf8NoBom)

Write-Host ("Scanned {0} package references across {1} repositories." -f $orderedReferences.Count, (($orderedReferences | Select-Object -ExpandProperty Repository -Unique).Count))
Write-Host ("Markdown written to '{0}'." -f $OutputPath)
