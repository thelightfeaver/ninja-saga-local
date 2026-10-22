@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
title Ninja Saga - Detener
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\stop-windows.ps1"
set "ERR=%ERRORLEVEL%"
echo.
pause
exit /b %ERR%
