param(
    [ValidateSet('inspect', 'delete')]
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
$credentialPath = Join-Path $stateRoot 'claude-desktop-credential.json'

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

function Resolve-ApprovedDeletionTarget(
    [string]$TargetPath,
    [string]$WorkDirectory,
    [string]$ProjectSlug
) {
    if (
        [string]::IsNullOrWhiteSpace($TargetPath) -or
        [string]::IsNullOrWhiteSpace($WorkDirectory) -or
        [string]::IsNullOrWhiteSpace($ProjectSlug) -or
        -not [IO.Path]::IsPathRooted($TargetPath) -or
        -not [IO.Path]::IsPathRooted($WorkDirectory) -or
        $TargetPath -notmatch '^[A-Za-z]:[\\/]' -or
        $WorkDirectory -notmatch '^[A-Za-z]:[\\/]'
    ) {
        throw 'The approved project deletion paths are not absolute Windows drive paths.'
    }

    $targetFull = [IO.Path]::GetFullPath($TargetPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $workFull = [IO.Path]::GetFullPath($WorkDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (
        [string]::IsNullOrWhiteSpace($targetFull) -or
        [string]::IsNullOrWhiteSpace($workFull) -or
        $targetFull -eq [IO.Path]::GetPathRoot($targetFull) -or
        $workFull -eq [IO.Path]::GetPathRoot($workFull)
    ) {
        throw 'The approved project deletion cannot target a drive root.'
    }

    $targetParent = [IO.Path]::GetDirectoryName($targetFull)
    $targetLeaf = [IO.Path]::GetFileName($targetFull)
    if (
        -not $targetParent.Equals($workFull, [StringComparison]::OrdinalIgnoreCase) -or
        -not $targetLeaf.Equals($ProjectSlug, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw 'The approved project target is not the exact registered child of its work directory.'
    }
    if ($targetFull.Replace('/', '\').Split('\') | Where-Object { $_.ToLocaleLowerInvariant() -eq '.tmp' }) {
        throw 'Temporary validation projects cannot be deleted through the project library.'
    }

    if (Test-Path -LiteralPath $targetFull) {
        if (Test-Path -LiteralPath $workFull) {
            $workItem = Get-Item -Force -LiteralPath $workFull
            if (($workItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A reparse-point work directory requires manual review before deletion.'
            }
        }
        $targetItem = Get-Item -Force -LiteralPath $targetFull
        if (-not $targetItem.PSIsContainer) {
            throw 'The registered project target is not a directory.'
        }
        if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A reparse-point project folder requires manual review before deletion.'
        }
        $nestedReparsePoint = Get-ChildItem -Force -LiteralPath $targetFull -Recurse |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
            Select-Object -First 1
        if ($null -ne $nestedReparsePoint) {
            throw "A nested reparse point requires manual review before deletion: $($nestedReparsePoint.FullName)"
        }
    }
    return $targetFull
}

if (-not (Test-Path -LiteralPath $credentialPath)) {
    Write-CompactJson ([ordered]@{ status = 'not_connected' })
    exit 0
}

$credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
$token = Unprotect-CogentStackValue ([string]$credential.token)
$listing = Invoke-CogentStackApi -Method Get -Path '/api/plugin/project-deletions' -Token $token
$requests = @($listing.requests)

if ($Mode -eq 'inspect') {
    Write-CompactJson ([ordered]@{ status = 'ok'; requests = $requests })
    exit 0
}

if ([string]::IsNullOrWhiteSpace($RequestId)) {
    if ($requests.Count -eq 0) {
        Write-CompactJson ([ordered]@{ status = 'no_requested_deletions' })
        exit 0
    }
    if ($requests.Count -gt 1) {
        Write-CompactJson ([ordered]@{ status = 'service_state_error'; requests = $requests })
        exit 1
    }
    $RequestId = [string]$requests[0].id
}

if ($RequestId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'The project deletion request ID is invalid.'
}

$selected = $requests | Where-Object { [string]$_.id -eq $RequestId } | Select-Object -First 1
if ($null -eq $selected) {
    Write-CompactJson ([ordered]@{ status = 'request_not_available'; requestId = $RequestId })
    exit 0
}

$targetPath = [string]$selected.targetPath
$projectRequestId = [string]$selected.projectRequestId
if ($projectRequestId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'The approved project request ID is invalid.'
}
$executionGrant = ''
$deletionDigest = ''
$claimed = $false
$folderRemoved = $false

try {
    $claim = Invoke-CogentStackApi -Method Post -Path '/api/plugin/project-deletions' -Token $token -Body @{
        action = 'claim'
        requestId = $RequestId
    }
    if (
        [string]$claim.status -ne 'claimed' -or
        $null -eq $claim.request -or
        [string]$claim.request.id -ne $RequestId -or
        [string]$claim.request.projectRequestId -ne $projectRequestId -or
        [string]::IsNullOrWhiteSpace([string]$claim.executionGrant) -or
        [string]$claim.deletionDigest -notmatch '^[0-9a-f]{64}$'
    ) {
        throw 'CogentStack returned an incomplete project deletion claim.'
    }
    $claimed = $true
    $executionGrant = [string]$claim.executionGrant
    $deletionDigest = [string]$claim.deletionDigest
    $targetParameters = @{
        TargetPath = [string]$claim.request.targetPath
        WorkDirectory = [string]$claim.request.workDirectory
        ProjectSlug = [string]$claim.request.projectSlug
    }
    $targetPath = Resolve-ApprovedDeletionTarget @targetParameters

    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Recurse -Force
        if (Test-Path -LiteralPath $targetPath) {
            throw 'The registered project folder still exists after deletion.'
        }
        $folderRemoved = $true
    }

    $completionMessage = if ($folderRemoved) {
        "Project registration and folder deleted from $targetPath."
    } else {
        "Project folder was already absent; registration deleted for $targetPath."
    }
    $completed = Invoke-CogentStackApi -Method Patch -Path '/api/plugin/project-deletions' -Token $token -Body @{
        action = 'complete'
        requestId = $RequestId
        deletionDigest = $deletionDigest
        executionGrant = $executionGrant
        statusMessage = $completionMessage
    }
    if ([string]$completed.status -ne 'deleted') {
        throw 'CogentStack did not confirm the project registration as deleted.'
    }
    Write-CompactJson ([ordered]@{
        status = 'deleted'
        requestId = $RequestId
        projectName = [string]$claim.request.projectName
        projectRequestId = $projectRequestId
        targetPath = $targetPath
        folderRemoved = $folderRemoved
        recoverable = $false
    })
} catch {
    $message = $_.Exception.Message
    if ($claimed -and $executionGrant -and $deletionDigest) {
        try {
            Invoke-CogentStackApi -Method Patch -Path '/api/plugin/project-deletions' -Token $token -Body @{
                action = 'fail'
                requestId = $RequestId
                deletionDigest = $deletionDigest
                executionGrant = $executionGrant
                statusMessage = $message
            } | Out-Null
        } catch {
            # Preserve the original deletion failure; the execution grant expires automatically.
        }
    }
    Write-CompactJson ([ordered]@{
        status = 'failed'
        requestId = $RequestId
        targetPath = $targetPath
        folderRemoved = $folderRemoved
        registrationFinalized = $false
        partialTargetRetained = (-not [string]::IsNullOrWhiteSpace($targetPath) -and (Test-Path -LiteralPath $targetPath))
        error = $message
    })
    exit 1
}

