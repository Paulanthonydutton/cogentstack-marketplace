param(
    [ValidateSet('Inspect', 'Open', 'Hide', 'Close')]
    [string]$Mode = 'Open',
    [string]$Url = 'https://cogentstack.app/stack?surface=chatgpt'
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

function Get-ChatDesktopWindow {
    @(Get-DesktopWindows | Where-Object {
        $_.ProcessName -match '(?i)^(chatgpt|codex)(?:[-_. ].*)?$' -and $_.Title -match '(?i)(chatgpt|codex)'
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
        message = 'The automatic ChatGPT/Codex companion layout is currently available on Windows only.'
    })
    exit 3
}

Add-Type -AssemblyName System.Windows.Forms
if ($null -eq ('CogentStackChatDesktopWindow' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class CogentStackChatDesktopWindow {
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

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out RECT value, int size);
}
'@
}

$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack'
$statePath = Join-Path $stateRoot 'chatgpt-companion-layout.json'

function Read-LayoutState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { return $null }
}

function Find-RememberedWindow($State, [string]$Kind) {
    if ($null -eq $State) { return $null }
    $handleProperty = if ($Kind -eq 'panel') { 'panelHandle' } else { 'chatDesktopHandle' }
    $processProperty = if ($Kind -eq 'panel') { 'panelProcessId' } else { 'chatDesktopProcessId' }
    $expectedHandle = [Int64]$State.$handleProperty
    $expectedProcess = [int]$State.$processProperty
    if ($expectedHandle -eq 0 -or $expectedProcess -le 0 -or -not [CogentStackChatDesktopWindow]::IsWindow([IntPtr]$expectedHandle)) {
        return $null
    }
    [uint32]$actualProcess = 0
    [CogentStackChatDesktopWindow]::GetWindowThreadProcessId([IntPtr]$expectedHandle, [ref]$actualProcess) | Out-Null
    if ([int]$actualProcess -ne $expectedProcess -or -not (Get-Process -Id $expectedProcess -ErrorAction SilentlyContinue)) {
        return $null
    }
    [pscustomobject]@{
        Handle = $expectedHandle
        ProcessId = $expectedProcess
        ProcessName = if ($Kind -eq 'panel') { 'msedge' } else { 'ChatGPT/Codex' }
        Title = ''
    }
}

function Get-WindowRectangle([Int64]$Handle) {
    $rectangle = New-Object CogentStackChatDesktopWindow+RECT
    if (-not [CogentStackChatDesktopWindow]::GetWindowRect([IntPtr]$Handle, [ref]$rectangle)) { return $null }
    [ordered]@{
        x = $rectangle.Left
        y = $rectangle.Top
        width = $rectangle.Right - $rectangle.Left
        height = $rectangle.Bottom - $rectangle.Top
    }
}

function Move-DesktopWindow($Window, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    [CogentStackChatDesktopWindow]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    if (-not [CogentStackChatDesktopWindow]::MoveWindow([IntPtr]$Window.Handle, $X, $Y, $Width, $Height, $true)) {
        throw "Windows could not position the $($Window.ProcessName) window."
    }
}

function Get-VisibleFrameInsets($Window) {
    $windowRectangle = New-Object CogentStackChatDesktopWindow+RECT
    $visibleRectangle = New-Object CogentStackChatDesktopWindow+RECT
    if (-not [CogentStackChatDesktopWindow]::GetWindowRect([IntPtr]$Window.Handle, [ref]$windowRectangle)) {
        return [ordered]@{ left = 0; top = 0; right = 0; bottom = 0 }
    }
    $result = [CogentStackChatDesktopWindow]::DwmGetWindowAttribute(
        [IntPtr]$Window.Handle,
        9,
        [ref]$visibleRectangle,
        [Runtime.InteropServices.Marshal]::SizeOf($visibleRectangle)
    )
    if ($result -ne 0) {
        return [ordered]@{ left = 0; top = 0; right = 0; bottom = 0 }
    }
    [ordered]@{
        left = [Math]::Max(0, $visibleRectangle.Left - $windowRectangle.Left)
        top = [Math]::Max(0, $visibleRectangle.Top - $windowRectangle.Top)
        right = [Math]::Max(0, $windowRectangle.Right - $visibleRectangle.Right)
        bottom = [Math]::Max(0, $windowRectangle.Bottom - $visibleRectangle.Bottom)
    }
}

function Move-VisibleDesktopWindow($Window, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    [CogentStackChatDesktopWindow]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    $insets = Get-VisibleFrameInsets $Window
    Move-DesktopWindow `
        $Window `
        ($X - [int]$insets.left) `
        ($Y - [int]$insets.top) `
        ($Width + [int]$insets.left + [int]$insets.right) `
        ($Height + [int]$insets.top + [int]$insets.bottom)
}

function Restore-ChatDesktopWindow($State) {
    $chatDesktopWindow = Find-RememberedWindow $State 'chatDesktop'
    if ($chatDesktopWindow -and $State.chatDesktopOriginal) {
        $original = $State.chatDesktopOriginal
        Move-DesktopWindow $chatDesktopWindow ([int]$original.x) ([int]$original.y) ([int]$original.width) ([int]$original.height)
    }
}

$state = Read-LayoutState
$rememberedPanel = Find-RememberedWindow $state 'panel'
$edgePath = Get-EdgePath
$chatDesktopWindow = @(Get-ChatDesktopWindow | Select-Object -First 1)

if ($Mode -eq 'Inspect') {
    Write-CompactJson ([ordered]@{
        status = 'inspected'
        platform = 'windows'
        chatDesktopWindowFound = [bool]$chatDesktopWindow
        companionWindowFound = [bool]$rememberedPanel
        edgeAvailable = [bool]$edgePath
    })
    exit 0
}

if ($Mode -in @('Hide', 'Close')) {
    if ($rememberedPanel) {
        if ($Mode -eq 'Hide') {
            [CogentStackChatDesktopWindow]::ShowWindow([IntPtr]$rememberedPanel.Handle, 0) | Out-Null
        } else {
            [CogentStackChatDesktopWindow]::PostMessage([IntPtr]$rememberedPanel.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
    Restore-ChatDesktopWindow $state
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

[CogentStackChatDesktopWindow]::ShowWindow([IntPtr]$panelWindow.Handle, 9) | Out-Null
if (-not $chatDesktopWindow) {
    Write-CompactJson ([ordered]@{
        status = 'opened_unarranged'
        message = 'CogentStack is open. No active ChatGPT or Codex window was available for automatic layout.'
    })
    exit 0
}

$originalRectangle = if ($state -and $state.chatDesktopOriginal) { $state.chatDesktopOriginal } else { Get-WindowRectangle $chatDesktopWindow.Handle }
$screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$chatDesktopWindow.Handle)
$area = $screen.WorkingArea
$gutter = 0
$chatDesktopWidth = [Math]::Floor($area.Width / 2)
$panelWidth = $area.Width - $chatDesktopWidth
$dpi = [CogentStackChatDesktopWindow]::GetDpiForWindow([IntPtr]$panelWindow.Handle)
if ($dpi -le 0) { $dpi = 96 }
$panelTopOffset = [Math]::Max(0, [Math]::Round(12 * ($dpi / 96)))

Move-VisibleDesktopWindow $chatDesktopWindow $area.X $area.Y $chatDesktopWidth $area.Height
Move-VisibleDesktopWindow $panelWindow ($area.X + $chatDesktopWidth) ($area.Y + $panelTopOffset) $panelWidth ($area.Height - $panelTopOffset)

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
[ordered]@{
    schemaVersion = 1
    chatDesktopHandle = [Int64]$chatDesktopWindow.Handle
    chatDesktopProcessId = [int]$chatDesktopWindow.ProcessId
    chatDesktopOriginal = $originalRectangle
    panelHandle = [Int64]$panelWindow.Handle
    panelProcessId = [int]$panelWindow.ProcessId
    updatedAt = [DateTimeOffset]::UtcNow.ToString('O')
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-CompactJson ([ordered]@{
    status = 'arranged'
    layout = 'equal-split-chatgpt-left-cogentstack-right'
    splitPercent = 50
    gutter = $gutter
    panelWidth = $panelWidth
    panelTopOffset = $panelTopOffset
    screen = [string]$screen.DeviceName
})
