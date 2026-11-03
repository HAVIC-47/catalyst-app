@echo off
rem Double-click to build dist\catalyst_<version>.aab for Google Play (see build_aab.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_aab.ps1" %*
pause
