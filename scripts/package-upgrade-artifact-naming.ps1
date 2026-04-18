#Requires -Version 5.1
<#
.SYNOPSIS
  Shared helpers for doc/ artifact file names (per-repository token, safe for concurrent jobs).

.NOTES
  Dot-source this file from other scripts: . (Join-Path $PSScriptRoot 'package-upgrade-artifact-naming.ps1')
#>

function Write-PackageUpgradeDocJsonAtomic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $dir = [System.IO.Path]::GetDirectoryName($TargetPath)
    if ([string]::IsNullOrWhiteSpace($dir)) {
        throw "TargetPath must include a directory: $TargetPath"
    }

    [System.IO.Directory]::CreateDirectory($dir) | Out-Null

    $leaf = [System.IO.Path]::GetFileName($TargetPath)
    $tempPath = Join-Path $dir ("{0}.{1}.{2}.tmp" -f $leaf, $PID, ([Guid]::NewGuid().ToString("N")))
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        if (Test-Path -LiteralPath $TargetPath) {
            [System.IO.File]::Replace($tempPath, $TargetPath, $null)
        }
        else {
            [System.IO.File]::Move($tempPath, $TargetPath)
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Get-PackageUpgradeRepositoryArtifactToken {
    <#
    .SYNOPSIS
      Build a stable, filesystem-safe token from a repo-relative path (e.g. Actors\Foo\Bar).
    .DESCRIPTION
      Uses path segments joined by '__' and replaces other non-alphanumeric (except . -) with '_'.
      If the result is long, uses an 80-char prefix plus '__' plus 16 hex chars of SHA256(lowercase full path).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRelativePath
    )

    $n = $RepositoryRelativePath.Trim().TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($n)) {
        return "default"
    }

    $n = $n -replace '/', '\'
    $token = ($n -replace '\\', '__')
    $token = $token -replace '[^\w\.\-]', '_'
    if ([string]::IsNullOrWhiteSpace($token)) {
        return "default"
    }

    if ($token.Length -gt 120) {
        $lower = $n.ToLowerInvariant()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($lower)
            $hashBytes = $sha.ComputeHash($bytes)
        }
        finally {
            $sha.Dispose()
        }
        $hex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16).ToLowerInvariant()
        $prefixLen = [Math]::Min(80, $token.Length)
        $token = "{0}__{1}" -f $token.Substring(0, $prefixLen), $hex
    }

    return $token
}
