[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'VERSION')).Trim()
if ([string]::IsNullOrWhiteSpace($version) -or $version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Invalid VERSION '$version'."
}

$buildBinary = Join-Path $repoRoot 'build\ReshadeEffectShaderToggler.addon32'
$buildChecksums = Join-Path $repoRoot 'build\SHA256SUMS.txt'
$archiveDirectory = Join-Path $repoRoot "releases\$version"

if (-not (Test-Path -LiteralPath $buildBinary) -or -not (Test-Path -LiteralPath $buildChecksums)) {
    throw 'Verified build output is missing. Run build-release.ps1 and verify-binary.ps1 first.'
}

New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
Copy-Item -LiteralPath $buildBinary -Destination (Join-Path $archiveDirectory 'ReshadeEffectShaderToggler.addon32') -Force
Copy-Item -LiteralPath $buildChecksums -Destination (Join-Path $archiveDirectory 'SHA256SUMS.txt') -Force
Write-Host "Archived: $archiveDirectory"
