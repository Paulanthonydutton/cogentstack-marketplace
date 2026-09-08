Set-StrictMode -Version Latest

function ConvertTo-CogentStackContextKey([string]$ProjectIdentifier) {
    if ([string]::IsNullOrWhiteSpace($ProjectIdentifier)) { return 'default' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("chatgpt-project:$($ProjectIdentifier.Trim().ToLowerInvariant())")
        $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        return "ctx-$digest"
    } finally {
        $sha.Dispose()
    }
}

function Test-CogentStackContextKey([string]$Value) {
    return $Value -eq 'default' -or $Value -match '^ctx-[0-9a-f]{64}$'
}

function Get-CogentStackProjectContext(
    [string]$ExplicitContextKey = '',
    [string]$WorkingDirectory = (Get-Location).Path
) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitContextKey)) {
        $normalized = $ExplicitContextKey.Trim().ToLowerInvariant()
        if (-not (Test-CogentStackContextKey $normalized)) { throw 'The explicit CogentStack project context is invalid.' }
        return [pscustomobject]@{ ContextKey = $normalized; Source = 'explicit'; Isolated = $normalized -ne 'default' }
    }

    $projectIdentifier = ''
    $source = ''
    if ($env:CODEX_PROJECT_ID -match '^g-p-[0-9a-f]{32}$') {
        $projectIdentifier = $env:CODEX_PROJECT_ID
        $source = 'codex-project-environment'
    } elseif ($WorkingDirectory -match '(?i)[\\/]\.codex[\\/]\.chatgpt-projects[\\/](g-p-[0-9a-f]{32})(?:[\\/]|$)') {
        $projectIdentifier = $Matches[1]
        $source = 'chatgpt-project-worktree'
    }

    if (-not $projectIdentifier) {
        return [pscustomobject]@{ ContextKey = 'default'; Source = 'legacy-default'; Isolated = $false }
    }
    $contextKey = ConvertTo-CogentStackContextKey $projectIdentifier
    return [pscustomobject]@{ ContextKey = $contextKey; Source = $source; Isolated = $true }
}

function Add-CogentStackContextToPath([string]$Path, [string]$ContextKey) {
    if (-not (Test-CogentStackContextKey $ContextKey)) { throw 'The CogentStack project context is invalid.' }
    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    return "$Path${separator}context=$([Uri]::EscapeDataString($ContextKey))"
}
