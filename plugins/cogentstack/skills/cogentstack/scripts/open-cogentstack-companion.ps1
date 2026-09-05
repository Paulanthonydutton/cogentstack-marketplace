param(
    [ValidateSet('Inspect', 'Open', 'Hide', 'Close', 'WatchExit')]
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

function Find-BrowserExecutable([string]$CommandName, [string[]]$Candidates) {
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) { return [string]$command.Source }
    $available = @($Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($available.Count -gt 0) { return [string]$available[0] }
    return $null
}

function Get-DefaultHttpsProgId {
    $choicePath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
    try { return [string](Get-ItemProperty -LiteralPath $choicePath -ErrorAction Stop).ProgId } catch { return '' }
}

function Get-CompanionBrowsers {
    $chromePath = Find-BrowserExecutable 'chrome.exe' @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    $edgePath = Find-BrowserExecutable 'msedge.exe' @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    )
    $defaultProgId = Get-DefaultHttpsProgId
    $available = @()
    if ($chromePath) {
        $available += [pscustomobject]@{
            Name = 'Google Chrome'
            ProcessName = 'chrome'
            ExecutablePath = $chromePath
            IsRegisteredDefault = $defaultProgId -match '(?i)^ChromeHTML'
        }
    }
    if ($edgePath) {
        $available += [pscustomobject]@{
            Name = 'Microsoft Edge'
            ProcessName = 'msedge'
            ExecutablePath = $edgePath
            IsRegisteredDefault = $defaultProgId -match '(?i)^MSEdgeHTM'
        }
    }
    @($available | Sort-Object @{ Expression = { -not $_.IsRegisteredDefault } }, Name)
}

if ($env:OS -ne 'Windows_NT') {
    Write-CompactJson ([ordered]@{
        status = 'unsupported_platform'
        message = 'The automatic ChatGPT/Codex companion layout is currently available on Windows only.'
    })
    exit 3
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if ($null -eq ('CogentStackWorkspaceWindows' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CogentStackWorkspaceWindows {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public int dwFlags;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowRgn(IntPtr hWnd, IntPtr region);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowRgn(IntPtr hWnd, IntPtr region, bool redraw);

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern int GetRgnBox(IntPtr region, out RECT rectangle);

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern bool DeleteObject(IntPtr value);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    public static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    public static extern IntPtr GetWindowLong32(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int index, IntPtr value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    public static extern IntPtr SetWindowLong32(IntPtr hWnd, int index, IntPtr value);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int capacity);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out RECT value, int size);

    public static IntPtr[] GetTopLevelWindows() {
        var windows = new List<IntPtr>();
        EnumWindows((handle, ignored) => {
            if (IsWindowVisible(handle) && GetWindowTextLength(handle) > 0) windows.Add(handle);
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }

    public static string GetWindowTitle(IntPtr hWnd) {
        var value = new StringBuilder(GetWindowTextLength(hWnd) + 1);
        GetWindowText(hWnd, value, value.Capacity);
        return value.ToString();
    }

    public static long GetWindowStyle(IntPtr hWnd) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, -16).ToInt64() : GetWindowLong32(hWnd, -16).ToInt64();
    }

    public static void SetWindowStyle(IntPtr hWnd, long value) {
        if (IntPtr.Size == 8) SetWindowLongPtr64(hWnd, -16, new IntPtr(value));
        else SetWindowLong32(hWnd, -16, new IntPtr(value));
    }
}
'@
}

$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack'
$statePath = Join-Path $stateRoot 'chatgpt-companion-layout.json'
$backdropTitle = 'CogentStack Workspace Backdrop'

function Get-WindowRectangle([Int64]$Handle) {
    $rectangle = New-Object CogentStackWorkspaceWindows+RECT
    if (-not [CogentStackWorkspaceWindows]::GetWindowRect([IntPtr]$Handle, [ref]$rectangle)) { return $null }
    [ordered]@{
        x = $rectangle.Left
        y = $rectangle.Top
        width = $rectangle.Right - $rectangle.Left
        height = $rectangle.Bottom - $rectangle.Top
    }
}

function Get-DesktopWindows {
    $foregroundHandle = [Int64][CogentStackWorkspaceWindows]::GetForegroundWindow()
    @([CogentStackWorkspaceWindows]::GetTopLevelWindows() | ForEach-Object {
        $windowHandle = [Int64]$_
        [uint32]$windowProcessId = 0
        [CogentStackWorkspaceWindows]::GetWindowThreadProcessId([IntPtr]$windowHandle, [ref]$windowProcessId) | Out-Null
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction SilentlyContinue
        if ($windowProcess) {
            $rectangle = Get-WindowRectangle $windowHandle
            [pscustomobject]@{
                Handle = $windowHandle
                ProcessId = [int]$windowProcessId
                ProcessName = [string]$windowProcess.ProcessName
                Title = [CogentStackWorkspaceWindows]::GetWindowTitle([IntPtr]$windowHandle)
                IsForeground = $windowHandle -eq $foregroundHandle
                IsMinimized = [CogentStackWorkspaceWindows]::IsIconic([IntPtr]$windowHandle)
                Area = if ($rectangle) { [int64]$rectangle.width * [int64]$rectangle.height } else { 0 }
            }
        }
    })
}

function Get-ChatDesktopWindow {
    $candidates = @(Get-DesktopWindows | Where-Object {
        $_.ProcessName -match '(?i)^(chatgpt|codex)(?:[-_. ].*)?$' -and $_.Title -match '(?i)(chatgpt|codex)'
    })
    $foreground = @($candidates | Where-Object { $_.IsForeground } | Select-Object -First 1)
    if ($foreground) { return $foreground }
    @($candidates | Where-Object { -not $_.IsMinimized } | Sort-Object @(
        @{ Expression = 'Area'; Descending = $true },
        @{ Expression = 'ProcessId'; Descending = $true }
    ) | Select-Object -First 1)
}

function Get-VisibleWindowRectangle([Int64]$Handle) {
    $rectangle = New-Object CogentStackWorkspaceWindows+RECT
    $result = [CogentStackWorkspaceWindows]::DwmGetWindowAttribute(
        [IntPtr]$Handle,
        9,
        [ref]$rectangle,
        [Runtime.InteropServices.Marshal]::SizeOf($rectangle)
    )
    if ($result -ne 0) { return Get-WindowRectangle $Handle }
    [ordered]@{
        x = $rectangle.Left
        y = $rectangle.Top
        width = $rectangle.Right - $rectangle.Left
        height = $rectangle.Bottom - $rectangle.Top
    }
}

function Get-MonitorWorkingArea([Int64]$Handle) {
    $monitor = [CogentStackWorkspaceWindows]::MonitorFromWindow([IntPtr]$Handle, 2)
    $info = New-Object CogentStackWorkspaceWindows+MONITORINFO
    $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($info)
    if ($monitor -eq [IntPtr]::Zero -or -not [CogentStackWorkspaceWindows]::GetMonitorInfo($monitor, [ref]$info)) {
        throw 'Windows could not determine the current monitor work area.'
    }
    [ordered]@{
        x = $info.rcWork.Left
        y = $info.rcWork.Top
        width = $info.rcWork.Right - $info.rcWork.Left
        height = $info.rcWork.Bottom - $info.rcWork.Top
    }
}

function Get-VisibleFrameInsets($Window) {
    $windowRectangle = New-Object CogentStackWorkspaceWindows+RECT
    $visibleRectangle = New-Object CogentStackWorkspaceWindows+RECT
    if (-not [CogentStackWorkspaceWindows]::GetWindowRect([IntPtr]$Window.Handle, [ref]$windowRectangle)) {
        return [ordered]@{ left = 0; top = 0; right = 0; bottom = 0 }
    }
    $result = [CogentStackWorkspaceWindows]::DwmGetWindowAttribute(
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

function Test-WindowHasCustomRegion($Window) {
    $probe = [CogentStackWorkspaceWindows]::CreateRectRgn(0, 0, 0, 0)
    if ($probe -eq [IntPtr]::Zero) { throw 'Windows could not allocate a browser-region probe.' }
    try {
        return [CogentStackWorkspaceWindows]::GetWindowRgn([IntPtr]$Window.Handle, $probe) -ne 0
    } finally {
        [CogentStackWorkspaceWindows]::DeleteObject($probe) | Out-Null
    }
}

function Clear-WindowRegion($Window) {
    if ($Window -and [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$Window.Handle)) {
        if (-not [CogentStackWorkspaceWindows]::SetWindowRgn([IntPtr]$Window.Handle, [IntPtr]::Zero, $true)) {
            throw 'Windows could not clear the temporary CogentStack browser crop.'
        }
    }
}

function Set-WindowContentRegion($Window, $DocumentRectangle) {
    $windowRectangle = Get-WindowRectangle $Window.Handle
    if (-not $windowRectangle) { throw 'Windows could not measure the browser before applying its content crop.' }

    $left = [int]$DocumentRectangle.x - [int]$windowRectangle.x
    $top = [int]$DocumentRectangle.y - [int]$windowRectangle.y
    $right = $left + [int]$DocumentRectangle.width
    $bottom = $top + [int]$DocumentRectangle.height
    if ($left -lt 0 -or $top -lt 0 -or $right -gt [int]$windowRectangle.width -or $bottom -gt [int]$windowRectangle.height) {
        throw 'Chrome reported document bounds outside its window; the browser crop was not applied.'
    }

    $region = [CogentStackWorkspaceWindows]::CreateRectRgn($left, $top, $right, $bottom)
    if ($region -eq [IntPtr]::Zero) { throw 'Windows could not allocate the CogentStack browser crop.' }
    if (-not [CogentStackWorkspaceWindows]::SetWindowRgn([IntPtr]$Window.Handle, $region, $true)) {
        [CogentStackWorkspaceWindows]::DeleteObject($region) | Out-Null
        throw 'Windows could not apply the CogentStack browser crop.'
    }

    # SetWindowRgn transfers ownership of the successful region to Windows.
    $verificationRegion = [CogentStackWorkspaceWindows]::CreateRectRgn(0, 0, 0, 0)
    if ($verificationRegion -eq [IntPtr]::Zero) {
        Clear-WindowRegion $Window
        throw 'Windows could not verify the CogentStack browser crop.'
    }
    try {
        $regionType = [CogentStackWorkspaceWindows]::GetWindowRgn([IntPtr]$Window.Handle, $verificationRegion)
        $regionRectangle = New-Object CogentStackWorkspaceWindows+RECT
        $boxType = [CogentStackWorkspaceWindows]::GetRgnBox($verificationRegion, [ref]$regionRectangle)
        if ($regionType -eq 0 -or $boxType -eq 0 -or $regionRectangle.Left -ne $left -or $regionRectangle.Top -ne $top -or $regionRectangle.Right -ne $right -or $regionRectangle.Bottom -ne $bottom) {
            Clear-WindowRegion $Window
            throw 'Windows did not retain the exact CogentStack browser crop.'
        }
    } finally {
        [CogentStackWorkspaceWindows]::DeleteObject($verificationRegion) | Out-Null
    }

    [ordered]@{
        left = $left
        top = $top
        right = [int]$windowRectangle.width - $right
        bottom = [int]$windowRectangle.height - $bottom
    }
}

function Move-DesktopWindow($Window, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    if (-not [CogentStackWorkspaceWindows]::MoveWindow([IntPtr]$Window.Handle, $X, $Y, $Width, $Height, $true)) {
        throw "Windows could not position the $($Window.ProcessName) window."
    }
}

function Move-VisibleDesktopWindow($Window, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $insets = Get-VisibleFrameInsets $Window
    Move-DesktopWindow `
        $Window `
        ($X - [int]$insets.left) `
        ($Y - [int]$insets.top) `
        ($Width + [int]$insets.left + [int]$insets.right) `
        ($Height + [int]$insets.top + [int]$insets.bottom)
}

function Read-LayoutState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { return $null }
}

function Find-RememberedWindow($State, [string]$Kind) {
    if ($null -eq $State) { return $null }
    $handleProperty = switch ($Kind) {
        'panel' { 'panelHandle' }
        'backdrop' { 'backdropHandle' }
        default { 'chatDesktopHandle' }
    }
    $processProperty = switch ($Kind) {
        'panel' { 'panelProcessId' }
        'backdrop' { 'backdropProcessId' }
        default { 'chatDesktopProcessId' }
    }
    if (-not $State.PSObject.Properties[$handleProperty] -or -not $State.PSObject.Properties[$processProperty]) { return $null }
    $expectedHandle = [Int64]$State.$handleProperty
    $expectedProcessId = [int]$State.$processProperty
    if ($expectedHandle -eq 0 -or $expectedProcessId -le 0 -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$expectedHandle)) {
        return $null
    }
    [uint32]$actualProcessId = 0
    [CogentStackWorkspaceWindows]::GetWindowThreadProcessId([IntPtr]$expectedHandle, [ref]$actualProcessId) | Out-Null
    $windowProcess = Get-Process -Id $expectedProcessId -ErrorAction SilentlyContinue
    if ([int]$actualProcessId -ne $expectedProcessId -or -not $windowProcess) { return $null }
    [pscustomobject]@{
        Handle = $expectedHandle
        ProcessId = $expectedProcessId
        ProcessName = [string]$windowProcess.ProcessName
        Title = [CogentStackWorkspaceWindows]::GetWindowTitle([IntPtr]$expectedHandle)
    }
}

function Get-AccountState($Window) {
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $elements = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        $signedOut = $false
        foreach ($element in $elements) {
            $name = [string]$element.Current.Name
            if ($name -match '(?i)^Open account for .+CogentStack website$' -or $name -match '(?i)^View subscriptions') {
                return 'signed_in'
            }
            if ($name -match '(?i)^Sign in(?:\s|$)') { $signedOut = $true }
        }
        if ($signedOut) { return 'signed_out' }
    } catch {}
    return 'unknown'
}

function Get-BrowserAddressValue($Window) {
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $addressCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            'Address and search bar'
        )
        $address = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $addressCondition)
        if (-not $address) { return '' }
        $valuePattern = $null
        if ($address.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
            return [string]([System.Windows.Automation.ValuePattern]$valuePattern).Current.Value
        }
    } catch {}
    return ''
}

function Test-CompanionExitAddress([string]$Address) {
    if (-not $Address) { return $false }
    return $Address -match '^(?:https?://)?(?:www\.)?cogentstack\.app/?(?:\?companion=close(?:#.*)?)?$'
}

function Get-WebDocumentRectangle($Window) {
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $documentCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Document
        )
        $documents = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $documentCondition)
        foreach ($document in $documents) {
            if ([string]$document.Current.Name -notmatch '(?i)^CogentStack \| Create or open a project$') { continue }
            $rectangle = $document.Current.BoundingRectangle
            if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { continue }
            return [ordered]@{
                x = [int][Math]::Round($rectangle.X)
                y = [int][Math]::Round($rectangle.Y)
                width = [int][Math]::Round($rectangle.Width)
                height = [int][Math]::Round($rectangle.Height)
            }
        }
    } catch {}
    return $null
}

function Wait-WebDocumentRectangle($Window, [scriptblock]$Accept, [int]$Attempts = 30) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $rectangle = Get-WebDocumentRectangle $Window
        if ($rectangle -and (& $Accept $rectangle)) { return $rectangle }
        Start-Sleep -Milliseconds 100
    }
    return Get-WebDocumentRectangle $Window
}

function Set-BrowserPageOnly($Window, $Area, [int]$PanelX, [int]$PanelWidth, [Int64]$OriginalStyle, [bool]$ResetManagedClip) {
    if ($ResetManagedClip) {
        Clear-WindowRegion $Window
    } elseif (Test-WindowHasCustomRegion $Window) {
        throw 'Chrome already has a custom window region, so CogentStack will not replace it.'
    }
    $documentBefore = Get-WebDocumentRectangle $Window
    $visibleBefore = Get-VisibleWindowRectangle $Window.Handle
    if (-not $documentBefore -or -not $visibleBefore) {
        throw 'Windows could not measure the CogentStack web document before hiding the browser controls.'
    }

    # Chrome can defer renderer resizing when a large background window changes style and size together.
    # First resize the still-framed window to the target half, then remove the frame after its document catches up.
    Move-VisibleDesktopWindow $Window $PanelX ([int]$Area.y) $PanelWidth ([int]$Area.height)
    [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$Window.Handle) | Out-Null
    [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$Window.Handle) | Out-Null
    $documentBefore = Wait-WebDocumentRectangle $Window {
        param($rectangle)
        [Math]::Abs([int]$rectangle.width - $PanelWidth) -le 64
    }
    $visibleBefore = Get-VisibleWindowRectangle $Window.Handle
    if (-not $documentBefore -or -not $visibleBefore -or [Math]::Abs([int]$documentBefore.width - $PanelWidth) -gt 64) {
        throw 'Chrome did not refresh the CogentStack document bounds before entering page-only mode.'
    }

    $normalChromeHeight = [Math]::Max(0, [int]$documentBefore.y - [int]$visibleBefore.y)
    $borderlessStyle = ($OriginalStyle -band (-bnot [Int64]0x00CF0000)) -bor [Int64]0x80000000
    [CogentStackWorkspaceWindows]::SetWindowStyle([IntPtr]$Window.Handle, $borderlessStyle)
    [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$Window.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0037) | Out-Null
    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$Window.Handle) | Out-Null
    [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$Window.Handle) | Out-Null

    if (-not [CogentStackWorkspaceWindows]::MoveWindow(
        [IntPtr]$Window.Handle,
        $PanelX,
        ([int]$Area.y - $normalChromeHeight),
        $PanelWidth,
        ([int]$Area.height + $normalChromeHeight + 24),
        $true
    )) {
        throw 'Windows could not size the CogentStack browser for page-only mode.'
    }
    $documentProbe = Wait-WebDocumentRectangle $Window {
        param($rectangle)
        [Math]::Abs([int]$rectangle.width - $PanelWidth) -le 64
    }

    $visibleProbe = Get-VisibleWindowRectangle $Window.Handle
    if (-not $visibleProbe -or -not $documentProbe) {
        throw 'Windows could not measure the CogentStack web document after hiding the browser controls.'
    }
    if ([Math]::Abs([int]$documentProbe.width - $PanelWidth) -gt 64) {
        throw 'Chrome did not refresh the CogentStack document bounds after entering page-only mode.'
    }

    $leftInset = [Math]::Max(0, [int]$documentProbe.x - [int]$visibleProbe.x)
    $topInset = [Math]::Max(0, [int]$documentProbe.y - [int]$visibleProbe.y)
    $rightInset = [Math]::Max(0, ([int]$visibleProbe.x + [int]$visibleProbe.width) - ([int]$documentProbe.x + [int]$documentProbe.width))
    $bottomInset = [Math]::Max(0, ([int]$visibleProbe.y + [int]$visibleProbe.height) - ([int]$documentProbe.y + [int]$documentProbe.height))

    if (-not [CogentStackWorkspaceWindows]::MoveWindow(
        [IntPtr]$Window.Handle,
        ($PanelX - $leftInset),
        ([int]$Area.y - $topInset),
        ($PanelWidth + $leftInset + $rightInset),
        ([int]$Area.height + $topInset + $bottomInset),
        $true
    )) {
        throw 'Windows could not align the CogentStack page-only frame.'
    }
    $documentFinal = Wait-WebDocumentRectangle $Window {
        param($rectangle)
        [Math]::Abs([int]$rectangle.x - $PanelX) -le 8 -and
        [Math]::Abs([int]$rectangle.y - [int]$Area.y) -le 8 -and
        [Math]::Abs([int]$rectangle.width - $PanelWidth) -le 8 -and
        [Math]::Abs([int]$rectangle.height - [int]$Area.height) -le 8
    }

    if (-not $documentFinal) { throw 'Windows could not verify the page-only CogentStack frame.' }
    for ($correctionAttempt = 0; $correctionAttempt -lt 4; $correctionAttempt++) {
        $horizontalCorrection = $PanelX - [int]$documentFinal.x
        $verticalCorrection = [int]$Area.y - [int]$documentFinal.y
        $widthCorrection = $PanelWidth - [int]$documentFinal.width
        $heightCorrection = [int]$Area.height - [int]$documentFinal.height
        if ($horizontalCorrection -eq 0 -and $verticalCorrection -eq 0 -and $widthCorrection -eq 0 -and $heightCorrection -eq 0) { break }
        $windowRectangle = Get-WindowRectangle $Window.Handle
        if (-not [CogentStackWorkspaceWindows]::MoveWindow(
            [IntPtr]$Window.Handle,
            ([int]$windowRectangle.x + $horizontalCorrection),
            ([int]$windowRectangle.y + $verticalCorrection),
            ([int]$windowRectangle.width + $widthCorrection),
            ([int]$windowRectangle.height + $heightCorrection),
            $true
        )) {
            throw 'Windows could not apply the final CogentStack page-only correction.'
        }
        $documentFinal = Wait-WebDocumentRectangle $Window {
            param($rectangle)
            [int]$rectangle.x -eq $PanelX -and
            [int]$rectangle.y -eq [int]$Area.y -and
            [int]$rectangle.width -eq $PanelWidth -and
            [int]$rectangle.height -eq [int]$Area.height
        } 10
        if (-not $documentFinal) { throw 'Windows could not verify the corrected page-only CogentStack frame.' }
    }
    if ([int]$documentFinal.x -ne $PanelX -or [int]$documentFinal.y -ne [int]$Area.y -or [int]$documentFinal.width -ne $PanelWidth -or [int]$documentFinal.height -ne [int]$Area.height) {
        throw 'Chrome did not converge on the exact CogentStack page-only bounds.'
    }
    $clipInsets = Set-WindowContentRegion $Window $documentFinal
    [ordered]@{
        originalStyle = $OriginalStyle
        appliedStyle = $borderlessStyle
        chromeInsets = [ordered]@{ left = $leftInset; top = $topInset; right = $rightInset; bottom = $bottomInset }
        clipInsets = $clipInsets
        contentClipped = $true
        contentFrame = $documentFinal
        windowFrame = Get-VisibleWindowRectangle $Window.Handle
    }
}

function Get-CogentStackTabCandidates($Window, $Browser, [bool]$SelectTabs) {
    $results = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
        foreach ($tab in $tabs) {
            if ([string]$tab.Current.Name -notmatch '(?i)^CogentStack \| Create or open a project(?:\s+-\s+Memory usage.*)?$') { continue }
            $accountState = 'unknown'
            if ($SelectTabs) {
                $selectionPattern = $null
                if ($tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
                    ([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Select()
                    Start-Sleep -Milliseconds 500
                    $accountState = Get-AccountState $Window
                }
            }
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                AccountState = $accountState
                ReusedExistingTab = $true
                HasTabStrip = $true
            }
        }
        if ($results.Count -eq 0 -and $Window.Title -match '(?i)^CogentStack \| Create or open a project') {
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                AccountState = if ($SelectTabs) { Get-AccountState $Window } else { 'unknown' }
                ReusedExistingTab = $true
                HasTabStrip = $tabs.Count -gt 0
            }
        }
    } catch {
        if ($Window.Title -match '(?i)^CogentStack \| Create or open a project') {
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                AccountState = 'unknown'
                ReusedExistingTab = $true
                HasTabStrip = $false
            }
        }
    }
    @($results)
}

function Find-ExistingCogentStackWindow($Browsers, [bool]$SelectTabs) {
    $candidates = @()
    $desktopWindows = @(Get-DesktopWindows)
    foreach ($candidateBrowser in $Browsers) {
        foreach ($browserWindow in @($desktopWindows | Where-Object { $_.ProcessName -eq $candidateBrowser.ProcessName })) {
            $candidates += @(Get-CogentStackTabCandidates $browserWindow $candidateBrowser $SelectTabs)
        }
    }
    $signedIn = @($candidates | Where-Object { $_.AccountState -eq 'signed_in' } | Select-Object -First 1)
    if ($signedIn) { return $signedIn }
    $normalWindow = @($candidates | Where-Object { $_.HasTabStrip } | Select-Object -First 1)
    if ($normalWindow) { return $normalWindow }
    @($candidates | Select-Object -First 1)
}

function Find-BackdropWindow {
    @(Get-DesktopWindows | Where-Object { $_.Title -eq $backdropTitle -and $_.ProcessName -match '(?i)^(powershell|pwsh)$' } | Select-Object -First 1)
}

function Start-WhiteBackdrop($Area) {
    $existing = @(Find-BackdropWindow | Select-Object -First 1)
    if ($existing) {
        Move-DesktopWindow $existing ([int]$Area.x) ([int]$Area.y) ([int]$Area.width) ([int]$Area.height)
        [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$existing.Handle, [IntPtr]1, 0, 0, 0, 0, 0x0013) | Out-Null
        return $existing
    }

    $backdropScript = @"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CogentStackBackdropDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
[CogentStackBackdropDpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = '$backdropTitle'
`$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
`$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
`$form.Bounds = New-Object System.Drawing.Rectangle($([int]$Area.x), $([int]$Area.y), $([int]$Area.width), $([int]$Area.height))
`$form.BackColor = [System.Drawing.Color]::White
`$form.ShowInTaskbar = `$false
`$form.ShowIcon = `$false
`$form.TopMost = `$false
[System.Windows.Forms.Application]::Run(`$form)
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($backdropScript))
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $powershellPath = if ($powershellCommand) { [string]$powershellCommand.Source } else { $null }
    if (-not $powershellPath) { throw 'Windows PowerShell is required to display the white CogentStack workspace background.' }
    $backdropProcess = Start-Process -FilePath $powershellPath -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) -WindowStyle Hidden -PassThru
    $backdrop = $null
    for ($attempt = 0; $attempt -lt 30 -and -not $backdrop; $attempt++) {
        Start-Sleep -Milliseconds 100
        $backdrop = @(Get-DesktopWindows | Where-Object { $_.ProcessId -eq $backdropProcess.Id -and $_.Title -eq $backdropTitle } | Select-Object -First 1)
    }
    if (-not $backdrop) { throw 'Windows could not create the white CogentStack workspace background.' }
    [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$backdrop.Handle, [IntPtr]1, 0, 0, 0, 0, 0x0013) | Out-Null
    return $backdrop
}

function Restore-Window($Window, $Rectangle) {
    if ($Window -and $Rectangle) {
        Move-DesktopWindow $Window ([int]$Rectangle.x) ([int]$Rectangle.y) ([int]$Rectangle.width) ([int]$Rectangle.height)
    }
}

function Restore-BrowserWindow($Window, $Rectangle, $Style) {
    if (-not $Window -or -not $Rectangle) { return }
    Clear-WindowRegion $Window
    if ($null -ne $Style) {
        [CogentStackWorkspaceWindows]::SetWindowStyle([IntPtr]$Window.Handle, [Int64]$Style)
        [CogentStackWorkspaceWindows]::SetWindowPos(
            [IntPtr]$Window.Handle,
            [IntPtr]::Zero,
            [int]$Rectangle.x,
            [int]$Rectangle.y,
            [int]$Rectangle.width,
            [int]$Rectangle.height,
            0x0020
        ) | Out-Null
    } else {
        Restore-Window $Window $Rectangle
    }
}

function Restore-CompanionLayout($State, [bool]$HideBackdrop, [bool]$RemoveState, [bool]$MaximizeBrowser = $false) {
    $rememberedChat = Find-RememberedWindow $State 'chatDesktop'
    $rememberedPanel = Find-RememberedWindow $State 'panel'
    $rememberedBackdrop = Find-RememberedWindow $State 'backdrop'
    if ($rememberedBackdrop) {
        if ($HideBackdrop) {
            [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$rememberedBackdrop.Handle, 0) | Out-Null
        } else {
            [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$rememberedBackdrop.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
    if ($State) {
        Restore-Window $rememberedChat $State.chatDesktopOriginal
        if ($State.PSObject.Properties['panelOriginal']) {
            $rememberedStyle = if ($State.PSObject.Properties['panelOriginalStyle']) { [Int64]$State.panelOriginalStyle } else { $null }
            Restore-BrowserWindow $rememberedPanel $State.panelOriginal $rememberedStyle
        }
    }
    $browserWindowMaximized = $false
    if ($MaximizeBrowser -and $rememberedPanel) {
        # SW_MAXIMIZE restores an ordinary framed browser window; it is not browser F11 fullscreen.
        [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$rememberedPanel.Handle, 3) | Out-Null
        $browserWindowMaximized = $true
    }
    if ($RemoveState -and (Test-Path -LiteralPath $statePath)) {
        Remove-Item -LiteralPath $statePath -Force
    }
    if ($rememberedPanel) {
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$rememberedPanel.Handle) | Out-Null
        [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$rememberedPanel.Handle) | Out-Null
    }
    return [ordered]@{
        browserWindowRestored = [bool]$rememberedPanel
        browserWindowMaximized = $browserWindowMaximized
        backdropFound = [bool]$rememberedBackdrop
    }
}

function Start-CompanionExitWatcher {
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $powershellPath = if ($powershellCommand) { [string]$powershellCommand.Source } else { $null }
    if (-not $powershellPath) { throw 'Windows PowerShell is required to monitor the CogentStack companion exit control.' }
    Start-Process -FilePath $powershellPath -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $PSCommandPath,
        '-Mode',
        'WatchExit'
    ) -WindowStyle Hidden -PassThru
}

function Test-WorkspaceLayout($Area, $ChatWindow, $PanelFrame, [int]$Gutter) {
    $chat = Get-VisibleWindowRectangle $ChatWindow.Handle
    $panel = $PanelFrame
    $chatRight = [int]$chat.x + [int]$chat.width
    $panelRight = [int]$panel.x + [int]$panel.width
    $areaRight = [int]$Area.x + [int]$Area.width
    $chatBottom = [int]$chat.y + [int]$chat.height
    $panelBottom = [int]$panel.y + [int]$panel.height
    $areaBottom = [int]$Area.y + [int]$Area.height
    $tolerance = 1
    $gapAligned = [Math]::Abs(($chatRight + $Gutter) - [int]$panel.x) -le $tolerance
    [ordered]@{
        verified = (
            [Math]::Abs([int]$chat.x - [int]$Area.x) -le $tolerance -and
            [Math]::Abs([int]$chat.y - [int]$Area.y) -le $tolerance -and
            $gapAligned -and
            [Math]::Abs([int]$panel.y - [int]$Area.y) -le $tolerance -and
            [Math]::Abs([int]$chat.width - [int]$panel.width) -le $tolerance -and
            [Math]::Abs($panelRight - $areaRight) -le $tolerance -and
            [Math]::Abs($chatBottom - $areaBottom) -le $tolerance -and
            [Math]::Abs($panelBottom - $areaBottom) -le $tolerance
        )
        joined = $Gutter -eq 0 -and $gapAligned
        separated = $Gutter -gt 0 -and $gapAligned
        equalWidth = [Math]::Abs([int]$chat.width - [int]$panel.width) -le $tolerance
        topAligned = [Math]::Abs([int]$chat.y - [int]$panel.y) -le $tolerance
        chat = $chat
        panel = $panel
    }
}

$state = Read-LayoutState
$browsers = @(Get-CompanionBrowsers)
$chatDesktopWindow = @(Get-ChatDesktopWindow | Select-Object -First 1)

if ($Mode -eq 'WatchExit') {
    $watcherMutex = New-Object System.Threading.Mutex($false, 'Local\CogentStackCompanionExitWatcher')
    $ownsMutex = $false
    try {
        $ownsMutex = $watcherMutex.WaitOne(0)
        if (-not $ownsMutex) { exit 0 }
        while ($true) {
            $watchState = Read-LayoutState
            if (-not $watchState) { break }
            $watchPanel = Find-RememberedWindow $watchState 'panel'
            if (-not $watchPanel) { break }
            if (Test-CompanionExitAddress (Get-BrowserAddressValue $watchPanel)) {
                Restore-CompanionLayout $watchState $false $true $true | Out-Null
                break
            }
            Start-Sleep -Milliseconds 250
        }
    } finally {
        if ($ownsMutex) { $watcherMutex.ReleaseMutex() }
        $watcherMutex.Dispose()
    }
    exit 0
}

if ($Mode -eq 'Inspect') {
    $existingPanel = @(Find-ExistingCogentStackWindow $browsers $false | Select-Object -First 1)
    Write-CompactJson ([ordered]@{
        status = 'inspected'
        platform = 'windows'
        chatDesktopWindowFound = [bool]$chatDesktopWindow
        existingCogentStackWindowFound = [bool]$existingPanel
        browserAvailable = $browsers.Count -gt 0
        browser = if ($existingPanel) { [string]$existingPanel.Browser.Name } elseif ($browsers.Count -gt 0) { [string]$browsers[0].Name } else { $null }
        registeredDefault = if ($existingPanel) { [bool]$existingPanel.Browser.IsRegisteredDefault } elseif ($browsers.Count -gt 0) { [bool]$browsers[0].IsRegisteredDefault } else { $false }
        launchMode = 'reuse-existing-browser-tab'
        browserContentMode = if ($state -and $state.PSObject.Properties['browserContentMode']) { [string]$state.browserContentMode } else { 'normal-window' }
        gutter = if ($state -and $state.PSObject.Properties['gutter']) { [int]$state.gutter } else { 0 }
        whiteBackdrop = [bool](Find-BackdropWindow)
    })
    exit 0
}

if ($Mode -in @('Hide', 'Close')) {
    $restore = Restore-CompanionLayout $state ($Mode -eq 'Hide') ($Mode -eq 'Close') $false
    Write-CompactJson ([ordered]@{
        status = $Mode.ToLowerInvariant()
        browserWindowRestored = [bool]$restore.browserWindowRestored
        browserWindowMaximized = [bool]$restore.browserWindowMaximized
        backdropFound = [bool]$restore.backdropFound
    })
    exit 0
}

$safeUrl = Confirm-CogentStackUrl $Url
if ($browsers.Count -eq 0) {
    Write-CompactJson ([ordered]@{
        status = 'browser_unavailable'
        message = 'Google Chrome or Microsoft Edge is required for the CogentStack companion workspace.'
    })
    exit 2
}

$panelSelection = @(Find-ExistingCogentStackWindow $browsers $true | Select-Object -First 1)
$openedNewTab = $false
if (-not $panelSelection) {
    $preferredBrowser = $browsers[0]
    Start-Process -FilePath $preferredBrowser.ExecutablePath -ArgumentList @($safeUrl) | Out-Null
    $openedNewTab = $true
    for ($attempt = 0; $attempt -lt 40 -and -not $panelSelection; $attempt++) {
        Start-Sleep -Milliseconds 250
        $panelSelection = @(Find-ExistingCogentStackWindow $browsers $true | Select-Object -First 1)
    }
}

if (-not $panelSelection) {
    Write-CompactJson ([ordered]@{
        status = 'opened_unarranged'
        message = 'CogentStack was opened in the normal browser, but its exact window could not be identified safely.'
    })
    exit 0
}

$panelWindow = $panelSelection.Window
$browser = $panelSelection.Browser
[CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$panelWindow.Handle, 9) | Out-Null
if (-not $chatDesktopWindow) {
    Write-CompactJson ([ordered]@{
        status = 'opened_unarranged'
        message = 'CogentStack is open in the normal browser. No active ChatGPT or Codex window was available for automatic layout.'
        browser = [string]$browser.Name
        accountState = [string]$panelSelection.AccountState
    })
    exit 0
}

$oldRememberedPanel = Find-RememberedWindow $state 'panel'
if ($state -and $state.PSObject.Properties['schemaVersion'] -and [int]$state.schemaVersion -lt 2 -and $oldRememberedPanel -and [Int64]$oldRememberedPanel.Handle -ne [Int64]$panelWindow.Handle) {
    [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$oldRememberedPanel.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

$chatOriginal = if ($state -and $state.PSObject.Properties['chatDesktopHandle'] -and [Int64]$state.chatDesktopHandle -eq [Int64]$chatDesktopWindow.Handle -and $state.PSObject.Properties['chatDesktopOriginal']) {
    $state.chatDesktopOriginal
} else {
    Get-WindowRectangle $chatDesktopWindow.Handle
}
$panelOriginal = if ($state -and $state.PSObject.Properties['panelHandle'] -and [Int64]$state.panelHandle -eq [Int64]$panelWindow.Handle -and $state.PSObject.Properties['panelOriginal']) {
    $state.panelOriginal
} else {
    Get-WindowRectangle $panelWindow.Handle
}
$panelOriginalStyle = if ($state -and $state.PSObject.Properties['panelHandle'] -and [Int64]$state.panelHandle -eq [Int64]$panelWindow.Handle -and $state.PSObject.Properties['panelOriginalStyle']) {
    [Int64]$state.panelOriginalStyle
} else {
    [CogentStackWorkspaceWindows]::GetWindowStyle([IntPtr]$panelWindow.Handle)
}

$area = Get-MonitorWorkingArea $chatDesktopWindow.Handle
$gutter = 12
$availableWidth = [int]$area.width - $gutter
$chatDesktopWidth = [Math]::Floor($availableWidth / 2)
$panelWidth = $availableWidth - $chatDesktopWidth
$panelX = [int]$area.x + $chatDesktopWidth + $gutter
$backdrop = Start-WhiteBackdrop $area

Move-VisibleDesktopWindow $chatDesktopWindow ([int]$area.x) ([int]$area.y) $chatDesktopWidth ([int]$area.height)
$pageOnly = $null
try {
    $resetManagedClip = (
        $state -and
        $state.PSObject.Properties['schemaVersion'] -and
        [int]$state.schemaVersion -ge 5 -and
        $state.PSObject.Properties['panelHandle'] -and
        [Int64]$state.panelHandle -eq [Int64]$panelWindow.Handle -and
        $state.PSObject.Properties['browserContentClipped'] -and
        [bool]$state.browserContentClipped
    )
    $pageOnly = Set-BrowserPageOnly $panelWindow $area $panelX $panelWidth $panelOriginalStyle ([bool]$resetManagedClip)
} catch {
    Restore-BrowserWindow $panelWindow $panelOriginal $panelOriginalStyle
    Restore-Window $chatDesktopWindow $chatOriginal
    if ($backdrop -and [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$backdrop.Handle)) {
        [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$backdrop.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    throw
}
[CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$chatDesktopWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
[CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$panelWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
[CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$panelWindow.Handle) | Out-Null
[CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$chatDesktopWindow.Handle) | Out-Null
[CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$chatDesktopWindow.Handle) | Out-Null
Start-Sleep -Milliseconds 200

$layout = Test-WorkspaceLayout $area $chatDesktopWindow $pageOnly.contentFrame $gutter
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
[ordered]@{
    schemaVersion = 5
    chatDesktopHandle = [Int64]$chatDesktopWindow.Handle
    chatDesktopProcessId = [int]$chatDesktopWindow.ProcessId
    chatDesktopOriginal = $chatOriginal
    panelHandle = [Int64]$panelWindow.Handle
    panelProcessId = [int]$panelWindow.ProcessId
    panelProcessName = [string]$panelWindow.ProcessName
    panelOriginal = $panelOriginal
    panelOriginalStyle = $panelOriginalStyle
    backdropHandle = [Int64]$backdrop.Handle
    backdropProcessId = [int]$backdrop.ProcessId
    browser = [string]$browser.Name
    browserContentMode = 'page-only'
    browserContentClipped = [bool]$pageOnly.contentClipped
    browserClipInsets = $pageOnly.clipInsets
    gutter = $gutter
    accountState = [string]$panelSelection.AccountState
    updatedAt = [DateTimeOffset]::UtcNow.ToString('O')
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

$exitWatcher = Start-CompanionExitWatcher

Write-CompactJson ([ordered]@{
    status = if ($layout.verified) { 'arranged' } else { 'opened_unarranged' }
    layout = 'equal-split-chatgpt-left-cogentstack-right'
    layoutVerified = [bool]$layout.verified
    joined = [bool]$layout.joined
    separated = [bool]$layout.separated
    equalWidth = [bool]$layout.equalWidth
    topAligned = [bool]$layout.topAligned
    splitPercent = 50
    gutter = $gutter
    whiteBackdrop = $true
    browserContentMode = 'page-only'
    browserChromeHidden = $true
    browserContentClipped = [bool]$pageOnly.contentClipped
    companionExitControl = 'header-x'
    companionExitWatcherStarted = [bool]$exitWatcher
    browserClipInsets = $pageOnly.clipInsets
    browser = [string]$browser.Name
    registeredDefault = [bool]$browser.IsRegisteredDefault
    reusedExistingTab = [bool]$panelSelection.ReusedExistingTab
    openedNewTab = $openedNewTab
    accountState = [string]$panelSelection.AccountState
    chatFrame = $layout.chat
    panelFrame = $layout.panel
    browserWindowFrame = $pageOnly.windowFrame
})
