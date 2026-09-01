param(
    [ValidateSet('Inspect', 'Open', 'Hide', 'Close')]
    [string]$Mode = 'Open',
    [string]$Url = 'https://cogentstack.app/stack?surface=claude-desktop'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-CompactJson($Value) {
    $Value | ConvertTo-Json -Compress | Write-Output
}

function Confirm-CogentStackUrl([string]$Candidate) {
    $parsed = $null
    if (-not [Uri]::TryCreate($Candidate, [UriKind]::Absolute, [ref]$parsed)) {
        throw 'CogentStack supplied an invalid companion URL.'
    }
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -notin @('cogentstack.app', 'www.cogentstack.app') -or $parsed.AbsolutePath -ne '/stack') {
        throw 'The companion may open only the protected CogentStack stack surface.'
    }
    return $parsed.AbsoluteUri
}

function Get-DesktopWindows {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
    } | ForEach-Object {
        [pscustomobject]@{
            Handle = [Int64]$_.MainWindowHandle
            ProcessId = [int]$_.Id
            ProcessName = [string]$_.ProcessName
            Title = [string]$_.MainWindowTitle
        }
    })
}

function Get-ClaudeWindow {
    @(Get-DesktopWindows | Where-Object {
        $_.ProcessName -match '(?i)^claude(?:[-_. ].*)?$' -and $_.Title -match '(?i)claude'
    } | Sort-Object ProcessId | Select-Object -First 1)
}

function Get-EdgePath {
    $command = Get-Command 'msedge.exe' -ErrorAction SilentlyContinue
    if ($command) { return [string]$command.Source }

    $candidates = @(@(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($candidates.Count -gt 0) { return [string]$candidates[0] }
    return $null
}

if ($env:OS -ne 'Windows_NT') {
    Write-CompactJson ([ordered]@{
        status = 'unsupported_platform'
        message = 'The automatic Claude companion layout is currently available on Windows only.'
    })
    exit 3
}

Add-Type -AssemblyName System.Windows.Forms
if ($null -eq ('CogentStackClaudeWindow' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class CogentStackClaudeWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
}

$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack'
$statePath = Join-Path $stateRoot 'claude-companion-layout.json'

function Read-LayoutState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { return $null }
}

function Find-RememberedWindow($State, [string]$Kind) {
    if ($null -eq $State) { return $null }
    $handleProperty = if ($Kind -eq 'panel') { 'panelHandle' } else { 'claudeHandle' }
    $processProperty = if ($Kind -eq 'panel') { 'panelProcessId' } else { 'claudeProcessId' }
    $expectedHandle = [Int64]$State.$handleProperty
    $expectedProcess = [int]$State.$processProperty
    if ($expectedHandle -eq 0 -or $expectedProcess -le 0 -or -not [CogentStackClaudeWindow]::IsWindow([IntPtr]$expectedHandle)) {
        return $null
    }
    [uint32]$actualProcess = 0
    [CogentStackClaudeWindow]::GetWindowThreadProcessId([IntPtr]$expectedHandle, [ref]$actualProcess) | Out-Null
    if ([int]$actualProcess -ne $expectedProcess -or -not (Get-Process -Id $expectedProcess -ErrorAction SilentlyContinue)) {
        return $null
    }
    [pscustomobject]@{
        Handle = $expectedHandle
        ProcessId = $expectedProcess
        ProcessName = if ($Kind -eq 'panel') { 'msedge' } else { 'Claude' }
        Title = ''
    }
}

function Get-WindowRectangle([Int64]$Handle) {
    $rectangle = New-Object CogentStackClaudeWindow+RECT
    if (-not [CogentStackClaudeWindow]::GetWindowRect([IntPtr]$Handle, [ref]$rectangle)) { return $null }
    [ordered]@{
        x = $rectangle.Left
        y = $rectangle.Top
        width = $rectangle.Right - $rectangle.Left
        height = $rectangle.Bottom - $rectangle.Top
    }
}

function Move-DesktopWindow($Window, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    [CogentStackClaudeWindow]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    if (-not [CogentStackClaudeWindow]::MoveWindow([IntPtr]$Window.Handle, $X, $Y, $Width, $Height, $true)) {
        throw "Windows could not position the $($Window.ProcessName) window."
    }
}

function Restore-ClaudeWindow($State) {
    $claudeWindow = Find-RememberedWindow $State 'claude'
    if ($claudeWindow -and $State.claudeOriginal) {
        $original = $State.claudeOriginal
        Move-DesktopWindow $claudeWindow ([int]$original.x) ([int]$original.y) ([int]$original.width) ([int]$original.height)
    }
}

$state = Read-LayoutState
$rememberedPanel = Find-RememberedWindow $state 'panel'
$edgePath = Get-EdgePath
$claudeWindow = @(Get-ClaudeWindow | Select-Object -First 1)

if ($Mode -eq 'Inspect') {
    Write-CompactJson ([ordered]@{
        status = 'inspected'
        platform = 'windows'
        claudeWindowFound = [bool]$claudeWindow
        companionWindowFound = [bool]$rememberedPanel
        edgeAvailable = [bool]$edgePath
    })
    exit 0
}

if ($Mode -in @('Hide', 'Close')) {
    if ($rememberedPanel) {
        if ($Mode -eq 'Hide') {
            [CogentStackClaudeWindow]::ShowWindow([IntPtr]$rememberedPanel.Handle, 0) | Out-Null
        } else {
            [CogentStackClaudeWindow]::PostMessage([IntPtr]$rememberedPanel.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
    Restore-ClaudeWindow $state
    if ($Mode -eq 'Close' -and (Test-Path -LiteralPath $statePath)) {
        Remove-Item -LiteralPath $statePath -Force
    }
    Write-CompactJson ([ordered]@{ status = $Mode.ToLowerInvariant(); panelFound = [bool]$rememberedPanel })
    exit 0
}

$safeUrl = Confirm-CogentStackUrl $Url
$panelWindow = $rememberedPanel
if (-not $panelWindow) {
    if (-not $edgePath) {
        Write-CompactJson ([ordered]@{
            status = 'browser_unavailable'
            message = 'Microsoft Edge is required for the installer-free CogentStack companion panel.'
        })
        exit 2
    }

    $beforeHandles = @{}
    Get-DesktopWindows | Where-Object { $_.ProcessName -eq 'msedge' } | ForEach-Object { $beforeHandles[[string]$_.Handle] = $true }
    Start-Process -FilePath $edgePath -ArgumentList @("--app=$safeUrl", '--new-window') | Out-Null

    for ($attempt = 0; $attempt -lt 50 -and -not $panelWindow; $attempt++) {
        Start-Sleep -Milliseconds 200
        $newEdgeWindows = @(Get-DesktopWindows | Where-Object {
            $_.ProcessName -eq 'msedge' -and -not $beforeHandles.ContainsKey([string]$_.Handle)
        })
        $panelWindow = @($newEdgeWindows | Where-Object { $_.Title -match '(?i)cogentstack' } | Select-Object -First 1)
        if (-not $panelWindow -and $newEdgeWindows.Count -eq 1) { $panelWindow = $newEdgeWindows[0] }
    }
}

if (-not $panelWindow) {
    Write-CompactJson ([ordered]@{
        status = 'opened_unarranged'
        message = 'CogentStack was opened, but its new app window could not be identified safely.'
    })
    exit 0
}

[CogentStackClaudeWindow]::ShowWindow([IntPtr]$panelWindow.Handle, 9) | Out-Null
if (-not $claudeWindow) {
    Write-CompactJson ([ordered]@{
        status = 'opened_unarranged'
        message = 'CogentStack is open. No active Claude window was available for automatic layout.'
    })
    exit 0
}

$originalRectangle = if ($state -and $state.claudeOriginal) { $state.claudeOriginal } else { Get-WindowRectangle $claudeWindow.Handle }
$screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$claudeWindow.Handle)
$area = $screen.WorkingArea
$gutter = 8
$panelWidth = [Math]::Min([Math]::Max(420, [Math]::Floor($area.Width * 0.34)), [Math]::Max(420, $area.Width - 640))
$claudeWidth = $area.Width - $panelWidth - $gutter

Move-DesktopWindow $claudeWindow $area.X $area.Y $claudeWidth $area.Height
Move-DesktopWindow $panelWindow ($area.X + $claudeWidth + $gutter) $area.Y $panelWidth $area.Height

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
[ordered]@{
    schemaVersion = 1
    claudeHandle = [Int64]$claudeWindow.Handle
    claudeProcessId = [int]$claudeWindow.ProcessId
    claudeOriginal = $originalRectangle
    panelHandle = [Int64]$panelWindow.Handle
    panelProcessId = [int]$panelWindow.ProcessId
    updatedAt = [DateTimeOffset]::UtcNow.ToString('O')
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-CompactJson ([ordered]@{
    status = 'arranged'
    layout = 'claude-left-cogentstack-right'
    panelWidth = $panelWidth
    screen = [string]$screen.DeviceName
})
