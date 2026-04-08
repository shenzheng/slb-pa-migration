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
$repositoryQueue = New-Object System.Collections.Generic.List[object]
$processedCount = 0

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

function Write-StepMessage {
    param(
        [string]$Message
    )

    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
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
        $repositoryQueue.Add([PSCustomObject]@{
                ProjectGroup = $projectGroup
                RepositoryPath = $_.FullName
                RepositoryName = $_.Name
            })
    }
}

$totalCount = $repositoryQueue.Count

Write-StepMessage ("Start pulling repositories from root '{0}'. Total repositories: {1}." -f $resolvedRoot, $totalCount)

foreach ($repository in $repositoryQueue) {
    $processedCount++
    $projectGroup = $repository.ProjectGroup
    $repositoryPath = $repository.RepositoryPath
    $repositoryName = $repository.RepositoryName
    $displayName = "[{0}] {1}" -f $projectGroup, $repositoryName
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $gitDirectory = Join-Path $repositoryPath ".git"

    Write-StepMessage ("({0}/{1}) Processing {2}." -f $processedCount, $totalCount, $displayName)

    if (-not (Test-Path -LiteralPath $gitDirectory)) {
        Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message "Skipped because .git was not found."
        Write-StepMessage ("({0}/{1}) Skipped {2}: .git was not found." -f $processedCount, $totalCount, $displayName)
        continue
    }

    Write-StepMessage ("({0}/{1}) Reading current branch for {2}." -f $processedCount, $totalCount, $displayName)
    $branchResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("rev-parse", "--abbrev-ref", "HEAD")

    if ($branchResult.ExitCode -ne 0) {
        $message = "Failed to read current branch: {0}" -f (($branchResult.Output -join " ").Trim())
        Add-Result -Collection $failures -ProjectGroup $projectGroup -Repository $repositoryName -Message $message
        Write-StepMessage ("({0}/{1}) Failed {2}: {3}" -f $processedCount, $totalCount, $displayName, $message)
        continue
    }

    $branchName = Get-FirstOutputLine -Output $branchResult.Output

    if ([string]::IsNullOrWhiteSpace($branchName) -or $branchName -eq "HEAD") {
        Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message "Skipped because repository is in detached HEAD state."
        Write-StepMessage ("({0}/{1}) Skipped {2}: detached HEAD." -f $processedCount, $totalCount, $displayName)
        continue
    }

    Write-StepMessage ("({0}/{1}) Checking upstream for {2} on branch '{3}'." -f $processedCount, $totalCount, $displayName, $branchName)
    $upstreamResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")

    if ($upstreamResult.ExitCode -ne 0) {
        $message = "Skipped because upstream is not configured for branch '{0}'." -f $branchName
        Add-Result -Collection $skips -ProjectGroup $projectGroup -Repository $repositoryName -Message $message
        Write-StepMessage ("({0}/{1}) Skipped {2}: upstream is not configured." -f $processedCount, $totalCount, $displayName)
        continue
    }

    $upstreamName = Get-FirstOutputLine -Output $upstreamResult.Output

    Write-StepMessage ("({0}/{1}) Pulling {2} from '{3}'." -f $processedCount, $totalCount, $displayName, $upstreamName)
    $pullResult = Invoke-GitCommand -RepositoryPath $repositoryPath -Arguments @("pull", "--ff-only")

    if ($pullResult.ExitCode -ne 0) {
        $message = "git pull failed for '{0}': {1}" -f $branchName, (($pullResult.Output -join " ").Trim())
        Add-Result -Collection $failures -ProjectGroup $projectGroup -Repository $repositoryName -Message $message
        Write-StepMessage ("({0}/{1}) Failed {2}: {3}" -f $processedCount, $totalCount, $displayName, $message)
        continue
    }

    $pullSummary = (($pullResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").Trim()

    if ([string]::IsNullOrWhiteSpace($pullSummary)) {
        $pullSummary = "Pull completed successfully."
    }

    $stopwatch.Stop()
    Add-Result -Collection $successes -ProjectGroup $projectGroup -Repository $repositoryName -Message ("Branch '{0}' from '{1}': {2}" -f $branchName, $upstreamName, $pullSummary)
    Write-StepMessage ("({0}/{1}) Completed {2} in {3:N1}s." -f $processedCount, $totalCount, $displayName, $stopwatch.Elapsed.TotalSeconds)
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
