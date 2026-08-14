[CmdletBinding()]
param([string]$ServiceUrl = 'https://cogentstack.app')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cogentstack-client.ps1')

$workspaceUrl = "$($ServiceUrl.TrimEnd('/'))/stack"
$response = Invoke-WebRequest -UseBasicParsing -Uri $workspaceUrl -Headers @{ Accept = 'text/html' } -TimeoutSec 15
if ($response.StatusCode -ne 200) {
    throw "CogentStack is unavailable at $workspaceUrl (HTTP $($response.StatusCode))."
}
[ordered]@{ status = 'ready'; url = $workspaceUrl; remote = -not (Test-CogentStackLoopbackUrl -Url $ServiceUrl) } | ConvertTo-Json -Compress
