@echo off
title TeknoParrot Manager
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TeknoParrot-Manager.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Script exited with an error. Check TeknoParrot-Manager.log for details.
    pause
)
