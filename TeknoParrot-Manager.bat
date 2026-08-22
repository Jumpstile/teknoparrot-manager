@echo off
rem TeknoParrot Manager v1.0 RC7 launcher.
title TeknoParrot Manager
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TeknoParrot-Manager.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Script exited with an error. Check TeknoParrot-Manager.log for details.
    pause
)
