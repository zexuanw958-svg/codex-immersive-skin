@echo off
setlocal
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0scripts\customize-theme-windows.ps1" %*
set "CODEX_IMMERSIVE_EXIT=%ERRORLEVEL%"
if not "%CODEX_IMMERSIVE_EXIT%"=="0" if not defined CODEX_IMMERSIVE_NO_PAUSE pause
exit /b %CODEX_IMMERSIVE_EXIT%
