[CmdletBinding()]
param([ValidateRange(0, 10000)][int]$TimeoutMilliseconds = 3000)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Find-NamedElement {
    param([System.Windows.Automation.AutomationElement]$Root, [string]$Name)
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $Name
    )
    return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Get-ClaudeWindowCandidates {
    $candidates = @()
    foreach ($process in @(Get-Process -Name Claude -ErrorAction SilentlyContinue)) {
        if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
            if ($null -eq $root) { continue }
            $hide = Find-NamedElement -Root $root -Name 'Hide sidebar'
            $show = Find-NamedElement -Root $root -Name 'Show sidebar'
            if ($null -ne $hide -or $null -ne $show) {
                $candidates += [pscustomobject]@{ ProcessId = $process.Id; Root = $root; Hide = $hide; Show = $show }
            }
        } catch { continue }
    }
    return @($candidates)
}

$deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
do {
    $candidates = @(Get-ClaudeWindowCandidates)
    if ($candidates.Count -eq 1) { break }
    if ($TimeoutMilliseconds -gt 0) { Start-Sleep -Milliseconds 100 }
} while ([DateTime]::UtcNow -lt $deadline)

if ($candidates.Count -eq 0) {
    [ordered]@{ status = 'unavailable'; message = 'No accessible Claude Code Desktop window with a sidebar toggle was found.' } | ConvertTo-Json -Compress
    exit 2
}
if ($candidates.Count -gt 1) {
    [ordered]@{ status = 'ambiguous'; message = 'More than one accessible Claude Code Desktop window has a sidebar toggle.'; candidateCount = $candidates.Count } | ConvertTo-Json -Compress
    exit 3
}

$candidate = $candidates[0]
if ($null -ne $candidate.Show) {
    [ordered]@{ status = 'already_hidden'; processId = $candidate.ProcessId } | ConvertTo-Json -Compress
    exit 0
}
$candidate.Hide.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
$verifyDeadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(500, $TimeoutMilliseconds))
do {
    Start-Sleep -Milliseconds 100
    if ($null -ne (Find-NamedElement -Root $candidate.Root -Name 'Show sidebar')) {
        [ordered]@{ status = 'hidden'; processId = $candidate.ProcessId } | ConvertTo-Json -Compress
        exit 0
    }
} while ([DateTime]::UtcNow -lt $verifyDeadline)

[ordered]@{ status = 'failed'; message = 'The Claude Code Desktop sidebar did not report a closed state.'; processId = $candidate.ProcessId } | ConvertTo-Json -Compress
exit 4
