@echo off
title Neatly - Desinstalador
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\desinstalar.ps1"
pause
