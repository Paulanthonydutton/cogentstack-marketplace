[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ProjectContextTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$contextScripts = @(
    'plugins\cogentspec\skills\cogentspec\scripts\project-context.ps1',
    'plugins\cogentstack\skills\cogentstack\scripts\project-context.ps1',
    'claude-plugins\cogentspec\skills\cogentspec\scripts\project-context.ps1',
    'claude-plugins\cogentstack\skills\cogentstack\scripts\project-context.ps1'
)
$contextPaths = @($contextScripts | ForEach-Object { Join-Path $repositoryRoot $_ })
$hashes = @($contextPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash } | Select-Object -Unique)
Assert-ProjectContextTest ($hashes.Count -eq 1) 'The provider and compatibility context helpers are not identical.'

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("cogentspec-context-" + [Guid]::NewGuid().ToString('N'))
$projectId = 'g-p-0123456789abcdef0123456789abcdef'
$projectWorkspace = Join-Path $fixtureRoot ".codex\.chatgpt-projects\$projectId"
$wrapperPath = Join-Path $fixtureRoot 'dot-source-fixture.ps1'

try {
    [void](New-Item -ItemType Directory -Path $projectWorkspace -Force)
    $canonicalScript = $contextPaths[0]

    Push-Location $projectWorkspace
    try {
        $directOutput = @(& $canonicalScript)
    } finally {
        Pop-Location
    }
    Assert-ProjectContextTest ($directOutput.Count -eq 1) 'Direct context execution did not emit exactly one record.'
    $direct = $directOutput[0] | ConvertFrom-Json
    Assert-ProjectContextTest ([string]$direct.contextKey -match '^ctx-[0-9a-f]{64}$') 'Direct context execution returned an invalid context key.'
    Assert-ProjectContextTest ([string]$direct.source -eq 'chatgpt-project-worktree') 'Direct context execution returned the wrong source.'
    Assert-ProjectContextTest ([bool]$direct.isolated) 'Direct context execution did not return an isolated context.'

    $wrapper = @'
param([Parameter(Mandatory = $true)][string]$ContextScript)
. $ContextScript
$resolved = Get-CogentSpecProjectContext -ExplicitContextKey ('ctx-' + ('a' * 64))
[ordered]@{
    contextKey = [string]$resolved.ContextKey
    source = [string]$resolved.Source
    isolated = [bool]$resolved.Isolated
} | ConvertTo-Json -Compress
'@
    Set-Content -LiteralPath $wrapperPath -Value $wrapper -Encoding UTF8
    $dotSourceOutput = @(& $wrapperPath -ContextScript $canonicalScript)
    Assert-ProjectContextTest ($dotSourceOutput.Count -eq 1) 'Dot-sourcing the context helper emitted unsolicited output.'
    $dotSource = $dotSourceOutput[0] | ConvertFrom-Json
    Assert-ProjectContextTest ([string]$dotSource.contextKey -eq ('ctx-' + ('a' * 64))) 'Dot-sourced context resolution returned the wrong explicit key.'
    Assert-ProjectContextTest ([string]$dotSource.source -eq 'explicit') 'Dot-sourced context resolution returned the wrong source.'
    Assert-ProjectContextTest ([bool]$dotSource.isolated) 'Dot-sourced context resolution did not preserve isolation.'

    [ordered]@{
        status = 'valid'
        copies = $contextPaths.Count
        directOutput = $true
        directSource = [string]$direct.source
        directIsolated = [bool]$direct.isolated
        dotSourceSilent = $true
        explicitContextPreserved = $true
    } | ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
