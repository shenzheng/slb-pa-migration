param(
    [string]$InputPath,
    [string]$Text,
    [string]$OutputPath,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Write-FatalError {
    param(
        [string]$Message
    )

    Write-Error $Message
    exit 1
}

function Resolve-WorkspacePath {
    param(
        [string]$BasePath,
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Get-InputBlocks {
    param(
        [string]$TextValue,
        [string]$InputPathValue,
        [string]$RootPathValue
    )

    $blocks = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrWhiteSpace($TextValue)) {
        $blocks.Add([PSCustomObject]@{
                Source = "Text"
                SourcePath = $null
                Content = $TextValue
            })
    }

    if (-not [string]::IsNullOrWhiteSpace($InputPathValue)) {
        $resolvedInputPath = Resolve-WorkspacePath -BasePath $RootPathValue -PathValue $InputPathValue
        if (-not (Test-Path -LiteralPath $resolvedInputPath -PathType Leaf)) {
            throw "Input file was not found at '$resolvedInputPath'."
        }

        $blocks.Add([PSCustomObject]@{
                Source = "InputPath"
                SourcePath = $resolvedInputPath
                Content = [System.IO.File]::ReadAllText($resolvedInputPath)
            })
    }

    return $blocks
}

function Get-PackageVersionCandidate {
    param(
        [string]$Content,
        [string]$Source,
        [string]$SourcePath
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    $lines = $Content -split "`r?`n"
    $sourcePriority = switch ($Source) {
        "InputPath" { 0 }
        "Text" { 1 }
        default { 9 }
    }

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $patterns = @(
            @{
                Pattern = '(?<!\d)(?<Prefix>#\s*)?(?<Version>\d+\.\d+\.\d+\.\d+)(?!\d)'
                BaseScore = 100
            }
        )

        foreach ($patternInfo in $patterns) {
            foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($line, $patternInfo.Pattern)) {
                if (-not $match.Success) {
                    continue
                }

                $matchedText = $match.Value.Trim()
                $version = $match.Groups["Version"].Value.Trim()
                $hasPrefix = -not [string]::IsNullOrWhiteSpace($match.Groups["Prefix"].Value)
                $contextScore = 0

                if ($line -match '(?i)\b(version|package|build|artifact|release|pipeline)\b') {
                    $contextScore += 20
                }

                if ($line -match '(?i)\b(azure devops|ado)\b') {
                    $contextScore += 10
                }

                if ($hasPrefix) {
                    $contextScore += 50
                }

                $candidates.Add([PSCustomObject]@{
                        PackageVersion = $version
                        MatchedText = $matchedText
                        Source = $Source
                        SourcePriority = $sourcePriority
                        SourcePath = $SourcePath
                        LineNumber = $lineIndex + 1
                        MatchStart = $match.Index
                        Score = $patternInfo.BaseScore + $contextScore
                    })
            }
        }
    }

    return $candidates
}

function Select-BestCandidate {
    param(
        [object[]]$Candidates
    )

    if ($null -eq $Candidates -or $Candidates.Count -eq 0) {
        return $null
    }

    return $Candidates |
        Sort-Object `
            @{ Expression = "Score"; Descending = $true }, `
            @{ Expression = "SourcePriority"; Descending = $false }, `
            @{ Expression = "LineNumber"; Descending = $false }, `
            @{ Expression = "MatchStart"; Descending = $false } |
        Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $workspaceRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
}
else {
    $workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$inputBlocks = Get-InputBlocks -TextValue $Text -InputPathValue $InputPath -RootPathValue $workspaceRoot
if ($inputBlocks.Count -eq 0) {
    Write-FatalError "No input was provided. Specify -Text, -InputPath, or both."
}

$allCandidates = New-Object System.Collections.Generic.List[object]
foreach ($block in $inputBlocks) {
    $blockCandidates = @(Get-PackageVersionCandidate -Content $block.Content -Source $block.Source -SourcePath $block.SourcePath)
    if ($null -ne $blockCandidates -and $blockCandidates.Count -gt 0) {
        foreach ($candidate in $blockCandidates) {
            $allCandidates.Add($candidate)
        }
    }
}

if ($allCandidates.Count -eq 0) {
    Write-FatalError "No pipeline package version was found in the provided input."
}

$selectedCandidate = Select-BestCandidate -Candidates @($allCandidates.ToArray())

if ($null -eq $selectedCandidate) {
    Write-FatalError "No pipeline package version was found in the provided input."
}

$resultObject = [PSCustomObject]@{
    PackageVersion = $selectedCandidate.PackageVersion
    MatchedText = $selectedCandidate.MatchedText
    Source = $selectedCandidate.Source
    SourcePath = $selectedCandidate.SourcePath
    LineNumber = $selectedCandidate.LineNumber
}

if ($AsJson.IsPresent) {
    $outputText = $resultObject | ConvertTo-Json -Depth 4 -Compress
}
else {
    $outputText = $resultObject.PackageVersion
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = Resolve-WorkspacePath -BasePath $workspaceRoot -PathValue $OutputPath
    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)

    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw "OutputPath must include a file name."
    }

    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    [System.IO.File]::WriteAllText($resolvedOutputPath, $outputText + "`r`n", [System.Text.UTF8Encoding]::new($false))
}

Write-Output $outputText
