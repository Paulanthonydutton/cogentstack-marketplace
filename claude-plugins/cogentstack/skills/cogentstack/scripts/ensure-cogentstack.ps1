Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceUrl = 'https://cogentstack.app/stack?surface=claude-desktop'
$response = Invoke-WebRequest -UseBasicParsing -Uri $workspaceUrl -Headers @{ Accept = 'text/html' } -TimeoutSec 15
if ($response.StatusCode -ne 200) {
    throw "CogentStack is unavailable at the protected Claude Desktop surface (HTTP $($response.StatusCode))."
}

[ordered]@{
    status = 'ready'
    url = $workspaceUrl
    surface = 'claude-desktop'
    remote = $true
} | ConvertTo-Json -Compress
