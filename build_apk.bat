@echo off
rem Double-click to build dist\Catalyst.apk (see build_apk.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_apk.ps1" %*
pause
