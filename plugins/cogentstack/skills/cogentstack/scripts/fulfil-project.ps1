param(
    [ValidateSet('inspect', 'create')]
    [string]$Mode = 'inspect',
    [string]$RequestId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])) {
    try {
        Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction Stop
    } catch {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    }
}

$serviceUrl = 'https://cogentstack.app'
$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack'
$credentialPath = Join-Path $stateRoot 'desktop-credential.json'

function Write-CompactJson($Value) {
    $Value | ConvertTo-Json -Depth 8 -Compress | Write-Output
}

function Unprotect-CogentStackValue([string]$Value) {
    $protected = [Convert]::FromBase64String($Value)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protected,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-CogentStackApi(
    [string]$Method,
    [string]$Path,
    [string]$Token,
    $Body = $null
) {
    $parameters = @{
        Method = $Method
        Uri = "$serviceUrl$Path"
        Headers = @{ Accept = 'application/json'; Authorization = "Bearer $Token" }
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 8 -Compress
    }
    return Invoke-RestMethod @parameters
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Resolve-ApprovedTarget([string]$TargetPath) {
    if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not [IO.Path]::IsPathRooted($TargetPath) -or $TargetPath -notmatch '^[A-Za-z]:[\\/]') {
        throw 'The approved project target is not an absolute Windows drive path.'
    }
    $fullPath = [IO.Path]::GetFullPath($TargetPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrWhiteSpace($fullPath) -or $fullPath -eq [IO.Path]::GetPathRoot($fullPath)) {
        throw 'The approved project target cannot be a drive root.'
    }
    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-ChildItem -Force -LiteralPath $fullPath | Select-Object -First 1
        if ($null -ne $existing) {
            throw "The approved project target is not empty: $fullPath"
        }
    }
    return $fullPath
}

function Test-ArtifactPath([string]$ArtifactPath) {
    if ([string]::IsNullOrWhiteSpace($ArtifactPath) -or [IO.Path]::IsPathRooted($ArtifactPath) -or $ArtifactPath -match '^[A-Za-z]:') {
        return $false
    }
    $segments = $ArtifactPath.Replace('\', '/').Split('/')
    return -not ($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' })
}

if (-not (Test-Path -LiteralPath $credentialPath)) {
    Write-CompactJson ([ordered]@{ status = 'not_connected' })
    exit 0
}

$credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
$token = Unprotect-CogentStackValue ([string]$credential.token)
$listing = Invoke-CogentStackApi -Method Get -Path '/api/plugin/project-requests?status=requested&limit=20' -Token $token
$requests = @($listing.requests)

if ($Mode -eq 'inspect') {
    Write-CompactJson ([ordered]@{ status = 'ok'; requests = $requests })
    exit 0
}

if ([string]::IsNullOrWhiteSpace($RequestId)) {
    if ($requests.Count -eq 0) {
        Write-CompactJson ([ordered]@{ status = 'no_requested_projects' })
        exit 0
    }
    if ($requests.Count -gt 1) {
        Write-CompactJson ([ordered]@{ status = 'selection_required'; requests = $requests })
        exit 0
    }
    $RequestId = [string]$requests[0].id
}

if ($RequestId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'The project request ID is invalid.'
}

$selected = $requests | Where-Object { [string]$_.id -eq $RequestId } | Select-Object -First 1
if ($null -eq $selected) {
    Write-CompactJson ([ordered]@{ status = 'request_not_available'; requestId = $RequestId })
    exit 0
}

$targetPath = Resolve-ApprovedTarget ([string]$selected.targetPath)
$executionGrant = ''
$artifactDigest = ''
$claimed = $false

try {
    $claim = Invoke-CogentStackApi -Method Post -Path '/api/plugin/project-requests' -Token $token -Body @{
        action = 'claim'
        requestId = $RequestId
    }
    if ([string]$claim.status -ne 'claimed' -or $null -eq $claim.artifact -or [string]::IsNullOrWhiteSpace([string]$claim.executionGrant)) {
        throw 'CogentStack returned an incomplete project artifact.'
    }
    $claimed = $true
    $executionGrant = [string]$claim.executionGrant
    $artifactDigest = [string]$claim.artifact.digest
    if ($artifactDigest -notmatch '^[0-9a-f]{64}$') {
        throw 'CogentStack returned an invalid project artifact digest.'
    }

    $files = @($claim.artifact.files)
    if ($files.Count -eq 0 -or $files.Count -gt 200) {
        throw 'CogentStack returned an invalid project artifact file count.'
    }

    $canonical = New-Object Text.StringBuilder
    $totalBytes = 0
    $seenPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        $artifactPath = ([string]$file.path).Replace('\', '/')
        if (-not (Test-ArtifactPath $artifactPath)) {
            throw "CogentStack returned an unsafe project artifact path: $artifactPath"
        }
        if (-not $seenPaths.Add($artifactPath)) {
            throw "CogentStack returned a duplicate project artifact path: $artifactPath"
        }
        $expectedHash = [string]$file.sha256
        if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
            throw "CogentStack returned an invalid checksum for $artifactPath"
        }
        $bytes = [Convert]::FromBase64String([string]$file.contentBase64)
        if ($bytes.Length -gt 1500000) {
            throw "CogentStack returned an oversized project artifact file: $artifactPath"
        }
        $totalBytes += $bytes.Length
        if ($totalBytes -gt 6000000) {
            throw 'CogentStack returned an oversized project artifact.'
        }
        if ((Get-Sha256Hex $bytes) -ne $expectedHash) {
            throw "Project artifact verification failed for $artifactPath"
        }
        [void]$canonical.Append($artifactPath).Append("`t").Append($expectedHash).Append("`n")
    }
    $computedDigest = Get-Sha256Hex ([Text.Encoding]::UTF8.GetBytes($canonical.ToString()))
    if ($computedDigest -ne $artifactDigest) {
        throw 'Project artifact verification failed.'
    }
    $claimedTarget = [IO.Path]::GetFullPath([string]$claim.request.targetPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not $claimedTarget.Equals($targetPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The claimed project target does not match the approved request.'
    }
    $targetPath = Resolve-ApprovedTarget $claimedTarget

    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    $targetPrefix = $targetPath.TrimEnd('\') + '\'
    foreach ($file in $files) {
        $artifactPath = ([string]$file.path).Replace('\', '/')
        $relativeWindowsPath = $artifactPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $destination = [IO.Path]::GetFullPath((Join-Path $targetPath $relativeWindowsPath))
        if (-not $destination.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Project artifact escaped the approved target: $artifactPath"
        }
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        [IO.File]::WriteAllBytes($destination, [Convert]::FromBase64String([string]$file.contentBase64))
    }

    $installOutput = & npm.cmd ci --prefer-offline --no-audit --no-fund --prefix $targetPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed: $($installOutput.Trim())"
    }
    $testOutput = & npm.cmd test --prefix $targetPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Project acceptance tests failed: $($testOutput.Trim())"
    }

    & git -C $targetPath init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Git initialization failed.' }
    & git -C $targetPath add -A
    if ($LASTEXITCODE -ne 0) { throw 'Git staging failed.' }
    $gitName = (& git -C $targetPath config user.name 2>$null | Out-String).Trim()
    if (-not $gitName) { & git -C $targetPath config user.name 'CogentStack Desktop' }
    $gitEmail = (& git -C $targetPath config user.email 2>$null | Out-String).Trim()
    if (-not $gitEmail) { & git -C $targetPath config user.email 'desktop@cogentstack.local' }
    & git -C $targetPath commit --quiet -m 'Initialize CogentStack project foundation'
    if ($LASTEXITCODE -ne 0) { throw 'Git baseline commit failed.' }
    $commit = (& git -C $targetPath rev-parse HEAD).Trim()

    $completed = Invoke-CogentStackApi -Method Patch -Path '/api/plugin/project-requests' -Token $token -Body @{
        action = 'complete'
        requestId = $RequestId
        artifactDigest = $artifactDigest
        executionGrant = $executionGrant
        statusMessage = "Project foundation created and verified at $targetPath."
    }
    Write-CompactJson ([ordered]@{
        status = [string]$completed.status
        requestId = $RequestId
        targetPath = $targetPath
        projectName = [string]$claim.request.projectName
        patternId = [string]$claim.request.patternId
        releaseMode = [string]$claim.request.releaseMode
        pack = $claim.request.pack
        tests = 'passed'
        commit = $commit
    })
} catch {
    $message = $_.Exception.Message
    if ($claimed -and $executionGrant -and $artifactDigest) {
        try {
            Invoke-CogentStackApi -Method Patch -Path '/api/plugin/project-requests' -Token $token -Body @{
                action = 'fail'
                requestId = $RequestId
                artifactDigest = $artifactDigest
                executionGrant = $executionGrant
                statusMessage = $message
            } | Out-Null
        } catch {
            # Preserve the original creation failure; the server grant will expire automatically.
        }
    }
    Write-CompactJson ([ordered]@{
        status = 'failed'
        requestId = $RequestId
        targetPath = $targetPath
        partialTargetRetained = (Test-Path -LiteralPath $targetPath)
        error = $message
    })
    exit 1
}
