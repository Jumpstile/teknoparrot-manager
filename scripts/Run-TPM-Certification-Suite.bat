@echo off
setlocal EnableDelayedExpansion
title TeknoParrot Manager Certification Suite
echo.
echo  TeknoParrot Manager Certification Suite
echo.
set "REPO_ROOT=%TPM_REPO_ROOT%"
if not "%~1"=="" set "REPO_ROOT=%~1"
if not defined REPO_ROOT (
    pushd "%~dp0.." >nul 2>nul
    if errorlevel 1 (
        echo ERROR: Could not resolve the repository root.
        exit /b 1
    )
    set "REPO_ROOT=!CD!"
    popd >nul
)
set "DEFAULT_TP_ROOT=C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot"
if not exist "%REPO_ROOT%\scripts\Run-TPM-Tests.ps1" (
    echo ERROR: Certification runner not found under %REPO_ROOT%.
    exit /b 1
)
pushd "%REPO_ROOT%"
if errorlevel 1 (
    echo ERROR: Could not enter repository folder %REPO_ROOT%.
    exit /b 1
)
echo Repository:
echo   %REPO_ROOT%
echo.
set "TP_ROOT=%~2"
if defined TPM_TEKNOPARROT_ROOT set "TP_ROOT=%TPM_TEKNOPARROT_ROOT%"
if not "%~2"=="" set "TP_ROOT=%~2"
if not defined TP_ROOT (
echo Default TeknoParrot root:
echo   %DEFAULT_TP_ROOT%
echo.
    set /p "TP_ROOT=Before certification starts, press Enter for the default or enter the TeknoParrot path: "
)
if not defined TP_ROOT set "TP_ROOT=%DEFAULT_TP_ROOT%"
echo.
echo Repository synchronization is not performed by certification.
echo The checked-out commit shown by the runner is the tested source.
echo.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\scripts\Run-TPM-Tests.ps1" -RepoPath "%REPO_ROOT%" -TeknoParrotRoot "%TP_ROOT%"
set "RUN_EXIT=%ERRORLEVEL%"
echo.
echo Certification process exit code: %RUN_EXIT%
set "HARNESS_REPORTS=%REPO_ROOT%\..\TPM-TestHarness\Reports"
set "LATEST_REPORT="
if exist "%HARNESS_REPORTS%" (
    for /f "delims=" %%D in ('dir "%HARNESS_REPORTS%" /b /ad /o-d 2^>nul') do (
        if not defined LATEST_REPORT set "LATEST_REPORT=%HARNESS_REPORTS%\%%D"
    )
)
if defined LATEST_REPORT (
    echo Report folder:
    echo   %LATEST_REPORT%
    echo.
)
rem Presentation is explicitly opt-in. It occurs only after RUN_EXIT is saved
rem and can never replace the certification result. API/noninteractive callers
rem leave TPM_PRESENT_RESULTS unset and therefore get neither Explorer nor pause.
if /i "%TPM_PRESENT_RESULTS%"=="1" (
    if defined LATEST_REPORT (
        echo Opening the completed report folder...
        start "" explorer.exe "%LATEST_REPORT%"
    )
    echo.
    echo Certification is complete. Press any key to close this window.
    pause >nul
)
popd >nul
endlocal & exit /b %RUN_EXIT%
