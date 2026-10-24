@echo off
title Organizador de Downloads - Desinstalador
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\desinstalar.ps1"
pause
