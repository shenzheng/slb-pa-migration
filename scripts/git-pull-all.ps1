param(
    [string]$RootPath,
    [string[]]$ProjectGroups = @("Actors", "Shared")
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$successes = New-Object System.Collections.Generic.List[object]
$skips = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]

function ConvertTo-ProcessArgumentString {
    param(
        [string[]]$Arguments
    )

    return (($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
                }
                else {
                    $_
                }
            }) -join " ")
}

function Add-Result {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$ProjectGroup,
        [string]$Repository,
        [string]$Message
    )

    $Collection.Add([PSCustomObject]@{
            ProjectGroup = $ProjectGroup
            Repository = $Repository
            Message = $Message
        })
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

    if (-not [string]::IsNullOrWhiteSpace($standardOutput)) {
        $output += ($standardOutput -split "`r?`n")
    }

    if (-not [string]::IsNullOrWhiteSpace($standardError)) {
        $output += ($standardError -split "`r?`n")
    }

    $exitCode = $process.ExitCode

    return [PSCustomObject]@{
        Output = @($output | Where-Object { $_ -ne "" })
        ExitCode = $exitCode
    }
}

function Get-FirstOutputLine {
    param(
        [object[]]$Output
    )

    $firstLine = $Output | Select-Object -First 1

    if ($null -eq $firstLine) {
        return ""
    }

    return $firstLine.ToString().Trim()
}

foreach ($projectGroup in $ProjectGroups) {
    $groupPath = Join-Path $resolvedRoot $projectGroup

    if (-not (Test-Path -LiteralPath $groupPath -PathType Container)) {
        Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository "-" -Message "Skipped because group path does not exist."
        continue
    }

    Get-ChildItem -LiteralPath $groupPath -Directory | Sort-Object Name | ForEach-Object {
        $repositoryPath = $_.FullName
        $repositoryName = $_.Name
        $gitDirectory = Join-Path $repositoryPath ".git"

        if (-not (Test-Path -LiteralPath $gitDirectory)) {
            Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message "Skipped because .git was not found."
            return
        }

        $branchResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("rev-parse", "--abbrev-ref", "HEAD")

        if ($branchResult.ExitCode -ne 0) {
            Add-Result -Collection $failures -ProjectGroup $projectGroup -Repository $repositoryName -Message ("Failed to read current branch: {0}" -f (($branchResult.Output -join " ").Trim()))
            return
        }

        $branchName = Get-FirstOutputLine -Output $branchResult.Output

        if ([string]::IsNullOrWhiteSpace($branchName) -or $branchName -eq "HEAD") {
            Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message "Skipped because repository is in detached HEAD state."
            return
        }

        $upstreamResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")

        if ($upstreamResult.ExitCode -ne 0) {
            Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message ("Skipped because upstream is not configured for branch '{0}'." -f $branchName)
            return
        }

        $upstreamName = Get-FirstOutputLine -Output $upstreamResult.Output
        $pullResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("pull", "--ff-only")

        if ($pullResult.ExitCode -ne 0) {
            Add-Result -Collection $failures -ProjectGroup $projectGroup -Repository $repositoryName -Message ("git pull failed for '{0}': {1}" -f $branchName, (($pullResult.Output -join " ").Trim()))
            return
        }

        $pullSummary = (($pullResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").Trim()

        if ([string]::IsNullOrWhiteSpace($pullSummary)) {
            $pullSummary = "Pull completed successfully."
        }

        Add-Result -Collection $successes -ProjectGroup $projectGroup -Repository $repositoryName -Message ("Branch '{0}' from '{1}': {2}" -f $branchName, $upstreamName, $pullSummary)
    }
}

Write-Host "Git pull summary"
Write-Host ("Succeeded: {0}" -f $successes.Count)
Write-Host ("Skipped:   {0}" -f $skips.Count)
Write-Host ("Failed:    {0}" -f $failures.Count)

if ($successes.Count -gt 0) {
    Write-Host ""
    Write-Host "[Succeeded]"
    $successes | ForEach-Object {
        Write-Host ("[{0}] {1} - {2}" -f $_.ProjectGroup, $_.Repository, $_.Message)
    }
}

if ($skips.Count -gt 0) {
    Write-Host ""
    Write-Host "[Skipped]"
    $skips | ForEach-Object {
        Write-Host ("[{0}] {1} - {2}" -f $_.ProjectGroup, $_.Repository, $_.Message)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "[Failed]"
    $failures | ForEach-Object {
        Write-Host ("[{0}] {1} - {2}" -f $_.ProjectGroup, $_.Repository, $_.Message)
    }

    exit 1
}

exit 0
