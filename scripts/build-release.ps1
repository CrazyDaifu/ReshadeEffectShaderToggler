[CmdletBinding()]
param(
    [string]$MsBuildPath,
    [string]$PlatformToolset,
    [string]$WindowsSdkVersion
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $repoRoot 'src\ReshadeEffectShaderToggler.sln'
$sourceBinary = Join-Path $repoRoot 'src\Win32\Release\ReshadeEffectShaderToggler.addon32'
$outputDirectory = Join-Path $repoRoot 'build'
$outputBinary = Join-Path $outputDirectory 'ReshadeEffectShaderToggler.addon32'

function Find-VisualStudioInstallation {
    $vswhereCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($vswhere in $vswhereCandidates) {
        $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
        if ($installation) {
            return $installation.Trim()
        }
    }

    throw 'Visual Studio with the C++ x86/x64 toolchain was not found.'
}

$visualStudio = Find-VisualStudioInstallation
if ([string]::IsNullOrWhiteSpace($MsBuildPath)) {
    $MsBuildPath = Join-Path $visualStudio 'MSBuild\Current\Bin\MSBuild.exe'
}
else {
    $MsBuildPath = [System.IO.Path]::GetFullPath($MsBuildPath)
}

if (-not (Test-Path -LiteralPath $MsBuildPath)) {
    throw "MSBuild was not found at '$MsBuildPath'."
}
if (-not (Test-Path -LiteralPath $solution)) {
    throw "Solution was not found at '$solution'."
}

if ([string]::IsNullOrWhiteSpace($PlatformToolset)) {
    if (Test-Path -LiteralPath (Join-Path $visualStudio 'MSBuild\Microsoft\VC\v180')) {
        $PlatformToolset = 'v145'
    }
    else {
        $PlatformToolset = 'v143'
    }
}

if ([string]::IsNullOrWhiteSpace($WindowsSdkVersion)) {
    $sdk19041 = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include\10.0.19041.0'
    $WindowsSdkVersion = if (Test-Path -LiteralPath $sdk19041) { '10.0.19041.0' } else { '10.0' }
}

$vcTargets = Get-ChildItem -LiteralPath (Join-Path $visualStudio 'MSBuild\Microsoft\VC') -Directory -Filter 'v*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
if ($vcTargets) {
    $env:VCTargetsPath = $vcTargets.FullName + '\'
}

$version = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'VERSION')).Trim()
$numericVersion = [regex]::Match($version, '^\d+(?:\.\d+){3}').Value
if ([string]::IsNullOrWhiteSpace($numericVersion)) {
    throw "VERSION '$version' must begin with four numeric components."
}

$previousGithubRef = $env:GITHUB_REF_NAME
try {
    $env:GITHUB_REF_NAME = "v$numericVersion"
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    & $MsBuildPath $solution `
        /t:Rebuild `
        /p:Configuration=Release `
        /p:Platform=x86 `
        "/p:PlatformToolset=$PlatformToolset" `
        "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion" `
        /m `
        /v:minimal
    if ($LASTEXITCODE -ne 0) {
        throw "Release/x86 build failed with exit code $LASTEXITCODE."
    }
}
finally {
    $env:GITHUB_REF_NAME = $previousGithubRef
}

if (-not (Test-Path -LiteralPath $sourceBinary)) {
    throw "Build completed without the expected output '$sourceBinary'."
}

Copy-Item -LiteralPath $sourceBinary -Destination $outputBinary -Force
Write-Host "Built: $outputBinary"
Write-Host "Toolset: $PlatformToolset"
Write-Host "Windows SDK: $WindowsSdkVersion"
