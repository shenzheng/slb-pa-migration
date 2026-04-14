#Requires -Version 5.1
<#
.SYNOPSIS
  查询 Prism 升级相关 Azure DevOps Pipeline 在指定分支上的最近一次构建状态，并生成结果页与「最后 Stage」日志视图链接。

.DESCRIPTION
  使用 Azure CLI 通过 AAD 获取 Azure DevOps 资源令牌（无需 PAT）：
    az login
    az account get-access-token --resource 499b84ac-1321-4277-86b9-215fbc768055

  「最后 Stage」由 Build Timeline API 中 type 为 Stage 的记录按 order 取最大者；日志深链使用
    .../_build/results?buildId=...&view=logs&t=<StageRecordId>
  若你方 DevOps UI 版本参数不同，仍以「构建结果」链接为准；可在浏览器中从该次运行打开最后 Stage 核对 query。

.PARAMETER DefinitionsPath
  默认为与本脚本同目录的 upgrade-pipeline-definitions.json。

.PARAMETER FallbackAnyBranch
  当指定分支无构建时，再查询该定义在全分支上最近一次完成记录（用于长期未打 dapr 的 Pipeline）。

.NOTES
  组织/项目默认值可从 JSON 读取；也可显式传入 -Organization / -Project 覆盖。
#>
param(
    [string]$Organization,
    [string]$Project,
    [string]$DefinitionsPath = (Join-Path $PSScriptRoot "upgrade-pipeline-definitions.json"),
    [string]$Branch = "refs/heads/dapr",
    [ValidateSet("Markdown", "Json", "Object")]
    [string]$OutputFormat = "Markdown",
    [switch]$FallbackAnyBranch,
    [switch]$SkipTimeline,
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:AzDevOpsResource = "499b84ac-1321-4277-86b9-215fbc768055"

function Get-CommandOrThrow {
    param([string]$Name)
    $c = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    if (-not $c) {
        throw "未找到命令 '$Name'。请先安装 Azure CLI：https://aka.ms/installazurecliwindows"
    }
}

function Get-AzureDevOpsAccessToken {
    Get-CommandOrThrow -Name "az"
    $stdout = & az account get-access-token --resource $script:AzDevOpsResource -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("无法获取 Azure DevOps 访问令牌。请先执行 'az login'（AAD）。`n{0}" -f ($stdout | Out-String))
    }
    $parsed = $stdout | ConvertFrom-Json
    if ([string]::IsNullOrEmpty($parsed.accessToken)) {
        throw "az 返回的 JSON 中缺少 accessToken。"
    }
    return [string]$parsed.accessToken
}

function Invoke-AzDevOpsGetJson {
    param(
        [string]$Uri,
        [string]$Token
    )
    $headers = @{
        Authorization = "Bearer $Token"
        Accept        = "application/json"
    }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
}

function Convert-BuildStatusToLabel {
    param([Nullable[int]]$Status)
    if ($null -eq $Status) { return "未知" }
    switch ($Status) {
        0 { return "无" }
        1 { return "进行中" }
        2 { return "已完成" }
        3 { return "取消中" }
        4 { return "已推迟" }
        5 { return "未开始" }
        default { return ("状态码 {0}" -f $Status) }
    }
}

function Convert-BuildResultToLabel {
    param([Nullable[int]]$Result)
    if ($null -eq $Result) { return "—" }
    switch ($Result) {
        0 { return "无" }
        2 { return "成功" }
        4 { return "部分成功" }
        8 { return "失败" }
        32 { return "已取消" }
        default { return ("结果码 {0}" -f $Result) }
    }
}

function Get-LastStageRecord {
    param([object]$TimelinePayload)
    if ($null -eq $TimelinePayload -or $null -eq $TimelinePayload.records) {
        return $null
    }
    $stages = @($TimelinePayload.records | Where-Object { $_.type -eq "Stage" })
    if ($stages.Count -eq 0) {
        return $null
    }
    $sorted = $stages | Sort-Object -Property @{ Expression = {
            $o = $_.order
            if ($null -eq $o) { return [int]::MinValue }
            try {
                return [int]$o
            }
            catch {
                return [int]::MinValue
            }
        }; Ascending = $false }
    return $sorted[0]
}

function Build-WebBase {
    param(
        [string]$Org,
        [string]$Proj
    )
    $oe = [uri]::EscapeDataString($Org)
    $pe = [uri]::EscapeDataString($Proj)
    return "https://dev.azure.com/$oe/$pe"
}

function Get-DefinitionsConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "找不到定义文件: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

Get-CommandOrThrow -Name "az"
$token = Get-AzureDevOpsAccessToken

$config = Get-DefinitionsConfig -Path $DefinitionsPath
$org = if ($Organization) { $Organization } else { $config.organization }
$proj = if ($Project) { $Project } else { $config.project }
if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($proj)) {
    throw "请在 upgrade-pipeline-definitions.json 中填写 organization/project，或使用 -Organization / -Project。"
}

$apiRoot = "https://dev.azure.com/$org/$proj/_apis"
$webBase = Build-WebBase -Org $org -Proj $proj
$apiVersion = "7.1"

$rows = New-Object System.Collections.Generic.List[object]

foreach ($p in $config.pipelines) {
    $defId = [int]$p.definitionId
    $name = [string]$p.pipelineName

    $buildUri = "$apiRoot/build/builds?definitions=$defId&branchName=$([uri]::EscapeDataString($Branch))&`$top=1&queryOrder=finishTimeDescending&api-version=$apiVersion"
    $list = Invoke-AzDevOpsGetJson -Uri $buildUri -Token $token
    $builds = @($list.value)
    $usedFallback = $false

    if ($builds.Count -eq 0 -and $FallbackAnyBranch) {
        $buildUri = "$apiRoot/build/builds?definitions=$defId&`$top=1&queryOrder=finishTimeDescending&api-version=$apiVersion"
        $list = Invoke-AzDevOpsGetJson -Uri $buildUri -Token $token
        $builds = @($list.value)
        $usedFallback = $true
    }

    if ($builds.Count -eq 0) {
        $rows.Add([ordered]@{
                PipelineName     = $name
                DefinitionId     = $defId
                BuildId          = $null
                BuildNumber      = $null
                SourceBranch     = $null
                StatusLabel      = "—"
                ResultLabel      = "无构建"
                FinishTimeUtc    = $null
                BuildWebUrl      = "$webBase/_build?definitionId=$defId"
                LastStageName    = $null
                LastStageLogsUrl = $null
                Note             = if ($usedFallback) { "指定分支无记录；已尝试全分支（仍无）" } else { "指定分支无构建记录" }
            }) | Out-Null
        continue
    }

    $b = $builds[0]
    $buildId = [int]$b.id
    $buildWeb = $b._links.web.href
    if ([string]::IsNullOrWhiteSpace($buildWeb)) {
        $buildWeb = "$webBase/_build/results?buildId=$buildId"
    }

    $statusLabel = Convert-BuildStatusToLabel -Status $b.status
    $resultLabel = if ($b.status -eq 2) {
        Convert-BuildResultToLabel -Result $b.result
    }
    else {
        ("— ({0})" -f $statusLabel)
    }

    $lastStageName = $null
    $lastStageLogsUrl = $null
    if (-not $SkipTimeline) {
        try {
            $timelineUri = "$apiRoot/build/builds/$buildId/timeline?api-version=$apiVersion"
            $timeline = Invoke-AzDevOpsGetJson -Uri $timelineUri -Token $token
            $stageRec = Get-LastStageRecord -TimelinePayload $timeline
            if ($null -ne $stageRec) {
                $lastStageName = $stageRec.name
                $sid = [string]$stageRec.id
                $lastStageLogsUrl = "$webBase/_build/results?buildId=$buildId&view=logs&t=$sid"
            }
        }
        catch {
            $lastStageName = $null
            $lastStageLogsUrl = $null
        }
    }

    $note = $null
    if ($usedFallback) {
        $note = "指定分支无记录；已使用全分支最近一次构建"
    }

    $rows.Add([ordered]@{
            PipelineName     = $name
            DefinitionId     = $defId
            BuildId          = $buildId
            BuildNumber      = $b.buildNumber
            SourceBranch     = $b.sourceBranch
            StatusLabel      = $statusLabel
            ResultLabel      = $resultLabel
            FinishTimeUtc    = $b.finishTime
            BuildWebUrl      = $buildWeb
            LastStageName    = $lastStageName
            LastStageLogsUrl = $lastStageLogsUrl
            Note             = $note
        }) | Out-Null
}

$outObjects = @($rows)

if ($OutputFormat -eq "Json") {
    $json = $outObjects | ConvertTo-Json -Depth 6
    if ($OutFile) {
        $outFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
        $parentDir = Split-Path -Parent $outFull
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($outFull, $json, [System.Text.UTF8Encoding]::new($true))
    }
    else {
        Write-Output $json
    }
}
elseif ($OutputFormat -eq "Object") {
    Write-Output $outObjects
}
else {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## Prism 升级 Pipeline 状态")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Pipeline | Def ID | Build | 结果 | 完成 (UTC) | 源分支 | 最后 Stage | 链接 |")
    [void]$sb.AppendLine("| --- | ---: | ---: | --- | --- | --- | --- | --- |")

    foreach ($r in $outObjects) {
        $bid = if ($null -eq $r.BuildId) { "—" } else { [string]$r.BuildId }
        $ft = if ([string]::IsNullOrWhiteSpace($r.FinishTimeUtc)) { "—" } else { $r.FinishTimeUtc }
        $br = if ([string]::IsNullOrWhiteSpace($r.SourceBranch)) { "—" } else { $r.SourceBranch }
        $stage = if ([string]::IsNullOrWhiteSpace($r.LastStageName)) { "—" } else { $r.LastStageName }
        $parts = New-Object System.Collections.Generic.List[string]
        if ($null -eq $r.BuildId) {
            if ($null -ne $r.BuildWebUrl -and -not [string]::IsNullOrWhiteSpace($r.BuildWebUrl)) {
                $parts.Add("[Pipeline 定义]($($r.BuildWebUrl))")
            }
        }
        else {
            if ($null -ne $r.BuildWebUrl -and -not [string]::IsNullOrWhiteSpace($r.BuildWebUrl)) {
                $parts.Add("[构建结果]($($r.BuildWebUrl))")
            }
            if (-not [string]::IsNullOrWhiteSpace($r.LastStageLogsUrl)) {
                $parts.Add("[最后 Stage 日志]($($r.LastStageLogsUrl))")
            }
        }
        if ($parts.Count -eq 0 -and $null -ne $r.DefinitionId) {
            $parts.Add("[Pipeline 定义]($webBase/_build?definitionId=$($r.DefinitionId))")
        }
        $linkCell = [string]::Join(" · ", $parts)
        if (-not [string]::IsNullOrWhiteSpace($r.Note)) {
            $linkCell = ("{0} *({1})*" -f $linkCell, ($r.Note -replace '\|', '/'))
        }
        [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | `{5}` | {6} | {7} |" -f `
                    $r.PipelineName,
                $r.DefinitionId,
                $bid,
                $r.ResultLabel,
                $ft,
                $br,
                $stage,
                $linkCell))
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- 生成参数: 分支 ``$Branch``；组织 ``$org``；项目 ``$proj``。")
    if ($FallbackAnyBranch) {
        [void]$sb.AppendLine("- 已启用 **FallbackAnyBranch**：某分支无记录时会改用全分支最近一次构建。")
    }
    if ($SkipTimeline) {
        [void]$sb.AppendLine("- 已 **SkipTimeline**：未解析最后 Stage。")
    }

    $text = $sb.ToString()
    if ($OutFile) {
        $outFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
        $parentDir = Split-Path -Parent $outFull
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($outFull, $text, [System.Text.UTF8Encoding]::new($true))
    }
    else {
        Write-Output $text
    }
}
