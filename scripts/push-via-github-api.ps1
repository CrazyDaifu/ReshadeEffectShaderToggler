[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$Branch,
    [string]$KnownGitHubTree
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-CheckedGit {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed ($LASTEXITCODE): git $($Arguments -join ' ')"
    }
}

function Get-GitOutput {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed ($LASTEXITCODE): git $($Arguments -join ' ')"
    }
    return $output
}

function Get-GitBlobBytes {
    param([Parameter(Mandatory = $true)][string]$Sha)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git.exe'
    $startInfo.Arguments = "cat-file blob $Sha"
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to read Git blob '$Sha'."
    }

    $memory = New-Object System.IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Unable to read Git blob '$Sha': $errorText"
        }
        return $memory.ToArray()
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Write-GitCommitObject {
    param(
        [Parameter(Mandatory = $true)][string]$Tree,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][object]$Author,
        [Parameter(Mandatory = $true)][object]$Committer,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $authorTimestamp = [DateTimeOffset]::Parse($Author.date).ToUnixTimeSeconds()
    $committerTimestamp = [DateTimeOffset]::Parse($Committer.date).ToUnixTimeSeconds()
    $body = "tree $Tree`nparent $Parent`nauthor $($Author.name) <$($Author.email)> $authorTimestamp +0000`n" +
        "committer $($Committer.name) <$($Committer.email)> $committerTimestamp +0000`n`n$Message"

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git.exe'
    $startInfo.Arguments = 'hash-object -t commit -w --stdin'
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Unable to write the GitHub-compatible commit object locally.'
    }

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()
        $sha = $process.StandardOutput.ReadToEnd().Trim()
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Unable to write the GitHub-compatible commit object locally: $errorText"
        }
        return $sha
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-GitHubRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Get', 'Post', 'Patch')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body
    )

    $uri = "https://api.github.com/$Path"
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $parameters = @{
                Method      = $Method
                Uri         = $uri
                Headers     = $script:headers
                ContentType = 'application/json; charset=utf-8'
            }
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Compress -Depth 8
                $parameters.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
            }
            return Invoke-RestMethod @parameters
        }
        catch {
            if ($attempt -eq 4) {
                throw
            }
            Write-Warning "GitHub API request failed (attempt $attempt/4). Retrying..."
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function ConvertFrom-GitQuotedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not ($Path.StartsWith('"') -and $Path.EndsWith('"'))) {
        return $Path
    }

    $value = $Path.Substring(1, $Path.Length - 2)
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($index = 0; $index -lt $value.Length; $index++) {
        $character = $value[$index]
        if ($character -ne '\') {
            $bytes.Add([byte][char]$character)
            continue
        }

        if ($index + 3 -lt $value.Length) {
            $octal = $value.Substring($index + 1, 3)
            if ($octal -match '^[0-7]{3}$') {
                $bytes.Add([Convert]::ToByte($octal, 8))
                $index += 3
                continue
            }
        }

        $index++
        if ($index -ge $value.Length) {
            throw "Invalid Git-quoted path '$Path'."
        }
        switch ($value[$index]) {
            'a' { $bytes.Add(7) }
            'b' { $bytes.Add(8) }
            't' { $bytes.Add(9) }
            'n' { $bytes.Add(10) }
            'v' { $bytes.Add(11) }
            'f' { $bytes.Add(12) }
            'r' { $bytes.Add(13) }
            '"' { $bytes.Add(34) }
            '\' { $bytes.Add(92) }
            default { throw "Unsupported Git path escape '\$($value[$index])' in '$Path'." }
        }
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Get-TreeEntries {
    param([Parameter(Mandatory = $true)][string]$Commit)

    $entries = New-Object System.Collections.Generic.List[object]
    $treeArguments = @('-c', 'core.quotePath=true', 'ls-tree', '-r', $Commit)
    foreach ($line in (Get-GitOutput @treeArguments)) {
        if ($line -notmatch '^(?<mode>[0-9]{6}) (?<type>blob|commit) (?<sha>[0-9a-f]{40})\t(?<path>.+)$') {
            throw "Unable to parse Git tree entry: $line"
        }
        $entries.Add([pscustomobject][ordered]@{
                path = ConvertFrom-GitQuotedPath $Matches.path
                mode = $Matches.mode
                type = $Matches.type
                sha  = $Matches.sha
            })
    }
    return $entries
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or is not available in PATH.'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI is not installed or is not available in PATH.'
}

Push-Location $repoRoot
try {
    $previousConsoleEncoding = [Console]::OutputEncoding
    $previousOutputEncoding = $OutputEncoding
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom

    $token = (& gh auth token).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to read the active GitHub CLI token.'
    }
    $script:headers = @{
        Authorization          = "Bearer $token"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'REST-one-click-publisher'
    }

    $localHead = (Get-GitOutput rev-parse HEAD).Trim()
    $remoteRef = Invoke-GitHubRequest Get "repos/$Repository/git/ref/heads/$Branch"
    $remoteHead = $remoteRef.object.sha

    Invoke-CheckedGit merge-base --is-ancestor $remoteHead $localHead
    $commits = @(Get-GitOutput rev-list --reverse "$remoteHead..$localHead")
    if ($commits.Count -eq 0) {
        Write-Host 'GitHub branch is already up to date.'
        exit 0
    }

    $knownBlobs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in (Get-TreeEntries $remoteHead)) {
        if ($entry.type -eq 'blob') {
            [void]$knownBlobs.Add($entry.sha)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($KnownGitHubTree)) {
        $knownTree = Invoke-GitHubRequest Get "repos/$Repository/git/trees/$KnownGitHubTree`?recursive=1"
        foreach ($entry in $knownTree.tree) {
            if ($entry.type -eq 'blob') {
                [void]$knownBlobs.Add($entry.sha)
            }
        }
    }

    $currentParent = $remoteHead
    foreach ($commit in $commits) {
        $commit = $commit.Trim()
        $entries = @(Get-TreeEntries $commit)
        $newBlobs = @($entries | Where-Object { $_.type -eq 'blob' -and -not $knownBlobs.Contains($_.sha) } | Select-Object -ExpandProperty sha -Unique)

        Write-Host "Uploading $($newBlobs.Count) new Git objects for commit $($commit.Substring(0, 8))..."
        for ($index = 0; $index -lt $newBlobs.Count; $index++) {
            $sha = $newBlobs[$index]
            $bytes = Get-GitBlobBytes $sha
            $blob = Invoke-GitHubRequest Post "repos/$Repository/git/blobs" @{
                content  = [Convert]::ToBase64String($bytes)
                encoding = 'base64'
            }
            if ($blob.sha -ne $sha) {
                throw "GitHub returned blob '$($blob.sha)' instead of expected '$sha'."
            }
            [void]$knownBlobs.Add($sha)
            if ((($index + 1) % 25) -eq 0 -or ($index + 1) -eq $newBlobs.Count) {
                Write-Host "  Uploaded $($index + 1)/$($newBlobs.Count) objects"
            }
        }

        $tree = Invoke-GitHubRequest Post "repos/$Repository/git/trees" @{ tree = $entries }
        $expectedTree = (Get-GitOutput rev-parse "$commit^{tree}").Trim()
        if ($tree.sha -ne $expectedTree) {
            throw "GitHub tree '$($tree.sha)' does not match local tree '$expectedTree'."
        }

        $message = ((Get-GitOutput show -s --format=%B $commit) -join "`n").TrimEnd("`r", "`n")
        $author = @{
            name  = ((Get-GitOutput show -s --format=%an $commit) -join '').Trim()
            email = ((Get-GitOutput show -s --format=%ae $commit) -join '').Trim()
            date  = ((Get-GitOutput show -s --format=%aI $commit) -join '').Trim()
        }
        $committer = @{
            name  = ((Get-GitOutput show -s --format=%cn $commit) -join '').Trim()
            email = ((Get-GitOutput show -s --format=%ce $commit) -join '').Trim()
            date  = ((Get-GitOutput show -s --format=%cI $commit) -join '').Trim()
        }
        $createdCommit = Invoke-GitHubRequest Post "repos/$Repository/git/commits" @{
            message   = $message
            tree      = $tree.sha
            parents   = @($currentParent)
            author    = $author
            committer = $committer
        }
        $localApiCommit = Write-GitCommitObject `
            -Tree $tree.sha `
            -Parent $currentParent `
            -Author $createdCommit.author `
            -Committer $createdCommit.committer `
            -Message $createdCommit.message
        if ($localApiCommit -ne $createdCommit.sha) {
            throw "Locally reconstructed API commit '$localApiCommit' does not match GitHub commit '$($createdCommit.sha)'."
        }
        $currentParent = $createdCommit.sha
    }

    [void](Invoke-GitHubRequest Patch "repos/$Repository/git/refs/heads/$Branch" @{
            sha   = $currentParent
            force = $false
        })

    if ($currentParent -ne $localHead) {
        Invoke-CheckedGit update-ref "refs/heads/$Branch" $currentParent $localHead
    }
    Invoke-CheckedGit update-ref "refs/remotes/origin/$Branch" $currentParent
    Invoke-CheckedGit branch "--set-upstream-to=origin/$Branch" $Branch
    Write-Host "GitHub API push completed: $Repository $Branch @ $currentParent"
}
finally {
    $token = $null
    if ($null -ne $previousConsoleEncoding) {
        [Console]::OutputEncoding = $previousConsoleEncoding
    }
    if ($null -ne $previousOutputEncoding) {
        $OutputEncoding = $previousOutputEncoding
    }
    Pop-Location
}
