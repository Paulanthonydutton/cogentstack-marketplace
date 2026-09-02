Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceUrl = 'https://cogentstack.app'
$publicWorkspaceUrl = "$serviceUrl/stack?surface=chatgpt"
$workspaceUrl = $publicWorkspaceUrl
$response = Invoke-WebRequest -UseBasicParsing -Uri $publicWorkspaceUrl -Headers @{ Accept = 'text/html' } -TimeoutSec 15
if ($response.StatusCode -ne 200) {
    throw "CogentStack is unavailable at $publicWorkspaceUrl (HTTP $($response.StatusCode))."
}

$credentialPath = Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack') 'desktop-credential.json'
$authenticated = $false

if (Test-Path -LiteralPath $credentialPath) {
    try {
        if ($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])) {
            try {
                Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction Stop
            } catch {
                Add-Type -AssemblyName System.Security -ErrorAction Stop
            }
        }

        $credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
        $protectedToken = [Convert]::FromBase64String([string]$credential.token)
        $tokenBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedToken,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $token = [Text.Encoding]::UTF8.GetString($tokenBytes)
        $grant = Invoke-RestMethod `
            -Method Post `
            -Uri "$serviceUrl/api/device-authorization/browser-grant" `
            -Headers @{ Accept = 'application/json'; Authorization = "Bearer $token" } `
            -TimeoutSec 20
        if ($grant.workspaceCode) {
            $workspaceUrl = "$publicWorkspaceUrl#desktop=$([Uri]::EscapeDataString([string]$grant.workspaceCode))"
            $authenticated = $true
        }
    } catch {
        # The official website remains the only sign-in authority. If the saved
        # Desktop authorization is unavailable, open the public workspace and
        # let the user reconnect through the website when a contract is used.
        $workspaceUrl = $publicWorkspaceUrl
    } finally {
        $token = $null
        $tokenBytes = $null
        $protectedToken = $null
    }
}

[ordered]@{
    status = 'ready'
    url = $workspaceUrl
    remote = $true
    authenticated = $authenticated
    loginAuthority = $serviceUrl
} | ConvertTo-Json -Compress
