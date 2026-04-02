param(
    [string]$RootPath = "."
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$extensions = @(
    ".cs",
    ".csproj",
    ".props",
    ".targets",
    ".sln",
    ".slnx",
    ".json",
    ".yml",
    ".yaml",
    ".md",
    ".ps1",
    ".nuspec",
    ".xml",
    ".config",
    ".txt"
)

$excludedDirs = @(
    ".git",
    ".vs",
    "bin",
    "obj",
    "packages",
    "artifacts",
    "TestResults"
)

function Test-ShouldSkipPath {
    param(
        [string]$FullName
    )

    foreach ($dir in $excludedDirs) {
        if ($FullName -match [regex]::Escape("\$dir\")) {
            return $true
        }
    }

    return $false
}

function Get-FileEncoding {
    param(
        [byte[]]$Bytes
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.UTF8Encoding]::new($true)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.UnicodeEncoding]::new($false, $true)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.UnicodeEncoding]::new($true, $true)
    }

    return [System.Text.UTF8Encoding]::new($false)
}

function Test-HasLfOnly {
    param(
        [byte[]]$Bytes
    )

    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 10) {
            if ($i -eq 0 -or $Bytes[$i - 1] -ne 13) {
                return $true
            }
        }
    }

    return $false
}

$normalizedFiles = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Where-Object {
    -not (Test-ShouldSkipPath -FullName $_.FullName) -and $extensions.Contains($_.Extension.ToLowerInvariant())
} | ForEach-Object {
    $path = $_.FullName
    $bytes = [System.IO.File]::ReadAllBytes($path)

    if (-not (Test-HasLfOnly -Bytes $bytes)) {
        return
    }

    $encoding = Get-FileEncoding -Bytes $bytes
    $content = $encoding.GetString($bytes)

    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }

    $normalized = $content -replace "`r?`n", "`r`n"

    if ($normalized -ceq $content) {
        return
    }

    [System.IO.File]::WriteAllText($path, $normalized, $encoding)
    $normalizedFiles.Add($path)
}

if ($normalizedFiles.Count -eq 0) {
    Write-Host "All matching text files already use CRLF. No files were changed."
    exit 0
}

Write-Host "Normalized CRLF for the following files:"
$normalizedFiles | ForEach-Object { Write-Host $_ }
