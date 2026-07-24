[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'VERSION')).Trim()
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "packages\ReshadeEffectShaderToggler-$version-GitHub.zip"
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (Test-Path -LiteralPath $OutputPath) {
    throw "Output archive already exists: '$OutputPath'. Remove or rename it before packaging."
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('REST-package-' + [guid]::NewGuid().ToString('N'))
$stagingRepo = Join-Path $stagingRoot 'ReshadeEffectShaderToggler'

try {
    New-Item -ItemType Directory -Path $stagingRepo -Force | Out-Null

    Get-ChildItem -LiteralPath $repoRoot -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($repoRoot.Length).TrimStart('\')
        if ($relative -match '^(\.git|\.vs)(\\|$)' -or
            $relative -match '^packages\\.*\.(zip|sha256)$' -or
            $relative -match '^deps\\reshade-v20-backup(\\|$)' -or
            $relative -match '^src\\(Win32|x64)(\\|$)' -or
            $relative -match '^deps\\libMinHook\\(Win32|x64)(\\|$)' -or
            $relative -match '\.(obj|pdb|idb|ipdb|iobj|lib|exp|tlog|recipe)$') {
            return
        }

        $destination = Join-Path $stagingRepo $relative
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    Compress-Archive -Path $stagingRepo -DestinationPath $OutputPath -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath
"$($hash.Hash) *$([System.IO.Path]::GetFileName($OutputPath))" |
    Set-Content -Encoding ASCII -LiteralPath ($OutputPath + '.sha256')
Write-Host "Created: $OutputPath"
Write-Host "SHA-256: $($hash.Hash)"
