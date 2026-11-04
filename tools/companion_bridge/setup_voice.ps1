$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ensure_python.ps1')
    $basePython = Get-CompanionPython -BridgeRoot $PSScriptRoot
    $dataRoot = Get-CompanionDataRoot
    $runtime = Join-Path $dataRoot 'voice-runtime'
    $python = Join-Path $runtime 'Scripts\python.exe'
    $ready = $false
    if (Test-Path -LiteralPath $python) {
        & $python -B -c 'import sys' 2>$null
        $ready = $LASTEXITCODE -eq 0
    }
    if (-not $ready) {
        & $basePython -m venv $runtime
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create local speech runtime.' }
    }
    & $python -m pip install --disable-pip-version-check --no-cache-dir -r (Join-Path $PSScriptRoot 'requirements-voice.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Speech dependency installation failed.' }
    $model = Join-Path $dataRoot 'models\faster-whisper-small'
    & $python -B (Join-Path $PSScriptRoot 'whisper_worker.py') --mode prepare --model $model
    if ($LASTEXITCODE -ne 0) { throw 'Whisper model download failed. Check connectivity and retry.' }
    Write-Output 'Local speech runtime and small model ready.'
    exit 0
} catch {
    Write-Output $_.Exception.Message
    exit 1
}
