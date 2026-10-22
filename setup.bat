@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
title Ninja Saga - Instalacion
echo.
echo  Ninja Saga - instalacion para Windows
echo  =====================================
echo.
echo  Esto descarga PHP, MariaDB y Node.js portables (~160 MB),
echo  prepara la base de datos y deja el juego listo para jugar.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\setup-windows.ps1" %*
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (
  echo  La instalacion fallo. Revisa runtime\logs\setup.log
) else (
  echo  Instalacion completada.
)
echo.
pause
exit /b %ERR%
