param(
    [ValidateSet('start', 'complete', 'status', 'disconnect')]
    [string]$Mode = 'start'
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
$pendingPath = Join-Path $stateRoot 'claude-desktop-authorization.json'
$credentialPath = Join-Path $stateRoot 'claude-desktop-credential.json'

function Protect-CogentStackValue([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
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

function Write-CompactJson($Value) {
    $Value | ConvertTo-Json -Compress | Write-Output
}

if ($Mode -eq 'status') {
    if (Test-Path -LiteralPath $credentialPath) {
        $credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
        Write-CompactJson ([ordered]@{
            status = 'connected'
            email = $credential.email
            plan = $credential.plan
            connectedAt = $credential.connectedAt
        })
    } else {
        Write-CompactJson ([ordered]@{ status = 'signed_out' })
    }
    exit 0
}

if ($Mode -eq 'disconnect') {
    if (-not (Test-Path -LiteralPath $credentialPath)) {
        Write-CompactJson ([ordered]@{ status = 'signed_out' })
        exit 0
    }
    $credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
    $token = Unprotect-CogentStackValue ([string]$credential.token)
    try {
        Invoke-RestMethod `
            -Method Delete `
            -Uri "$serviceUrl/api/device-authorization/token" `
            -Headers @{ Accept = 'application/json'; Authorization = "Bearer $token" } `
            -TimeoutSec 20 | Out-Null
    } finally {
        Remove-Item -LiteralPath $credentialPath -Force
    }
    Write-CompactJson ([ordered]@{ status = 'signed_out' })
    exit 0
}

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

if ($Mode -eq 'start') {
    $requestBody = @{ deviceName = 'Claude Code Desktop on Windows' } | ConvertTo-Json -Compress
    $authorization = Invoke-RestMethod `
        -Method Post `
        -Uri "$serviceUrl/api/device-authorization" `
        -ContentType 'application/json' `
        -Headers @{ Accept = 'application/json' } `
        -Body $requestBody `
        -TimeoutSec 20

    [ordered]@{
        deviceCode = Protect-CogentStackValue ([string]$authorization.deviceCode)
        userCode = [string]$authorization.userCode
        expiresAt = [string]$authorization.expiresAt
        intervalSeconds = [int]$authorization.intervalSeconds
    } | ConvertTo-Json | Set-Content -LiteralPath $pendingPath -Encoding UTF8

    Start-Process ([string]$authorization.verificationUriComplete)
    Write-CompactJson ([ordered]@{
        status = 'approval_required'
        expiresAt = [string]$authorization.expiresAt
        pollAfterSeconds = [int]$authorization.intervalSeconds
    })
    exit 0
}

if (-not (Test-Path -LiteralPath $pendingPath)) {
    Write-CompactJson ([ordered]@{ status = 'not_started' })
    exit 0
}

$pending = Get-Content -Raw -LiteralPath $pendingPath | ConvertFrom-Json
if ([DateTimeOffset]::Parse([string]$pending.expiresAt) -le [DateTimeOffset]::UtcNow) {
    Remove-Item -LiteralPath $pendingPath -Force
    Write-CompactJson ([ordered]@{ status = 'expired' })
    exit 0
}

$deviceCode = Unprotect-CogentStackValue ([string]$pending.deviceCode)
$tokenBody = @{ deviceCode = $deviceCode } | ConvertTo-Json -Compress
try {
    $result = Invoke-RestMethod `
        -Method Post `
        -Uri "$serviceUrl/api/device-authorization/token" `
        -ContentType 'application/json' `
        -Headers @{ Accept = 'application/json' } `
        -Body $tokenBody `
        -TimeoutSec 20
} catch {
    $statusCode = [int]$_.Exception.Response.StatusCode
    if ($statusCode -eq 410) {
        Remove-Item -LiteralPath $pendingPath -Force
        Write-CompactJson ([ordered]@{ status = 'expired' })
        exit 0
    }
    throw
}

if ([string]$result.status -eq 'authorization_pending') {
    Write-CompactJson ([ordered]@{
        status = 'approval_pending'
        expiresAt = [string]$pending.expiresAt
        pollAfterSeconds = [int]$pending.intervalSeconds
    })
    exit 0
}

if ([string]$result.status -ne 'authorized' -or -not $result.token -or -not $result.browserCode) {
    throw 'CogentStack returned an incomplete Desktop authorization.'
}

[ordered]@{
    token = Protect-CogentStackValue ([string]$result.token)
    email = [string]$result.subscriber.email
    plan = [string]$result.subscriber.plan
    connectedAt = [string]$result.createdAt
} | ConvertTo-Json | Set-Content -LiteralPath $credentialPath -Encoding UTF8
Remove-Item -LiteralPath $pendingPath -Force

$workspaceUrl = "$serviceUrl/stack?surface=claude-desktop#desktop=$([Uri]::EscapeDataString([string]$result.browserCode))"
Write-CompactJson ([ordered]@{
    status = 'authorized'
    email = [string]$result.subscriber.email
    plan = [string]$result.subscriber.plan
    workspaceUrl = $workspaceUrl
})
