#Requires -Version 5.1
<#
.SYNOPSIS
  Queue an Azure DevOps pipeline run for a Prism actor/service folder using upgrade-pipeline-definitions.json.

.DESCRIPTION
  Resolves definitionId by matching RepositoryFolderName to pipelineName (case-insensitive), then runs:
  az pipelines run --organization ... --project ... --id ... --branch ...

  Requires: Azure CLI, azure-devops extension, az login, and permission to queue builds.

.PARAMETER RepositoryFolderName
  Last segment of the actor path, e.g. Rhapsody.Computation.ChannelProjection or rhapsody.computation.killsheet.

.PARAMETER DefinitionId
  If set, skips name lookup and uses this definition id.

.PARAMETER Branch
  ADO branch ref, e.g. refs/heads/dapr. If omitted, uses current git branch as refs/heads/<name>.

.PARAMETER DefinitionsPath
  Default: scripts/upgrade-pipeline-definitions.json next to this script.

.PARAMETER DryRun
  Print az command only; do not queue a run.

.PARAMETER Parameters
  Optional. Passed to `az pipelines run --parameters` as one string of space-separated name=value pairs,
  e.g. CDPkgVersion=latest (required by some LibraryCloud / rhapsody templates).
#>
param(
    [string]$RepositoryFolderName,
    [int]$DefinitionId = 0,
    [string]$Branch,
    [string]$DefinitionsPath,
    [string]$Parameters,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$null = Get-Command -Name "az" -CommandType Application -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($DefinitionsPath)) {
    $DefinitionsPath = Join-Path $PSScriptRoot "upgrade-pipeline-definitions.json"
}
elseif (-not [System.IO.Path]::IsPathRooted($DefinitionsPath)) {
    $DefinitionsPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $DefinitionsPath))
}

if (-not (Test-Path -LiteralPath $DefinitionsPath -PathType Leaf)) {
    throw "Definitions file not found: $DefinitionsPath"
}

$defsRaw = Get-Content -LiteralPath $DefinitionsPath -Raw -Encoding UTF8
$defs = $defsRaw | ConvertFrom-Json
$org = [string]$defs.organization
$project = [string]$defs.project
if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($project)) {
    throw "Definitions JSON must contain organization and project: $DefinitionsPath"
}

$resolvedId = $DefinitionId
if ($resolvedId -le 0) {
    if ([string]::IsNullOrWhiteSpace($RepositoryFolderName)) {
        throw "Provide -RepositoryFolderName or -DefinitionId."
    }
    $name = $RepositoryFolderName.Trim().TrimEnd('\', '/')
    $leaf = Split-Path -Path $name -Leaf
    $match = @($defs.pipelines | Where-Object { [string]$_.pipelineName -ieq $leaf })
    if ($match.Count -eq 0) {
        $match = @($defs.pipelines | Where-Object { [string]$_.pipelineName -ieq $name })
    }
    if ($match.Count -ne 1) {
        $names = ($defs.pipelines | ForEach-Object { $_.pipelineName }) -join "`n  "
        throw "Expected exactly one pipeline for '$RepositoryFolderName'; found $($match.Count). Known names:`n  $names"
    }
    $resolvedId = [int]$match[0].definitionId
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
    $null = Get-Command -Name "git" -CommandType Application -ErrorAction Stop
    Push-Location (Join-Path $PSScriptRoot "..")
    try {
        $short = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($short)) {
            throw "Could not resolve git branch; pass -Branch explicitly (e.g. refs/heads/dapr)."
        }
        if ($short -eq "HEAD") {
            throw "Detached HEAD; pass -Branch explicitly (e.g. refs/heads/dapr)."
        }
        $Branch = "refs/heads/$short"
    }
    finally {
        Pop-Location
    }
}

$orgUrl = "https://dev.azure.com/$org"

Write-Host "Organization: $orgUrl"
Write-Host "Project:      $project"
Write-Host "DefinitionId: $resolvedId"
Write-Host "Branch:       $Branch"

$argList = @(
    "pipelines", "run",
    "--organization", $orgUrl,
    "--project", $project,
    "--id", "$resolvedId",
    "--branch", $Branch
)
if (-not [string]::IsNullOrWhiteSpace($Parameters)) {
    $argList += "--parameters"
    $argList += $Parameters.Trim()
}

if ($DryRun) {
    Write-Host "`nDryRun: az $($argList -join ' ')"
    return
}

$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$outText = ""
try {
    $proc = Start-Process -FilePath "az" -ArgumentList $argList -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $outText = ""
    if (Test-Path -LiteralPath $stdoutFile) {
        $outText = Get-Content -LiteralPath $stdoutFile -Raw -Encoding UTF8
    }
    $errText = ""
    if (Test-Path -LiteralPath $stderrFile) {
        $errText = Get-Content -LiteralPath $stderrFile -Raw -Encoding UTF8
    }
    if ($null -eq $proc -or $proc.ExitCode -ne 0) {
        throw "az pipelines run failed ($($proc.ExitCode)): $errText"
    }
}
finally {
    Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`naz pipelines run completed."
if (-not [string]::IsNullOrWhiteSpace($outText)) {
    Write-Host $outText.TrimEnd()
}
