param(
    [ValidateSet('inspect', 'initialize', 'refresh')]
    [string]$Mode = 'inspect',
    [string]$ContextKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-context.ps1')
. (Join-Path $PSScriptRoot 'native-command.ps1')

$serviceUrl = 'https://cogentspec.com'
$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentSpec'
$credentialPath = Join-Path $stateRoot 'desktop-credential.json'
$projectContext = Get-CogentSpecProjectContext -ExplicitContextKey $ContextKey
$contextQuery = "context=$([Uri]::EscapeDataString($projectContext.ContextKey))"
$knowledgePaths = @('PROJECT_KNOWLEDGE.md', 'CURRENT_STATE.md', 'HANDOFF.md', 'docs/decisions/README.md')

function Write-CompactJson($Value) {
    $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

function Unprotect-CogentSpecValue([string]$Value) {
    if ($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])) {
        try { Add-Type -AssemblyName System.Security.Cryptography.ProtectedData -ErrorAction Stop } catch { Add-Type -AssemblyName System.Security -ErrorAction Stop }
    }
    $protected = [Convert]::FromBase64String($Value)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protected, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Confirm-ProjectRoot([string]$TargetPath) {
    if ([string]::IsNullOrWhiteSpace($TargetPath) -or -not [IO.Path]::IsPathRooted($TargetPath)) { throw 'The registered CogentSpec project path is invalid.' }
    $root = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path.TrimEnd('\', '/')
    if ($root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\', '/')) { throw 'A drive root cannot be loaded as project knowledge.' }
    $item = Get-Item -Force -LiteralPath $root
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The registered project path is not a safe local directory.' }
    return $root
}

if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
    Write-CompactJson ([ordered]@{ status = 'desktop_authorization_required'; activeProjectPreserved = $true })
    exit 0
}

$credential = Get-Content -Raw -LiteralPath $credentialPath | ConvertFrom-Json
$token = Unprotect-CogentSpecValue ([string]$credential.token)
try {
    $runtime = Invoke-RestMethod -Method Get -Uri "$serviceUrl/api/plugin/project-runtime?$contextQuery" -Headers @{ Accept = 'application/json'; Authorization = "Bearer $token" } -TimeoutSec 30
} finally {
    $token = $null
}
if (-not $runtime.activeProject) {
    Write-CompactJson ([ordered]@{ status = 'no_active_project'; context = $projectContext })
    exit 0
}

$root = Confirm-ProjectRoot ([string]$runtime.activeProject.targetPath)
$manifestPath = Join-Path $root '.coge\knowledge-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and $Mode -ne 'initialize') { throw 'This project predates portable knowledge. Initialize and review its knowledge pack before moving it to a new ChatGPT Project.' }
if ($Mode -eq 'initialize' -and -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $encoding = New-Object Text.UTF8Encoding($false)
    New-Item -ItemType Directory -Path (Join-Path $root '.coge') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs\decisions') -Force | Out-Null
    $bindingPath = Join-Path $root '.coge\contract-binding.json'
    $binding = if (Test-Path -LiteralPath $bindingPath -PathType Leaf) { Get-Content -Raw -LiteralPath $bindingPath | ConvertFrom-Json } else { $null }
    $initialFiles = [ordered]@{
        'AGENTS.md' = "# CogentSpec project knowledge`n`nRead PROJECT_KNOWLEDGE.md, CURRENT_STATE.md, HANDOFF.md, and .coge/knowledge-manifest.json before changing this project. Keep durable decisions, constraints, architecture, verified tests, and outstanding work in those files. Never store credentials, private account data, or protected CogentSpec contract contents in Git.`n"
        'PROJECT_KNOWLEDGE.md' = "# $([string]$runtime.activeProject.projectName): portable project knowledge`n`n## Purpose`n`nDocument the established product goal after reviewing the existing implementation and evidence.`n`n## Stable constraints`n`n- Project type: $([string]$runtime.activeProject.projectType)`n`n## Architecture`n`nDocument the verified current architecture here.`n`n## Decisions`n`nRecord only decisions supported by repository evidence or confirmed by the user.`n`n## Acceptance`n`nDocument the verified acceptance approach here.`n"
        'CURRENT_STATE.md' = "# Current state`n`nLast reviewed: $([DateTimeOffset]::UtcNow.ToString('O'))`n`n## Working now`n`n- Review and record verified existing behaviour.`n`n## Verified evidence`n`n- Portable knowledge initialized for this existing project; historical content still requires review.`n`n## Outstanding work`n`n- Reconstruct only evidence-backed outstanding work from the repository and user confirmation.`n`n## Risks and blockers`n`n- Conversation-only history may not yet be represented here.`n"
        'HANDOFF.md' = "# Project handoff`n`n1. Read AGENTS.md, PROJECT_KNOWLEDGE.md, and CURRENT_STATE.md.`n2. Confirm Git branch, revision, and dirty state before editing.`n3. Load this project in CogentSpec to restore protected state for the current logical context.`n4. Never pull over dirty work automatically.`n"
        'docs/decisions/README.md' = "# Architecture decisions`n`nCreate one Markdown file per durable, evidence-backed decision. Include date, status, context, decision, consequences, and any superseded decision. Do not store secrets or protected contract contents.`n"
    }
    foreach ($entry in $initialFiles.GetEnumerator()) {
        $destination = Join-Path $root ([string]$entry.Key)
        if (-not (Test-Path -LiteralPath $destination)) { [IO.File]::WriteAllText($destination, [string]$entry.Value, $encoding) }
    }
    $manifestValue = [ordered]@{
        schemaVersion = 1
        project = [ordered]@{
            requestId = [string]$runtime.activeProject.requestId
            name = [string]$runtime.activeProject.projectName
            type = [string]$runtime.activeProject.projectType
            contextKey = $projectContext.ContextKey
        }
        binding = if ($binding) { $binding } else { [ordered]@{} }
        knowledgeFiles = $knowledgePaths
        initializedFromExistingProject = $true
        createdAt = [DateTimeOffset]::UtcNow.ToString('O')
    }
    [IO.File]::WriteAllText($manifestPath, (($manifestValue | ConvertTo-Json -Depth 10) + "`n"), $encoding)
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ([string]$manifest.project.requestId -ne [string]$runtime.activeProject.requestId) { throw 'The local knowledge manifest does not match the protected active project.' }

$documents = @()
foreach ($relativePath in $knowledgePaths) {
    $fullPath = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "The portable knowledge pack is incomplete: $relativePath" }
    $content = [IO.File]::ReadAllText($fullPath)
    if ([Text.Encoding]::UTF8.GetByteCount($content) -gt 100000) { throw "The portable knowledge file is too large: $relativePath" }
    $documents += [ordered]@{ path = $relativePath; content = $content }
}

$git = [ordered]@{ available = $false; branch = ''; revision = ''; dirty = $false; changedPaths = @(); originConfigured = $false }
if (Test-Path -LiteralPath (Join-Path $root '.git')) {
    $branchResult = Invoke-CogentSpecNativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'branch', '--show-current')
    $revisionResult = Invoke-CogentSpecNativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'rev-parse', 'HEAD')
    $statusResult = Invoke-CogentSpecNativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'status', '--porcelain=v1', '--untracked-files=normal')
    $remoteResult = Invoke-CogentSpecNativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'remote')
    $changedPaths = @($statusResult.Output -split "`r?`n" | Where-Object { $_ } | Select-Object -First 200)
    $git = [ordered]@{
        available = $revisionResult.ExitCode -eq 0
        branch = $branchResult.Output.Trim()
        revision = $revisionResult.Output.Trim()
        dirty = $changedPaths.Count -gt 0
        changedPaths = $changedPaths
        originConfigured = @($remoteResult.Output -split "`r?`n") -contains 'origin'
    }
}

$state = [ordered]@{
    schemaVersion = 1
    projectRequestId = [string]$runtime.activeProject.requestId
    projectName = [string]$runtime.activeProject.projectName
    contextKey = $projectContext.ContextKey
    repository = $git
    refreshedAt = [DateTimeOffset]::UtcNow.ToString('O')
}
if ($Mode -eq 'refresh') {
    $statePath = Join-Path $root '.coge\knowledge-state.json'
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($statePath, (($state | ConvertTo-Json -Depth 8) + "`n"), $encoding)
}

Write-CompactJson ([ordered]@{
    status = if ($Mode -eq 'refresh') { 'refreshed' } elseif ($Mode -eq 'initialize') { 'initialized' } else { 'loaded' }
    context = [ordered]@{ key = $projectContext.ContextKey; source = $projectContext.Source; isolated = $projectContext.Isolated }
    activeProject = $runtime.activeProject
    manifest = $manifest
    repository = $git
    documents = $documents
})
