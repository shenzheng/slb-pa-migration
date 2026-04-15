<#
.SYNOPSIS
  Register existing nested clones under Actors/, Pipeline/, and Shared/ as git submodules of the PA repo.

.DESCRIPTION
  Today these folders are gitignored in PA but each contains its own .git. This script removes each
  working tree and runs `git submodule add` so PA records gitlinks + .gitmodules.

  Branch for `git submodule add -b` (and .gitmodules "branch"):
  - Each (default): use each nested repo's current branch (git rev-parse --abbrev-ref HEAD).
  - Parent: use the PA repo's current branch name for every submodule (all must exist on origin).

  Run with -WhatIf first to preview. Commit or stash work in nested repos before running; uncommitted
  changes inside those folders will be deleted when the directory is removed.

.NOTES
  Requires: git in PATH, network access to Azure DevOps remotes, SSH keys for git@ssh.dev.azure.com.
#>
param(
    [string]$RootPath,
    [string[]]$ProjectGroups = @("Actors", "Pipeline", "Shared"),
    [ValidateSet('Each', 'Parent')]
    [string]$BranchMode = 'Each',
    [switch]$WhatIf,
    [switch]$AllowDirty,
    [string]$Only
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)
    return (($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
                }
                else {
                    $_
                }
            }) -join " ")
}

function Invoke-GitCommand {
    param(
        [string]$RepositoryPath,
        [string[]]$Arguments
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "git"
    $startInfo.WorkingDirectory = $RepositoryPath
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $output = @()
    if (-not [string]::IsNullOrWhiteSpace($standardOutput)) { $output += ($standardOutput -split "`r?`n") }
    if (-not [string]::IsNullOrWhiteSpace($standardError)) { $output += ($standardError -split "`r?`n") }
    return [PSCustomObject]@{
        Output   = @($output | Where-Object { $_ -ne "" })
        ExitCode = $process.ExitCode
    }
}

function Get-FirstLine {
    param([object[]]$Output)
    $line = $Output | Select-Object -First 1
    if ($null -eq $line) { return "" }
    return $line.ToString().Trim()
}

function Test-PathIsSubmodule {
    param(
        [string]$RepoRoot,
        [string]$RelativePath
    )
    $r = Invoke-GitCommand -RepositoryPath $RepoRoot -Arguments @("ls-files", "-s", "--", $RelativePath)
    if ($r.ExitCode -ne 0) { return $false }
    $line = Get-FirstLine -Output $r.Output
    # git ls-files -s: "160000 <sha> <stage>\t<path>" for submodule gitlink
    return $line -match '^160000\s'
}

function Remove-DirectoryRobust {
    param(
        [string]$LiteralPath
    )
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }
    # Drop read-only/system/hidden flags that often block deletes on Windows.
    cmd /c "attrib -r -s -h `"$LiteralPath\*`" /s /d" 2>$null | Out-Null

    $attempts = 10
    for ($i = 0; $i -lt $attempts; $i++) {
        try {
            Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            # Move aside then delete — often succeeds when in-place delete hits transient locks.
            try {
                $stashName = "__pa_submodule_delete__" + [Guid]::NewGuid().ToString("N")
                $parent = Split-Path -LiteralPath $LiteralPath -Parent
                $stashPath = Join-Path $parent $stashName
                Rename-Item -LiteralPath $LiteralPath -NewName $stashName -ErrorAction Stop
                Start-Sleep -Milliseconds 400
                Remove-Item -LiteralPath $stashPath -Recurse -Force -ErrorAction Stop
                return
            }
            catch {
                cmd /c "rd /s /q `"$LiteralPath`"" 2>$null | Out-Null
                if (-not (Test-Path -LiteralPath $LiteralPath)) {
                    return
                }
                Start-Sleep -Milliseconds 1000
            }
        }
    }
    throw "Could not remove directory after retries: $LiteralPath"
}

function Clear-StaleSubmoduleMetadata {
    param(
        [string]$RepoRoot,
        [string]$RelativePath
    )
    if (Test-PathIsSubmodule -RepoRoot $RepoRoot -RelativePath $RelativePath) {
        return
    }
    $relFs = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $modDir = Join-Path $RepoRoot (Join-Path ".git\modules" $relFs)
    if (Test-Path -LiteralPath $modDir) {
        Remove-Item -LiteralPath $modDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $section = "submodule." + $RelativePath
    Invoke-GitCommand -RepositoryPath $RepoRoot -Arguments @("config", "--local", "--remove-section", $section) | Out-Null
}

function Remove-GitignoreSubmoduleLines {
    param([string]$GitignorePath)
    if (-not (Test-Path -LiteralPath $GitignorePath)) { return }
    $lines = Get-Content -LiteralPath $GitignorePath
    # Rhapsody.Computation.Flowback/ matches Actors/Rhapsody.Computation.Flowback without a leading slash.
    $toRemove = @('Actors/', 'Pipeline/', 'Shared/', 'Rhapsody.Computation.Flowback/')
    $newLines = $lines | Where-Object { $_ -notin $toRemove }
    if ($newLines.Count -eq $lines.Count) { return }
    $header = "# Actors/, Pipeline/, Shared/: tracked as git submodules (see .gitmodules)."
    if ($newLines -notcontains $header) {
        $newLines = @($header) + $newLines
    }
    Set-Content -LiteralPath $GitignorePath -Value $newLines -Encoding utf8
}

$parentBranchResult = Invoke-GitCommand -RepositoryPath $resolvedRoot -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
$parentBranch = Get-FirstLine -Output $parentBranchResult.Output
if ($parentBranchResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($parentBranch)) {
    Write-Error "Could not read PA repo current branch at '$resolvedRoot'."
}

$repositoryQueue = New-Object System.Collections.Generic.List[object]

foreach ($projectGroup in $ProjectGroups) {
    $groupPath = Join-Path $resolvedRoot $projectGroup
    if (-not (Test-Path -LiteralPath $groupPath -PathType Container)) {
        Write-Warning "Skipping missing group path: $groupPath"
        continue
    }
    Get-ChildItem -LiteralPath $groupPath -Directory | Sort-Object Name | ForEach-Object {
        $rel = ($projectGroup + "/" + $_.Name) -replace '\\', '/'
        if (-not [string]::IsNullOrWhiteSpace($Only) -and $rel -notlike "*$Only*") {
            return
        }
        $gitMarker = Join-Path $_.FullName ".git"
        if (-not (Test-Path -LiteralPath $gitMarker)) {
            return
        }
        $repositoryQueue.Add([PSCustomObject]@{
                Group        = $projectGroup
                Name         = $_.Name
                FullPath     = $_.FullName
                RelativePath = $rel
            })
    }
}

Write-Host ("PA root: {0}" -f $resolvedRoot)
Write-Host ("PA branch: {0} | BranchMode: {1} | WhatIf: {2}" -f $parentBranch, $BranchMode, $WhatIf)
Write-Host ("Repositories to process: {0}" -f $repositoryQueue.Count)
Write-Host ""

$exitCode = 0
$index = 0

if (-not $WhatIf -and $repositoryQueue.Count -gt 0) {
    $gitignorePath = Join-Path $resolvedRoot ".gitignore"
    Remove-GitignoreSubmoduleLines -GitignorePath $gitignorePath
}

foreach ($repo in $repositoryQueue) {
    $index++
    $rel = $repo.RelativePath
    $display = $rel

    if (Test-PathIsSubmodule -RepoRoot $resolvedRoot -RelativePath $rel) {
        Write-Host ("[{0}/{1}] SKIP (already submodule): {2}" -f $index, $repositoryQueue.Count, $display)
        continue
    }

    $remoteResult = Invoke-GitCommand -RepositoryPath $repo.FullPath -Arguments @("remote", "get-url", "origin")
    if ($remoteResult.ExitCode -ne 0) {
        Write-Warning ("[{0}/{1}] SKIP (no origin): {2}" -f $index, $repositoryQueue.Count, $display)
        $exitCode = 1
        continue
    }
    $remoteUrl = Get-FirstLine -Output $remoteResult.Output

    $branchName = $null
    if ($BranchMode -eq 'Parent') {
        $branchName = $parentBranch
    }
    else {
        $br = Invoke-GitCommand -RepositoryPath $repo.FullPath -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
        if ($br.ExitCode -ne 0) {
            Write-Warning ("[{0}/{1}] SKIP (branch): {2}" -f $index, $repositoryQueue.Count, $display)
            $exitCode = 1
            continue
        }
        $branchName = Get-FirstLine -Output $br.Output
    }

    if ($branchName -eq "HEAD") {
        Write-Warning ("[{0}/{1}] SKIP (detached HEAD): {2}" -f $index, $repositoryQueue.Count, $display)
        $exitCode = 1
        continue
    }

    if (-not $AllowDirty) {
        $st = Invoke-GitCommand -RepositoryPath $repo.FullPath -Arguments @("status", "--porcelain")
        if ($st.ExitCode -eq 0 -and ($st.Output | Where-Object { $_ } | Measure-Object).Count -gt 0) {
            Write-Warning ("[{0}/{1}] SKIP (dirty working tree, use -AllowDirty to override): {2}" -f $index, $repositoryQueue.Count, $display)
            $exitCode = 1
            continue
        }
    }

    if ($WhatIf) {
        Write-Host ("[{0}/{1}] WHATIF: submodule add -b {2} {3} {4}" -f $index, $repositoryQueue.Count, $branchName, $remoteUrl, $rel)
        continue
    }

    Write-Host ("[{0}/{1}] Removing and re-adding as submodule: {2} (branch {3})" -f $index, $repositoryQueue.Count, $display, $branchName)
    Clear-StaleSubmoduleMetadata -RepoRoot $resolvedRoot -RelativePath $rel
    Remove-DirectoryRobust -LiteralPath $repo.FullPath

    $addArgs = @("submodule", "add", "-b", $branchName, $remoteUrl, $rel)
    $addResult = Invoke-GitCommand -RepositoryPath $resolvedRoot -Arguments $addArgs
    if ($addResult.ExitCode -ne 0) {
        Write-Error ("git submodule add failed for {0}: {1}" -f $rel, (($addResult.Output -join " ").Trim()))
    }
}

if (-not $WhatIf -and $repositoryQueue.Count -gt 0 -and $exitCode -eq 0) {
    Write-Host ""
    Write-Host "Next: review `git status`, then commit .gitmodules and submodule gitlinks."
}

exit $exitCode
