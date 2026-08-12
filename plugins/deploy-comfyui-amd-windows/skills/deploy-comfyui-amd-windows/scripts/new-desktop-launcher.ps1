[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ComfyUIRoot,
    [Parameter(Mandatory)][string]$PythonPath,
    [ValidateRange(1024,65535)][int]$Port = 8188,
    [string]$LauncherPath,
    [string]$ShortcutPath,
    [string]$StopScriptPath,
    [string]$StopShortcutPath,
    [string]$IconPath,
    [string]$VcVarsPath,
    [string[]]$ExtraArgument = @()
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ComfyUIRoot)
$python = [IO.Path]::GetFullPath($PythonPath)
if (-not (Test-Path -LiteralPath (Join-Path $root 'main.py') -PathType Leaf)) { throw "ComfyUI main.py not found under: $root" }
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Python executable not found: $python" }

$skillRoot = Split-Path -Parent $PSScriptRoot
if (-not $IconPath) { $IconPath = Join-Path $skillRoot 'assets\community-node-setup.ico' }
if (-not $LauncherPath) { $LauncherPath = Join-Path (Split-Path -Parent $root) 'Launch_ComfyUI_AMD_ROCm.cmd' }
if (-not $ShortcutPath) { $ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ComfyUI AMD ROCm.lnk' }
if (-not $StopScriptPath) { $StopScriptPath = Join-Path (Split-Path -Parent $root) 'Stop_ComfyUI_AMD_ROCm.ps1' }
if (-not $StopShortcutPath) { $StopShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Stop ComfyUI AMD ROCm.lnk' }

if (-not $VcVarsPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($vs) {
            $candidate = Join-Path ($vs | Select-Object -Last 1) 'VC\Auxiliary\Build\vcvars64.bat'
            if (Test-Path -LiteralPath $candidate) { $VcVarsPath = $candidate }
        }
    }
}
if (-not $VcVarsPath) {
    foreach ($candidate in @(
        "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "$env:ProgramFiles\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "$env:ProgramFiles\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
    )) { if (Test-Path -LiteralPath $candidate) { $VcVarsPath = $candidate; break } }
}

function Escape-CmdValue([string]$Value) { $Value.Replace('%','%%').Replace('"','') }
$rootCmd = Escape-CmdValue $root
$pythonCmd = Escape-CmdValue $python
$vcCmd = if ($VcVarsPath) { Escape-CmdValue ([IO.Path]::GetFullPath($VcVarsPath)) } else { '' }
$argCmd = ($ExtraArgument | ForEach-Object { '"' + (Escape-CmdValue $_) + '"' }) -join ' '
$url = "http://127.0.0.1:$Port/"

$template = @'
@echo off
%SystemRoot%\System32\chcp.com 65001 >nul 2>&1
setlocal EnableExtensions
title ComfyUI AMD ROCm
set "COMFYUI_URL=__URL__"
set "COMFYUI_ROOT=__ROOT__"
set "COMFYUI_PYTHON=__PYTHON__"
set "VCVARS64=__VCVARS__"
powershell.exe -NoProfile -Command "try { Invoke-RestMethod '__URL__system_stats' -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto already_running
if /I "%~1"=="--check" (echo OFFLINE& exit /b 1)
if not exist "%COMFYUI_PYTHON%" (echo [ERROR] Python not found: %COMFYUI_PYTHON%& pause& exit /b 2)
if not exist "%COMFYUI_ROOT%\main.py" (echo [ERROR] ComfyUI main.py not found: %COMFYUI_ROOT%& pause& exit /b 3)
if not defined VCVARS64 goto vc_ready
if not exist "%VCVARS64%" goto vc_ready
call "%VCVARS64%" >nul 2>&1
if errorlevel 1 (echo [ERROR] Failed to load Visual Studio x64 environment.& pause& exit /b 4)
:vc_ready
set HIP_VISIBLE_DEVICES=0
set ROCM_SDK_TARGET_FAMILY=custom
set "HF_HOME=%COMFYUI_ROOT%\models\.cache\huggingface"
set "HUGGINGFACE_HUB_CACHE=%HF_HOME%\hub"
set "TORCH_HOME=%COMFYUI_ROOT%\models\.cache\torch"
set "TRITON_CACHE_DIR=%COMFYUI_ROOT%\.cache\triton"
if not exist "%HF_HOME%" mkdir "%HF_HOME%" >nul 2>&1
if not exist "%TORCH_HOME%" mkdir "%TORCH_HOME%" >nul 2>&1
if not exist "%TRITON_CACHE_DIR%" mkdir "%TRITON_CACHE_DIR%" >nul 2>&1
cd /d "%COMFYUI_ROOT%"
echo [INFO] Starting ComfyUI AMD ROCm at %COMFYUI_URL%
echo [INFO] Keep this window open while using ComfyUI.
"%COMFYUI_PYTHON%" main.py --auto-launch --port __PORT__ __ARGS__
echo.
echo [INFO] ComfyUI stopped with exit code %ERRORLEVEL%.
pause
exit /b 0
:already_running
if /I "%~1"=="--check" (echo RUNNING& exit /b 0)
echo [INFO] Healthy ComfyUI instance already running. Opening browser...
start "" "%COMFYUI_URL%"
exit /b 0
'@
$content = $template.Replace('__URL__',$url).Replace('__ROOT__',$rootCmd).Replace('__PYTHON__',$pythonCmd).Replace('__VCVARS__',$vcCmd).Replace('__PORT__',[string]$Port).Replace('__ARGS__',$argCmd)
$content = ($content -replace "`r?`n", "`r`n").TrimEnd("`r","`n") + "`r`n"

$stopTemplate = @'
[CmdletBinding()]
param([switch]$Force,[switch]$Quiet)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$ComfyUIRoot = '__ROOT_PS__'
$ExpectedPython = '__PYTHON_PS__'
$LauncherPath = '__LAUNCHER_PS__'
$Port = __PORT__
$BaseUrl = 'http://127.0.0.1:__PORT__'
$isChinese = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh'

function T([string]$Zh,[string]$En) { if ($isChinese) { $Zh } else { $En } }
function Show-Message([string]$Text,[string]$Title,[string]$Icon='Information') {
    if ($Quiet) { return }
    [Windows.Forms.MessageBox]::Show($Text,$Title,'OK',$Icon) | Out-Null
}

try {
    try {
        $queue = Invoke-RestMethod "$BaseUrl/queue" -TimeoutSec 3
    } catch {
        Show-Message (T 'ComfyUI 当前没有运行，无需关闭。' 'ComfyUI is not running.') (T 'ComfyUI 已关闭' 'ComfyUI is stopped')
        exit 0
    }

    $running = @($queue.queue_running).Count
    $pending = @($queue.queue_pending).Count
    if (($running + $pending) -gt 0 -and -not $Force) {
        if ($Quiet) { exit 3 }
        $answer = [Windows.Forms.MessageBox]::Show(
            (T "ComfyUI 仍有任务。`r`n`r`n正在运行：$running`r`n等待中：$pending`r`n`r`n现在关闭会中断任务，是否仍要关闭？" "ComfyUI still has jobs.`r`n`r`nRunning: $running`r`nPending: $pending`r`n`r`nClosing now interrupts them. Close anyway?"),
            (T '确认关闭 ComfyUI' 'Confirm ComfyUI shutdown'),'YesNo','Warning')
        if ($answer -ne 'Yes') { exit 3 }
    }

    $expectedPythonFull = [IO.Path]::GetFullPath($ExpectedPython)
    $listener = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
    $matches = foreach ($item in $listener) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($item.OwningProcess)" -ErrorAction Stop
        $exeMatches = $process.ExecutablePath -and ([IO.Path]::GetFullPath($process.ExecutablePath) -eq $expectedPythonFull)
        $commandMatches = $process.CommandLine -match '(?i)(^|[\s"''\\/])main\.py(?:\s|$)' -and $process.CommandLine -match "(?i)--port(?:=|\s+)$Port(?:\s|$)"
        if ($exeMatches -and $commandMatches) { $process }
    }
    if (@($matches).Count -ne 1) {
        throw (T '端口上的进程与本安装实例不匹配。为避免误关其他程序，关闭器已停止；请关闭标题为 ComfyUI AMD ROCm 的启动窗口，或向维护者求助。' 'The listening process does not match this installation. To avoid stopping another program, shutdown was refused. Close the ComfyUI AMD ROCm launcher window or ask for help.')
    }

    $target = @($matches)[0]
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($target.ParentProcessId)" -ErrorAction SilentlyContinue
    if (($running + $pending) -gt 0) {
        try { Invoke-RestMethod "$BaseUrl/interrupt" -Method Post -TimeoutSec 3 | Out-Null } catch { }
        Start-Sleep -Milliseconds 500
    }
    Stop-Process -Id $target.ProcessId -ErrorAction Stop
    try { Wait-Process -Id $target.ProcessId -Timeout 10 -ErrorAction Stop } catch { }
    if (Get-Process -Id $target.ProcessId -ErrorAction SilentlyContinue) {
        throw (T 'ComfyUI 未能在 10 秒内退出。' 'ComfyUI did not exit within 10 seconds.')
    }

    if ($parent -and $parent.Name -ieq 'cmd.exe' -and $parent.CommandLine -like "*$LauncherPath*") {
        Stop-Process -Id $parent.ProcessId -ErrorAction SilentlyContinue
    }
    Show-Message (T 'ComfyUI 已正常关闭。' 'ComfyUI has been stopped.') (T '关闭完成' 'Shutdown complete')
} catch {
    if ($Quiet) { [Console]::Error.WriteLine($_.Exception.Message) }
    Show-Message ((T '无法安全关闭 ComfyUI：' 'Could not safely stop ComfyUI:') + "`r`n`r`n" + $_.Exception.Message) (T '关闭未完成' 'Shutdown incomplete') 'Error'
    exit 2
}
'@
function Escape-PsSingleQuoted([string]$Value) { $Value.Replace("'", "''") }
$rootPs = Escape-PsSingleQuoted $root
$pythonPs = Escape-PsSingleQuoted $python
$launcherPs = Escape-PsSingleQuoted ([IO.Path]::GetFullPath($LauncherPath))
$stopContent = $stopTemplate.Replace('__ROOT_PS__',$rootPs).Replace('__PYTHON_PS__',$pythonPs).Replace('__LAUNCHER_PS__',$launcherPs).Replace('__PORT__',[string]$Port)
$stopContent = ($stopContent -replace "`r?`n", "`r`n").TrimEnd("`r","`n") + "`r`n"

$launcherFull = [IO.Path]::GetFullPath($LauncherPath)
$shortcutFull = [IO.Path]::GetFullPath($ShortcutPath)
$stopScriptFull = [IO.Path]::GetFullPath($StopScriptPath)
$stopShortcutFull = [IO.Path]::GetFullPath($StopShortcutPath)
if ($PSCmdlet.ShouldProcess($launcherFull, 'Create AMD ComfyUI launcher')) {
    $launcherParent = Split-Path -Parent $launcherFull
    if (-not (Test-Path -LiteralPath $launcherParent)) { New-Item -ItemType Directory -Path $launcherParent -Force | Out-Null }
    [IO.File]::WriteAllText($launcherFull, $content, [Text.UTF8Encoding]::new($false))
}
if ($PSCmdlet.ShouldProcess($stopScriptFull, 'Create AMD ComfyUI shutdown tool')) {
    $stopParent = Split-Path -Parent $stopScriptFull
    if (-not (Test-Path -LiteralPath $stopParent)) { New-Item -ItemType Directory -Path $stopParent -Force | Out-Null }
    # Windows PowerShell 5 requires a BOM to parse non-ASCII script literals reliably.
    [IO.File]::WriteAllText($stopScriptFull, $stopContent, [Text.UTF8Encoding]::new($true))
}
if ($PSCmdlet.ShouldProcess($shortcutFull, 'Create desktop shortcut')) {
    $shortcutParent = Split-Path -Parent $shortcutFull
    if (-not (Test-Path -LiteralPath $shortcutParent)) { New-Item -ItemType Directory -Path $shortcutParent -Force | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutFull)
    $shortcut.TargetPath = $launcherFull
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'ComfyUI AMD ROCm launcher'
    if (Test-Path -LiteralPath $IconPath) { $shortcut.IconLocation = ([IO.Path]::GetFullPath($IconPath)) + ',0' }
    $shortcut.Save()
}
if ($PSCmdlet.ShouldProcess($stopShortcutFull, 'Create desktop shutdown shortcut')) {
    $stopShortcutParent = Split-Path -Parent $stopShortcutFull
    if (-not (Test-Path -LiteralPath $stopShortcutParent)) { New-Item -ItemType Directory -Path $stopShortcutParent -Force | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($stopShortcutFull)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $stopScriptFull + '"'
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'Safely stop this ComfyUI AMD ROCm instance'
    if (Test-Path -LiteralPath $IconPath) { $shortcut.IconLocation = ([IO.Path]::GetFullPath($IconPath)) + ',0' }
    $shortcut.Save()
}
[ordered]@{ launcher = $launcherFull; shortcut = $shortcutFull; stopScript = $stopScriptFull; stopShortcut = $stopShortcutFull; icon = $IconPath; vcvars64 = $VcVarsPath; port = $Port } | ConvertTo-Json
