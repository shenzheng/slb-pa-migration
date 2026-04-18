#Requires -Version 5.1
<#
.SYNOPSIS
  Bump PackageReference versions under a repository folder using doc/latest-packages.merged.json (or custom path).

.DESCRIPTION
  Loads merged package versions, walks *.csproj (excluding bin/obj), updates Version attributes on
  PackageReference elements when a mapping exists and the version differs. UTF-8 no BOM output, CRLF.
  Skips references without a Version attribute (e.g. central package management).

.PARAMETER RootPath
  Monorepo root. Default: parent of scripts directory.

.PARAMETER RepositoryPath
  Required. Relative to root, e.g. Actors\Rhapsody.Computation.ChannelProjection

.PARAMETER MergedLatestPath
  When omitted: doc/latest-packages.<artifactToken>.merged.json for this -RepositoryPath (same token as
  merge-latest-package-versions.ps1 -RepositoryPath). Use the global doc/latest-packages.merged.json only
  when you intentionally merged without -RepositoryPath.

.PARAMETER WhatIf
  If set, reports planned changes without writing files.
#>
param(
    [string]$RootPath,
    [Parameter(Mandatory = $true)]
    [string]$RepositoryPath,
    [string]$MergedLatestPath,
    [switch]$WhatIf
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

if ([string]::IsNullOrWhiteSpace($MergedLatestPath)) {
    $artifactToken = Get-PackageUpgradeRepositoryArtifactToken -RepositoryRelativePath $repoRelative
    $MergedLatestPath = Join-Path $resolvedRoot ("doc\latest-packages.{0}.merged.json" -f $artifactToken)
}
elseif (-not [System.IO.Path]::IsPathRooted($MergedLatestPath)) {
    $MergedLatestPath = Join-Path $resolvedRoot $MergedLatestPath
}

if (-not (Test-Path -LiteralPath $MergedLatestPath -PathType Leaf)) {
    throw "Merged latest file not found: $MergedLatestPath"
}

$mergedRaw = Get-Content -LiteralPath $MergedLatestPath -Raw -Encoding UTF8
$mergedObj = $mergedRaw | ConvertFrom-Json
if ($null -eq $mergedObj.packages) {
    throw "Merged JSON missing 'packages': $MergedLatestPath"
}

$versionMap = New-Object "System.Collections.Generic.Dictionary[string,string]" ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($prop in $mergedObj.packages.PSObject.Properties) {
    $id = [string]$prop.Name
    $ver = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($ver)) {
        continue
    }
    $versionMap[$id] = $ver
}

function Test-UnderBinOrObj {
    param([string]$FullPath)
    return $FullPath -match '(\\|/)(bin|obj)(\\|/)'
}

function Load-XmlDocumentPreservingWhitespace {
    param([string]$Path)
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $true
        $doc.Load($reader)
        return $doc
    }
    finally {
        $reader.Dispose()
    }
}

function Save-XmlDocumentCrlf {
    param(
        [System.Xml.XmlDocument]$Document,
        [string]$Path
    )
    $ws = New-Object System.Xml.XmlWriterSettings
    $ws.OmitXmlDeclaration = $true
    $ws.Encoding = New-Object System.Text.UTF8Encoding $false
    $ws.NewLineChars = "`r`n"
    # ReplaceAll exists on .NET Core+ only; Windows PowerShell 5.1 / .NET Framework has None | Entitize.
    $nlhType = [System.Xml.NewLineHandling]
    if ([enum]::IsDefined($nlhType, 'ReplaceAll')) {
        $ws.NewLineHandling = [System.Xml.NewLineHandling]::ReplaceAll
    }
    else {
        $ws.NewLineHandling = [System.Xml.NewLineHandling]::None
    }
    $ws.Indent = $false
    $writer = [System.Xml.XmlWriter]::Create($Path, $ws)
    try {
        $Document.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

$csprojs = Get-ChildItem -LiteralPath $repoFull -Recurse -File -Filter "*.csproj" |
    Where-Object { -not (Test-UnderBinOrObj -FullPath $_.FullName) } |
    Sort-Object FullName

$planned = New-Object System.Collections.Generic.List[string]
$skippedNoMapping = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$skippedNoVersionAttr = 0

foreach ($proj in $csprojs) {
    $doc = Load-XmlDocumentPreservingWhitespace -Path $proj.FullName
    $nodes = $doc.GetElementsByTagName("PackageReference")
    $fileChanged = $false

    foreach ($node in $nodes) {
        $include = $node.GetAttribute("Include")
        if ([string]::IsNullOrWhiteSpace($include)) {
            continue
        }
        if (-not $versionMap.ContainsKey($include)) {
            [void]$skippedNoMapping.Add($include)
            continue
        }
        $target = $versionMap[$include]
        if (-not $node.HasAttribute("Version")) {
            $skippedNoVersionAttr++
            continue
        }
        $current = $node.GetAttribute("Version")
        if ($current -ceq $target) {
            continue
        }
        $rel = $proj.FullName.Substring($resolvedRoot.Length).TrimStart('\')
        $planned.Add("$rel : $include $current -> $target") | Out-Null
        if (-not $WhatIf) {
            $node.SetAttribute("Version", $target)
            $fileChanged = $true
        }
    }

    if ($fileChanged) {
        Save-XmlDocumentCrlf -Document $doc -Path $proj.FullName
    }
}

if ($planned.Count -eq 0) {
    Write-Host "No version changes needed (or nothing mapped)."
}
else {
    Write-Host "Planned changes ($($planned.Count)):"
    $planned | ForEach-Object { Write-Host "  $_" }
}

if ($skippedNoMapping.Count -gt 0) {
    Write-Host ("`nPackages referenced but not in merged map ({0}): {1}" -f $skippedNoMapping.Count, (($skippedNoMapping | Sort-Object) -join ", "))
}

if ($skippedNoVersionAttr -gt 0) {
    Write-Host "`nSkipped $skippedNoVersionAttr PackageReference node(s) without Version attribute."
}

if ($WhatIf) {
    Write-Host "`nWhatIf: no files were modified."
}
