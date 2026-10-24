@echo off
title Neatly - Instalador
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\instalar.ps1"
echo.
pause
