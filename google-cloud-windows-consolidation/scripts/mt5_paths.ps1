# Canonical MT5 terminal discovery for Windows PowerShell 5.1+.
function Find-MT5Terminal {
    param([string]$ConfiguredPath = $env:MT5_TERMINAL_PATH)

    $candidates = @()
    if ($ConfiguredPath) { $candidates += $ConfiguredPath.Trim('"') }
    $candidates += @(
        "C:\Program Files\VIG Group MT5 Terminal\terminal64.exe",
        "C:\Program Files\MetaTrader 5\terminal64.exe",
        "C:\Program Files (x86)\MetaTrader 5\terminal64.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}
