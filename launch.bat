@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
title Ninja Saga - Servidor local
echo.
echo  Iniciando Ninja Saga...
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\launch-windows.ps1" %*
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (
  echo  No se pudo iniciar. Revisa runtime\logs\ y ejecuta setup.bat si es la primera vez.
  echo.
  pause
)
exit /b %ERR%
