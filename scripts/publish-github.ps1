[CmdletBinding()]
param(
    [string]$UpstreamRepository = '4lex4nder/ReshadeEffectShaderToggler',
    [string]$ForkName = 'ReshadeEffectShaderToggler',
    [string]$ReleaseTag,
    [switch]$PublishRelease
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Program $($Arguments -join ' ')"
    }
}

function Test-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $Program @Arguments *> $null
        return $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or is not available in PATH.'
}

$gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $gh) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $winget) {
        throw 'GitHub CLI is required. Install it from https://cli.github.com/.'
    }
    Invoke-Checked $winget install --id GitHub.cli --exact --accept-package-agreements --accept-source-agreements
    $gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (-not (Test-Path -LiteralPath $gh)) {
        throw 'GitHub CLI installation completed, but gh.exe was not found. Restart the terminal and retry.'
    }
}

Push-Location $repoRoot
try {
    if (-not (Test-NativeCommand $gh auth status)) {
        Write-Host 'GitHub login is required. Complete the browser authentication flow.'
        Invoke-Checked $gh auth login --web --git-protocol https
    }

    $version = (Get-Content -Raw -LiteralPath '.\VERSION').Trim()
    if ([string]::IsNullOrWhiteSpace($version) -or $version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
        throw "Invalid VERSION '$version'."
    }
    if ($PublishRelease) {
        if ($version -match '-') {
            throw "VERSION '$version' is a pre-release and cannot create a formal tag."
        }
        if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
            $ReleaseTag = "v$version"
        }
        if ($ReleaseTag -ne "v$version") {
            throw "Release tag '$ReleaseTag' does not match VERSION '$version'. Expected 'v$version'."
        }
    }

    Write-Host "Building and verifying $version before upload..."
    Invoke-Checked powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-release.ps1')
    Invoke-Checked powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-binary.ps1')
    Invoke-Checked powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'archive-version.ps1')

    if (-not (Test-Path -LiteralPath '.git')) {
        Invoke-Checked git init -b main
        Invoke-Checked git remote add upstream "https://github.com/$UpstreamRepository.git"
    }
    elseif (-not (Test-NativeCommand git remote get-url upstream)) {
        Invoke-Checked git remote add upstream "https://github.com/$UpstreamRepository.git"
    }

    # Anchor an uncommitted source snapshot to the actual upstream main commit.
    # Mixed reset preserves every working-tree file while establishing fork ancestry.
    if (-not (Test-NativeCommand git rev-parse --verify HEAD)) {
        Invoke-Checked git fetch upstream main --tags
        Invoke-Checked git reset --mixed upstream/main
    }

    $branch = (& git branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = 'main'
        Invoke-Checked git switch -c $branch
    }

    $login = (& $gh api user --jq .login).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($login)) {
        throw 'Unable to determine the authenticated GitHub account.'
    }

    if ([string]::IsNullOrWhiteSpace((& git config --local user.name))) {
        Invoke-Checked git config --local user.name $login
    }
    if ([string]::IsNullOrWhiteSpace((& git config --local user.email))) {
        Invoke-Checked git config --local user.email "$login@users.noreply.github.com"
    }

    Invoke-Checked git add --all
    if (-not (Test-NativeCommand git diff --cached --quiet)) {
        Invoke-Checked git commit -m "Fix D3D9 windowed surface rendering ($version)"
    }

    $forkRepository = "$login/$ForkName"
    if (Test-NativeCommand $gh api "repos/$forkRepository") {
        $repositoryInfo = (& $gh api "repos/$forkRepository" | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect GitHub repository '$forkRepository'."
        }
        if (-not $repositoryInfo.fork -or $repositoryInfo.parent.full_name -ne $UpstreamRepository) {
            throw "Repository '$forkRepository' exists but is not a fork of '$UpstreamRepository'. Choose another -ForkName or rename the existing repository."
        }
    }
    else {
        Write-Host "Creating GitHub fork $forkRepository from $UpstreamRepository..."
        $upstreamOwner, $upstreamName = $UpstreamRepository.Split('/', 2)
        if ([string]::IsNullOrWhiteSpace($upstreamOwner) -or [string]::IsNullOrWhiteSpace($upstreamName)) {
            throw "Invalid upstream repository '$UpstreamRepository'."
        }
        Invoke-Checked $gh api --method POST "repos/$UpstreamRepository/forks" -f "name=$ForkName"

        $forkReady = $false
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            if (Test-NativeCommand $gh repo view $forkRepository) {
                $forkReady = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        if (-not $forkReady) {
            throw "GitHub accepted the fork request, but '$forkRepository' was not ready in time. Run the script again."
        }
    }

    $originUrl = "https://github.com/$forkRepository.git"
    if (Test-NativeCommand git remote get-url origin) {
        Invoke-Checked git remote set-url origin $originUrl
    }
    else {
        Invoke-Checked git remote add origin $originUrl
    }

    try {
        Invoke-Checked git push --set-upstream origin $branch
    }
    catch {
        Write-Warning 'Normal Git push failed. Falling back to the GitHub REST API.'
        Invoke-Checked powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'push-via-github-api.ps1') `
            -Repository $forkRepository `
            -Branch $branch
    }

    if ($PublishRelease) {
        if (-not (Test-NativeCommand git rev-parse --verify "refs/tags/$ReleaseTag")) {
            Invoke-Checked git tag -a $ReleaseTag -m "ReshadeEffectShaderToggler $version"
        }
        elseif ((& git rev-list -n 1 $ReleaseTag).Trim() -ne (& git rev-parse HEAD).Trim()) {
            throw "Tag '$ReleaseTag' already points to a different commit."
        }
        Invoke-Checked git push origin $ReleaseTag
    }

    $url = (& $gh repo view $forkRepository --json url --jq .url).Trim()
    Write-Host ''
    Write-Host "Published fork: $url"
    Write-Host "Actions: $url/actions"
    Write-Host "Branch: $branch"
    if ($PublishRelease) {
        Write-Host "Release workflow triggered by $ReleaseTag."
    }
    else {
        Write-Host 'Candidate updated. No formal release tag was created.'
    }
}
finally {
    Pop-Location
}
