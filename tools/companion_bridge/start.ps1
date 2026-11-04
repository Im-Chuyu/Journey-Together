param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    $modRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    Set-Location -LiteralPath $modRoot
    . (Join-Path $PSScriptRoot 'ensure_python.ps1')
    $pythonExecutable = Get-CompanionPython -BridgeRoot $PSScriptRoot -NoDownload:$CheckOnly
    $windowless = Join-Path (Split-Path -Parent $pythonExecutable) 'pythonw.exe'
    if (-not (Test-Path -LiteralPath $windowless)) { throw 'pythonw.exe is missing. Install the complete Python distribution with Tkinter.' }
    if ($CheckOnly) { @{ready=$true; executable=$windowless} | ConvertTo-Json -Compress; exit 0 }
    Start-Process -FilePath $windowless -ArgumentList @('-B', '-m', 'tools.companion_bridge.launch') -WorkingDirectory $modRoot -WindowStyle Hidden
    exit 0
} catch {
    if ($CheckOnly) { Write-Error $_.Exception.Message; exit 1 }
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Companion assistant startup failed') | Out-Null
    exit 1
}
