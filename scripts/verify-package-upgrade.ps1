param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias("Path")]
    [string[]]$RepositoryPath,

    [switch]$RunTest,

    [switch]$AsJson,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$script:TextExtensions = @(
    ".cs",
    ".csproj",
    ".fsproj",
    ".vbproj",
    ".props",
    ".targets",
    ".sln",
    ".slnx",
    ".json",
    ".yml",
    ".yaml",
    ".md",
    ".ps1",
    ".nuspec",
    ".xml",
    ".config",
    ".txt"
)

$script:ExcludedDirectoryNames = @(
    ".git",
    ".vs",
    "bin",
    "obj",
    "packages",
    "artifacts",
    "TestResults"
)

$dotnetCommand = Get-Command -Name dotnet -CommandType Application -ErrorAction Stop

function Resolve-WorkspacePath {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw "RepositoryPath cannot be empty."
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $PathValue))
}

function Test-ShouldSkipPath {
    param(
        [string]$FullName
    )

    foreach ($dir in $script:ExcludedDirectoryNames) {
        $pattern = "(^|[\\/])$([regex]::Escape($dir))([\\/]|$)"
        if ($FullName -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-OutputExcerpt {
    param(
        [string]$Text,
        [int]$HeadLineCount = 12,
        [int]$TailLineCount = 12
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $lines = @($Text -split "\r?\n")
    if ($lines.Count -le ($HeadLineCount + $TailLineCount)) {
        return ($lines -join "`r`n").Trim()
    }

    $head = $lines | Select-Object -First $HeadLineCount
    $tail = $lines | Select-Object -Last $TailLineCount
    return (($head + @("...")) + $tail) -join "`r`n"
}

function Get-XmlDocument {
    param(
        [string]$Path
    )

    try {
        return [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    }
    catch {
        return $null
    }
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

function Get-PropertyMapFromXmlDocument {
    param(
        [xml]$XmlDocument
    )

    $map = @{}

    if ($null -eq $XmlDocument) {
        return $map
    }

    foreach ($propertyGroup in $XmlDocument.SelectNodes("/*[local-name()='Project']/*[local-name()='PropertyGroup']")) {
        foreach ($propertyNode in $propertyGroup.ChildNodes) {
            if ($propertyNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                continue
            }

            $propertyValue = ""
            if ($null -ne $propertyNode.InnerText) {
                $propertyValue = $propertyNode.InnerText.Trim()
            }

            $map[$propertyNode.LocalName] = $propertyValue
        }
    }

    return $map
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

function Normalize-VersionText {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = $Value.Trim()
    $normalized = $normalized.Trim('"').Trim("'")

    if ($normalized.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase) -and $normalized.Length -gt 1) {
        $remainder = $normalized.Substring(1)
        if ($remainder -match '^\d') {
            $normalized = $remainder
        }
    }

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    return $normalized
}

function Get-ProjectPropertyMap {
    param(
        [string]$ProjectPath,
        [string]$RepositoryRoot
    )

    $projectXml = Get-XmlDocument -Path $ProjectPath
    if ($null -eq $projectXml) {
        return @{}
    }

    $projectDirectory = Split-Path -Parent $ProjectPath
    $propertyFiles = @(Get-DirectoryAncestorProps -ProjectDirectory $projectDirectory -RootBoundary $RepositoryRoot)
    $propertyMap = @{}

    foreach ($propertyFile in $propertyFiles) {
        $xml = Get-XmlDocument -Path $propertyFile
        $fileProperties = Get-PropertyMapFromXmlDocument -XmlDocument $xml

        foreach ($propertyName in $fileProperties.Keys) {
            $propertyMap[$propertyName] = $fileProperties[$propertyName]
        }
    }

    $projectProperties = Get-PropertyMapFromXmlDocument -XmlDocument $projectXml
    foreach ($propertyName in $projectProperties.Keys) {
        $propertyMap[$propertyName] = $projectProperties[$propertyName]
    }

    return $propertyMap
}

function Get-ResolvedVersionValue {
    param(
        [string]$Value,
        [hashtable]$PropertyMap
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $resolvedValue = Resolve-PropertyValue -Value $Value -Properties $PropertyMap -Visited (New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase))
    if ($resolvedValue -match '\$\(') {
        return $null
    }

    return Normalize-VersionText -Value $resolvedValue
}

function Get-PackageIdFromItemNode {
    param(
        [System.Xml.XmlNode]$ItemNode
    )

    foreach ($attributeName in @("Include", "Update")) {
        $attributeValue = $ItemNode.GetAttribute($attributeName)
        if (-not [string]::IsNullOrWhiteSpace($attributeValue)) {
            return $attributeValue.Trim()
        }
    }

    return $null
}

function Get-PackageVersionFromItemNode {
    param(
        [System.Xml.XmlNode]$ItemNode,
        [hashtable]$PropertyMap
    )

    $versionValue = $ItemNode.GetAttribute("Version")
    if ([string]::IsNullOrWhiteSpace($versionValue)) {
        $versionChild = $ItemNode.SelectSingleNode("*[local-name()='Version']")
        if ($null -ne $versionChild -and -not [string]::IsNullOrWhiteSpace($versionChild.InnerText)) {
            $versionValue = $versionChild.InnerText.Trim()
        }
    }

    return Get-ResolvedVersionValue -Value $versionValue -PropertyMap $PropertyMap
}

function Get-NearbyPackagesConfigMap {
    param(
        [string]$ProjectPath
    )

    $packagesConfigPath = Join-Path (Split-Path -Parent $ProjectPath) "packages.config"
    $map = @{}

    if (-not (Test-Path -LiteralPath $packagesConfigPath -PathType Leaf)) {
        return $map
    }

    $packagesConfigXml = Get-XmlDocument -Path $packagesConfigPath
    if ($null -eq $packagesConfigXml) {
        return $map
    }

    foreach ($packageNode in $packagesConfigXml.SelectNodes("/*[local-name()='packages']/*[local-name()='package']")) {
        $packageId = $packageNode.GetAttribute("id")
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $version = Normalize-VersionText -Value $packageNode.GetAttribute("version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            continue
        }

        $map[$packageId] = [PSCustomObject]@{
            PackageId = $packageId
            Version = $version
            Source = $packagesConfigPath
            SourceKind = "PackagesConfig"
        }
    }

    return $map
}

function Get-ProjectDependencyInfo {
    param(
        [string]$ProjectPath,
        [string]$RepositoryRoot
    )

    $projectXml = Get-XmlDocument -Path $ProjectPath
    if ($null -eq $projectXml) {
        return $null
    }

    $propertyMap = Get-ProjectPropertyMap -ProjectPath $ProjectPath -RepositoryRoot $RepositoryRoot
    $projectDirectory = Split-Path -Parent $ProjectPath
    $propertyFiles = @(Get-DirectoryAncestorProps -ProjectDirectory $projectDirectory -RootBoundary $RepositoryRoot)

    $centralVersionMap = @{}
    $packageReferenceMap = @{}

    foreach ($propertyFile in $propertyFiles) {
        $propertyXml = Get-XmlDocument -Path $propertyFile
        if ($null -eq $propertyXml) {
            continue
        }

        foreach ($packageVersionNode in $propertyXml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageVersion']")) {
            $packageId = Get-PackageIdFromItemNode -ItemNode $packageVersionNode
            if ([string]::IsNullOrWhiteSpace($packageId)) {
                continue
            }

            $resolvedVersion = Get-PackageVersionFromItemNode -ItemNode $packageVersionNode -PropertyMap $propertyMap
            if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
                continue
            }

            $centralVersionMap[$packageId] = [PSCustomObject]@{
                PackageId = $packageId
                Version = $resolvedVersion
                Source = $propertyFile
                SourceKind = "PackageVersion"
            }
        }

        foreach ($packageReferenceNode in $propertyXml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageReference']")) {
            $packageId = Get-PackageIdFromItemNode -ItemNode $packageReferenceNode
            if ([string]::IsNullOrWhiteSpace($packageId)) {
                continue
            }

            $resolvedVersion = Get-PackageVersionFromItemNode -ItemNode $packageReferenceNode -PropertyMap $propertyMap
            if ([string]::IsNullOrWhiteSpace($resolvedVersion) -and $centralVersionMap.ContainsKey($packageId)) {
                $resolvedVersion = $centralVersionMap[$packageId].Version
            }

            if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
                continue
            }

            $packageReferenceMap[$packageId] = [PSCustomObject]@{
                PackageId = $packageId
                Version = $resolvedVersion
                Source = $propertyFile
                SourceKind = "PropsPackageReference"
            }
        }
    }

    foreach ($packageReferenceNode in $projectXml.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='PackageReference']")) {
        $packageId = Get-PackageIdFromItemNode -ItemNode $packageReferenceNode
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $resolvedVersion = Get-PackageVersionFromItemNode -ItemNode $packageReferenceNode -PropertyMap $propertyMap
        if ([string]::IsNullOrWhiteSpace($resolvedVersion) -and $centralVersionMap.ContainsKey($packageId)) {
            $resolvedVersion = $centralVersionMap[$packageId].Version
        }

        if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
            continue
        }

        $packageReferenceMap[$packageId] = [PSCustomObject]@{
            PackageId = $packageId
            Version = $resolvedVersion
            Source = $ProjectPath
            SourceKind = "ProjectPackageReference"
        }
    }

    $packagesConfigMap = Get-NearbyPackagesConfigMap -ProjectPath $ProjectPath
    foreach ($packageId in $packagesConfigMap.Keys) {
        if (-not $packageReferenceMap.ContainsKey($packageId)) {
            $packageReferenceMap[$packageId] = $packagesConfigMap[$packageId]
        }
    }

    return [PSCustomObject]@{
        ProjectPath = $ProjectPath
        PackageReferences = @($packageReferenceMap.Values | Sort-Object PackageId)
        PackageReferenceMap = $packageReferenceMap
    }
}

function Get-NuspecDependencyInfo {
    param(
        [string]$NuspecPath
    )

    $nuspecXml = Get-XmlDocument -Path $NuspecPath
    if ($null -eq $nuspecXml) {
        return $null
    }

    $packageIdNode = $nuspecXml.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='id']")
    $packageId = $null

    if ($null -ne $packageIdNode -and -not [string]::IsNullOrWhiteSpace($packageIdNode.InnerText)) {
        $packageId = $packageIdNode.InnerText.Trim()
    }

    $dependencyMap = @{}
    $dependencyNodes = $nuspecXml.SelectNodes("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='dependencies']/*[local-name()='dependency'] | /*[local-name()='package']/*[local-name()='metadata']/*[local-name()='dependencies']/*[local-name()='group']/*[local-name()='dependency']")
    foreach ($dependencyNode in $dependencyNodes) {
        $dependencyId = $dependencyNode.GetAttribute("id")
        if ([string]::IsNullOrWhiteSpace($dependencyId)) {
            continue
        }

        $dependencyVersion = Normalize-VersionText -Value $dependencyNode.GetAttribute("version")
        if ([string]::IsNullOrWhiteSpace($dependencyVersion)) {
            continue
        }

        $dependencyMap[$dependencyId] = [PSCustomObject]@{
            PackageId = $dependencyId
            Version = $dependencyVersion
            Source = $NuspecPath
        }
    }

    return [PSCustomObject]@{
        NuspecPath = $NuspecPath
        PackageId = $packageId
        Dependencies = @($dependencyMap.Values | Sort-Object PackageId)
        DependencyMap = $dependencyMap
    }
}

function Get-IdentifierVariants {
    param(
        [string]$Value
    )

    $variants = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($Value.Trim())

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ([string]::IsNullOrWhiteSpace($current)) {
            continue
        }

        if (-not $variants.Add($current)) {
            continue
        }

        foreach ($suffix in @("Actor", ".IntegrationTests", "IntegrationTests", ".UnitTests", "UnitTests", ".Tests", "Tests")) {
            if ($current.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase) -and $current.Length -gt $suffix.Length) {
                $trimmed = $current.Substring(0, $current.Length - $suffix.Length).TrimEnd('.', '-')
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $queue.Enqueue($trimmed)
                }
            }
        }

        $segments = $current -split '\.'
        if ($segments.Length -gt 1) {
            $queue.Enqueue($segments[-1])
            $queue.Enqueue(($segments[-2..-1] -join '.'))
        }
    }

    return @($variants)
}

function Find-AssociatedProjectFile {
    param(
        [object]$NuspecInfo,
        [object[]]$ProjectFiles
    )

    if ($null -eq $ProjectFiles -or $ProjectFiles.Count -eq 0) {
        return $null
    }

    $nuspecPath = $NuspecInfo.NuspecPath
    $nuspecStem = [System.IO.Path]::GetFileNameWithoutExtension($nuspecPath)
    $nuspecDirectory = Split-Path -Parent $nuspecPath
    $packageId = $NuspecInfo.PackageId

    $exactStemMatches = @($ProjectFiles | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -ieq $nuspecStem })
    if ($exactStemMatches.Count -eq 1) {
        return [PSCustomObject]@{
            Path = $exactStemMatches[0].FullName
            MatchType = "ExactStem"
            IsAmbiguous = $false
        }
    }

    if ($exactStemMatches.Count -gt 1) {
        $sameDirectoryMatches = @($exactStemMatches | Where-Object { (Split-Path -Parent $_) -ieq $nuspecDirectory })
        if ($sameDirectoryMatches.Count -eq 1) {
            return [PSCustomObject]@{
                Path = $sameDirectoryMatches[0].FullName
                MatchType = "ExactStemSameDirectory"
                IsAmbiguous = $false
            }
        }

        return [PSCustomObject]@{
            Path = $null
            MatchType = "AmbiguousExactStem"
            IsAmbiguous = $true
        }
    }

    $sameDirectoryProjects = @($ProjectFiles | Where-Object { (Split-Path -Parent $_) -ieq $nuspecDirectory })
    if ($sameDirectoryProjects.Count -eq 1) {
        return [PSCustomObject]@{
            Path = $sameDirectoryProjects[0].FullName
            MatchType = "SameDirectory"
            IsAmbiguous = $false
        }
    }

    $candidateKeys = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($nuspecStem, $packageId)) {
        foreach ($variant in (Get-IdentifierVariants -Value $value)) {
            [void]$candidateKeys.Add($variant)
        }
    }

    $variantMatches = @(
        $ProjectFiles | Where-Object {
            $projectStem = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)
            foreach ($projectVariant in (Get-IdentifierVariants -Value $projectStem)) {
                if ($candidateKeys.Contains($projectVariant)) {
                    return $true
                }
            }

            return $false
        }
    )

    if ($variantMatches.Count -eq 1) {
        return [PSCustomObject]@{
            Path = $variantMatches[0].FullName
            MatchType = "VariantStem"
            IsAmbiguous = $false
        }
    }

    if ($variantMatches.Count -gt 1) {
        $sameDirectoryVariantMatches = @($variantMatches | Where-Object { (Split-Path -Parent $_.FullName) -ieq $nuspecDirectory })
        if ($sameDirectoryVariantMatches.Count -eq 1) {
            return [PSCustomObject]@{
                Path = $sameDirectoryVariantMatches[0].FullName
                MatchType = "VariantStemSameDirectory"
                IsAmbiguous = $false
            }
        }

        return [PSCustomObject]@{
            Path = $null
            MatchType = "AmbiguousVariantStem"
            IsAmbiguous = $true
        }
    }

    if ($ProjectFiles.Count -eq 1) {
        return [PSCustomObject]@{
            Path = $ProjectFiles[0].FullName
            MatchType = "SingleProject"
            IsAmbiguous = $false
        }
    }

    return [PSCustomObject]@{
        Path = $null
        MatchType = "Ambiguous"
        IsAmbiguous = $true
    }
}

function Get-DependencyConsistencyReport {
    param(
        [string]$RepositoryRoot
    )

    $nuspecFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter *.nuspec -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-ShouldSkipPath -FullName $_.FullName) } |
        Sort-Object FullName

    $projectFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".csproj", ".fsproj", ".vbproj", ".sfproj") } |
        Where-Object { -not (Test-ShouldSkipPath -FullName $_.FullName) } |
        Sort-Object FullName

    $checks = New-Object System.Collections.Generic.List[object]

    if (@($nuspecFiles).Count -eq 0) {
        return [PSCustomObject]@{
            Status = "Skipped"
            Note = "No nuspec files were found."
            NuspecFileCount = 0
            ProjectFileCount = @($projectFiles).Count
            NuspecFiles = @()
            ProjectFiles = @($projectFiles | ForEach-Object { $_.FullName })
            Checks = @()
            PassedCheckCount = 0
            FailedCheckCount = 0
            SkippedCheckCount = 0
            ReservedCheckCount = 0
        }
    }

    if (@($projectFiles).Count -eq 0) {
        return [PSCustomObject]@{
            Status = "Skipped"
            Note = "No project files were found."
            NuspecFileCount = @($nuspecFiles).Count
            ProjectFileCount = 0
            NuspecFiles = @($nuspecFiles | ForEach-Object { $_.FullName })
            ProjectFiles = @()
            Checks = @()
            PassedCheckCount = 0
            FailedCheckCount = 0
            SkippedCheckCount = 0
            ReservedCheckCount = 0
        }
    }

    foreach ($nuspecFile in $nuspecFiles) {
        $nuspecInfo = Get-NuspecDependencyInfo -NuspecPath $nuspecFile.FullName
        if ($null -eq $nuspecInfo) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $null
                    ProjectPath = $null
                    MatchType = "Unknown"
                    Status = "Reserved"
                    Reason = "Unable to parse nuspec file."
                })
            continue
        }

        $projectMatch = Find-AssociatedProjectFile -NuspecInfo $nuspecInfo -ProjectFiles $projectFiles
        if ($null -eq $projectMatch) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $null
                    MatchType = $null
                    Status = "Skipped"
                    Reason = "No matching project file was found."
                })
            continue
        }

        if ($projectMatch.IsAmbiguous) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $null
                    MatchType = $projectMatch.MatchType
                    Status = "Reserved"
                    Reason = "Multiple project candidates matched this nuspec."
                })
            continue
        }

        $projectInfo = Get-ProjectDependencyInfo -ProjectPath $projectMatch.Path -RepositoryRoot $RepositoryRoot
        if ($null -eq $projectInfo) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $projectMatch.Path
                    MatchType = $projectMatch.MatchType
                    Status = "Skipped"
                    Reason = "Project dependencies could not be read."
                })
            continue
        }

        if ($nuspecInfo.Dependencies.Count -eq 0) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $projectMatch.Path
                    MatchType = $projectMatch.MatchType
                    Status = "Skipped"
                    Reason = "No nuspec dependencies were declared."
                    NuspecDependencyCount = 0
                    ProjectPackageReferenceCount = @($projectInfo.PackageReferences).Count
                    DependencyDiffs = @()
                })
            continue
        }

        $dependencyDiffs = New-Object System.Collections.Generic.List[object]
        $candidateIds = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dependency in $nuspecInfo.Dependencies) {
            [void]$candidateIds.Add($dependency.PackageId)
        }
        foreach ($packageReference in $projectInfo.PackageReferences) {
            [void]$candidateIds.Add($packageReference.PackageId)
        }

        foreach ($candidateId in ($candidateIds | Sort-Object)) {
            $nuspecDependency = $null
            $projectDependency = $null

            if ($nuspecInfo.DependencyMap.ContainsKey($candidateId)) {
                $nuspecDependency = $nuspecInfo.DependencyMap[$candidateId]
            }

            if ($projectInfo.PackageReferenceMap.ContainsKey($candidateId)) {
                $projectDependency = $projectInfo.PackageReferenceMap[$candidateId]
            }

            if ($null -eq $nuspecDependency) {
                $dependencyDiffs.Add([PSCustomObject]@{
                        PackageId = $candidateId
                        NuspecVersion = $null
                        ProjectVersion = $projectDependency.Version
                        Status = "MissingInNuspec"
                        Reason = "Package reference exists in the project but is not declared in nuspec dependencies."
                    })
                continue
            }

            if ($null -eq $projectDependency) {
                $dependencyDiffs.Add([PSCustomObject]@{
                        PackageId = $candidateId
                        NuspecVersion = $nuspecDependency.Version
                        ProjectVersion = $null
                        Status = "MissingInProject"
                        Reason = "Dependency exists in nuspec but not in the matched project package references."
                    })
                continue
            }

            if ($nuspecDependency.Version -ine $projectDependency.Version) {
                $dependencyDiffs.Add([PSCustomObject]@{
                        PackageId = $candidateId
                        NuspecVersion = $nuspecDependency.Version
                        ProjectVersion = $projectDependency.Version
                        Status = "VersionMismatch"
                        Reason = "Dependency version differs between nuspec and project."
                    })
            }
        }

        if ($dependencyDiffs.Count -eq 0) {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $projectMatch.Path
                    MatchType = $projectMatch.MatchType
                    Status = "Passed"
                    Reason = "All nuspec dependencies match the project package references."
                    NuspecDependencyCount = $nuspecInfo.Dependencies.Count
                    ProjectPackageReferenceCount = @($projectInfo.PackageReferences).Count
                    DependencyDiffs = @()
                })
        }
        else {
            $checks.Add([PSCustomObject]@{
                    NuspecPath = $nuspecFile.FullName
                    PackageId = $nuspecInfo.PackageId
                    ProjectPath = $projectMatch.Path
                    MatchType = $projectMatch.MatchType
                    Status = "Failed"
                    Reason = "One or more nuspec dependencies differ from the project package references."
                    NuspecDependencyCount = $nuspecInfo.Dependencies.Count
                    ProjectPackageReferenceCount = @($projectInfo.PackageReferences).Count
                    DependencyDiffs = @($dependencyDiffs.ToArray())
                })
        }
    }

    $checkArray = @($checks.ToArray())
    $passedCount = @($checkArray | Where-Object { $_.Status -eq "Passed" }).Count
    $failedCount = @($checkArray | Where-Object { $_.Status -eq "Failed" }).Count
    $skippedCount = @($checkArray | Where-Object { $_.Status -eq "Skipped" }).Count
    $reservedCount = @($checkArray | Where-Object { $_.Status -eq "Reserved" }).Count

    $status = "Skipped"
    $note = "Dependency consistency checks did not produce a definitive result."

    if ($failedCount -gt 0) {
        $status = "Failed"
        $note = "One or more nuspec dependencies differ from the matched project package references."
    }
    elseif ($passedCount -gt 0 -and $skippedCount -eq 0 -and $reservedCount -eq 0) {
        $status = "Passed"
        $note = "All checked nuspec dependencies match the matched project package references."
    }
    elseif ($reservedCount -gt 0) {
        $status = "Reserved"
        $note = "Some nuspec files require manual review because the project match is ambiguous."
    }
    elseif ($passedCount -gt 0) {
        $status = "Skipped"
        $note = "Some nuspec files matched, but not every nuspec dependency set could be compared."
    }

    return [PSCustomObject]@{
        Status = $status
        Note = $note
        NuspecFileCount = @($nuspecFiles).Count
        ProjectFileCount = @($projectFiles).Count
        NuspecFiles = @($nuspecFiles | ForEach-Object { $_.FullName })
        ProjectFiles = @($projectFiles | ForEach-Object { $_.FullName })
        Checks = $checkArray
        PassedCheckCount = $passedCount
        FailedCheckCount = $failedCount
        SkippedCheckCount = $skippedCount
        ReservedCheckCount = $reservedCount
    }
}

function Invoke-DotNetCommand {
    param(
        [string]$WorkingDirectory,
        [string[]]$Arguments,
        [string]$CheckName
    )

    $commandText = ("{0} {1}" -f $dotnetCommand.Source, ($Arguments -join " ")).Trim()
    $startedAt = Get-Date
    $outputText = ""
    $exitCode = 0
    $status = "Passed"
    $errorMessage = $null

    try {
        Push-Location -LiteralPath $WorkingDirectory
        $output = & $dotnetCommand.Source @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = (@($output) -join "`r`n").Trim()

        if ($exitCode -ne 0) {
            $status = "Failed"
        }
    }
    catch {
        $status = "Failed"
        $exitCode = -1
        $errorMessage = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $outputText = $errorMessage
        }
    }
    finally {
        Pop-Location -ErrorAction SilentlyContinue
    }

    $completedAt = Get-Date
    $duration = [int][Math]::Max(0, ($completedAt - $startedAt).TotalMilliseconds)

    if ($status -eq "Passed") {
        $summary = "Passed"
    }
    else {
        $summary = if ($exitCode -eq -1 -and -not [string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage } else { "Exit code $exitCode" }
    }

    return [PSCustomObject]@{
        CheckName = $CheckName
        Command = $commandText
        WorkingDirectory = $WorkingDirectory
        Status = $status
        ExitCode = $exitCode
        StartedAt = $startedAt.ToString("o")
        CompletedAt = $completedAt.ToString("o")
        DurationMs = $duration
        OutputLineCount = if ([string]::IsNullOrWhiteSpace($outputText)) { 0 } else { @($outputText -split "\r?\n").Count }
        OutputExcerpt = Get-OutputExcerpt -Text $outputText
        Summary = $summary
    }
}

function Test-IsTestProject {
    param(
        [string]$ProjectPath
    )

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
        return $false
    }

    $content = Get-Content -LiteralPath $ProjectPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $false
    }

    return ($content -match '<IsTestProject>\s*true\s*</IsTestProject>') -or ($content -match 'Microsoft\.NET\.Test\.Sdk')
}

function Get-PrimaryEntryPoint {
    param(
        [string]$RepositoryRoot
    )

    $searchOrders = @(
        @{ Depth = 0; Pattern = "*.slnx"; Label = "Solution" },
        @{ Depth = 0; Pattern = "*.sln"; Label = "Solution" },
        @{ Depth = 0; Pattern = "*.csproj"; Label = "Project" },
        @{ Depth = 0; Pattern = "*.fsproj"; Label = "Project" },
        @{ Depth = 0; Pattern = "*.vbproj"; Label = "Project" },
        @{ Depth = 0; Pattern = "*.sfproj"; Label = "Project" },
        @{ Depth = 1; Pattern = "*.slnx"; Label = "Solution" },
        @{ Depth = 1; Pattern = "*.sln"; Label = "Solution" },
        @{ Depth = 1; Pattern = "*.csproj"; Label = "Project" },
        @{ Depth = 1; Pattern = "*.fsproj"; Label = "Project" },
        @{ Depth = 1; Pattern = "*.vbproj"; Label = "Project" },
        @{ Depth = 1; Pattern = "*.sfproj"; Label = "Project" }
    )

    foreach ($search in $searchOrders) {
        if ($search.Depth -eq 0) {
            $items = Get-ChildItem -LiteralPath $RepositoryRoot -File -Filter $search.Pattern -ErrorAction SilentlyContinue | Sort-Object Name
        }
        else {
            $items = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter $search.Pattern -ErrorAction SilentlyContinue | Where-Object { -not (Test-ShouldSkipPath -FullName $_.FullName) } | Sort-Object FullName
        }

        if (@($items).Count -gt 0) {
            $item = $items | Select-Object -First 1
            return [PSCustomObject]@{
                Path = $item.FullName
                Kind = $search.Label
                SearchDepth = $search.Depth
            }
        }
    }

    return $null
}

function Get-TestTargets {
    param(
        [string]$RepositoryRoot
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $projectFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".csproj", ".fsproj", ".vbproj", ".sfproj") } |
        Where-Object { -not (Test-ShouldSkipPath -FullName $_.FullName) } |
        Sort-Object FullName

    foreach ($project in $projectFiles) {
        if (Test-IsTestProject -ProjectPath $project.FullName) {
            $targets.Add([PSCustomObject]@{
                    Path = $project.FullName
                    Kind = "TestProject"
                })
        }
    }

    return $targets
}

function Get-CrlfReport {
    param(
        [string]$RepositoryRoot
    )

    $offendingFiles = New-Object System.Collections.Generic.List[string]
    $inspectedCount = 0

    $files = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $script:TextExtensions -contains $_.Extension.ToLowerInvariant() -and -not (Test-ShouldSkipPath -FullName $_.FullName)
        }

    foreach ($file in $files) {
        $inspectedCount++
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -eq 10) {
                if ($index -eq 0 -or $bytes[$index - 1] -ne 13) {
                    $offendingFiles.Add($file.FullName)
                    break
                }
            }
        }
    }

    return [PSCustomObject]@{
        Status = if ($offendingFiles.Count -eq 0) { "Passed" } else { "Failed" }
        InspectedFileCount = $inspectedCount
        OffendingFileCount = $offendingFiles.Count
        OffendingFiles = @($offendingFiles)
    }
}

function Get-DependencyConsistencyPlaceholder {
    param(
        [string]$RepositoryRoot
    )

    return Get-DependencyConsistencyReport -RepositoryRoot $RepositoryRoot
}

function Write-CheckSummary {
    param(
        [string]$Label,
        [object]$CheckResult
    )

    $suffix = ""
    if ($null -ne $CheckResult) {
        if ($CheckResult.Status -eq "Passed") {
            $suffix = "Passed in $($CheckResult.DurationMs) ms"
        }
        elseif ($CheckResult.Status -eq "Skipped") {
            $suffix = "Skipped: $($CheckResult.Reason)"
        }
        elseif ($CheckResult.Status -eq "Reserved") {
            $suffix = "Reserved: $($CheckResult.Note)"
        }
        else {
            $suffix = "Failed: $($CheckResult.Summary)"
        }
    }

    Write-Host ("    {0}: {1}" -f $Label, $suffix)
}

$repositoryResults = New-Object System.Collections.Generic.List[object]

foreach ($repositoryInput in $RepositoryPath) {
    $resolvedRepository = Resolve-WorkspacePath -PathValue $repositoryInput
    if (-not (Test-Path -LiteralPath $resolvedRepository)) {
        throw "RepositoryPath was not found: '$resolvedRepository'."
    }

    $repositoryRoot = if ((Test-Path -LiteralPath $resolvedRepository -PathType Leaf)) {
        Split-Path -Parent $resolvedRepository
    }
    else {
        $resolvedRepository
    }

    $primaryEntryPoint = Get-PrimaryEntryPoint -RepositoryRoot $repositoryRoot
    $testTargets = Get-TestTargets -RepositoryRoot $repositoryRoot

    $restoreResult = $null
    $buildResult = $null
    $testResult = $null

    if ($null -ne $primaryEntryPoint) {
        $restoreResult = Invoke-DotNetCommand -WorkingDirectory $repositoryRoot -Arguments @("restore", $primaryEntryPoint.Path) -CheckName "Restore"

        if ($restoreResult.Status -eq "Passed") {
            $buildResult = Invoke-DotNetCommand -WorkingDirectory $repositoryRoot -Arguments @("build", $primaryEntryPoint.Path, "--no-restore") -CheckName "Build"
        }
        else {
            $buildResult = [PSCustomObject]@{
                CheckName = "Build"
                Command = "dotnet build $($primaryEntryPoint.Path) --no-restore"
                WorkingDirectory = $repositoryRoot
                Status = "Skipped"
                ExitCode = $null
                StartedAt = $null
                CompletedAt = $null
                DurationMs = 0
                OutputLineCount = 0
                OutputExcerpt = ""
                Summary = "Build skipped because restore failed."
                Reason = "Restore failed."
            }
        }
    }
    else {
        $restoreResult = [PSCustomObject]@{
            CheckName = "Restore"
            Command = "dotnet restore"
            WorkingDirectory = $repositoryRoot
            Status = "Skipped"
            ExitCode = $null
            StartedAt = $null
            CompletedAt = $null
            DurationMs = 0
            OutputLineCount = 0
            OutputExcerpt = ""
            Summary = "No solution or project entry point was found."
            Reason = "No entry point found."
        }

        $buildResult = [PSCustomObject]@{
            CheckName = "Build"
            Command = "dotnet build"
            WorkingDirectory = $repositoryRoot
            Status = "Skipped"
            ExitCode = $null
            StartedAt = $null
            CompletedAt = $null
            DurationMs = 0
            OutputLineCount = 0
            OutputExcerpt = ""
            Summary = "No solution or project entry point was found."
            Reason = "No entry point found."
        }
    }

    $testEntries = New-Object System.Collections.Generic.List[object]
    if ($RunTest) {
        if ($testTargets.Count -eq 0) {
            $testResult = [PSCustomObject]@{
                Status = "Skipped"
                Reason = "No test projects were detected."
                Targets = @()
            }
        }
        else {
            foreach ($testTarget in $testTargets) {
                $testInvocation = Invoke-DotNetCommand -WorkingDirectory $repositoryRoot -Arguments @("test", $testTarget.Path, "--no-restore") -CheckName "Test"
                $testEntries.Add([PSCustomObject]@{
                        Path = $testTarget.Path
                        Kind = $testTarget.Kind
                        Result = $testInvocation
                    })
            }

            $aggregateStatus = "Passed"
            $failingTestEntries = @($testEntries.ToArray() | Where-Object { $_.Result.Status -ne "Passed" })
            if ($failingTestEntries.Count -gt 0) {
                $aggregateStatus = "Failed"
            }

            $testResult = [PSCustomObject]@{
                Status = $aggregateStatus
                Reason = if ($aggregateStatus -eq "Passed") { "All detected test projects passed." } else { "One or more test projects failed." }
                Targets = @($testEntries.ToArray())
            }
        }
    }
    else {
        $testResult = [PSCustomObject]@{
            Status = "Skipped"
            Reason = "RunTest switch was not set."
            Targets = @()
        }
    }

    $repositoryResult = [PSCustomObject]@{
        RepositoryPath = $repositoryRoot
        InputPath = $resolvedRepository
        PrimaryEntryPoint = if ($null -ne $primaryEntryPoint) { $primaryEntryPoint.Path } else { $null }
        EntryPointKind = if ($null -ne $primaryEntryPoint) { $primaryEntryPoint.Kind } else { $null }
        PrimaryEntryPointSearchDepth = if ($null -ne $primaryEntryPoint) { $primaryEntryPoint.SearchDepth } else { $null }
        Restore = $restoreResult
        Build = $buildResult
        Tests = $testResult
        CrLf = Get-CrlfReport -RepositoryRoot $repositoryRoot
        DependencyConsistency = Get-DependencyConsistencyPlaceholder -RepositoryRoot $repositoryRoot
    }

    $repositoryResults.Add($repositoryResult)
}

$repositoryResultsArray = @($repositoryResults.ToArray())

    $summary = [PSCustomObject]@{
        TotalRepositories = $repositoryResultsArray.Count
        PassedRepositories = (@($repositoryResultsArray | Where-Object { $_.Restore.Status -eq "Passed" -and $_.Build.Status -eq "Passed" -and $_.CrLf.Status -eq "Passed" -and ($_.Tests.Status -eq "Passed" -or $_.Tests.Status -eq "Skipped") -and $_.DependencyConsistency.Status -in @("Reserved", "Passed", "Skipped") }).Count)
    FailedRepositories = (@($repositoryResultsArray | Where-Object { $_.Restore.Status -eq "Failed" -or $_.Build.Status -eq "Failed" -or $_.CrLf.Status -eq "Failed" -or ($_.Tests.Status -eq "Failed") -or $_.DependencyConsistency.Status -eq "Failed" }).Count)
    SkippedRepositories = (@($repositoryResultsArray | Where-Object { $_.Restore.Status -eq "Skipped" -and $_.Build.Status -eq "Skipped" }).Count)
    RunTest = [bool]$RunTest
}

$report = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString("o")
    Tool = "verify-package-upgrade.ps1"
    ReportKind = "Framework"
    Repositories = $repositoryResultsArray
    Summary = $summary
}

Write-Host ("Verified {0} repository target(s)." -f $summary.TotalRepositories)
foreach ($repository in $repositoryResultsArray) {
    Write-Host ("Repository: {0}" -f $repository.RepositoryPath)
    if ($null -ne $repository.PrimaryEntryPoint) {
        Write-Host ("  Primary entry point: {0} ({1})" -f $repository.PrimaryEntryPoint, $repository.EntryPointKind)
    }
    else {
        Write-Host "  Primary entry point: not found"
    }

    Write-CheckSummary -Label "Restore" -CheckResult $repository.Restore
    Write-CheckSummary -Label "Build" -CheckResult $repository.Build

    if ($repository.Tests.Status -eq "Skipped") {
        Write-Host ("    Test: Skipped: {0}" -f $repository.Tests.Reason)
    }
    else {
        Write-Host ("    Test: {0}" -f $repository.Tests.Status)
        foreach ($target in $repository.Tests.Targets) {
            Write-Host ("      {0}: {1}" -f $target.Path, $target.Result.Status)
        }
    }

    Write-Host ("    CRLF: {0} (inspected {1}, offending {2})" -f $repository.CrLf.Status, $repository.CrLf.InspectedFileCount, $repository.CrLf.OffendingFileCount)
    Write-Host ("    Dependency consistency: {0}" -f $repository.DependencyConsistency.Status)
}

if ($AsJson) {
    $json = $report | ConvertTo-Json -Depth 10

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $outputDirectory = [System.IO.Path]::GetDirectoryName((Resolve-WorkspacePath -PathValue $OutputPath))
        if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
            throw "OutputPath must include a file name."
        }

        $resolvedOutputPath = Resolve-WorkspacePath -PathValue $OutputPath
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null
        [System.IO.File]::WriteAllText($resolvedOutputPath, ($json + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    }

    Write-Output $json
}
else {
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutputPath = Resolve-WorkspacePath -PathValue $OutputPath
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null
        [System.IO.File]::WriteAllText($resolvedOutputPath, (($report | ConvertTo-Json -Depth 10) + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    }

    Write-Output $report
}
