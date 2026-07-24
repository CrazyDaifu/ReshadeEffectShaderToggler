[CmdletBinding()]
param(
    [string]$BinaryPath,
    [string]$DumpbinPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BinaryPath)) {
    $BinaryPath = Join-Path $repoRoot 'build\ReshadeEffectShaderToggler.addon32'
}
$BinaryPath = [System.IO.Path]::GetFullPath($BinaryPath)

function Find-Dumpbin {
    $vswhereCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($vswhere in $vswhereCandidates) {
        $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
        if (-not $installation) { continue }

        $candidate = Get-ChildItem -LiteralPath (Join-Path $installation.Trim() 'VC\Tools\MSVC') -Filter dumpbin.exe -Recurse -File |
            Where-Object { $_.FullName -match 'Hostx64\\x64\\dumpbin\.exe$' -or $_.FullName -match 'Hostx64\\x86\\dumpbin\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($candidate) { return $candidate }
    }

    throw 'dumpbin.exe was not found in the Visual Studio C++ toolchain.'
}

if (-not (Test-Path -LiteralPath $BinaryPath)) {
    throw "Binary not found: '$BinaryPath'. Run build-release.ps1 first."
}
if ([System.IO.Path]::GetExtension($BinaryPath) -ne '.addon32') {
    throw "Expected a .addon32 binary, got '$BinaryPath'."
}
if ([string]::IsNullOrWhiteSpace($DumpbinPath)) {
    $DumpbinPath = Find-Dumpbin
}
if (-not (Test-Path -LiteralPath $DumpbinPath)) {
    throw "dumpbin.exe was not found at '$DumpbinPath'."
}

$headers = (& $DumpbinPath /headers $BinaryPath | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'dumpbin /headers failed.' }
$exports = (& $DumpbinPath /exports $BinaryPath | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'dumpbin /exports failed.' }

if ($headers -notmatch '14C machine \(x86\)') {
    throw 'Binary is not PE32/x86.'
}
if ($exports -notmatch '(?m)^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+DESCRIPTION(?:\s*=.*)?$') {
    throw 'Required ReShade export DESCRIPTION was not found.'
}
if ($exports -notmatch '(?m)^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+NAME(?:\s*=.*)?$') {
    throw 'Required ReShade export NAME was not found.'
}

$item = Get-Item -LiteralPath $BinaryPath
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $BinaryPath
$checksumPath = Join-Path (Split-Path -Parent $BinaryPath) 'SHA256SUMS.txt'
"$($hash.Hash) *$($item.Name)" | Set-Content -Encoding ASCII -LiteralPath $checksumPath

Write-Host "Verified: $($item.FullName)"
Write-Host 'Architecture: PE32/x86'
Write-Host 'Exports: NAME, DESCRIPTION'
Write-Host "Size: $($item.Length) bytes"
Write-Host "SHA-256: $($hash.Hash)"
Write-Host "Checksum: $checksumPath"
