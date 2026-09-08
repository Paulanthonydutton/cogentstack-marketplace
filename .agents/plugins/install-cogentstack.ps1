[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallationRequest,

    [ValidateRange(5, 30)]
    [int]$DeadlineSeconds = 30,

    [switch]$MarketplacePrepared,

    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$marketplaceName = 'cogentstack'
$marketplaceSource = 'https://github.com/Paulanthonydutton/cogentstack-marketplace.git'
$workspaceUrl = 'https://cogentstack.app/stack?surface=chatgpt'
$requiredSparsePaths = @('.agents/plugins', 'plugins/cogentstack')
$timer = [Diagnostics.Stopwatch]::StartNew()
$privateInstallationRequest = [string]$InstallationRequest
$InstallationRequest = ''
$claimJob = $null
$claimAttempted = $false
$claimSucceeded = $false
$stage = 'initialization'

function Get-RemainingMilliseconds {
    $remaining = ($DeadlineSeconds * 1000) - [int]$timer.ElapsedMilliseconds
    if ($remaining -le 0) {
        throw 'The bounded CogentStack installation exceeded 30 seconds before the account request was consumed.'
    }
    return $remaining
}

function Invoke-BoundedNative {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $remaining = Get-RemainingMilliseconds
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $isCommandScript = [IO.Path]::GetExtension($FilePath) -in @('.cmd', '.bat')
    $startInfo.FileName = if ($isCommandScript) { $env:ComSpec } else { $FilePath }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($isCommandScript) {
        $quotedArguments = @($Arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' })
        $startInfo.Arguments = '/d /s /c ""' + $FilePath + '" ' + ($quotedArguments -join ' ') + '"'
    } else {
        foreach ($argument in $Arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Could not start $FilePath."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($remaining)) {
            try { $process.Kill($true) } catch { }
            throw 'The bounded CogentStack installation exceeded 30 seconds.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            $detail = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { "exit code $($process.ExitCode)" }
            throw "A required installation command failed: $detail"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Read-JsonResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    try {
        return $Text | ConvertFrom-Json
    } catch {
        throw "$Operation did not return valid JSON."
    }
}

function Get-MarketplaceState {
    $json = Invoke-BoundedNative -FilePath $script:codexPath -Arguments @('plugin', 'marketplace', 'list', '--json')
    $result = Read-JsonResult -Text $json -Operation 'Marketplace inspection'
    return @($result.marketplaces | Where-Object { $_.name -eq $marketplaceName }) | Select-Object -First 1
}

function Add-CogentStackMarketplace {
    [void](Invoke-BoundedNative -FilePath $script:codexPath -Arguments @(
        'plugin', 'marketplace', 'add', $marketplaceSource,
        '--sparse', $requiredSparsePaths[0],
        '--sparse', $requiredSparsePaths[1],
        '--json'
    ))
}

function Test-StringSetEqual {
    param([string[]]$Actual, [string[]]$Expected)
    $difference = @(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject @($Actual | Sort-Object))
    return $difference.Count -eq 0
}

try {
    if ($privateInstallationRequest -notmatch '^cgb_[A-Za-z0-9_-]{40,}$') {
        throw 'The account-bound installation request is missing or invalid. Copy a fresh request from https://cogentstack.app/install.'
    }

    $codexCommand = @(Get-Command codex.cmd -CommandType Application -ErrorAction Stop) | Select-Object -First 1
    $gitCommand = @(Get-Command git.exe -CommandType Application -ErrorAction Stop) | Select-Object -First 1
    $script:codexPath = [string]$codexCommand.Source
    $gitPath = [string]$gitCommand.Source

    $stage = 'workspace readiness'
    $webTimeout = [Math]::Max(1, [Math]::Min(5, [Math]::Floor((Get-RemainingMilliseconds) / 1000)))
    $response = Invoke-WebRequest `
        -Uri $workspaceUrl `
        -UseBasicParsing `
        -MaximumRedirection 0 `
        -TimeoutSec $webTimeout
    if ([int]$response.StatusCode -ne 200) {
        throw 'The CogentStack workspace did not return HTTP 200.'
    }
    $baseResponseProperties = @($response.BaseResponse.PSObject.Properties.Name)
    $finalUrl = if ($baseResponseProperties -contains 'RequestMessage' -and $response.BaseResponse.RequestMessage.RequestUri) {
        $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    } elseif ($baseResponseProperties -contains 'ResponseUri' -and $response.BaseResponse.ResponseUri) {
        $response.BaseResponse.ResponseUri.AbsoluteUri
    } else {
        $workspaceUrl
    }
    if ($finalUrl -ne $workspaceUrl) {
        throw 'The CogentStack workspace redirected instead of returning the official ChatGPT surface.'
    }
    if ($response.Content -notmatch 'Creating a Project:' -or $response.Content -notmatch 'Find a project type') {
        throw 'The CogentStack workspace is missing a required project-creation marker.'
    }

    if ($MarketplacePrepared) {
        $stage = 'prepared marketplace verification'
        $marketplace = Get-MarketplaceState
        if (-not $marketplace -or -not (Test-Path -LiteralPath ([string]$marketplace.root))) {
            throw 'The prepared CogentStack marketplace registration is unavailable.'
        }
        $marketplaceRoot = (Resolve-Path -LiteralPath ([string]$marketplace.root) -ErrorAction Stop).Path.TrimEnd('\', '/')
        $installerMarketplaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path.TrimEnd('\', '/')
        if (-not [string]::Equals($marketplaceRoot, $installerMarketplaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The bounded installer is not running from the prepared CogentStack marketplace.'
        }
        $preparedRemote = Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $marketplaceRoot, 'remote', 'get-url', 'origin')
        $preparedSparse = @((Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $marketplaceRoot, 'sparse-checkout', 'list')) -split "`r?`n" | Where-Object { $_ })
        if ($preparedRemote.Trim() -ne $marketplaceSource -or -not (Test-StringSetEqual -Actual $preparedSparse -Expected $requiredSparsePaths)) {
            throw 'The prepared CogentStack marketplace does not match the official Git source and sparse paths.'
        }
    } else {
        $stage = 'marketplace registration inspection'
        $marketplace = Get-MarketplaceState
        $registrationMatches = $false
        if ($marketplace -and (Test-Path -LiteralPath ([string]$marketplace.root))) {
            $root = [string]$marketplace.root
            $remote = Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $root, 'remote', 'get-url', 'origin')
            $sparse = @((Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $root, 'sparse-checkout', 'list')) -split "`r?`n" | Where-Object { $_ })
            $registrationMatches = $remote.Trim() -eq $marketplaceSource -and (Test-StringSetEqual -Actual $sparse -Expected $requiredSparsePaths)
        }

        $stage = 'marketplace registration repair'
        if ($marketplace -and -not $registrationMatches) {
            [void](Invoke-BoundedNative -FilePath $script:codexPath -Arguments @('plugin', 'marketplace', 'remove', $marketplaceName, '--json'))
            Add-CogentStackMarketplace
        } elseif (-not $marketplace) {
            Add-CogentStackMarketplace
        }

        $stage = 'marketplace refresh'
        [void](Invoke-BoundedNative -FilePath $script:codexPath -Arguments @('plugin', 'marketplace', 'upgrade', $marketplaceName))

        $stage = 'refreshed marketplace verification'
        $marketplace = Get-MarketplaceState
        if (-not $marketplace -or -not (Test-Path -LiteralPath ([string]$marketplace.root))) {
            throw 'The refreshed CogentStack marketplace registration is unavailable.'
        }
        $marketplaceRoot = [string]$marketplace.root
        $refreshedRemote = Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $marketplaceRoot, 'remote', 'get-url', 'origin')
        $refreshedSparse = @((Invoke-BoundedNative -FilePath $gitPath -Arguments @('-C', $marketplaceRoot, 'sparse-checkout', 'list')) -split "`r?`n" | Where-Object { $_ })
        if ($refreshedRemote.Trim() -ne $marketplaceSource -or -not (Test-StringSetEqual -Actual $refreshedSparse -Expected $requiredSparsePaths)) {
            throw 'The refreshed CogentStack marketplace does not match the official Git source and sparse paths.'
        }
    }

    $stage = 'plugin installation'
    $installJson = Invoke-BoundedNative -FilePath $script:codexPath -Arguments @('plugin', 'add', 'cogentstack@cogentstack', '--json')
    $installResult = Read-JsonResult -Text $installJson -Operation 'Plugin installation'
    $installedPath = [string]$installResult.installedPath
    if (-not $installedPath -or -not (Test-Path -LiteralPath $installedPath)) {
        throw 'The CogentStack plugin installation did not return a valid installed package path.'
    }

    $stage = 'installed and enabled verification'
    $pluginListJson = Invoke-BoundedNative -FilePath $script:codexPath -Arguments @('plugin', 'list', '--json')
    $pluginList = Read-JsonResult -Text $pluginListJson -Operation 'Installed plugin inspection'
    $installedPlugin = @($pluginList.installed | Where-Object { $_.pluginId -eq 'cogentstack@cogentstack' }) | Select-Object -First 1
    if (-not $installedPlugin -or -not [bool]$installedPlugin.installed -or -not [bool]$installedPlugin.enabled) {
        throw 'The CogentStack plugin is not installed and enabled.'
    }

    $stage = 'package integrity verification'
    $sourcePluginPath = Join-Path $marketplaceRoot 'plugins\cogentstack'
    $sourceManifestPath = Join-Path $sourcePluginPath '.codex-plugin\plugin.json'
    $installedManifestPath = Join-Path $installedPath '.codex-plugin\plugin.json'
    $sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json
    $installedManifest = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
    if ([string]$sourceManifest.version -ne [string]$installedManifest.version -or [string]$installedPlugin.version -ne [string]$sourceManifest.version) {
        throw 'The installed CogentStack version does not match the refreshed marketplace package.'
    }

    $allowedFiles = @(
        '.codex-plugin/plugin.json',
        'assets/icon.png',
        'assets/logo.png',
        'skills/cogentstack/agents/openai.yaml',
        'skills/cogentstack/scripts/connect-cogentstack.ps1',
        'skills/cogentstack/scripts/delete-project.ps1',
        'skills/cogentstack/scripts/ensure-cogentstack.ps1',
        'skills/cogentstack/scripts/fulfil-project.ps1',
        'skills/cogentstack/scripts/generate-project-preview.ps1',
        'skills/cogentstack/scripts/hide-codex-sidebar.ps1',
        'skills/cogentstack/scripts/native-command.ps1',
        'skills/cogentstack/scripts/open-cogentstack-companion.ps1',
        'skills/cogentstack/scripts/prepare-deployment.ps1',
        'skills/cogentstack/scripts/project-context.ps1',
        'skills/cogentstack/scripts/project-knowledge.ps1',
        'skills/cogentstack/SKILL.md'
    )
    $actualFiles = @(Get-ChildItem -LiteralPath $installedPath -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($installedPath.Length + 1).Replace('\', '/')
    })
    if (-not (Test-StringSetEqual -Actual $actualFiles -Expected $allowedFiles)) {
        throw 'The installed CogentStack package does not match the official public-file allowlist.'
    }
    foreach ($relativePath in $allowedFiles) {
        $nativeRelativePath = $relativePath.Replace('/', '\')
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $sourcePluginPath $nativeRelativePath) -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath (Join-Path $installedPath $nativeRelativePath) -Algorithm SHA256).Hash
        if ($sourceHash -ne $installedHash) {
            throw "The installed package differs from the refreshed marketplace at $relativePath."
        }
    }

    $skillText = Get-Content -LiteralPath (Join-Path $installedPath 'skills\cogentstack\SKILL.md') -Raw
    $requiredSkillStatements = @(
        'Run `scripts/ensure-cogentstack.ps1 -Mode Companion` exactly once.',
        'run `scripts/hide-codex-sidebar.ps1` exactly once before arranging the windows.',
        'run `scripts/open-cogentstack-companion.ps1 -Mode Open -Url <exact returned URL>` exactly once.',
        '`browserContentMode: page-only`',
        '`browserChromeHidden: true`',
        '`browserContentClipped: true`',
        '`gutter: 12`',
        '`separated: true`',
        '`whiteDivider: true`',
        '`dividerMasksShadows: true`',
        '`layoutVerified: true`',
        'The companion header presents **−**, **+**, and **X** in that order.',
        'Use the embedded mode only when the user explicitly asks to keep CogentStack inside Codex',
        '`placement` set to `right`'
    )
    foreach ($statement in $requiredSkillStatements) {
        if (-not $skillText.Contains($statement)) {
            throw 'The installed launcher skill is missing a required companion or optional-panel guarantee.'
        }
    }

    $companionScript = Get-Content -LiteralPath (Join-Path $installedPath 'skills\cogentstack\scripts\open-cogentstack-companion.ps1') -Raw
    if ($companionScript.Contains('--app') -or $companionScript.Contains('--new-window')) {
        throw 'The companion helper contains a prohibited browser-window launch flag.'
    }
    foreach ($requiredMarker in @('companion=suspend', 'companion=resume', 'whiteDivider', 'dividerMasksShadows', 'SW_MAXIMIZE')) {
        if (-not $companionScript.Contains($requiredMarker)) {
            throw 'The companion helper is missing a required reversible-layout marker.'
        }
    }

    if ($ValidateOnly) {
        [ordered]@{
            status = 'validated'
            installed = $true
            enabled = $true
            version = [string]$installedManifest.version
            accountRequestConsumed = $false
            durationMs = [int]$timer.ElapsedMilliseconds
        } | ConvertTo-Json -Compress | Write-Output
        exit 0
    }

    $stage = 'account-bound installation claim'
    $remainingForClaim = Get-RemainingMilliseconds
    if ($remainingForClaim -lt 2000) {
        throw 'The bounded installation did not leave enough time to safely consume the account request.'
    }
    $connectScript = Join-Path $installedPath 'skills\cogentstack\scripts\connect-cogentstack.ps1'
    $claimJob = Start-Job -ScriptBlock {
        param($ConnectionHelper, $PrivateRequest)
        & $ConnectionHelper -Mode claim -InstallationRequest $PrivateRequest
    } -ArgumentList $connectScript, $privateInstallationRequest
    $claimAttempted = $true
    $privateInstallationRequest = ''

    $claimWaitSeconds = [Math]::Max(1, [Math]::Floor((Get-RemainingMilliseconds) / 1000))
    if (-not (Wait-Job -Job $claimJob -Timeout $claimWaitSeconds)) {
        Stop-Job -Job $claimJob -ErrorAction SilentlyContinue
        throw 'The bounded CogentStack installation exceeded 30 seconds while establishing the account-bound connection.'
    }
    $claimOutput = (@(Receive-Job -Job $claimJob -ErrorAction Stop) | ForEach-Object { [string]$_ }) -join "`n"
    $claimResult = Read-JsonResult -Text $claimOutput.Trim() -Operation 'Account-bound installation claim'
    if ([string]$claimResult.status -ne 'connected' -or -not [bool]$claimResult.accountBound -or -not [bool]$claimResult.installationBound) {
        throw 'The account-bound installation claim did not return the three required connection guarantees.'
    }
    $claimSucceeded = $true

    [ordered]@{
        status = 'installed'
        connected = $true
        accountBound = $true
        installationBound = $true
        version = [string]$installedManifest.version
        durationMs = [int]$timer.ElapsedMilliseconds
    } | ConvertTo-Json -Compress | Write-Output
} catch {
    [ordered]@{
        status = 'failed'
        reason = "$stage`: $([string]$_.Exception.Message)"
        accountRequestConsumed = if ($claimSucceeded) { $true } elseif ($claimAttempted) { $null } else { $false }
        durationMs = [int]$timer.ElapsedMilliseconds
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
} finally {
    $InstallationRequest = ''
    $privateInstallationRequest = ''
    if ($claimJob) {
        Remove-Job -Job $claimJob -Force -ErrorAction SilentlyContinue
    }
}
