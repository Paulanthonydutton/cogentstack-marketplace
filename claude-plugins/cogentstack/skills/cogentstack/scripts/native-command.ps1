Set-StrictMode -Version Latest

function Invoke-CogentStackNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $nativeOutput = ''
    $nativeExitCode = -1
    try {
        # Windows PowerShell 5.1 promotes native stderr records according to
        # ErrorActionPreference. Capture both streams without allowing a warning
        # from a successful process to skip the real exit-code check.
        $ErrorActionPreference = 'Continue'
        $nativeOutput = & $FilePath @ArgumentList 2>&1 | Out-String
        $nativeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = [int]$nativeExitCode
        Output = $nativeOutput.Trim()
    }
}
