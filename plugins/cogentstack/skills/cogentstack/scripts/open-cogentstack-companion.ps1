param(
    [ValidateSet('Inspect', 'Open', 'Hide', 'Close', 'Suspend', 'Resume', 'Toggle', 'InstallToggle', 'PrepareRuntime', 'WatchExit', 'CreateProjectWorker', 'PreviewProjectWorker')]
    [string]$Mode = 'Open',
    [string]$Url = 'https://cogentstack.app/stack?surface=chatgpt',
    [string]$RequestId = '',
    [string]$ContextKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'project-context.ps1')

function Write-CompactJson($Value) {
    $Value | ConvertTo-Json -Compress | Write-Output
}

function Enter-CompanionOpenMutex {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\CogentStackCompanionOpen')
    $ownsMutex = $false
    try {
        $ownsMutex = $mutex.WaitOne(30000)
    } catch [System.Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }
    if (-not $ownsMutex) {
        $mutex.Dispose()
        throw 'Another CogentStack launch is still selecting the shared workspace tab.'
    }
    return $mutex
}

function Exit-CompanionOpenMutex($Mutex) {
    if (-not $Mutex) { return }
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
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

function Get-CogentStackContextFromUrl([string]$Candidate) {
    $match = [regex]::Match($Candidate, '(?i)(?:[?&])context=([^&#]+)')
    if (-not $match.Success) { return 'default' }
    $value = [Uri]::UnescapeDataString($match.Groups[1].Value).ToLowerInvariant()
    if ($value -ne 'default' -and $value -notmatch '^ctx-[0-9a-f]{64}$') { throw 'The companion URL contains an invalid project context.' }
    return $value
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

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint command);

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

    [DllImport("kernel32.dll")]
    public static extern void SetLastError(uint errorCode);

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
    public static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);

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

    public static bool IsWindowAbove(IntPtr upper, IntPtr lower) {
        if (upper == IntPtr.Zero || lower == IntPtr.Zero || upper == lower) return false;
        var current = GetWindow(lower, 3);
        while (current != IntPtr.Zero) {
            if (current == upper) return true;
            current = GetWindow(current, 3);
        }
        return false;
    }

    public static long GetWindowStyle(IntPtr hWnd) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, -16).ToInt64() : GetWindowLong32(hWnd, -16).ToInt64();
    }

    public static void SetWindowStyle(IntPtr hWnd, long value) {
        if (IntPtr.Size == 8) SetWindowLongPtr64(hWnd, -16, new IntPtr(value));
        else SetWindowLong32(hWnd, -16, new IntPtr(value));
    }

    public static bool SetWindowOwner(IntPtr hWnd, IntPtr owner) {
        SetLastError(0);
        IntPtr previous = IntPtr.Size == 8 ? SetWindowLongPtr64(hWnd, -8, owner) : SetWindowLong32(hWnd, -8, owner);
        return previous != IntPtr.Zero || Marshal.GetLastWin32Error() == 0;
    }
}
'@
}

$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack'
$statePath = Join-Path $stateRoot 'chatgpt-companion-layout.json'
$bindingPath = Join-Path $stateRoot 'chatgpt-companion-contexts.json'
$backdropTitle = 'CogentStack Workspace Backdrop'
$dividerTitle = 'CogentStack Workspace Divider'

function Get-StableChatProjectKey([string]$ProjectName) {
    $normalized = $ProjectName.Trim().Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
    if (-not $normalized) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return 'chat-project-' + ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $hash.Dispose()
    }
}

function Get-StableChatProjectKeyFromContext([string]$ContextKey) {
    if ($ContextKey -notmatch '^ctx-([0-9a-f]{64})$') { return $null }
    return 'chat-context-' + $Matches[1]
}

function Get-ActiveChatProject($ChatWindow) {
    if (-not $ChatWindow -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$ChatWindow.Handle)) {
        return [ordered]@{ resolved = $false; reason = 'chat_window_unavailable' }
    }
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$ChatWindow.Handle)
        $buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)
        $projectNames = @()
        foreach ($button in $buttons) {
            if ([bool]$button.Current.IsOffscreen) { continue }
            $rectangle = $button.Current.BoundingRectangle
            if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { continue }
            $buttonName = [string]$button.Current.Name
            $match = [regex]::Match($buttonName, '^Project:\s*(.+)$')
            if ($match.Success) {
                $projectNames += $match.Groups[1].Value.Trim()
            }
        }
        $projectNames = @($projectNames | Sort-Object -Unique)
        if ($projectNames.Count -ne 1) {
            return [ordered]@{ resolved = $false; reason = if ($projectNames.Count -eq 0) { 'no_active_project' } else { 'ambiguous_active_project' } }
        }
        return [ordered]@{
            resolved = $true
            key = Get-StableChatProjectKey $projectNames[0]
            source = 'accessibility'
        }
    } catch {
        return [ordered]@{ resolved = $false; reason = 'project_accessibility_unavailable' }
    }
}

function Wait-ActiveChatProject($ChatWindow, [int]$Attempts = 16, [int]$DelayMilliseconds = 250) {
    $lastResult = [ordered]@{ resolved = $false; reason = 'no_active_project' }
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $lastResult = Get-ActiveChatProject $ChatWindow
        if ($lastResult.resolved) {
            $lastResult['attempts'] = $attempt + 1
            return $lastResult
        }
        if ($attempt + 1 -lt $Attempts) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }
    $lastResult['attempts'] = $Attempts
    return $lastResult
}

function Read-ContextBindings {
    if (-not (Test-Path -LiteralPath $bindingPath -PathType Leaf)) {
        return [ordered]@{ schemaVersion = 1; bindings = @() }
    }
    try {
        $registry = Get-Content -Raw -LiteralPath $bindingPath | ConvertFrom-Json
        if (-not $registry.PSObject.Properties['bindings']) { throw 'missing bindings' }
        return $registry
    } catch {
        return [ordered]@{ schemaVersion = 1; bindings = @() }
    }
}

function Find-ContextBinding([string]$ProjectKey) {
    if (-not $ProjectKey) { return $null }
    $registry = Read-ContextBindings
    @($registry.bindings | Where-Object {
        $_.PSObject.Properties['projectKey'] -and [string]$_.projectKey -eq $ProjectKey -and
        $_.PSObject.Properties['workspaceUrl'] -and $_.PSObject.Properties['contextKey']
    } | Select-Object -First 1)
}

function Find-ContextBindingByContext([string]$ContextKey) {
    if (-not $ContextKey) { return $null }
    $registry = Read-ContextBindings
    @($registry.bindings | Where-Object {
        $_.PSObject.Properties['projectKey'] -and
        $_.PSObject.Properties['workspaceUrl'] -and
        $_.PSObject.Properties['contextKey'] -and
        [string]$_.contextKey -eq $ContextKey
    } | Sort-Object @{ Expression = {
        if ($_.PSObject.Properties['updatedAt']) { [string]$_.updatedAt } else { '' }
    }; Descending = $true } | Select-Object -First 1)
}

function Resolve-ChatProjectForOpen($VisibleProject, $HostProjectContext, [string]$RequestedContextKey, $RememberedContextBinding, $VisibleProjectBinding) {
    if ([bool]$HostProjectContext.Isolated -and [string]$HostProjectContext.ContextKey -ne $RequestedContextKey) {
        return [pscustomobject][ordered]@{
            project = [ordered]@{
                resolved = $false
                reason = 'project_context_conflict'
                attempts = if ($VisibleProject.Contains('attempts')) { [int]$VisibleProject.attempts } else { 1 }
            }
            stableContextFallbackUsed = $false
            stableContextBindingPending = $false
        }
    }
    if ($VisibleProject.resolved) {
        $visibleBindingConflicts = [bool](
            [bool]$HostProjectContext.Isolated -and
            $VisibleProjectBinding -and
            [string]$VisibleProjectBinding.contextKey -ne 'default' -and
            [string]$VisibleProjectBinding.contextKey -ne $RequestedContextKey
        )
        $requestedBindingConflicts = [bool](
            [bool]$HostProjectContext.Isolated -and
            $RememberedContextBinding -and
            [string]$RememberedContextBinding.projectKey -ne [string]$VisibleProject.key
        )
        if ($visibleBindingConflicts -or $requestedBindingConflicts) {
            return [pscustomobject][ordered]@{
                project = [ordered]@{
                    resolved = $false
                    reason = 'project_context_conflict'
                    attempts = if ($VisibleProject.Contains('attempts')) { [int]$VisibleProject.attempts } else { 1 }
                }
                stableContextFallbackUsed = $false
                stableContextBindingPending = $false
            }
        }
        return [pscustomobject][ordered]@{
            project = $VisibleProject
            stableContextFallbackUsed = $false
            stableContextBindingPending = $false
        }
    }
    if (-not [bool]$HostProjectContext.Isolated -or [string]$HostProjectContext.ContextKey -ne $RequestedContextKey) {
        return [pscustomobject][ordered]@{
            project = $VisibleProject
            stableContextFallbackUsed = $false
            stableContextBindingPending = $false
        }
    }
    $fallbackProjectKey = if ($RememberedContextBinding) {
        [string]$RememberedContextBinding.projectKey
    } else {
        Get-StableChatProjectKeyFromContext $RequestedContextKey
    }
    if (-not $fallbackProjectKey) {
        return [pscustomobject][ordered]@{
            project = $VisibleProject
            stableContextFallbackUsed = $false
            stableContextBindingPending = $false
        }
    }
    return [pscustomobject][ordered]@{
        project = [ordered]@{
            resolved = $true
            key = $fallbackProjectKey
            source = if ($RememberedContextBinding) { 'remembered-context-binding' } else { 'stable-project-context' }
            attempts = if ($VisibleProject.Contains('attempts')) { [int]$VisibleProject.attempts } else { 1 }
        }
        stableContextFallbackUsed = $true
        stableContextBindingPending = -not [bool]$RememberedContextBinding
    }
}

function Save-ContextBinding([string]$ProjectKey, [string]$ContextKey, [string]$WorkspaceUrl) {
    if (-not $ProjectKey) { throw 'The active ChatGPT Project identity is unavailable.' }
    $safeWorkspaceUrl = Confirm-CogentStackUrl $WorkspaceUrl
    if ((Get-CogentStackContextFromUrl $safeWorkspaceUrl) -ne $ContextKey) {
        throw 'The ChatGPT Project binding does not match the CogentStack context.'
    }
    $registry = Read-ContextBindings
    $bindings = @($registry.bindings | Where-Object {
        -not $_.PSObject.Properties['projectKey'] -or [string]$_.projectKey -ne $ProjectKey
    })
    $bindings += [ordered]@{
        projectKey = $ProjectKey
        contextKey = $ContextKey
        workspaceUrl = $safeWorkspaceUrl
        updatedAt = [DateTimeOffset]::UtcNow.ToString('O')
    }
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [ordered]@{ schemaVersion = 1; bindings = $bindings } |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $bindingPath -Encoding UTF8
}

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

function Set-WindowContentRegion($Window, $DocumentRectangle, [bool]$PreserveOffscreenTop = $false) {
    $windowRectangle = Get-WindowRectangle $Window.Handle
    if (-not $windowRectangle) { throw 'Windows could not measure the browser before applying its content crop.' }

    $left = [int]$DocumentRectangle.x - [int]$windowRectangle.x
    $documentTop = [int]$DocumentRectangle.y - [int]$windowRectangle.y
    # Browser controls are already positioned above the monitor. Keeping the
    # region's top at the real window top prevents a later Chrome accessibility
    # reflow from clipping the CogentStack banner and its exit control.
    $top = if ($PreserveOffscreenTop) { 0 } else { $documentTop }
    $right = $left + [int]$DocumentRectangle.width
    $bottom = $documentTop + [int]$DocumentRectangle.height
    if ($documentTop -lt 0 -or $left -lt 0 -or $top -lt 0 -or $right -le $left -or $bottom -le $top -or $right -gt [int]$windowRectangle.width -or $bottom -gt [int]$windowRectangle.height) {
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
    # Electron can change its DWM frame after leaving maximized state. Correct
    # against the post-move visible rectangle so the divider starts at the real
    # ChatGPT edge instead of being covered by its newly sized frame.
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $visible = Get-VisibleWindowRectangle $Window.Handle
        if (-not $visible) { break }
        $dx = $X - [int]$visible.x
        $dy = $Y - [int]$visible.y
        $dw = $Width - [int]$visible.width
        $dh = $Height - [int]$visible.height
        if ([Math]::Abs($dx) -le 1 -and [Math]::Abs($dy) -le 1 -and [Math]::Abs($dw) -le 1 -and [Math]::Abs($dh) -le 1) { break }
        $raw = Get-WindowRectangle $Window.Handle
        if (-not $raw) { break }
        Move-DesktopWindow $Window `
            ([int]$raw.x + $dx) `
            ([int]$raw.y + $dy) `
            ([int]$raw.width + $dw) `
            ([int]$raw.height + $dh)
    }
}

function Read-LayoutState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { return $null }
}

function Save-LayoutState($State) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Set-LayoutStateStatus($State, [string]$Status) {
    $State | Add-Member -MemberType NoteProperty -Name layoutStatus -Value $Status -Force
    $State | Add-Member -MemberType NoteProperty -Name updatedAt -Value ([DateTimeOffset]::UtcNow.ToString('O')) -Force
    Save-LayoutState $State
}

function Find-RememberedWindow($State, [string]$Kind) {
    if ($null -eq $State) { return $null }
    $handleProperty = switch ($Kind) {
        'panel' { 'panelHandle' }
        'backdrop' { 'backdropHandle' }
        'divider' { 'dividerHandle' }
        default { 'chatDesktopHandle' }
    }
    $processProperty = switch ($Kind) {
        'panel' { 'panelProcessId' }
        'backdrop' { 'backdropProcessId' }
        'divider' { 'dividerProcessId' }
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

function Wait-AccountState($Window, [int]$Attempts = 20) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $accountState = Get-AccountState $Window
        if ($accountState -ne 'unknown') { return $accountState }
        Start-Sleep -Milliseconds 250
    }
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

function ConvertTo-CogentStackUri([string]$Address) {
    if (-not $Address) { return $null }
    $candidate = $Address.Trim()
    if ($candidate -notmatch '^[a-z][a-z0-9+.-]*://') { $candidate = "https://$candidate" }
    $parsed = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$parsed)) { return $null }
    if ($parsed.Scheme -notin @('http', 'https') -or $parsed.Host -notin @('cogentstack.app', 'www.cogentstack.app')) { return $null }
    return $parsed
}

function Test-CogentStackAddress([string]$Address) {
    return $null -ne (ConvertTo-CogentStackUri $Address)
}

function Test-CogentStackWorkspaceAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    return $null -ne $parsed -and $parsed.AbsolutePath -eq '/stack'
}

function Test-CogentStackHomeAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    return $null -ne $parsed -and $parsed.AbsolutePath -eq '/'
}

function Test-CogentStackTerminalInstallAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath -notin @('/install', '/claude')) { return $false }
    return $parsed.Query -match '(?i)(?:^|[?&])installation_state=(?:completed|superseded)(?:&|$)'
}

function Select-BrowserTabCandidate($Candidate) {
    if (-not $Candidate) { return $false }
    if (-not $Candidate.PSObject.Properties['Tab'] -or -not $Candidate.Tab) { return $true }
    if ($Candidate.PSObject.Properties['IsSelected'] -and [bool]$Candidate.IsSelected) { return $true }
    try {
        $selectionPattern = $null
        if (-not $Candidate.Tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) { return $false }
        ([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Select()
        Start-Sleep -Milliseconds 350
        if ($Candidate.PSObject.Properties['IsSelected']) { $Candidate.IsSelected = $true }
        if ($Candidate.PSObject.Properties['Activated']) { $Candidate.Activated = $true }
        return $true
    } catch {
        return $false
    }
}

function Restore-BrowserTabSelection($Tab) {
    if (-not $Tab) { return }
    try {
        $selectionPattern = $null
        if ($Tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
            ([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Select()
            Start-Sleep -Milliseconds 150
        }
    } catch {}
}

function Confirm-BrowserTabCandidate($Candidate) {
    if (-not $Candidate) { return $false }
    if (-not (Select-BrowserTabCandidate $Candidate)) { return $false }
    $addressValue = Get-BrowserAddressValue $Candidate.Window
    $addressMatches = (
        ([bool]$Candidate.IsWorkspace -and (Test-CogentStackWorkspaceAddress $addressValue)) -or
        ([bool]$Candidate.IsHome -and (Test-CogentStackHomeAddress $addressValue))
    )
    if (-not $addressMatches) {
        if ($Candidate.PSObject.Properties['OriginalSelectedTab'] -and $Candidate.OriginalSelectedTab -and
            (-not $Candidate.PSObject.Properties['Tab'] -or $Candidate.OriginalSelectedTab -ne $Candidate.Tab)) {
            Restore-BrowserTabSelection $Candidate.OriginalSelectedTab
        }
        return $false
    }
    $Candidate.Address = $addressValue
    $Candidate.AccountState = Wait-AccountState $Candidate.Window 8
    return $true
}

function Set-BrowserWorkspaceAddress($Window, [string]$TargetUrl) {
    try {
        $targetContextKey = Get-CogentStackContextFromUrl (Confirm-CogentStackUrl $TargetUrl)
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $addressCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            'Address and search bar'
        )
        $address = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $addressCondition)
        if (-not $address) { return $false }
        $valuePattern = $null
        if (-not $address.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) { return $false }
        [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$Window.Handle) | Out-Null
        [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$Window.Handle) | Out-Null
        $address.SetFocus()
        ([System.Windows.Automation.ValuePattern]$valuePattern).SetValue($TargetUrl)
        Start-Sleep -Milliseconds 100
        [CogentStackWorkspaceWindows]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero)
        [CogentStackWorkspaceWindows]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero)
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            Start-Sleep -Milliseconds 250
            $currentAddress = Get-BrowserAddressValue $Window
            if (
                (Test-CogentStackWorkspaceAddress $currentAddress) -and
                (Get-CogentStackContextFromUrl $currentAddress) -eq $targetContextKey -and
                (Get-WebDocumentRectangle $Window)
            ) {
                return $true
            }
        }
    } catch {}
    return $false
}

function Test-CompanionExitAddress([string]$Address) {
    if (-not $Address) { return $false }
    return $Address -match '^(?:https?://)?(?:www\.)?cogentstack\.app/?(?:\?companion=close(?:#.*)?)?$'
}

function Test-CompanionSuspendAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath -ne '/stack') { return $false }
    return $parsed.Query -match '(?i)(?:^|[?&])companion=suspend(?:&|$)'
}

function Test-CompanionResumeAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath -ne '/stack') { return $false }
    return $parsed.Query -match '(?i)(?:^|[?&])companion=resume(?:&|$)'
}

function Test-CompanionProjectDeletionAddress([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    return $null -ne $parsed -and
        $parsed.AbsolutePath.TrimEnd('/') -eq '/stack' -and
        $parsed.Query -match '(?i)(?:^|[?&])desktop_action=delete_project(?:&|$)'
}

function Get-CompanionProjectDeletionRequestId([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath.TrimEnd('/') -ne '/stack' -or
        $parsed.Query -notmatch '(?i)(?:^|[?&])desktop_action=delete_project(?:&|$)') {
        return ''
    }
    $requestMatch = [regex]::Match($parsed.Query, '(?i)(?:^|[?&])desktop_request=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:&|$)')
    if (-not $requestMatch.Success) { return '' }
    return $requestMatch.Groups[1].Value.ToLowerInvariant()
}

function Get-CompanionProjectCreationRequestId([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath.TrimEnd('/') -ne '/stack' -or
        $parsed.Query -notmatch '(?i)(?:^|[?&])desktop_action=create_project(?:&|$)') {
        return ''
    }
    $requestMatch = [regex]::Match($parsed.Query, '(?i)(?:^|[?&])desktop_request=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:&|$)')
    if (-not $requestMatch.Success) { return '' }
    return $requestMatch.Groups[1].Value.ToLowerInvariant()
}

function Get-CompanionProjectPreviewRequestId([string]$Address) {
    $parsed = ConvertTo-CogentStackUri $Address
    if ($null -eq $parsed -or $parsed.AbsolutePath.TrimEnd('/') -ne '/stack' -or
        $parsed.Query -notmatch '(?i)(?:^|[?&])desktop_action=preview_project(?:&|$)') {
        return ''
    }
    $requestMatch = [regex]::Match($parsed.Query, '(?i)(?:^|[?&])desktop_request=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:&|$)')
    if (-not $requestMatch.Success) { return '' }
    return $requestMatch.Groups[1].Value.ToLowerInvariant()
}

function Test-CompanionOwnedAddress([string]$Address) {
    if (-not $Address) { return $false }
    return Test-CogentStackAddress $Address
}

function Select-RememberedCogentStackWorkspaceTab($Window) {
    if (Test-CogentStackWorkspaceAddress (Get-BrowserAddressValue $Window)) { return $true }
    $workspaceCandidates = @(Get-CogentStackTabCandidates $Window $null | Where-Object { $_.IsWorkspace })
    $candidate = @($workspaceCandidates | Where-Object { $_.IsSelected } | Select-Object -First 1)
    if (-not $candidate) { $candidate = @($workspaceCandidates | Select-Object -First 1) }
    if (-not $candidate) { return $false }
    return Confirm-BrowserTabCandidate $candidate
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
            if (-not (Test-CogentStackWorkspaceTitle ([string]$document.Current.Name))) { continue }
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

function Get-CogentStackHeaderAnchorRectangle($Window) {
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $nameCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            'CogentStack home'
        )
        $anchors = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCondition)
        foreach ($anchor in $anchors) {
            if ($anchor.Current.ControlType -ne [System.Windows.Automation.ControlType]::Hyperlink) { continue }
            $rectangle = $anchor.Current.BoundingRectangle
            if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { continue }
            return [ordered]@{
                x = [int][Math]::Round($rectangle.X)
                y = [int][Math]::Round($rectangle.Y)
                width = [int][Math]::Round($rectangle.Width)
                height = [int][Math]::Round($rectangle.Height)
                offscreen = [bool]$anchor.Current.IsOffscreen
            }
        }
    } catch {}
    return $null
}

function Test-CogentStackHeaderVisible($Window, $Area) {
    $anchor = Get-CogentStackHeaderAnchorRectangle $Window
    if (-not $anchor -or $anchor.offscreen) { return $false }
    $anchorBottom = [int]$anchor.y + [int]$anchor.height
    $headerBandBottom = [int]$Area.y + [Math]::Min(180, [int]$Area.height)
    return [int]$anchor.y -ge [int]$Area.y -and $anchorBottom -le $headerBandBottom
}

function Wait-CogentStackHeaderVisible($Window, $Area, [int]$Attempts = 30) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        if (Test-CogentStackHeaderVisible $Window $Area) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return Test-CogentStackHeaderVisible $Window $Area
}

function Test-CogentStackWorkspaceTitle([string]$Title) {
    return [bool]($Title -match '(?i)^CogentStack \| Create or (?:edit|open) a project(?:\s+-\s+Memory usage.*)?$')
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
    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Window.Handle, 9) | Out-Null
    Start-Sleep -Milliseconds 150
    Move-VisibleDesktopWindow $Window $PanelX ([int]$Area.y) $PanelWidth ([int]$Area.height)
    [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$Window.Handle) | Out-Null
    [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$Window.Handle) | Out-Null
    $documentBefore = Wait-WebDocumentRectangle $Window {
        param($rectangle)
        [Math]::Abs([int]$rectangle.width - $PanelWidth) -le 64
    }
    $visibleBefore = Get-VisibleWindowRectangle $Window.Handle
    if (-not $documentBefore -or -not $visibleBefore) {
        throw 'Windows could not remeasure the CogentStack document before entering page-only mode.'
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
    $measuredTopInset = [Math]::Max(0, [int]$documentProbe.y - [int]$visibleProbe.y)
    # The UI Automation document can briefly resolve to the workspace scroll
    # region below the CogentStack header. Preserve the browser-chrome height
    # measured before removing the frame so that transient result cannot crop
    # the banner out of the page-only panel.
    $topInset = if ($normalChromeHeight -gt 0) { $normalChromeHeight } else { $measuredTopInset }
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
    $clipInsets = Set-WindowContentRegion $Window $documentFinal $true
    [ordered]@{
        originalStyle = $OriginalStyle
        appliedStyle = $borderlessStyle
        chromeInsets = [ordered]@{ left = $leftInset; top = $topInset; right = $rightInset; bottom = $bottomInset }
        clipInsets = $clipInsets
        topCropRemoved = [bool]($clipInsets.top -eq 0)
        contentClipped = $true
        contentFrame = $documentFinal
        windowFrame = Get-VisibleWindowRectangle $Window.Handle
    }
}

function Get-CogentStackTabCandidates($Window, $Browser) {
    $results = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window.Handle)
        $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
        $originalSelectedTab = $null
        foreach ($tab in $tabs) {
            try {
                $selectionPattern = $null
                if ($tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern) -and
                    ([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Current.IsSelected) {
                    $originalSelectedTab = $tab
                    break
                }
            } catch {}
        }
        foreach ($tab in $tabs) {
            $tabName = [string]$tab.Current.Name
            $isWorkspaceTitle = Test-CogentStackWorkspaceTitle $tabName
            $isHomeTitle = $tabName -match '(?i)^CogentStack \| AI Production Stack(?:\s+-\s+Memory usage.*)?$'
            if (-not $isWorkspaceTitle -and -not $isHomeTitle) { continue }
            $isSelected = $false
            try {
                $selectionPattern = $null
                if ($tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
                    $isSelected = [bool]([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Current.IsSelected
                }
            } catch {}
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                Tab = $tab
                TabName = $tabName
                OriginalSelectedTab = $originalSelectedTab
                IsSelected = $isSelected
                Activated = $false
                AccountState = 'unknown'
                Address = ''
                IsWorkspace = $isWorkspaceTitle
                IsHome = $isHomeTitle
                ReusedExistingTab = $true
                HasTabStrip = $true
            }
        }
        if ($results.Count -eq 0 -and (Test-CogentStackWorkspaceTitle ([string]$Window.Title))) {
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                Tab = $null
                TabName = [string]$Window.Title
                OriginalSelectedTab = $originalSelectedTab
                IsSelected = $true
                Activated = $false
                AccountState = 'unknown'
                Address = ''
                IsWorkspace = $true
                IsHome = $false
                ReusedExistingTab = $true
                HasTabStrip = $tabs.Count -gt 0
            }
        }
    } catch {
        if (Test-CogentStackWorkspaceTitle ([string]$Window.Title)) {
            $results += [pscustomobject]@{
                Window = $Window
                Browser = $Browser
                Tab = $null
                TabName = [string]$Window.Title
                OriginalSelectedTab = $null
                IsSelected = $true
                Activated = $false
                AccountState = 'unknown'
                Address = ''
                IsWorkspace = $true
                IsHome = $false
                ReusedExistingTab = $true
                HasTabStrip = $false
            }
        }
    }
    @($results)
}

function Find-ExistingCogentStackWindow($Browsers) {
    $candidates = @()
    $desktopWindows = @(Get-DesktopWindows)
    foreach ($candidateBrowser in $Browsers) {
        foreach ($browserWindow in @($desktopWindows | Where-Object { $_.ProcessName -eq $candidateBrowser.ProcessName })) {
            $candidates += @(Get-CogentStackTabCandidates $browserWindow $candidateBrowser)
        }
    }
    $selectedWorkspace = @($candidates | Where-Object { $_.IsWorkspace -and $_.IsSelected } | Select-Object -First 1)
    if ($selectedWorkspace) { return $selectedWorkspace }
    $workspaceWindow = @($candidates | Where-Object { $_.IsWorkspace } | Select-Object -First 1)
    if ($workspaceWindow) { return $workspaceWindow }
    $selectedHome = @($candidates | Where-Object { $_.IsHome -and $_.IsSelected } | Select-Object -First 1)
    if ($selectedHome) { return $selectedHome }
    $homeWindow = @($candidates | Where-Object { $_.IsHome } | Select-Object -First 1)
    if ($homeWindow) { return $homeWindow }
    return $null
}

function Find-BackdropWindow {
    @(Get-DesktopWindows | Where-Object { $_.Title -eq $backdropTitle -and $_.ProcessName -match '(?i)^(powershell|pwsh)$' } | Select-Object -First 1)
}

function Find-DividerWindow {
    @(Get-DesktopWindows | Where-Object { $_.Title -eq $dividerTitle -and $_.ProcessName -match '(?i)^(powershell|pwsh)$' } | Select-Object -First 1)
}

function Set-WhiteBackdropLayer($Backdrop, $BehindWindow) {
    if (-not $Backdrop -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$Backdrop.Handle) -or
        -not $BehindWindow -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$BehindWindow.Handle)) {
        throw 'The white CogentStack workspace background is unavailable.'
    }
    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Backdrop.Handle, 5) | Out-Null
    # Some DWM configurations keep a borderless form in the desktop's lower band.
    # Promote then demote it, and finally anchor it immediately behind the Codex
    # window. This leaves both companion panels above it and the wallpaper below it.
    $promoted = [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$Backdrop.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
    $demoted = [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$Backdrop.Handle, [IntPtr](-2), 0, 0, 0, 0, 0x0013)
    $anchored = [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$Backdrop.Handle, [IntPtr]$BehindWindow.Handle, 0, 0, 0, 0, 0x0013)
    if (-not $promoted -or -not $demoted -or -not $anchored) {
        throw 'Windows could not place the white CogentStack background behind the workspace panels.'
    }
}

function Test-WorkspacePanelsAboveBackdrop($Backdrop, $ChatWindow, $PanelWindow) {
    $chatAboveBackdrop = [bool](
        $Backdrop -and $ChatWindow -and
        [CogentStackWorkspaceWindows]::IsWindowAbove([IntPtr]$ChatWindow.Handle, [IntPtr]$Backdrop.Handle)
    )
    $panelAboveBackdrop = [bool](
        $Backdrop -and $PanelWindow -and
        [CogentStackWorkspaceWindows]::IsWindowAbove([IntPtr]$PanelWindow.Handle, [IntPtr]$Backdrop.Handle)
    )
    [ordered]@{
        verified = $chatAboveBackdrop -and $panelAboveBackdrop
        chatAboveBackdrop = $chatAboveBackdrop
        panelAboveBackdrop = $panelAboveBackdrop
    }
}

function Start-WhiteBackdrop($Area, $BehindWindow) {
    $existing = @(Find-BackdropWindow | Select-Object -First 1)
    if ($existing) {
        Move-DesktopWindow $existing ([int]$Area.x) ([int]$Area.y) ([int]$Area.width) ([int]$Area.height)
        Set-WhiteBackdropLayer $existing $BehindWindow
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
    Set-WhiteBackdropLayer $backdrop $BehindWindow
    return $backdrop
}

function Get-WhiteDividerArea($Area, [int]$LeftWidth, [int]$Gutter) {
    if ($Gutter -le 0) { throw 'The CogentStack divider requires a positive gutter.' }
    [ordered]@{
        x = [int]$Area.x + $LeftWidth
        y = [int]$Area.y
        width = $Gutter
        height = [int]$Area.height
    }
}

function Set-WhiteDividerLayer($Divider, $ChatWindow, $PanelWindow) {
    if (-not $Divider -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$Divider.Handle)) {
        throw 'The white CogentStack divider is unavailable.'
    }
    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$Divider.Handle, 5) | Out-Null
    if (-not $ChatWindow -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$ChatWindow.Handle) -or
        -not $PanelWindow -or -not [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$PanelWindow.Handle)) {
        throw 'The companion panels are unavailable for divider placement.'
    }
    # Make the passive divider an owned window of the CogentStack browser. An
    # owned window stays above its owner and its DWM shadow, but is not globally
    # topmost, so unrelated foreground windows still cover it normally.
    $owned = [CogentStackWorkspaceWindows]::SetWindowOwner([IntPtr]$Divider.Handle, [IntPtr]$PanelWindow.Handle)
    $anchored = [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$Divider.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013)
    if (-not $owned -or -not $anchored) {
        throw 'Windows could not anchor the CogentStack divider between the companion panels.'
    }
}

function Start-WhiteDivider($Area, $ChatWindow, $PanelWindow) {
    $existing = @(Find-DividerWindow | Select-Object -First 1)
    if ($existing) {
        Move-DesktopWindow $existing ([int]$Area.x) ([int]$Area.y) ([int]$Area.width) ([int]$Area.height)
        Set-WhiteDividerLayer $existing $ChatWindow $PanelWindow
        return $existing
    }

    $dividerScript = @"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CogentStackDividerWindow {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern IntPtr GetWindowLong32(IntPtr hWnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern IntPtr SetWindowLong32(IntPtr hWnd, int index, IntPtr value);
    public static void MakePassive(IntPtr hWnd) {
        const int GWL_EXSTYLE = -20;
        const long WS_EX_TRANSPARENT = 0x00000020L;
        const long WS_EX_TOOLWINDOW = 0x00000080L;
        const long WS_EX_NOACTIVATE = 0x08000000L;
        long style = IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, GWL_EXSTYLE).ToInt64() : GetWindowLong32(hWnd, GWL_EXSTYLE).ToInt64();
        IntPtr value = new IntPtr(style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
        if (IntPtr.Size == 8) SetWindowLongPtr64(hWnd, GWL_EXSTYLE, value);
        else SetWindowLong32(hWnd, GWL_EXSTYLE, value);
    }
}
'@
[CogentStackDividerWindow]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = '$dividerTitle'
`$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
`$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
`$form.Bounds = New-Object System.Drawing.Rectangle($([int]$Area.x), $([int]$Area.y), $([int]$Area.width), $([int]$Area.height))
`$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
`$form.BackColor = [System.Drawing.Color]::White
`$desktopEdge = New-Object System.Windows.Forms.Panel
`$desktopEdge.Name = 'CogentStackDesktopEdge'
`$desktopEdge.Dock = [System.Windows.Forms.DockStyle]::Left
`$desktopEdge.Width = 2
`$desktopEdge.BackColor = [System.Drawing.Color]::FromArgb(205, 205, 205)
`$form.Controls.Add(`$desktopEdge)
`$panelEdge = New-Object System.Windows.Forms.Panel
`$panelEdge.Name = 'CogentStackPanelEdge'
`$panelEdge.Dock = [System.Windows.Forms.DockStyle]::Right
`$panelEdge.Width = 2
`$panelEdge.BackColor = [System.Drawing.Color]::FromArgb(205, 205, 205)
`$form.Controls.Add(`$panelEdge)
`$form.ShowInTaskbar = `$false
`$form.ShowIcon = `$false
`$form.TopMost = `$false
[CogentStackDividerWindow]::MakePassive(`$form.Handle)
[System.Windows.Forms.Application]::Run(`$form)
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dividerScript))
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $powershellPath = if ($powershellCommand) { [string]$powershellCommand.Source } else { $null }
    if (-not $powershellPath) { throw 'Windows PowerShell is required to display the white CogentStack divider.' }
    $dividerProcess = Start-Process -FilePath $powershellPath -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) -WindowStyle Hidden -PassThru
    $divider = $null
    for ($attempt = 0; $attempt -lt 30 -and -not $divider; $attempt++) {
        Start-Sleep -Milliseconds 100
        $divider = @(Get-DesktopWindows | Where-Object { $_.ProcessId -eq $dividerProcess.Id -and $_.Title -eq $dividerTitle } | Select-Object -First 1)
    }
    if (-not $divider) { throw 'Windows could not create the white CogentStack divider.' }
    Move-DesktopWindow $divider ([int]$Area.x) ([int]$Area.y) ([int]$Area.width) ([int]$Area.height)
    Set-WhiteDividerLayer $divider $ChatWindow $PanelWindow
    return $divider
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
    $rememberedDivider = Find-RememberedWindow $State 'divider'
    if (-not $rememberedDivider) { $rememberedDivider = @(Find-DividerWindow | Select-Object -First 1) }
    if (-not $rememberedBackdrop) { $rememberedBackdrop = @(Find-BackdropWindow | Select-Object -First 1) }
    if ($rememberedDivider) {
        if ($HideBackdrop) {
            [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$rememberedDivider.Handle, 0) | Out-Null
        } else {
            [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$rememberedDivider.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
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
        dividerFound = [bool]$rememberedDivider
    }
}

function Reset-OrphanedCompanionLayout($ChatWindow, $PanelWindow) {
    $orphanBackdrop = @(Find-BackdropWindow | Select-Object -First 1)
    $orphanDivider = @(Find-DividerWindow | Select-Object -First 1)
    $panelRectangle = if ($PanelWindow) { Get-WindowRectangle $PanelWindow.Handle } else { $null }
    $workingArea = if ($ChatWindow) { Get-MonitorWorkingArea $ChatWindow.Handle } else { $null }
    $orphanPageOnly = [bool](
        $panelRectangle -and $workingArea -and
        [int]$panelRectangle.y -lt ([int]$workingArea.y - 64)
    )
    if (-not $orphanBackdrop -and -not $orphanDivider -and -not $orphanPageOnly) { return $false }
    if ($orphanDivider) {
        [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$orphanDivider.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    if ($orphanBackdrop) {
        [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$orphanBackdrop.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    if ($PanelWindow) {
        Clear-WindowRegion $PanelWindow
        [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$PanelWindow.Handle, 3) | Out-Null
    }
    if ($ChatWindow) {
        [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$ChatWindow.Handle, 3) | Out-Null
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$ChatWindow.Handle) | Out-Null
        [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$ChatWindow.Handle) | Out-Null
    }
    Start-Sleep -Milliseconds 200
    return $true
}

function Install-WorkModeShortcut {
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) { return $null }
    $programs = [Environment]::GetFolderPath('Programs')
    if (-not $programs) { return $null }
    $shortcutRoot = Join-Path $programs 'CogentStack'
    $shortcutPath = Join-Path $shortcutRoot 'CogentStack Work Mode (Codex).lnk'
    New-Item -ItemType Directory -Path $shortcutRoot -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = [string]$powershellCommand.Source
    $shortcut.Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode Toggle"
    $shortcut.WorkingDirectory = Split-Path -Parent $PSCommandPath
    $shortcut.Description = 'Suspend or resume the existing CogentStack and Codex split-screen work mode.'
    $shortcut.Save()
    return $shortcutPath
}

function Suspend-CompanionLayout($State, [bool]$MaximizeBrowser = $true, [string]$Reason = 'manual', [bool]$ActivateChat = $false) {
    if (-not $State) {
        return [ordered]@{ status = 'cold_start_required'; suspended = $false; fastResumeAvailable = $false }
    }
    $chatWindow = Find-RememberedWindow $State 'chatDesktop'
    $panelWindow = Find-RememberedWindow $State 'panel'
    if (-not $chatWindow -or -not $panelWindow) {
        if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
        return [ordered]@{ status = 'cold_start_required'; suspended = $false; fastResumeAvailable = $false }
    }
    $restore = Restore-CompanionLayout $State $true $false $MaximizeBrowser
    $State | Add-Member -MemberType NoteProperty -Name browserContentMode -Value 'normal-window' -Force
    $State | Add-Member -MemberType NoteProperty -Name browserContentClipped -Value $false -Force
    $State | Add-Member -MemberType NoteProperty -Name suspendReason -Value $Reason -Force
    $State | Add-Member -MemberType NoteProperty -Name suspendedAt -Value ([DateTimeOffset]::UtcNow.ToString('O')) -Force
    Set-LayoutStateStatus $State 'suspended'
    if ($ActivateChat -and $chatWindow) {
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$chatWindow.Handle) | Out-Null
        [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$chatWindow.Handle) | Out-Null
    }
    $watcher = Start-CompanionExitWatcher
    return [ordered]@{
        status = 'suspended'
        suspended = $true
        fastResumeAvailable = $true
        browserWindowRestored = [bool]$restore.browserWindowRestored
        browserWindowMaximized = [bool]$restore.browserWindowMaximized
        companionWatcherStarted = [bool]$watcher
        shortcut = Install-WorkModeShortcut
    }
}

function Resume-CompanionLayout($State) {
    if (-not $State) {
        return [ordered]@{ status = 'cold_start_required'; resumed = $false; fastResumeAvailable = $false }
    }
    $chatWindow = Find-RememberedWindow $State 'chatDesktop'
    $panelWindow = Find-RememberedWindow $State 'panel'
    if (-not $chatWindow -or -not $panelWindow) {
        if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
        return [ordered]@{ status = 'cold_start_required'; resumed = $false; fastResumeAvailable = $false }
    }
    if (-not (Select-RememberedCogentStackWorkspaceTab $panelWindow)) {
        $restore = Restore-CompanionLayout $State $false $true $true
        return [ordered]@{ status = 'cold_start_required'; resumed = $false; fastResumeAvailable = $false; reason = 'remembered_workspace_tab_unavailable'; browserWindowRestored = [bool]$restore.browserWindowRestored }
    }
    $workspaceUrl = if ($State.PSObject.Properties['workspaceUrl']) { [string]$State.workspaceUrl } else { 'https://cogentstack.app/stack?surface=chatgpt' }
    $panelAddress = Get-BrowserAddressValue $panelWindow
    if ((Test-CompanionSuspendAddress $panelAddress) -or (Test-CompanionResumeAddress $panelAddress)) {
        if (-not (Set-BrowserWorkspaceAddress $panelWindow $workspaceUrl)) {
            return [ordered]@{ status = 'cold_start_required'; resumed = $false; fastResumeAvailable = $false; reason = 'workspace_address_not_restored' }
        }
    }
    $layoutStatus = if ($State.PSObject.Properties['layoutStatus']) { [string]$State.layoutStatus } else { 'active' }
    if ($layoutStatus -eq 'active') {
        $activeArea = Get-MonitorWorkingArea $chatWindow.Handle
        $activeGutter = if ($State.PSObject.Properties['gutter']) { [int]$State.gutter } else { 12 }
        $activeAvailableWidth = [int]$activeArea.width - $activeGutter
        $activeChatWidth = [Math]::Floor($activeAvailableWidth / 2)
        $activeDivider = Find-RememberedWindow $State 'divider'
        $activePanelFrame = Get-WebDocumentRectangle $panelWindow
        $activeLayout = if ($activeDivider -and $activePanelFrame) {
            Test-WorkspaceLayout $activeArea $chatWindow $activePanelFrame $activeGutter $activeDivider $panelWindow
        } else {
            $null
        }
        $activeHeaderVisible = Wait-CogentStackHeaderVisible $panelWindow $activeArea 10
        $activeTopCropRemoved = [bool]($State.PSObject.Properties['browserTopCropRemoved'] -and [bool]$State.browserTopCropRemoved)
        if (-not $activeLayout -or -not $activeLayout.verified -or -not $activeHeaderVisible -or -not $activeTopCropRemoved) {
            if ($activeDivider) {
                [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$activeDivider.Handle, 0) | Out-Null
            }
            if ($State.PSObject.Properties['browserContentClipped'] -and [bool]$State.browserContentClipped) {
                Clear-WindowRegion $panelWindow
            }
            $State | Add-Member -MemberType NoteProperty -Name layoutStatus -Value 'suspended' -Force
            Save-LayoutState $State
            return Resume-CompanionLayout $State
        }
        $activeBackdrop = Find-RememberedWindow $State 'backdrop'
        if (-not $activeBackdrop) {
            $activeBackdrop = Start-WhiteBackdrop $activeArea $panelWindow
            $State | Add-Member -MemberType NoteProperty -Name backdropHandle -Value ([Int64]$activeBackdrop.Handle) -Force
            $State | Add-Member -MemberType NoteProperty -Name backdropProcessId -Value ([int]$activeBackdrop.ProcessId) -Force
            Save-LayoutState $State
        } else {
            Move-DesktopWindow $activeBackdrop ([int]$activeArea.x) ([int]$activeArea.y) ([int]$activeArea.width) ([int]$activeArea.height)
            Set-WhiteBackdropLayer $activeBackdrop $panelWindow
        }
        [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$panelWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
        [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$chatWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$panelWindow.Handle) | Out-Null
        [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$chatWindow.Handle) | Out-Null
        $activeDividerArea = Get-WhiteDividerArea $activeArea $activeChatWidth $activeGutter
        $activeDivider = Start-WhiteDivider $activeDividerArea $chatWindow $panelWindow
        $activeLayering = Test-WorkspacePanelsAboveBackdrop $activeBackdrop $chatWindow $panelWindow
        if (-not $activeLayering.verified) {
            $restore = Restore-CompanionLayout $State $false $true $true
            return [ordered]@{
                status = 'active_layout_rejected'
                resumed = $false
                fastResumeAvailable = $false
                layoutVerified = $false
                layoutDetails = $activeLayout
                workspacePanelsAboveBackdrop = $false
                layeringDetails = $activeLayering
                browserWindowRestored = [bool]$restore.browserWindowRestored
            }
        }
        $State | Add-Member -MemberType NoteProperty -Name schemaVersion -Value 13 -Force
        $State | Add-Member -MemberType NoteProperty -Name dividerHandle -Value ([Int64]$activeDivider.Handle) -Force
        $State | Add-Member -MemberType NoteProperty -Name dividerProcessId -Value ([int]$activeDivider.ProcessId) -Force
        Save-LayoutState $State
        $watcher = Start-CompanionExitWatcher
        return [ordered]@{
            status = 'already_active'
            resumed = $true
            fastResumeAvailable = $true
            whiteBackdrop = [bool]$activeBackdrop
            backdropLayer = if ($activeBackdrop) { 'above-desktop-behind-panels' } else { 'missing' }
            whiteDivider = [bool]$activeDivider
            dividerEdgeVisible = [bool]($activeDivider -and $activeLayout.dividerLayered)
            dividerEdgeColor = '#CDCDCD'
            dividerMasksShadows = [bool]($activeDivider -and $activeLayout.dividerLayered)
            workspacePanelsAboveBackdrop = [bool]$activeLayering.verified
            headerVisible = [bool]$activeHeaderVisible
            browserTopCropRemoved = $activeTopCropRemoved
            companionExitWatcherStarted = [bool]$watcher
        }
    }
    $area = Get-MonitorWorkingArea $chatWindow.Handle
    $gutter = if ($State.PSObject.Properties['gutter']) { [int]$State.gutter } else { 12 }
    $availableWidth = [int]$area.width - $gutter
    $chatWidth = [Math]::Floor($availableWidth / 2)
    $panelWidth = $availableWidth - $chatWidth
    $panelX = [int]$area.x + $chatWidth + $gutter
    $backdrop = Find-RememberedWindow $State 'backdrop'
    if ($backdrop) {
        Move-DesktopWindow $backdrop ([int]$area.x) ([int]$area.y) ([int]$area.width) ([int]$area.height)
        Set-WhiteBackdropLayer $backdrop $chatWindow
    } else {
        $backdrop = Start-WhiteBackdrop $area $chatWindow
    }
    Move-VisibleDesktopWindow $chatWindow ([int]$area.x) ([int]$area.y) $chatWidth ([int]$area.height)
    $pageOnly = $null
    try {
        $originalStyle = [Int64]$State.panelOriginalStyle
        $pageOnly = Set-BrowserPageOnly $panelWindow $area $panelX $panelWidth $originalStyle $false
    } catch {
        Restore-BrowserWindow $panelWindow $State.panelOriginal ([Int64]$State.panelOriginalStyle)
        Restore-Window $chatWindow $State.chatDesktopOriginal
        if ($backdrop -and [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$backdrop.Handle)) {
            [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$backdrop.Handle, 0) | Out-Null
        }
        throw
    }
    [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$chatWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
    [CogentStackWorkspaceWindows]::SetWindowPos([IntPtr]$panelWindow.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0013) | Out-Null
    [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$panelWindow.Handle) | Out-Null
    [CogentStackWorkspaceWindows]::BringWindowToTop([IntPtr]$chatWindow.Handle) | Out-Null
    [CogentStackWorkspaceWindows]::SetForegroundWindow([IntPtr]$chatWindow.Handle) | Out-Null
    $divider = $null
    try {
        $dividerArea = Get-WhiteDividerArea $area $chatWidth $gutter
        $divider = Start-WhiteDivider $dividerArea $chatWindow $panelWindow
    } catch {
        Restore-BrowserWindow $panelWindow $State.panelOriginal ([Int64]$State.panelOriginalStyle)
        Restore-Window $chatWindow $State.chatDesktopOriginal
        if ($backdrop -and [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$backdrop.Handle)) {
            [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$backdrop.Handle, 0) | Out-Null
        }
        throw
    }
    Start-Sleep -Milliseconds 200
    $layout = Test-WorkspaceLayout $area $chatWindow $pageOnly.contentFrame $gutter $divider $panelWindow
    $layering = Test-WorkspacePanelsAboveBackdrop $backdrop $chatWindow $panelWindow
    $headerVisible = Wait-CogentStackHeaderVisible $panelWindow $area
    $layoutAccepted = [bool]($layout.verified -and $layering.verified -and $headerVisible -and $pageOnly.topCropRemoved)
    $State | Add-Member -MemberType NoteProperty -Name schemaVersion -Value 13 -Force
    $State | Add-Member -MemberType NoteProperty -Name backdropHandle -Value ([Int64]$backdrop.Handle) -Force
    $State | Add-Member -MemberType NoteProperty -Name backdropProcessId -Value ([int]$backdrop.ProcessId) -Force
    $State | Add-Member -MemberType NoteProperty -Name dividerHandle -Value ([Int64]$divider.Handle) -Force
    $State | Add-Member -MemberType NoteProperty -Name dividerProcessId -Value ([int]$divider.ProcessId) -Force
    $State | Add-Member -MemberType NoteProperty -Name browserContentMode -Value 'page-only' -Force
    $State | Add-Member -MemberType NoteProperty -Name browserContentClipped -Value ([bool]$pageOnly.contentClipped) -Force
    $State | Add-Member -MemberType NoteProperty -Name browserTopCropRemoved -Value ([bool]$pageOnly.topCropRemoved) -Force
    $State | Add-Member -MemberType NoteProperty -Name browserClipInsets -Value $pageOnly.clipInsets -Force
    if (-not $layoutAccepted) {
        $restore = Restore-CompanionLayout $State $false $true $true
        return [ordered]@{
            status = 'resume_rejected'
            resumed = $false
            fastResumeAvailable = $false
            layoutVerified = $false
            layoutDetails = $layout
            workspacePanelsAboveBackdrop = [bool]$layering.verified
            layeringDetails = $layering
            headerVisible = [bool]$headerVisible
            browserTopCropRemoved = [bool]$pageOnly.topCropRemoved
            browserWindowRestored = [bool]$restore.browserWindowRestored
        }
    }
    Set-LayoutStateStatus $State 'active'
    $watcher = Start-CompanionExitWatcher
    return [ordered]@{
        status = if ($layoutAccepted) { 'resumed' } else { 'resumed_unverified' }
        resumed = $true
        fastResumeAvailable = $true
        layoutVerified = $layoutAccepted
        headerVisible = [bool]$headerVisible
        browserTopCropRemoved = [bool]$pageOnly.topCropRemoved
        splitPercent = 50
        gutter = $gutter
        whiteBackdrop = $true
        backdropLayer = 'above-desktop-behind-panels'
        whiteDivider = [bool]$divider
        dividerEdgeVisible = [bool]($divider -and $layout.dividerLayered)
        dividerEdgeColor = '#CDCDCD'
        dividerMasksShadows = [bool]($layout.dividerAligned -and $layout.dividerLayered)
        workspacePanelsAboveBackdrop = [bool]$layering.verified
        layeringDetails = $layering
        companionExitWatcherStarted = [bool]$watcher
        shortcut = Install-WorkModeShortcut
    }
}

function Show-ColdStartRequired {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        'The previous CogentStack work mode is no longer available. Open CogentStack from Codex once to establish a fresh split screen.',
        'CogentStack Work Mode',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Start-CompanionExitWatcher {
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $powershellPath = if ($powershellCommand) { [string]$powershellCommand.Source } else { $null }
    if (-not $powershellPath) { throw 'Windows PowerShell is required to monitor the CogentStack companion exit control.' }
    $watcherScript = Install-CompanionRuntimeSnapshot
    Start-Process -FilePath $powershellPath -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $watcherScript,
        '-Mode',
        'WatchExit'
    ) -WindowStyle Hidden -PassThru
}

function Install-CompanionRuntimeSnapshot {
    $sourceScript = [IO.Path]::GetFullPath($PSCommandPath)
    $sourceDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
    $runtimeRoot = Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CogentStack') 'companion-runtime'
    $contentHash = (Get-FileHash -LiteralPath $sourceScript -Algorithm SHA256).Hash.ToLowerInvariant()
    $runtimeDirectory = Join-Path $runtimeRoot $contentHash
    $runtimeScript = Join-Path $runtimeDirectory ([IO.Path]::GetFileName($sourceScript))
    $requiredScripts = @(
        'open-cogentstack-companion.ps1',
        'project-context.ps1',
        'delete-project.ps1',
        'fulfil-project.ps1',
        'generate-project-preview.ps1'
    )
    $snapshotReady = (Test-Path -LiteralPath $runtimeScript -PathType Leaf) -and
        -not @($requiredScripts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $runtimeDirectory $_) -PathType Leaf) }).Count
    if ($snapshotReady) { return $runtimeScript }

    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    $stagingDirectory = Join-Path $runtimeRoot (".$contentHash-$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    try {
        Get-ChildItem -LiteralPath $sourceDirectory -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagingDirectory $_.Name) -Force
        }
        foreach ($requiredScript in $requiredScripts) {
            if (-not (Test-Path -LiteralPath (Join-Path $stagingDirectory $requiredScript) -PathType Leaf)) {
                throw "The companion runtime snapshot is missing $requiredScript."
            }
        }
        if (-not (Test-Path -LiteralPath $runtimeDirectory)) {
            Move-Item -LiteralPath $stagingDirectory -Destination $runtimeDirectory
        }
    } finally {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }
    if (-not (Test-Path -LiteralPath $runtimeScript -PathType Leaf)) {
        throw 'The immutable companion runtime snapshot could not be prepared.'
    }
    return $runtimeScript
}

function Start-ApprovedProjectCreationWorker([string]$ApprovedRequestId, [string]$ApprovedContextKey) {
    if ($ApprovedRequestId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $false }
    if ($ApprovedContextKey -ne 'default' -and $ApprovedContextKey -notmatch '^ctx-[0-9a-f]{64}$') { return $false }
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) { return $false }
    try {
        $worker = Start-Process -FilePath ([string]$powershellCommand.Source) -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $PSCommandPath,
            '-Mode',
            'CreateProjectWorker',
            '-RequestId',
            $ApprovedRequestId,
            '-ContextKey',
            $ApprovedContextKey
        ) -WindowStyle Hidden -PassThru
        return $null -ne $worker
    } catch {
        return $false
    }
}

function Start-ActiveProjectPreviewWorker([string]$PreviewRequestId, [string]$PreviewContextKey) {
    if ($PreviewRequestId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $false }
    if ($PreviewContextKey -ne 'default' -and $PreviewContextKey -notmatch '^ctx-[0-9a-f]{64}$') { return $false }
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) { return $false }
    try {
        $worker = Start-Process -FilePath ([string]$powershellCommand.Source) -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $PSCommandPath,
            '-Mode',
            'PreviewProjectWorker',
            '-RequestId',
            $PreviewRequestId,
            '-ContextKey',
            $PreviewContextKey
        ) -WindowStyle Hidden -PassThru
        return $null -ne $worker
    } catch {
        return $false
    }
}

function Invoke-ApprovedProjectDeletion([string]$ContextKey = 'default', [string]$ApprovedRequestId = '') {
    $deleteScript = Join-Path $PSScriptRoot 'delete-project.ps1'
    if (-not (Test-Path -LiteralPath $deleteScript -PathType Leaf)) { return $false }
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) { return $false }
    try {
        $arguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $deleteScript,
            '-Mode',
            'delete',
            '-ContextKey',
            $ContextKey
        )
        if ($ApprovedRequestId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $arguments += @('-RequestId', $ApprovedRequestId)
        }
        $process = Start-Process -FilePath ([string]$powershellCommand.Source) -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        return $process.ExitCode -eq 0
    } catch {
        return $false
    }
}

function Invoke-ApprovedProjectCreation([string]$RequestId, [string]$ContextKey = 'default') {
    if ($RequestId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $false }
    $creationScript = Join-Path $PSScriptRoot 'fulfil-project.ps1'
    if (-not (Test-Path -LiteralPath $creationScript -PathType Leaf)) { return $false }
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) { return $false }
    try {
        $process = Start-Process -FilePath ([string]$powershellCommand.Source) -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $creationScript,
            '-Mode',
            'create',
            '-RequestId',
            $RequestId,
            '-ContextKey',
            $ContextKey
        ) -WindowStyle Hidden -Wait -PassThru
        return $process.ExitCode -eq 0
    } catch {
        return $false
    }
}

function Invoke-ActiveProjectPreview([string]$ContextKey = 'default') {
    $previewScript = Join-Path $PSScriptRoot 'generate-project-preview.ps1'
    if (-not (Test-Path -LiteralPath $previewScript -PathType Leaf)) {
        return [pscustomobject]@{ success = $false; localUrl = '' }
    }
    $powershellCommand = Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $powershellCommand) {
        return [pscustomobject]@{ success = $false; localUrl = '' }
    }
    try {
        # Run the generator in a child host because its terminal branches use `exit`.
        # An in-process invocation would terminate this worker before it could report
        # failure or open the verified preview.
        $output = @(& ([string]$powershellCommand.Source) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $previewScript -Mode generate -ContextKey $ContextKey 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        $jsonLine = @($output | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
        if ($exitCode -ne 0 -or -not $jsonLine) {
            return [pscustomobject]@{ success = $false; localUrl = '' }
        }
        $result = $jsonLine | ConvertFrom-Json
        if ([string]$result.status -notin @('generated', 'already_running') -or -not [bool]$result.remembered) {
            return [pscustomobject]@{ success = $false; localUrl = '' }
        }
        $previewUri = $null
        if (-not [Uri]::TryCreate([string]$result.localUrl, [UriKind]::Absolute, [ref]$previewUri)) {
            return [pscustomobject]@{ success = $false; localUrl = '' }
        }
        if (
            $previewUri.Scheme -ne 'http' -or
            $previewUri.Host -notin @('localhost', '127.0.0.1', '::1', '[::1]') -or
            $previewUri.IsDefaultPort -or
            -not [string]::IsNullOrWhiteSpace($previewUri.UserInfo)
        ) {
            return [pscustomobject]@{ success = $false; localUrl = '' }
        }
        return [pscustomobject]@{ success = $true; localUrl = $previewUri.AbsoluteUri }
    } catch {
        return [pscustomobject]@{ success = $false; localUrl = '' }
    }
}

function Test-WorkspaceLayout($Area, $ChatWindow, $PanelFrame, [int]$Gutter, $DividerWindow, $PanelWindow) {
    $chat = Get-VisibleWindowRectangle $ChatWindow.Handle
    $panel = $PanelFrame
    $divider = if ($DividerWindow) { Get-WindowRectangle $DividerWindow.Handle } else { $null }
    $chatRight = [int]$chat.x + [int]$chat.width
    $panelRight = [int]$panel.x + [int]$panel.width
    $areaRight = [int]$Area.x + [int]$Area.width
    $chatBottom = [int]$chat.y + [int]$chat.height
    $panelBottom = [int]$panel.y + [int]$panel.height
    $areaBottom = [int]$Area.y + [int]$Area.height
    $tolerance = 1
    $gapAligned = [Math]::Abs(($chatRight + $Gutter) - [int]$panel.x) -le $tolerance
    $dividerAligned = [bool](
        $divider -and
        [Math]::Abs([int]$divider.x - $chatRight) -le $tolerance -and
        [Math]::Abs([int]$divider.y - [int]$Area.y) -le $tolerance -and
        [Math]::Abs([int]$divider.width - $Gutter) -le $tolerance -and
        [Math]::Abs([int]$divider.height - [int]$Area.height) -le $tolerance
    )
    $dividerLayered = [bool](
        $dividerAligned -and $PanelWindow -and
        [CogentStackWorkspaceWindows]::GetWindow([IntPtr]$DividerWindow.Handle, 4) -eq [IntPtr]$PanelWindow.Handle -and
        [CogentStackWorkspaceWindows]::IsWindowAbove([IntPtr]$DividerWindow.Handle, [IntPtr]$PanelWindow.Handle)
    )
    [ordered]@{
        verified = (
            [Math]::Abs([int]$chat.x - [int]$Area.x) -le $tolerance -and
            [Math]::Abs([int]$chat.y - [int]$Area.y) -le $tolerance -and
            $gapAligned -and
            [Math]::Abs([int]$panel.y - [int]$Area.y) -le $tolerance -and
            [Math]::Abs([int]$chat.width - [int]$panel.width) -le $tolerance -and
            [Math]::Abs($panelRight - $areaRight) -le $tolerance -and
            [Math]::Abs($chatBottom - $areaBottom) -le $tolerance -and
            [Math]::Abs($panelBottom - $areaBottom) -le $tolerance -and
            $dividerLayered
        )
        joined = $Gutter -eq 0 -and $gapAligned
        separated = $Gutter -gt 0 -and $gapAligned
        equalWidth = [Math]::Abs([int]$chat.width - [int]$panel.width) -le $tolerance
        topAligned = [Math]::Abs([int]$chat.y - [int]$panel.y) -le $tolerance
        dividerAligned = $dividerAligned
        dividerLayered = $dividerLayered
        chat = $chat
        panel = $panel
        divider = $divider
    }
}

if ($Mode -eq 'PrepareRuntime') {
    $runtimeScript = Install-CompanionRuntimeSnapshot
    Write-CompactJson ([ordered]@{ status = 'ready'; runtimeScript = $runtimeScript; sourceIndependent = $runtimeScript -ne [IO.Path]::GetFullPath($PSCommandPath) })
    exit 0
}

$state = Read-LayoutState
$browsers = @(Get-CompanionBrowsers)
$chatDesktopWindow = @(Get-ChatDesktopWindow | Select-Object -First 1)
$hostProjectContext = Get-CogentStackProjectContext
$activeChatProject = if ($Mode -eq 'Open') {
    Wait-ActiveChatProject $chatDesktopWindow
} else {
    Get-ActiveChatProject $chatDesktopWindow
}

if ($Mode -eq 'InstallToggle') {
    $shortcut = Install-WorkModeShortcut
    Write-CompactJson ([ordered]@{ status = if ($shortcut) { 'installed' } else { 'unavailable' }; shortcut = $shortcut })
    exit $(if ($shortcut) { 0 } else { 2 })
}

if ($Mode -eq 'Suspend') {
    Write-CompactJson (Suspend-CompanionLayout $state $true)
    exit 0
}

if ($Mode -eq 'Resume') {
    $resume = Resume-CompanionLayout $state
    Write-CompactJson $resume
    exit $(if ($resume.resumed) { 0 } else { 2 })
}

if ($Mode -eq 'Toggle') {
    $layoutStatus = if ($state -and $state.PSObject.Properties['layoutStatus']) { [string]$state.layoutStatus } else { 'active' }
    $toggle = if ($state -and $layoutStatus -eq 'active') { Suspend-CompanionLayout $state $true } else { Resume-CompanionLayout $state }
    if ($toggle.status -eq 'cold_start_required') { Show-ColdStartRequired }
    Write-CompactJson $toggle
    exit $(if ($toggle.status -eq 'cold_start_required') { 2 } else { 0 })
}

if ($Mode -eq 'CreateProjectWorker') {
    $creationMutex = New-Object System.Threading.Mutex($false, "Local\CogentStackCompanionProjectCreation-$($RequestId.ToLowerInvariant())")
    $ownsCreationMutex = $false
    try {
        $ownsCreationMutex = $creationMutex.WaitOne(0)
        if (-not $ownsCreationMutex) { exit 0 }
        $created = Invoke-ApprovedProjectCreation $RequestId $ContextKey
        if (-not $created) {
            $workerState = Read-LayoutState
            $workerPanel = if ($workerState) { Find-RememberedWindow $workerState 'panel' } else { $null }
            if ($workerState -and $workerPanel) {
                $returnUrl = [string]$workerState.workspaceUrl
                $returnUrl = "$returnUrl$(if ($returnUrl.Contains('?')) { '&' } else { '?' })desktop_creation=failed&desktop_request=$RequestId"
                Set-BrowserWorkspaceAddress $workerPanel $returnUrl | Out-Null
            }
        }
        exit $(if ($created) { 0 } else { 1 })
    } finally {
        if ($ownsCreationMutex) { $creationMutex.ReleaseMutex() }
        $creationMutex.Dispose()
    }
}

if ($Mode -eq 'PreviewProjectWorker') {
    if ($RequestId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { exit 1 }
    if ($ContextKey -ne 'default' -and $ContextKey -notmatch '^ctx-[0-9a-f]{64}$') { exit 1 }
    $previewMutex = New-Object System.Threading.Mutex($false, "Local\CogentStackCompanionProjectPreview-$($RequestId.ToLowerInvariant())")
    $ownsPreviewMutex = $false
    try {
        $ownsPreviewMutex = $previewMutex.WaitOne(0)
        if (-not $ownsPreviewMutex) { exit 0 }
        $preview = Invoke-ActiveProjectPreview $ContextKey
        $workerState = Read-LayoutState
        $workerPanel = if (
            $workerState -and
            [string]$workerState.contextKey -eq $ContextKey
        ) { Find-RememberedWindow $workerState 'panel' } else { $null }
        if ($workerState -and $workerPanel) {
            $previewResult = if ($preview.success) { 'ready' } else { 'failed' }
            $returnUrl = [string]$workerState.workspaceUrl
            $returnUrl = "$returnUrl$(if ($returnUrl.Contains('?')) { '&' } else { '?' })desktop_preview=$previewResult&desktop_request=$RequestId"
            Set-BrowserWorkspaceAddress $workerPanel $returnUrl | Out-Null
        }
        if ($preview.success) {
            Start-Sleep -Milliseconds 350
            Start-Process -FilePath ([string]$preview.localUrl) | Out-Null
        }
        exit $(if ($preview.success) { 0 } else { 1 })
    } finally {
        if ($ownsPreviewMutex) { $previewMutex.ReleaseMutex() }
        $previewMutex.Dispose()
    }
}

if ($Mode -eq 'WatchExit') {
    $watcherMutex = New-Object System.Threading.Mutex($false, 'Local\CogentStackCompanionExitWatcher')
    $ownsMutex = $false
    $pendingProjectKey = $null
    $pendingProjectCount = 0
    $handledCreationRequests = New-Object 'System.Collections.Generic.HashSet[string]'
    $handledPreviewRequests = New-Object 'System.Collections.Generic.HashSet[string]'
    try {
        $ownsMutex = $watcherMutex.WaitOne(0)
        if (-not $ownsMutex) { exit 0 }
        while ($true) {
            $watchState = Read-LayoutState
            if (-not $watchState) { break }
            $watchPanel = Find-RememberedWindow $watchState 'panel'
            if (-not $watchPanel) { break }
            $watchAddress = Get-BrowserAddressValue $watchPanel
            if (Test-CompanionExitAddress $watchAddress) {
                Restore-CompanionLayout $watchState $false $true $true | Out-Null
                break
            }
            $watchContextKey = if ($watchState.PSObject.Properties['contextKey']) { [string]$watchState.contextKey } else { 'default' }
            $creationRequestId = Get-CompanionProjectCreationRequestId $watchAddress
            $creationAddressContextKey = if ($creationRequestId) {
                try { Get-CogentStackContextFromUrl $watchAddress } catch { '' }
            } else { '' }
            if (
                $creationRequestId -and
                $creationAddressContextKey -eq $watchContextKey -and
                $handledCreationRequests.Add($creationRequestId)
            ) {
                # The exact request and logical context were already approved in the hosted
                # workspace. Start the independent worker before transient ChatGPT Project
                # visibility checks can suspend the companion and strand that approval.
                $creationStarted = Start-ApprovedProjectCreationWorker $creationRequestId $watchContextKey
                if (-not $creationStarted) {
                    $returnUrl = [string]$watchState.workspaceUrl
                    $returnUrl = "$returnUrl$(if ($returnUrl.Contains('?')) { '&' } else { '?' })desktop_creation=failed&desktop_request=$creationRequestId"
                    Set-BrowserWorkspaceAddress $watchPanel $returnUrl | Out-Null
                }
                Start-Sleep -Milliseconds 500
                continue
            }
            $previewRequestId = Get-CompanionProjectPreviewRequestId $watchAddress
            $previewAddressContextKey = if ($previewRequestId) {
                try { Get-CogentStackContextFromUrl $watchAddress } catch { '' }
            } else { '' }
            if (
                $previewRequestId -and
                $previewAddressContextKey -eq $watchContextKey -and
                $handledPreviewRequests.Add($previewRequestId)
            ) {
                # The user explicitly pressed the hosted preview control. Start the exact
                # active project's verified preview before any transient Project visibility
                # change can suspend the companion and lose the one-click request.
                $previewStarted = Start-ActiveProjectPreviewWorker $previewRequestId $watchContextKey
                if (-not $previewStarted) {
                    $returnUrl = [string]$watchState.workspaceUrl
                    $returnUrl = "$returnUrl$(if ($returnUrl.Contains('?')) { '&' } else { '?' })desktop_preview=failed&desktop_request=$previewRequestId"
                    Set-BrowserWorkspaceAddress $watchPanel $returnUrl | Out-Null
                }
                Start-Sleep -Milliseconds 500
                continue
            }
            $layoutStatus = if ($watchState.PSObject.Properties['layoutStatus']) { [string]$watchState.layoutStatus } else { 'active' }
            $watchChat = Find-RememberedWindow $watchState 'chatDesktop'
            $activeProject = Get-ActiveChatProject $watchChat
            $rememberedProjectKey = if ($watchState.PSObject.Properties['chatProjectKey']) { [string]$watchState.chatProjectKey } else { '' }
            if (-not $activeProject.resolved) {
                if ($pendingProjectKey -eq 'unresolved') { $pendingProjectCount++ } else {
                    $pendingProjectKey = 'unresolved'
                    $pendingProjectCount = 1
                }
                if ($pendingProjectCount -lt 4) {
                    Start-Sleep -Milliseconds 250
                    continue
                }
                if ($layoutStatus -eq 'active') {
                    Suspend-CompanionLayout $watchState $true 'inactive-project' $true | Out-Null
                }
                Start-Sleep -Milliseconds 250
                continue
            }
            $visualBindingPending = [bool](
                $watchState.PSObject.Properties['chatProjectVisualBindingPending'] -and
                [bool]$watchState.chatProjectVisualBindingPending
            )
            if ($visualBindingPending) {
                $bindingDeadline = [DateTimeOffset]::MinValue
                $deadlineValid = $watchState.PSObject.Properties['chatProjectVisualBindingDeadlineUtc'] -and
                    [DateTimeOffset]::TryParse([string]$watchState.chatProjectVisualBindingDeadlineUtc, [ref]$bindingDeadline)
                $existingVisualBinding = Find-ContextBinding ([string]$activeProject.key)
                if ($deadlineValid -and [DateTimeOffset]::UtcNow -le $bindingDeadline -and -not $existingVisualBinding) {
                    Save-ContextBinding ([string]$activeProject.key) ([string]$watchState.contextKey) ([string]$watchState.workspaceUrl)
                    $watchState | Add-Member -MemberType NoteProperty -Name chatProjectKey -Value ([string]$activeProject.key) -Force
                    $watchState | Add-Member -MemberType NoteProperty -Name chatProjectIdentitySource -Value 'accessibility-late-binding' -Force
                    $watchState | Add-Member -MemberType NoteProperty -Name chatProjectVisualBindingPending -Value $false -Force
                    $watchState | Add-Member -MemberType NoteProperty -Name updatedAt -Value ([DateTimeOffset]::UtcNow.ToString('O')) -Force
                    Save-LayoutState $watchState
                    $rememberedProjectKey = [string]$activeProject.key
                } else {
                    $watchState | Add-Member -MemberType NoteProperty -Name chatProjectVisualBindingPending -Value $false -Force
                    Save-LayoutState $watchState
                }
            }
            $observedProjectKey = [string]$activeProject.key
            if ($observedProjectKey -ne $rememberedProjectKey) {
                if ($layoutStatus -eq 'active') {
                    Suspend-CompanionLayout $watchState $true 'inactive-project' $true | Out-Null
                }
                Start-Sleep -Milliseconds 250
                continue
            }
            $pendingProjectKey = $null
            $pendingProjectCount = 0
            $suspendReason = if ($watchState.PSObject.Properties['suspendReason']) { [string]$watchState.suspendReason } else { 'manual' }
            if ($layoutStatus -eq 'suspended' -and $suspendReason -eq 'inactive-project') {
                Resume-CompanionLayout $watchState | Out-Null
                Start-Sleep -Milliseconds 250
                continue
            }
            $watchAddress = Get-BrowserAddressValue $watchPanel
            if (Test-CompanionProjectDeletionAddress $watchAddress) {
                $deletionRequestId = Get-CompanionProjectDeletionRequestId $watchAddress
                $deleted = Invoke-ApprovedProjectDeletion $watchContextKey $deletionRequestId
                $returnUrl = [string]$watchState.workspaceUrl
                if (-not $deleted) {
                    $returnUrl = "$returnUrl$(if ($returnUrl.Contains('?')) { '&' } else { '?' })desktop_deletion=failed"
                }
                Set-BrowserWorkspaceAddress $watchPanel $returnUrl | Out-Null
                Start-Sleep -Milliseconds 500
                continue
            }
            $watchDivider = Find-RememberedWindow $watchState 'divider'
            $watchBackdrop = Find-RememberedWindow $watchState 'backdrop'
            if ($watchDivider) {
                $watchLayoutVerified = $false
                $watchHeaderVisible = $false
                $watchTopCropRemoved = [bool]($watchState.PSObject.Properties['browserTopCropRemoved'] -and [bool]$watchState.browserTopCropRemoved)
                if ($layoutStatus -eq 'active' -and $watchChat) {
                    $watchArea = Get-MonitorWorkingArea $watchChat.Handle
                    $watchGutter = if ($watchState.PSObject.Properties['gutter']) { [int]$watchState.gutter } else { 12 }
                    $watchPanelFrame = Get-WebDocumentRectangle $watchPanel
                    if ($watchPanelFrame) {
                        $watchLayout = Test-WorkspaceLayout $watchArea $watchChat $watchPanelFrame $watchGutter $watchDivider $watchPanel
                        $watchLayoutVerified = [bool]$watchLayout.verified
                        $watchHeaderVisible = Test-CogentStackHeaderVisible $watchPanel $watchArea
                    }
                }
                if ($layoutStatus -eq 'active' -and $watchLayoutVerified -and $watchHeaderVisible -and $watchTopCropRemoved) {
                    $watchLayering = Test-WorkspacePanelsAboveBackdrop $watchBackdrop $watchChat $watchPanel
                    if (-not $watchLayering.verified) {
                        Restore-CompanionLayout $watchState $false $true $true | Out-Null
                        break
                    }
                    try { Set-WhiteDividerLayer $watchDivider $watchChat $watchPanel } catch { }
                } elseif ($layoutStatus -eq 'active' -and $watchLayoutVerified -and (-not $watchHeaderVisible -or -not $watchTopCropRemoved)) {
                    try { Resume-CompanionLayout $watchState | Out-Null } catch { }
                    Start-Sleep -Milliseconds 250
                    continue
                } else {
                    [CogentStackWorkspaceWindows]::ShowWindow([IntPtr]$watchDivider.Handle, 0) | Out-Null
                }
            }
            if (Test-CompanionResumeAddress $watchAddress) {
                Resume-CompanionLayout $watchState | Out-Null
                Start-Sleep -Milliseconds 250
                continue
            }
            if ($layoutStatus -eq 'suspended') {
                Start-Sleep -Milliseconds 250
                continue
            }
            if (
                (Test-CompanionSuspendAddress $watchAddress) -or
                ($watchAddress -and -not (Test-CompanionOwnedAddress $watchAddress))
            ) {
                Suspend-CompanionLayout $watchState $true | Out-Null
                Start-Sleep -Milliseconds 250
                continue
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
    $existingPanel = @(Find-ExistingCogentStackWindow $browsers | Select-Object -First 1)
    $inspectDivider = @(Find-DividerWindow | Select-Object -First 1)
    $inspectPanelWindow = if ($state) { Find-RememberedWindow $state 'panel' } elseif ($existingPanel) { $existingPanel.Window } else { $null }
    $inspectDividerLayered = [bool](
        $inspectDivider -and $chatDesktopWindow -and $inspectPanelWindow -and
        [CogentStackWorkspaceWindows]::GetWindow([IntPtr]$inspectDivider.Handle, 4) -eq [IntPtr]$inspectPanelWindow.Handle -and
        [CogentStackWorkspaceWindows]::IsWindowAbove([IntPtr]$inspectDivider.Handle, [IntPtr]$inspectPanelWindow.Handle)
    )
    Write-CompactJson ([ordered]@{
        status = 'inspected'
        platform = 'windows'
        chatDesktopWindowFound = [bool]$chatDesktopWindow
        chatProjectResolved = [bool]$activeChatProject.resolved
        chatProjectBound = [bool]($activeChatProject.resolved -and (Find-ContextBinding ([string]$activeChatProject.key)))
        existingCogentStackWindowFound = [bool]$existingPanel
        browserAvailable = $browsers.Count -gt 0
        browser = if ($existingPanel) { [string]$existingPanel.Browser.Name } elseif ($browsers.Count -gt 0) { [string]$browsers[0].Name } else { $null }
        registeredDefault = if ($existingPanel) { [bool]$existingPanel.Browser.IsRegisteredDefault } elseif ($browsers.Count -gt 0) { [bool]$browsers[0].IsRegisteredDefault } else { $false }
        launchMode = 'reuse-existing-browser-tab'
        browserContentMode = if ($state -and $state.PSObject.Properties['browserContentMode']) { [string]$state.browserContentMode } else { 'normal-window' }
        browserTopCropRemoved = [bool]($state -and $state.PSObject.Properties['browserTopCropRemoved'] -and [bool]$state.browserTopCropRemoved)
        layoutStatus = if ($state -and $state.PSObject.Properties['layoutStatus']) { [string]$state.layoutStatus } else { 'inactive' }
        fastResumeAvailable = [bool]($state -and $state.PSObject.Properties['layoutStatus'] -and [string]$state.layoutStatus -eq 'suspended')
        gutter = if ($state -and $state.PSObject.Properties['gutter']) { [int]$state.gutter } else { 0 }
        whiteBackdrop = [bool](Find-BackdropWindow)
        whiteDivider = [bool]$inspectDivider
        dividerEdgeVisible = $inspectDividerLayered
        dividerEdgeColor = '#CDCDCD'
        dividerMasksShadows = $inspectDividerLayered
    })
    exit 0
}

if ($Mode -eq 'Hide') {
    $restore = Restore-CompanionLayout $state $true $false $false
    if ($state) {
        $state | Add-Member -MemberType NoteProperty -Name browserContentMode -Value 'normal-window' -Force
        $state | Add-Member -MemberType NoteProperty -Name browserContentClipped -Value $false -Force
        Set-LayoutStateStatus $state 'suspended'
    }
    Write-CompactJson ([ordered]@{
        status = 'hide'
        browserWindowRestored = [bool]$restore.browserWindowRestored
        browserWindowMaximized = [bool]$restore.browserWindowMaximized
        backdropFound = [bool]$restore.backdropFound
        dividerFound = [bool]$restore.dividerFound
        fastResumeAvailable = [bool]$state
    })
    exit 0
}

if ($Mode -eq 'Close') {
    $restore = Restore-CompanionLayout $state $false $true $true
    Write-CompactJson ([ordered]@{
        status = 'close'
        browserWindowRestored = [bool]$restore.browserWindowRestored
        browserWindowMaximized = [bool]$restore.browserWindowMaximized
        backdropFound = [bool]$restore.backdropFound
        dividerFound = [bool]$restore.dividerFound
        fastResumeAvailable = $false
    })
    exit 0
}

$safeUrl = Confirm-CogentStackUrl $Url
$requestedContextKey = Get-CogentStackContextFromUrl $safeUrl
$rememberedContextBinding = if ([bool]$hostProjectContext.Isolated -and [string]$hostProjectContext.ContextKey -eq $requestedContextKey) {
    Find-ContextBindingByContext $requestedContextKey
} else { $null }
$visibleProjectBinding = if ($activeChatProject.resolved) { Find-ContextBinding ([string]$activeChatProject.key) } else { $null }
$openProjectResolution = Resolve-ChatProjectForOpen $activeChatProject $hostProjectContext $requestedContextKey $rememberedContextBinding $visibleProjectBinding
$activeChatProject = $openProjectResolution.project
$stableContextFallbackUsed = [bool]$openProjectResolution.stableContextFallbackUsed
$stableContextBindingPending = [bool]$openProjectResolution.stableContextBindingPending
if (-not $activeChatProject.resolved) {
    Write-CompactJson ([ordered]@{
        status = 'chatgpt_project_unresolved'
        message = 'CogentStack was not opened because neither a stable ChatGPT Project context nor one active Project accessibility identity could be verified.'
        reason = [string]$activeChatProject.reason
        contextSource = [string]$hostProjectContext.Source
        contextIsolated = [bool]$hostProjectContext.Isolated
        projectDetectionAttempts = if ($activeChatProject.Contains('attempts')) { [int]$activeChatProject.attempts } else { 1 }
        openedNewTab = $false
    })
    exit 2
}
if ($browsers.Count -eq 0) {
    Write-CompactJson ([ordered]@{
        status = 'browser_unavailable'
        message = 'Google Chrome or Microsoft Edge is required for the CogentStack companion workspace.'
    })
    exit 2
}

$openMutex = Enter-CompanionOpenMutex
try {
    # The remembered verified workspace is authoritative. Reusing it avoids any
    # browser-wide discovery and does not touch other browser tabs.
    if ($state) {
        $rememberedContextKey = if ($state.PSObject.Properties['contextKey']) { [string]$state.contextKey } else { 'default' }
        $rememberedProjectKey = if ($state.PSObject.Properties['chatProjectKey']) { [string]$state.chatProjectKey } else { '' }
        if ($rememberedContextKey -ne $requestedContextKey -or $rememberedProjectKey -ne [string]$activeChatProject.key) {
            Restore-CompanionLayout $state $false $true $false | Out-Null
            $state = $null
        }
    }
    if ($state) {
        $rememberedPanelBeforeResume = Find-RememberedWindow $state 'panel'
        $rememberedWorkspaceAlreadySelected = [bool]($rememberedPanelBeforeResume -and (Test-CogentStackWorkspaceAddress (Get-BrowserAddressValue $rememberedPanelBeforeResume)))
        $rememberedResume = Resume-CompanionLayout $state
        if ([string]$rememberedResume.status -in @('already_active', 'resumed')) {
            $rememberedPanel = Find-RememberedWindow $state 'panel'
            $rememberedResume['browser'] = if ($state.PSObject.Properties['browser']) { [string]$state.browser } else { $null }
            $rememberedResume['accountState'] = if ($rememberedPanel) { Wait-AccountState $rememberedPanel 8 } else { 'unknown' }
            $rememberedResume['reusedExistingTab'] = $true
            $rememberedResume['reusedExistingHomeTab'] = $false
            $rememberedResume['openedNewTab'] = $false
            $rememberedResume['tabResolution'] = 'remembered-workspace'
            $rememberedResume['candidateTabsActivated'] = if ($rememberedWorkspaceAlreadySelected) { 0 } else { 1 }
            Write-CompactJson $rememberedResume
            exit 0
        }
        if ([string]$rememberedResume.status -ne 'cold_start_required') {
            $rememberedResume['reusedExistingTab'] = $true
            $rememberedResume['openedNewTab'] = $false
            $rememberedResume['tabResolution'] = 'remembered-workspace'
            $rememberedResume['candidateTabsActivated'] = if ($rememberedWorkspaceAlreadySelected) { 0 } else { 1 }
            Write-CompactJson $rememberedResume
            exit 0
        }
        $state = $null
    }

    # Cold discovery inventories exact workspace/home titles without selecting
    # anything. Only the single chosen candidate is then activated and its URL
    # is verified. A mismatch fails closed and restores the original tab.
    $panelSelection = Find-ExistingCogentStackWindow $browsers | Select-Object -First 1
    $reusedExistingTab = [bool]$panelSelection
    $reusedExistingHomeTab = $false
    $openedNewTab = $false
    $tabResolution = if ($panelSelection) { 'exact-title-inventory' } else { 'new-tab' }
    $candidateTabsActivated = 0
    if ($panelSelection) {
        if (-not (Confirm-BrowserTabCandidate $panelSelection)) {
            Write-CompactJson ([ordered]@{
                status = 'opened_unarranged'
                message = 'An exact CogentStack tab title was found, but its address did not verify as the CogentStack workspace or home page. The original browser tab was restored and no new tab was opened.'
                browser = [string]$panelSelection.Browser.Name
                reusedExistingTab = $true
                openedNewTab = $false
                tabResolution = $tabResolution
                candidateTabsActivated = if ([bool]$panelSelection.Activated) { 1 } else { 0 }
            })
            exit 0
        }
        $candidateTabsActivated = if ([bool]$panelSelection.Activated) { 1 } else { 0 }
        $reusedExistingHomeTab = [bool]$panelSelection.IsHome
        $selectedContextKey = Get-CogentStackContextFromUrl (Get-BrowserAddressValue $panelSelection.Window)
        if (-not [bool]$panelSelection.IsWorkspace -or $selectedContextKey -ne $requestedContextKey) {
            if (-not (Set-BrowserWorkspaceAddress $panelSelection.Window $safeUrl)) {
                Write-CompactJson ([ordered]@{
                    status = 'opened_unarranged'
                    message = 'An existing CogentStack tab was found, but it could not be navigated safely to the workspace.'
                    browser = [string]$panelSelection.Browser.Name
                    reusedExistingTab = $true
                    reusedExistingHomeTab = $reusedExistingHomeTab
                    openedNewTab = $false
                    accountState = [string]$panelSelection.AccountState
                    tabResolution = $tabResolution
                    candidateTabsActivated = $candidateTabsActivated
                })
                exit 0
            }
            $panelSelection.IsWorkspace = $true
            $panelSelection.AccountState = Wait-AccountState $panelSelection.Window
        }
    }
    if (-not $panelSelection) {
        $preferredBrowser = $browsers[0]
        Start-Process -FilePath $preferredBrowser.ExecutablePath -ArgumentList @($safeUrl) | Out-Null
        $openedNewTab = $true
        for ($attempt = 0; $attempt -lt 40 -and -not $panelSelection; $attempt++) {
            Start-Sleep -Milliseconds 250
            $panelSelection = Find-ExistingCogentStackWindow $browsers | Select-Object -First 1
        }
        if ($panelSelection -and -not (Confirm-BrowserTabCandidate $panelSelection)) {
            Write-CompactJson ([ordered]@{
                status = 'opened_unarranged'
                message = 'The newly opened CogentStack tab did not verify as the requested workspace.'
                browser = [string]$panelSelection.Browser.Name
                reusedExistingTab = $false
                openedNewTab = $true
                tabResolution = $tabResolution
                candidateTabsActivated = if ([bool]$panelSelection.Activated) { 1 } else { 0 }
            })
            exit 0
        }
        if ($panelSelection) { $candidateTabsActivated = if ([bool]$panelSelection.Activated) { 1 } else { 0 } }
    }
} finally {
    Exit-CompanionOpenMutex $openMutex
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
if (-not $state) {
    Reset-OrphanedCompanionLayout $chatDesktopWindow $panelWindow | Out-Null
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
$backdrop = Start-WhiteBackdrop $area $chatDesktopWindow

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
$divider = $null
try {
    $dividerArea = Get-WhiteDividerArea $area $chatDesktopWidth $gutter
    $divider = Start-WhiteDivider $dividerArea $chatDesktopWindow $panelWindow
} catch {
    Restore-BrowserWindow $panelWindow $panelOriginal $panelOriginalStyle
    Restore-Window $chatDesktopWindow $chatOriginal
    if ($backdrop -and [CogentStackWorkspaceWindows]::IsWindow([IntPtr]$backdrop.Handle)) {
        [CogentStackWorkspaceWindows]::PostMessage([IntPtr]$backdrop.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    throw
}
Start-Sleep -Milliseconds 200

$layout = Test-WorkspaceLayout $area $chatDesktopWindow $pageOnly.contentFrame $gutter $divider $panelWindow
$layering = Test-WorkspacePanelsAboveBackdrop $backdrop $chatDesktopWindow $panelWindow
$headerVisible = Wait-CogentStackHeaderVisible $panelWindow $area
$layoutAccepted = [bool]($layout.verified -and $layering.verified -and $headerVisible -and $pageOnly.topCropRemoved)
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$layoutState = [pscustomobject][ordered]@{
    schemaVersion = 15
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
    dividerHandle = [Int64]$divider.Handle
    dividerProcessId = [int]$divider.ProcessId
    browser = [string]$browser.Name
    reusedExistingTab = $reusedExistingTab
    reusedExistingHomeTab = $reusedExistingHomeTab
    openedNewTab = $openedNewTab
    tabResolution = $tabResolution
    candidateTabsActivated = $candidateTabsActivated
    browserContentMode = 'page-only'
    browserContentClipped = [bool]$pageOnly.contentClipped
    browserTopCropRemoved = [bool]$pageOnly.topCropRemoved
    browserClipInsets = $pageOnly.clipInsets
    gutter = $gutter
    accountState = [string]$panelSelection.AccountState
    workspaceUrl = $safeUrl
    contextKey = $requestedContextKey
    chatProjectKey = [string]$activeChatProject.key
    chatProjectIdentitySource = if ($activeChatProject.Contains('source')) { [string]$activeChatProject.source } else { 'accessibility' }
    chatProjectStableContextFallback = $stableContextFallbackUsed
    chatProjectVisualBindingPending = $stableContextBindingPending
    chatProjectVisualBindingDeadlineUtc = if ($stableContextBindingPending) { [DateTimeOffset]::UtcNow.AddSeconds(30).ToString('O') } else { $null }
    suspendReason = 'none'
    layoutStatus = 'active'
    updatedAt = [DateTimeOffset]::UtcNow.ToString('O')
}
if (-not $layoutAccepted) {
    $restore = Restore-CompanionLayout $layoutState $false $true $true
    Write-CompactJson ([ordered]@{
        status = 'layout_rejected'
        layoutVerified = $false
        layoutDetails = $layout
        workspacePanelsAboveBackdrop = [bool]$layering.verified
        headerVisible = [bool]$headerVisible
        browserTopCropRemoved = [bool]$pageOnly.topCropRemoved
        browserWindowRestored = [bool]$restore.browserWindowRestored
        browserWindowMaximized = [bool]$restore.browserWindowMaximized
        companionExitWatcherStarted = $false
    })
    exit 0
}
Save-LayoutState $layoutState
Save-ContextBinding ([string]$activeChatProject.key) $requestedContextKey $safeUrl

$exitWatcher = Start-CompanionExitWatcher
$workModeShortcut = Install-WorkModeShortcut

Write-CompactJson ([ordered]@{
    status = if ($layoutAccepted) { 'arranged' } else { 'opened_unarranged' }
    layout = 'equal-split-chatgpt-left-cogentstack-right'
    layoutVerified = $layoutAccepted
    headerVisible = [bool]$headerVisible
    browserTopCropRemoved = [bool]$pageOnly.topCropRemoved
    joined = [bool]$layout.joined
    separated = [bool]$layout.separated
    equalWidth = [bool]$layout.equalWidth
    topAligned = [bool]$layout.topAligned
    splitPercent = 50
    gutter = $gutter
    whiteBackdrop = $true
    backdropLayer = 'above-desktop-behind-panels'
    whiteDivider = [bool]$divider
    dividerEdgeVisible = [bool]($divider -and $layout.dividerLayered)
    dividerEdgeColor = '#CDCDCD'
    dividerMasksShadows = [bool]($layout.dividerAligned -and $layout.dividerLayered)
    workspacePanelsAboveBackdrop = [bool]$layering.verified
    browserContentMode = 'page-only'
    browserChromeHidden = $true
    browserContentClipped = [bool]$pageOnly.contentClipped
    companionExitControl = 'header-x'
    companionSuspendControl = 'header-collapse'
    companionExitWatcherStarted = [bool]$exitWatcher
    fastResumeAvailable = $true
    workModeShortcut = $workModeShortcut
    browserClipInsets = $pageOnly.clipInsets
    browser = [string]$browser.Name
    registeredDefault = [bool]$browser.IsRegisteredDefault
    reusedExistingTab = $reusedExistingTab
    reusedExistingHomeTab = $reusedExistingHomeTab
    openedNewTab = $openedNewTab
    tabResolution = $tabResolution
    candidateTabsActivated = $candidateTabsActivated
    accountState = [string]$panelSelection.AccountState
    contextKey = $requestedContextKey
    chatProjectBound = $true
    chatProjectIdentitySource = if ($activeChatProject.Contains('source')) { [string]$activeChatProject.source } else { 'accessibility' }
    chatProjectStableContextFallback = $stableContextFallbackUsed
    chatFrame = $layout.chat
    panelFrame = $layout.panel
    browserWindowFrame = $pageOnly.windowFrame
})
