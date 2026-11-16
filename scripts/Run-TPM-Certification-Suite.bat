@echo off
setlocal EnableExtensions
title TeknoParrot Manager Certification Suite
echo.
echo  TeknoParrot Manager Certification Suite
echo.
set "REPO_ROOT=%TPM_REPO_ROOT%"
if not "%~1"=="" set "REPO_ROOT=%~1"
rem No pushd here: for a \\server\share repository, pushd maps a temporary drive letter and popd takes it away again.
if not defined REPO_ROOT for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"
rem A folder written with a closing backslash is the same folder. The runner looks for the reports next to the repository folder.
if "%REPO_ROOT:~-1%"=="\" if not "%REPO_ROOT:~-2%"==":\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
rem There is no default TeknoParrot folder. A run reads the folder it is given, so the folder must be named on purpose:
rem argument 2 or TPM_TEKNOPARROT_ROOT. The run also starts only when TPM_REAL_DATA_TESTS=1 is set (see docs\TPM-CERTIFICATION-SUITE.md).
if not exist "%REPO_ROOT%\scripts\Run-TPM-Tests.ps1" echo ERROR: Certification runner not found under "%REPO_ROOT%".
if not exist "%REPO_ROOT%\scripts\Run-TPM-Tests.ps1" exit /b 1
pushd "%REPO_ROOT%"
if errorlevel 1 echo ERROR: Could not enter repository folder "%REPO_ROOT%".
if errorlevel 1 exit /b 1
echo Repository:
echo   "%REPO_ROOT%"
echo.
set "TP_ROOT="
if defined TPM_TEKNOPARROT_ROOT set "TP_ROOT=%TPM_TEKNOPARROT_ROOT%"
if not "%~2"=="" set "TP_ROOT=%~2"
if not defined TP_ROOT (
    echo ERROR: No TeknoParrot folder was given. Nothing was read or changed.
    echo.
    echo This file does nothing useful when you double-click it.
    echo Open a console window in the repository folder, then type:
    echo.
    echo   set TPM_REAL_DATA_TESTS=1
    echo   set TPM_TEKNOPARROT_ROOT=YOUR-TEKNOPARROT-FOLDER
    echo   scripts\Run-TPM-Certification-Suite.bat
    echo.
    echo You can also give the folder as the second argument.
    echo The run reads that folder, so it only starts with TPM_REAL_DATA_TESTS=1.
    echo.
    echo Press any key to close this window.
    pause >nul
    popd >nul
    exit /b 2
)
if "%TP_ROOT:~-1%"=="\" if not "%TP_ROOT:~-2%"==":\" set "TP_ROOT=%TP_ROOT:~0,-1%"
echo.
echo Repository synchronization is not performed by certification.
echo The checked-out commit shown by the runner is the tested source.
echo.
rem PowerShell reads a backslash in front of a closing quote as an escaped quote. A folder that still ends in one (a drive such as D:\) gets a second one.
set "ARG_REPO=%REPO_ROOT%"
set "ARG_TP=%TP_ROOT%"
if "%ARG_REPO:~-1%"=="\" set "ARG_REPO=%ARG_REPO%\"
if "%ARG_TP:~-1%"=="\" set "ARG_TP=%ARG_TP%\"
set "HARNESS_REPORTS=%REPO_ROOT%\..\TPM-TestHarness\Reports"
for %%I in ("%HARNESS_REPORTS%") do set "HARNESS_REPORTS=%%~fI"
set "BEFORE_REPORT="
if exist "%HARNESS_REPORTS%" for /f "delims=" %%D in ('dir "%HARNESS_REPORTS%" /b /ad /o-d 2^>nul') do if not defined BEFORE_REPORT set "BEFORE_REPORT=%%D"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\scripts\Run-TPM-Tests.ps1" -RepoPath "%ARG_REPO%" -TeknoParrotRoot "%ARG_TP%"
set "RUN_EXIT=%ERRORLEVEL%"
echo.
echo Certification process exit code: %RUN_EXIT%
rem Only a report folder that did not exist before this run belongs to this run.
set "LATEST_REPORT="
if exist "%HARNESS_REPORTS%" for /f "delims=" %%D in ('dir "%HARNESS_REPORTS%" /b /ad /o-d 2^>nul') do if not defined LATEST_REPORT set "LATEST_REPORT=%%D"
set "NEW_REPORT="
if defined LATEST_REPORT if /i not "%LATEST_REPORT%"=="%BEFORE_REPORT%" set "NEW_REPORT=%HARNESS_REPORTS%\%LATEST_REPORT%"
if defined NEW_REPORT echo Report folder:
if defined NEW_REPORT echo   "%NEW_REPORT%"
if not defined NEW_REPORT echo This run did not write a report.
echo.
rem Presentation is explicitly opt-in. It occurs only after RUN_EXIT is saved
rem and can never replace the certification result. API/noninteractive callers
rem leave TPM_PRESENT_RESULTS unset and therefore get neither Explorer nor pause.
if /i not "%TPM_PRESENT_RESULTS%"=="1" goto :finish
if defined NEW_REPORT echo Opening the completed report folder...
if defined NEW_REPORT start "" explorer.exe "%NEW_REPORT%"
echo.
if defined NEW_REPORT echo Certification is complete. Press any key to close this window.
if not defined NEW_REPORT echo Certification did not write a report. Press any key to close this window.
pause >nul
:finish
popd >nul
endlocal & exit /b %RUN_EXIT%
