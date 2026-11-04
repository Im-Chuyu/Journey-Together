function Initialize-CompanionVoice {
    param([string]$BridgeRoot = $PSScriptRoot)
    $ErrorActionPreference = 'Stop'
    . (Join-Path $BridgeRoot 'paths.ps1')
    $dataRoot = Get-CompanionDataRoot
    $python = Join-Path $dataRoot 'voice-runtime\Scripts\python.exe'
    $model = Join-Path $dataRoot 'models\faster-whisper-small\model.bin'
    if ((Test-Path -LiteralPath $python) -and (Test-Path -LiteralPath $model)) {
        & $python -B -c 'import faster_whisper, sounddevice' 2>$null
        if ($LASTEXITCODE -eq 0) { return }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '一路同行 · 首次准备语音'
    $form.Width = 520; $form.Height = 160; $form.StartPosition = 'CenterScreen'
    $label = New-Object System.Windows.Forms.Label
    $label.Text = '正在准备离线语音和下载模型（约461MB）。首次需要联网，请稍候。'
    $label.SetBounds(16,16,470,48); $form.Controls.Add($label)
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Style = 'Marquee'; $bar.SetBounds(16,70,470,18); $form.Controls.Add($bar)
    $logs = Join-Path $dataRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $process = $null
    try {
        $form.Show(); [System.Windows.Forms.Application]::DoEvents()
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $BridgeRoot 'setup_voice.ps1')+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'voice-bootstrap.log') -RedirectStandardError (Join-Path $logs 'voice-bootstrap-error.log')
        while (-not $process.WaitForExit(100)) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($form.IsDisposed) {
                & taskkill.exe /PID $process.Id /T /F *> $null
                throw 'Voice preparation cancelled. Run the launcher again to resume.'
            }
        }
        if ($process.ExitCode -ne 0) { throw ('Voice preparation failed. Log: '+(Join-Path $logs 'voice-bootstrap.log')) }
    } finally { $form.Dispose() }
}
