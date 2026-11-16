@echo off
rem TeknoParrot Manager launcher.
title TeknoParrot Manager
rem Everything below is ONE command line, so cmd has read all of it before the manager starts.
rem An update can replace this file while the manager runs; cmd must never read from this file afterwards.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TeknoParrot-Manager.ps1" %* || (echo.& echo Script exited with an error. Read the message above this line.& echo The log is TeknoParrot-Manager.log, in the TeknoParrotManager\Logs folder inside your TeknoParrot folder.& echo If that folder is not set up yet, the log is next to this launcher.& pause) & call exit /b %%errorlevel%%
