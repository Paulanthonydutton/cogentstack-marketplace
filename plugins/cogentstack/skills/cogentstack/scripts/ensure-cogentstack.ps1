Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceUrl = 'https://cogentstack.app/stack'
$response = Invoke-WebRequest -UseBasicParsing -Uri $workspaceUrl -Headers @{ Accept = 'text/html' } -TimeoutSec 15
if ($response.StatusCode -ne 200) {
    throw "CogentStack is unavailable at $workspaceUrl (HTTP $($response.StatusCode))."
}
[ordered]@{ status = 'ready'; url = $workspaceUrl; remote = $true } | ConvertTo-Json -Compress
