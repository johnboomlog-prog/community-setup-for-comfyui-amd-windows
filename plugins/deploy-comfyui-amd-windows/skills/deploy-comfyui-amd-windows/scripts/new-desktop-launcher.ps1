[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ComfyUIRoot,
    [Parameter(Mandatory)][string]$PythonPath,
    [ValidateRange(1024,65535)][int]$Port = 8188,
    [string]$LauncherPath,
    [string]$ShortcutPath,
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
if (-not $IconPath) { $IconPath = Join-Path $skillRoot 'assets\comfyui.ico' }
if (-not $LauncherPath) { $LauncherPath = Join-Path (Split-Path -Parent $root) 'Launch_ComfyUI_AMD_ROCm.cmd' }
if (-not $ShortcutPath) { $ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ComfyUI AMD ROCm.lnk' }

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

$launcherFull = [IO.Path]::GetFullPath($LauncherPath)
$shortcutFull = [IO.Path]::GetFullPath($ShortcutPath)
if ($PSCmdlet.ShouldProcess($launcherFull, 'Create AMD ComfyUI launcher')) {
    $launcherParent = Split-Path -Parent $launcherFull
    if (-not (Test-Path -LiteralPath $launcherParent)) { New-Item -ItemType Directory -Path $launcherParent -Force | Out-Null }
    [IO.File]::WriteAllText($launcherFull, $content, [Text.UTF8Encoding]::new($false))
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
[ordered]@{ launcher = $launcherFull; shortcut = $shortcutFull; icon = $IconPath; vcvars64 = $VcVarsPath; port = $Port } | ConvertTo-Json
