#Requires -Version 5.1
<#
.SYNOPSIS
  List top-level NuGet package references for all projects under a single repository folder via dotnet CLI.

.DESCRIPTION
  Discovers *.csproj under -RepositoryPath (excluding bin/obj), runs
  dotnet list "<csproj>" package --format json per project, and writes a JSON summary (UTF-8 no BOM, CRLF).

.PARAMETER RootPath
  Monorepo root. Default: parent of scripts directory.

.PARAMETER RepositoryPath
  Required. Path relative to RootPath, e.g. Actors\Rhapsody.Computation.ChannelProjection

.PARAMETER OutPath
  Default: <Root>/doc/dependences.<artifactToken>.json where artifactToken is derived from the full
  -RepositoryPath (path segments as __, safe chars only; long paths get a hash suffix) so concurrent
  jobs for different folders do not collide on the last segment alone.

.PARAMETER IncludeTransitive
  If set, runs dotnet list with --include-transitive (larger output).
#>
param(
    [string]$RootPath,
    [Parameter(Mandatory = $true)]
    [string]$RepositoryPath,
    [string]$OutPath,
    [switch]$IncludeTransitive
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
$repoRelative = $RepositoryPath.Trim().TrimEnd('\', '/')
$repoFull = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $repoRelative))

if (-not (Test-Path -LiteralPath $repoFull -PathType Container)) {
    throw "RepositoryPath not found: $repoFull"
}

$null = Get-Command -Name "dotnet" -CommandType Application -ErrorAction Stop

$artifactToken = Get-PackageUpgradeRepositoryArtifactToken -RepositoryRelativePath $repoRelative

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $resolvedRoot ("doc\dependences.{0}.json" -f $artifactToken)
}
elseif (-not [System.IO.Path]::IsPathRooted($OutPath)) {
    $OutPath = Join-Path $resolvedRoot $OutPath
}

function Test-UnderBinOrObj {
    param([string]$FullPath)
    return $FullPath -match '(\\|/)(bin|obj)(\\|/)'
}

$csprojs = Get-ChildItem -LiteralPath $repoFull -Recurse -File -Filter "*.csproj" |
    Where-Object { -not (Test-UnderBinOrObj -FullPath $_.FullName) } |
    Sort-Object FullName

if ($csprojs.Count -eq 0) {
    throw "No .csproj files found under: $repoFull"
}

function Get-RelativeFromRoot {
    param(
        [string]$BaseRoot,
        [string]$Target
    )
    $baseUri = New-Object System.Uri ($BaseRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar)
    $targetUri = New-Object System.Uri $Target
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

$perProject = New-Object System.Collections.Generic.List[object]
$aggregate = @{}

foreach ($proj in $csprojs) {
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $argList = @(
            "list",
            $proj.FullName,
            "package",
            "--format",
            "json"
        )
        if ($IncludeTransitive) {
            $argList += "--include-transitive"
        }

        $proc = Start-Process -FilePath "dotnet" -ArgumentList $argList -WorkingDirectory $resolvedRoot `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        if ($null -eq $proc -or $proc.ExitCode -ne 0) {
            $errText = ""
            if (Test-Path -LiteralPath $stderrFile) {
                $errText = Get-Content -LiteralPath $stderrFile -Raw -Encoding UTF8
            }
            throw "dotnet list failed ($($proc.ExitCode)) for $($proj.FullName): $errText"
        }

        $stdout = Get-Content -LiteralPath $stdoutFile -Raw -Encoding UTF8
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    $doc = $stdout | ConvertFrom-Json
    $relProj = Get-RelativeFromRoot -BaseRoot $resolvedRoot -Target $proj.FullName

    $topLevel = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($doc.projects)) {
        foreach ($fx in @($p.frameworks)) {
            foreach ($pkg in @($fx.topLevelPackages)) {
                $id = [string]$pkg.id
                if ([string]::IsNullOrWhiteSpace($id)) {
                    continue
                }
                $req = [string]$pkg.requestedVersion
                $resolvedVer = [string]$pkg.resolvedVersion
                $topLevel.Add([ordered]@{
                        id               = $id
                        requestedVersion = $req
                        resolvedVersion  = $resolvedVer
                        framework        = [string]$fx.framework
                    }) | Out-Null

                if (-not $aggregate.ContainsKey($id)) {
                    $aggregate[$id] = [ordered]@{
                        packageId          = $id
                        requestedVersions    = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::Ordinal)
                        resolvedVersions     = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::Ordinal)
                        projectRelativePaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
                    }
                }
                $slot = $aggregate[$id]
                if (-not [string]::IsNullOrWhiteSpace($req)) {
                    [void]$slot.requestedVersions.Add($req)
                }
                if (-not [string]::IsNullOrWhiteSpace($resolvedVer)) {
                    [void]$slot.resolvedVersions.Add($resolvedVer)
                }
                [void]$slot.projectRelativePaths.Add($relProj)
            }
        }
    }

    $perProject.Add([ordered]@{
            projectRelativePath = $relProj
            topLevelPackages    = @($topLevel.ToArray())
        })
}

$packagesOut = [ordered]@{}
foreach ($id in ($aggregate.Keys | Sort-Object)) {
    $slot = $aggregate[$id]
    $reqArr = @($slot.requestedVersions | Sort-Object)
    $resArr = @($slot.resolvedVersions | Sort-Object)
    $projArr = @($slot.projectRelativePaths | Sort-Object)
    $packagesOut[$id] = [ordered]@{
        packageId               = $id
        requestedVersionSamples = $reqArr
        resolvedVersionSamples  = $resArr
        projectRelativePaths    = $projArr
    }
}

$payload = [ordered]@{
    generatedAt            = (Get-Date).ToUniversalTime().ToString("o")
    rootPath               = $resolvedRoot
    repositoryRelativePath = $repoRelative
    repositoryAbsolutePath = $repoFull
    artifactToken          = $artifactToken
    includeTransitive      = [bool]$IncludeTransitive
    projectCount            = $csprojs.Count
    projects                = @($perProject.ToArray())
    packages                = [ordered]@{}
}
foreach ($k in $packagesOut.Keys) {
    $payload.packages[$k] = $packagesOut[$k]
}

$json = ($payload | ConvertTo-Json -Depth 20 -Compress)
Write-PackageUpgradeDocJsonAtomic -TargetPath $OutPath -Content ($json + "`r`n")

Write-Host ("Wrote dependences for {0} project(s), {1} package id(s) -> {2}" -f $csprojs.Count, $packagesOut.Count, $OutPath)
