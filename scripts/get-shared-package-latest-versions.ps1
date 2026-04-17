#Requires -Version 5.1
<#
.SYNOPSIS
  从 Azure DevOps Artifacts（Packaging API，az devops invoke）查询 Shared 目录 nuspec 对应包的最新版本。

.DESCRIPTION
  包 ID 来自 Shared/**/*.nuspec 的 <id>；对每个包使用 packageNameQuery 查询该 feed，避免全量列举超过 1000 条时的遗漏。

  需：Azure CLI、azure-devops 扩展、az login。

.PARAMETER RootPath
  仓库根目录，默认脚本上级目录。

.PARAMETER ConfigPath
  默认 scripts/shared-package-feed-config.json。

.PARAMETER OutJsonPath
  默认 doc/shared-package-versions.json。

.PARAMETER OutMarkdownPath
  若指定，额外写入 Markdown 表格。

.PARAMETER PackageIds
  可选；不指定则从 nuspec 扫描。
#>
param(
    [string]$RootPath,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "shared-package-feed-config.json"),
    [string]$OutJsonPath,
    [string]$OutMarkdownPath,
    [string[]]$PackageIds = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CommandOrThrow {
    param([string]$Name)
    $c = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    if (-not $c) {
        throw "未找到命令 '$Name'。请先安装 Azure CLI。"
    }
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-PackageIdsFromNuspecUnderShared {
    param([string]$SharedDirectory)
    $ids = New-Object System.Collections.Generic.HashSet[string]
    Get-ChildItem -LiteralPath $SharedDirectory -Filter '*.nuspec' -File -Recurse -ErrorAction Stop | ForEach-Object {
        [xml]$x = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $id = $x.package.metadata.id
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            [void]$ids.Add($id.Trim())
        }
    }
    return ($ids | Sort-Object)
}

function Get-LatestVersionStringFromPackage {
    param($Pkg)
    if (-not $Pkg -or -not $Pkg.versions) {
        return $null
    }
    foreach ($v in $Pkg.versions) {
        if ($null -ne $v.isLatest -and $v.isLatest -eq $true) {
            return [string]$v.version
        }
    }
    $arr = @($Pkg.versions)
    if ($arr.Count -gt 0) {
        return [string]$arr[$arr.Count - 1].version
    }
    return $null
}

function Resolve-FeedFromName {
    param(
        [string]$Organization,
        [string]$FeedName
    )
    $feedsOut = & az devops invoke --organization $Organization --area Packaging --resource Feeds --api-version "6.0-preview" --http-method GET -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("获取 feeds 列表失败：{0}" -f ($feedsOut | Out-String))
    }
    $feedsJson = $feedsOut | ConvertFrom-Json
    $matches = @($feedsJson.value | Where-Object { $_.name -eq $FeedName })
    if ($matches.Count -eq 0) {
        throw "未找到名为 '$FeedName' 的 feed。"
    }
    if ($matches.Count -gt 1) {
        throw "存在多个名为 '$FeedName' 的 feed。"
    }
    $f = $matches[0]
    $fid = [string]$f.id
    $proj = $null
    if (($f | Get-Member -MemberType NoteProperty -Name project -ErrorAction SilentlyContinue) -and $f.project) {
        $proj = $f.project.name
    }
    return [PSCustomObject]@{ FeedId = $fid; ProjectName = $proj }
}

function Get-PackageByNameQuery {
    param(
        [string]$Organization,
        [string]$FeedId,
        [string]$ProjectName,
        [string]$PackageId
    )
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $stdout = & az devops invoke --organization $Organization --area Packaging --resource Packages --route-parameters "project=$ProjectName" "feedId=$FeedId" --api-version "6.0-preview" --http-method GET --query-parameters "packageNameQuery=$PackageId" -o json 2>&1
    }
    else {
        $stdout = & az devops invoke --organization $Organization --area Packaging --resource Packages --route-parameters "feedId=$FeedId" --api-version "6.0-preview" --http-method GET --query-parameters "packageNameQuery=$PackageId" -o json 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw ("查询包失败 ($PackageId)：{0}" -f ($stdout | Out-String))
    }
    $j = $stdout | ConvertFrom-Json
    if (-not $j.value -or @($j.value).Count -eq 0) {
        return $null
    }
    foreach ($cand in $j.value) {
        $n = $null
        if ($cand.PSObject.Properties.Name -contains 'name') {
            $n = [string]$cand.name
        }
        if ($n -eq $PackageId) {
            return Get-LatestVersionStringFromPackage -Pkg $cand
        }
    }
    $first = $j.value[0]
    return Get-LatestVersionStringFromPackage -Pkg $first
}

Get-CommandOrThrow -Name "az"
$null = & az extension show --name azure-devops -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "请先安装扩展：az extension add --name azure-devops"
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
else {
    $RootPath = [System.IO.Path]::GetFullPath($RootPath)
}

if ([string]::IsNullOrWhiteSpace($OutJsonPath)) {
    $OutJsonPath = Join-Path $RootPath "doc\shared-package-versions.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutJsonPath)) {
    $OutJsonPath = Join-Path $RootPath $OutJsonPath
}

$cfg = Read-JsonFile -Path $ConfigPath
$org = [string]$cfg.organizationUrl
$feedName = [string]$cfg.feedName
if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($feedName)) {
    throw "配置中缺少 organizationUrl 或 feedName：$ConfigPath"
}

$sharedDir = Join-Path $RootPath "Shared"
if (-not (Test-Path -LiteralPath $sharedDir)) {
    throw "未找到 Shared 目录：$sharedDir"
}

if ($null -eq $PackageIds -or $PackageIds.Count -eq 0) {
    $PackageIds = @(Get-PackageIdsFromNuspecUnderShared -SharedDirectory $sharedDir)
}
if ($PackageIds.Count -eq 0) {
    throw "包 ID 列表为空。"
}

$feedMeta = Resolve-FeedFromName -Organization $org -FeedName $feedName

$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$rows = New-Object System.Collections.Generic.List[object]

foreach ($pkgId in $PackageIds) {
    try {
        $ver = Get-PackageByNameQuery -Organization $org -FeedId $feedMeta.FeedId -ProjectName $feedMeta.ProjectName -PackageId $pkgId
        if ($null -ne $ver) {
            $rows.Add([PSCustomObject]@{ packageId = $pkgId; latestVersion = $ver; error = $null }) | Out-Null
        }
        else {
            $rows.Add([PSCustomObject]@{ packageId = $pkgId; latestVersion = $null; error = "feed 中未找到该包或无可读版本。" }) | Out-Null
        }
    }
    catch {
        $rows.Add([PSCustomObject]@{ packageId = $pkgId; latestVersion = $null; error = $_.Exception.Message }) | Out-Null
    }
}

$outObj = [PSCustomObject]@{
    generatedAt     = $generatedAt
    organizationUrl = $org
    feedName        = $feedName
    feedId          = $feedMeta.FeedId
    packageCount    = $rows.Count
    packages        = $rows.ToArray()
}

$jsonDir = [System.IO.Path]::GetDirectoryName($OutJsonPath)
if (-not [string]::IsNullOrWhiteSpace($jsonDir)) {
    [System.IO.Directory]::CreateDirectory($jsonDir) | Out-Null
}

$jsonText = $outObj | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($OutJsonPath, $jsonText, [System.Text.UTF8Encoding]::new($true))
Write-Host "已写入: $OutJsonPath"

if (-not [string]::IsNullOrWhiteSpace($OutMarkdownPath)) {
    if (-not [System.IO.Path]::IsPathRooted($OutMarkdownPath)) {
        $OutMarkdownPath = Join-Path $RootPath $OutMarkdownPath
    }
    $mdDir = [System.IO.Path]::GetDirectoryName($OutMarkdownPath)
    if (-not [string]::IsNullOrWhiteSpace($mdDir)) {
        [System.IO.Directory]::CreateDirectory($mdDir) | Out-Null
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Shared packages — latest versions (ADO feed)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("Generated (UTC): $generatedAt") | Out-Null
    $lines.Add("Feed: ``$feedName`` @ ``$org``") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Package | Version |") | Out-Null
    $lines.Add("| --- | --- |") | Out-Null
    foreach ($p in $rows) {
        $cell = if ($p.latestVersion) { $p.latestVersion } else { "" }
        if ($p.error) {
            $cell = if ($cell) { "$cell; $($p.error)" } else { $p.error }
        }
        $lines.Add("| $($p.packageId) | $cell |") | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutMarkdownPath, $lines, [System.Text.UTF8Encoding]::new($true))
    Write-Host "已写入: $OutMarkdownPath"
}
