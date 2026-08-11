@echo off
setlocal
set "WIZARD_DIR=%~dp0"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" (
  echo Windows PowerShell 5.1 was not found.
  pause
  exit /b 1
)
"%POWERSHELL_EXE%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%WIZARD_DIR%Community-Setup-for-ComfyUI.ps1"
if errorlevel 1 (
  echo.
  echo The deployment wizard exited with an error. See the report directory for details.
  pause
)
