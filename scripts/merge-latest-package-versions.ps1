#Requires -Version 5.1
<#
.SYNOPSIS
  Merge doc/package-versions.json and doc/shared-package-versions.json into one latest-version map.

.DESCRIPTION
  Rules: for each package ID present in either source, if shared-package-versions has a non-empty
  latestVersion and no error, use that; otherwise use package-versions. Output is UTF-8 (no BOM),
  newline CRLF.

.PARAMETER RootPath
  Repository root. Default: parent of scripts directory.

.PARAMETER PackageVersionsPath
  Default: <Root>/doc/package-versions.json

.PARAMETER SharedPackageVersionsPath
  Default: <Root>/doc/shared-package-versions.json

.PARAMETER RepositoryPath
  Optional. Repo-relative path (e.g. Actors\Rhapsody.Computation.ChannelProjection). When set and -OutPath
  is omitted, writes doc/latest-packages.<token>.merged.json so concurrent jobs for different repos do not
  overwrite each other.

.PARAMETER OutPath
  When omitted: if -RepositoryPath is set, default is doc/latest-packages.<token>.merged.json; otherwise
  doc/latest-packages.merged.json (global map). Writes use an atomic replace on the target file.
#>
param(
    [string]$RootPath,
    [string]$PackageVersionsPath,
    [string]$SharedPackageVersionsPath,
    [string]$RepositoryPath,
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$namingScript = Join-Path $PSScriptRoot "package-upgrade-artifact-naming.ps1"
if (-not (Test-Path -LiteralPath $namingScript -PathType Leaf)) {
    throw "Required script not found: $namingScript"
}
. $namingScript

function Resolve-RootPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    }
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Value))
}

$resolvedRoot = Resolve-RootPath -Value $RootPath

if ([string]::IsNullOrWhiteSpace($PackageVersionsPath)) {
    $PackageVersionsPath = Join-Path $resolvedRoot "doc\package-versions.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($PackageVersionsPath)) {
    $PackageVersionsPath = Join-Path $resolvedRoot $PackageVersionsPath
}

if ([string]::IsNullOrWhiteSpace($SharedPackageVersionsPath)) {
    $SharedPackageVersionsPath = Join-Path $resolvedRoot "doc\shared-package-versions.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($SharedPackageVersionsPath)) {
    $SharedPackageVersionsPath = Join-Path $resolvedRoot $SharedPackageVersionsPath
}

$resolvedArtifactToken = $null
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) {
        $repoRel = $RepositoryPath.Trim().TrimEnd('\', '/')
        $resolvedArtifactToken = Get-PackageUpgradeRepositoryArtifactToken -RepositoryRelativePath $repoRel
        $OutPath = Join-Path $resolvedRoot ("doc\latest-packages.{0}.merged.json" -f $resolvedArtifactToken)
    }
    else {
        $OutPath = Join-Path $resolvedRoot "doc\latest-packages.merged.json"
    }
}
elseif (-not [System.IO.Path]::IsPathRooted($OutPath)) {
    $OutPath = Join-Path $resolvedRoot $OutPath
}

foreach ($p in @($PackageVersionsPath, $SharedPackageVersionsPath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "Input file not found: $p"
    }
}

function Read-PackageVersionsDictionary {
    param([string]$JsonPath)
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj.packages) {
        throw "Missing 'packages' object in: $JsonPath"
    }
    $d = @{}
    foreach ($prop in $obj.packages.PSObject.Properties) {
        $name = [string]$prop.Name
        $val = $prop.Value
        if ($null -eq $val) {
            continue
        }
        $d[$name] = [string]$val
    }
    return $d
}

function Read-SharedFeedDictionary {
    param([string]$JsonPath)
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj.packages) {
        throw "Missing 'packages' array in: $JsonPath"
    }
    $d = @{}
    foreach ($entry in @($obj.packages)) {
        if ($null -eq $entry) {
            continue
        }
        $err = $entry.error
        if (-not [string]::IsNullOrWhiteSpace([string]$err)) {
            continue
        }
        $id = [string]$entry.packageId
        $ver = [string]$entry.latestVersion
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($ver)) {
            continue
        }
        $d[$id] = $ver
    }
    return $d
}

$d1 = Read-PackageVersionsDictionary -JsonPath $PackageVersionsPath
$d2 = Read-SharedFeedDictionary -JsonPath $SharedPackageVersionsPath

$keySet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($k in $d1.Keys) { [void]$keySet.Add($k) }
foreach ($k in $d2.Keys) { [void]$keySet.Add($k) }

$merged = [ordered]@{}
foreach ($k in ($keySet | Sort-Object)) {
    if ($d2.ContainsKey($k)) {
        $merged[$k] = $d2[$k]
    }
    elseif ($d1.ContainsKey($k)) {
        $merged[$k] = $d1[$k]
    }
}

$payload = [ordered]@{
    mergedAt      = (Get-Date).ToUniversalTime().ToString("o")
    rootPath      = $resolvedRoot
    sources       = [ordered]@{
        packageVersions        = $PackageVersionsPath
        sharedPackageVersions  = $SharedPackageVersionsPath
    }
    packageCount  = $merged.Count
    packages      = [ordered]@{}
}
if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) {
    $repoRelForPayload = $RepositoryPath.Trim().TrimEnd('\', '/')
    $payload.repositoryRelativePath = $repoRelForPayload
    if ($null -ne $resolvedArtifactToken) {
        $payload.artifactToken = $resolvedArtifactToken
    }
    else {
        $payload.artifactToken = Get-PackageUpgradeRepositoryArtifactToken -RepositoryRelativePath $repoRelForPayload
    }
}
foreach ($k in $merged.Keys) {
    $payload.packages[$k] = $merged[$k]
}

$json = ($payload | ConvertTo-Json -Depth 20 -Compress)
Write-PackageUpgradeDocJsonAtomic -TargetPath $OutPath -Content ($json + "`r`n")

Write-Host "Wrote $($merged.Count) package id(s) to $OutPath"
