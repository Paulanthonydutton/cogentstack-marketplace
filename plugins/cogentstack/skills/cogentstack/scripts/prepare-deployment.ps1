param([ValidateSet("inspect", "prepare")][string]$Mode = "prepare", [string]$RequestId = "")
$ErrorActionPreference = "Stop"
$BaseUrl = "https://cogentstack.app"
$CredentialPath = Join-Path $env:LOCALAPPDATA "CogentStack\desktop-credential.json"

function Read-Credential {
  if (-not (Test-Path -LiteralPath $CredentialPath -PathType Leaf)) { throw "CogentStack Desktop is not connected." }
  $stored = Get-Content -LiteralPath $CredentialPath -Raw | ConvertFrom-Json
  $token = [System.Net.NetworkCredential]::new("", (ConvertTo-SecureString ([string]$stored.protectedToken))).Password
  if ([string]::IsNullOrWhiteSpace($token)) { throw "CogentStack Desktop credential is empty." }
  return $token
}

function Invoke-Api([string]$Method, [string]$Token, [object]$Body = $null) {
  $arguments = @{ Uri = "$BaseUrl/api/plugin/deployment-packs"; Method = $Method; Headers = @{ Authorization = "Bearer $Token"; Accept = "application/json" }; UseBasicParsing = $true }
  if ($null -ne $Body) { $arguments.ContentType = "application/json"; $arguments.Body = ($Body | ConvertTo-Json -Depth 8 -Compress) }
  return Invoke-RestMethod @arguments
}

function Get-ContentHash([string]$Content) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Content)))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
}

function Confirm-Target([string]$TargetPath) {
  if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not [IO.Path]::IsPathRooted($TargetPath)) { throw "The registered project path is invalid." }
  $resolved = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
  if ($resolved.TrimEnd('\') -eq [IO.Path]::GetPathRoot($resolved).TrimEnd('\')) { throw "A drive root cannot be used as a project folder." }
  $item = Get-Item -LiteralPath $resolved -Force
  if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "The registered project folder is not a safe local directory." }
  return $resolved
}

$token = Read-Credential
$current = Invoke-Api "GET" $token
if ($Mode -eq "inspect") { $current | ConvertTo-Json -Depth 6 -Compress; exit 0 }
if ([string]::IsNullOrWhiteSpace($RequestId)) { $RequestId = [string]@($current.requests)[0].id }
if ([string]::IsNullOrWhiteSpace($RequestId)) { throw "No approved Deployment Pack request is waiting." }
$claim = Invoke-Api "POST" $token @{ action = "claim"; requestId = $RequestId }
$target = Confirm-Target ([string]$claim.targetPath)
$allowed = @("DEPLOYMENT.md", "deployment.manifest.json")
try {
  if (@($claim.artifact.files).Count -ne 2) { throw "The approved Deployment Pack must contain exactly two files." }
  foreach ($file in @($claim.artifact.files)) {
    $name = [string]$file.path
    if ($allowed -notcontains $name) { throw "The Deployment Pack contains an unapproved file path." }
    $content = [string]$file.content
    if ((Get-ContentHash $content) -ne [string]$file.sha256) { throw "The Deployment Pack file integrity check failed." }
    $destination = Join-Path $target $name
    if ([IO.Path]::GetDirectoryName($destination).TrimEnd('\') -ne $target.TrimEnd('\')) { throw "The Deployment Pack destination escaped the project folder." }
    $temporary = "$destination.cogentstack.tmp"
    [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $destination -Force
  }
  Invoke-Api "PATCH" $token @{ action = "complete"; requestId = $RequestId; artifactDigest = [string]$claim.artifact.digest; executionGrant = [string]$claim.executionGrant; statusMessage = "Deployment Pack prepared in the registered project folder." } | Out-Null
  @{ status = "prepared"; targetPath = $target; files = $allowed } | ConvertTo-Json -Compress
} catch {
  try { Invoke-Api "PATCH" $token @{ action = "fail"; requestId = $RequestId; artifactDigest = [string]$claim.artifact.digest; executionGrant = [string]$claim.executionGrant; statusMessage = $_.Exception.Message } | Out-Null } catch { }
  throw
}
