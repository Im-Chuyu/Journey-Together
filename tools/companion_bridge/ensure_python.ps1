function Test-CompanionPython {
    param([string]$Executable)
    if (-not (Test-Path -LiteralPath $Executable) -or -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $Executable) 'pythonw.exe'))) { return $false }
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable -B -c 'import sys, tkinter; assert sys.version_info >= (3,10) and sys.maxsize > 2**32; tkinter.Tcl()' *> $null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
    finally { $ErrorActionPreference = $savedPreference }
}

function Test-CompanionInstallerHash {
    param([string]$Path, [string]$ExpectedHash)
    if (-not [IO.File]::Exists($Path)) { return $false }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        $digest = [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '')
        return $digest -eq $ExpectedHash
    } finally {
        if ($stream) { $stream.Dispose() }
        $sha256.Dispose()
    }
}

function Save-CompanionPythonInstaller {
    param([string[]]$Sources, [string]$Installer, [string]$ExpectedHash, $Form, $Label)
    $ErrorActionPreference = 'Stop'
    if (Test-CompanionInstallerHash $Installer $ExpectedHash) { return }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $failures = @()
    foreach ($source in $Sources) {
        $sourceHost = ([Uri]$source).Host
        $part = "$Installer.$([Guid]::NewGuid().ToString('N')).part"
        $client = [Net.WebClient]::new()
        try {
            if ($Form) {
                $Label.Text = "正在从 $sourceHost 下载 Python，请稍候。"
                [System.Windows.Forms.Application]::DoEvents()
                if ($Form.IsDisposed) { throw '已取消 Python 准备。' }
            }
            $download = $client.DownloadFileTaskAsync([Uri]$source, $part)
            $deadline = [DateTime]::UtcNow.AddMinutes(10)
            $idleDeadline = [DateTime]::UtcNow.AddSeconds(25)
            $lastLength = 0
            while (-not $download.IsCompleted) {
                if ($Form) {
                    [System.Windows.Forms.Application]::DoEvents()
                    if ($Form.IsDisposed) { throw '已取消 Python 准备。' }
                }
                $file = Get-Item -LiteralPath $part -ErrorAction SilentlyContinue
                $now = [DateTime]::UtcNow
                if ($file -and $file.Length -gt $lastLength) {
                    $lastLength = $file.Length
                    $idleDeadline = $now.AddSeconds(25)
                }
                if ($now -ge $idleDeadline -or $now -ge $deadline) { throw '下载超时。' }
                Start-Sleep -Milliseconds 100
            }
            $download.GetAwaiter().GetResult() | Out-Null
            if (-not (Test-CompanionInstallerHash $part $ExpectedHash)) {
                throw '安装包 SHA-256 校验失败。'
            }
            Move-Item -LiteralPath $part -Destination $Installer -Force
            return
        } catch {
            if ($Form -and $Form.IsDisposed) { throw }
            $failures += "${sourceHost}：$($_.Exception.GetBaseException().Message)"
        } finally {
            $client.CancelAsync()
            $client.Dispose()
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        }
    }
    throw ("所有 Python 下载源均失败。可稍后重试，或将同版本的 64 位完整安装包放到以下路径后重试：" +
        "`n$Installer`n`n" + ($failures -join "`n"))
}

function Get-CompanionPython {
    param([string]$BridgeRoot = $PSScriptRoot, [switch]$NoDownload, [switch]$Quiet)
    $ErrorActionPreference = 'Stop'
    . (Join-Path $BridgeRoot 'paths.ps1')
    $dataRoot = Get-CompanionDataRoot
    $runtime = Join-Path $dataRoot 'python'
    $python = Join-Path $runtime 'python.exe'
    if (Test-CompanionPython $python) { return $python }
    $installed = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($installed -and $installed.Source -notlike '*\WindowsApps\*') {
        if (Test-CompanionPython $installed.Source) { return $installed.Source }
    }
    foreach ($registryRoot in @('HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore')) {
        foreach ($version in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
            $install = Get-Item -LiteralPath ($version.PSPath + '\InstallPath') -ErrorAction SilentlyContinue
            if ($install -and $install.GetValue('')) {
                $candidate = Join-Path $install.GetValue('') 'python.exe'
                if (Test-CompanionPython $candidate) { return $candidate }
            }
        }
    }
    if ($NoDownload) { throw 'Python with Tkinter is not ready. Run StartVoice.vbs to prepare it.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'The assistant bootstrap requires 64-bit Windows.' }
    $cache = Join-Path $dataRoot 'downloads'
    $logs = Join-Path $dataRoot 'logs'
    New-Item -ItemType Directory -Force -Path $cache, $logs | Out-Null
    $version = '3.14.10'
    $installerName = "python-$version-amd64.exe"
    $installer = Join-Path $cache $installerName
    $sources = @(
        "https://www.python.org/ftp/python/$version/$installerName"
        "https://mirrors.aliyun.com/python-release/windows/$installerName"
        "https://mirrors.huaweicloud.com/python/$version/$installerName"
    )
    $expectedHash = '92480239264744fe0386a1bd8275786fefa126e3129e56a68e22b52c73329965'
    $form = $null
    $label = $null
    try {
        if (-not $Quiet) {
            Add-Type -AssemblyName System.Windows.Forms
            $form = New-Object System.Windows.Forms.Form
            $form.Text = '一路同行 · 首次准备'
            $form.Width = 500; $form.Height = 180; $form.StartPosition = 'CenterScreen'
            $label = New-Object System.Windows.Forms.Label
            $label.Text = '首次运行，正在下载 Python 到模组本地目录，请稍候。'
            $label.SetBounds(16, 16, 450, 48); $form.Controls.Add($label)
            $bar = New-Object System.Windows.Forms.ProgressBar
            $bar.Style = 'Marquee'; $bar.SetBounds(16, 70, 450, 18); $form.Controls.Add($bar)
            $form.Show(); [System.Windows.Forms.Application]::DoEvents()
        }
        Save-CompanionPythonInstaller -Sources $sources -Installer $installer -ExpectedHash $expectedHash -Form $form -Label $label
        if (-not (Test-CompanionInstallerHash $installer $expectedHash)) { throw 'Python 安装包 SHA-256 校验失败。' }
        if ($form) {
            if ($form.IsDisposed) { throw 'Python preparation cancelled.' }
            $label.Text = '下载完成，正在配置 Python 和窗口组件，请稍候。'
            $form.ControlBox = $false; $label.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        }
        $arguments = @('/quiet', 'InstallAllUsers=0', ('TargetDir="'+$runtime+'"'),
            'Include_launcher=0', 'Include_test=0', 'Include_doc=0', 'Include_dev=0', 'Include_tools=0',
            'Include_tcltk=1', 'Include_pip=1', 'Shortcuts=0', 'PrependPath=0', 'AssociateFiles=0', 'CompileAll=0',
            '/log', ('"'+(Join-Path $logs 'python-install.log')+'"'))
        $process = Start-Process -FilePath $installer -ArgumentList $arguments -PassThru -WindowStyle Hidden
        while (-not $process.WaitForExit(100)) { if ($form) { [System.Windows.Forms.Application]::DoEvents() } }
        if ($process.ExitCode -notin @(0, 3010)) { throw ('Python installation failed. Log: '+(Join-Path $logs 'python-install.log')+'. Exit: '+$process.ExitCode) }
        if (-not (Test-CompanionPython $python)) { throw 'Python/Tkinter preparation failed.' }
        return $python
    } finally {
        if ($form) { $form.Dispose() }
    }
}
