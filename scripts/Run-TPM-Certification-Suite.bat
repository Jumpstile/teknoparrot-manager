@echo off
setlocal EnableDelayedExpansion

title TeknoParrot Manager Certification Suite

echo.
echo ============================================
echo  TeknoParrot Manager Certification Suite
echo ============================================
echo.

rem This file is meant to be double-clicked from anywhere -- the Desktop, a
rem USB stick, wherever -- not just from inside the repo's scripts\ folder.
rem That means it can't rely on its own location (%~dp0) to find the repo;
rem it needs the repo's real path hardcoded here instead. Edit REPO_ROOT if
rem the repo ever moves.
set "REPO_ROOT=E:\Development\teknoparrot-manager"
set "DEFAULT_TP_ROOT=C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot"

if not exist "%REPO_ROOT%\scripts\Run-TPM-Tests.ps1" (
    echo ERROR: Repository not found at:
    echo   %REPO_ROOT%
    echo.
    echo Edit REPO_ROOT near the top of this .bat file if the repo has moved.
    echo.
    pause
    exit /b 1
)

cd /d "%REPO_ROOT%"

echo Repository:
echo   %REPO_ROOT%
echo.

rem Auto-update to the latest pushed commit on whatever branch is currently
rem checked out, before running. This intentionally discards any local
rem changes in the repo (git reset --hard) -- this repo checkout is meant
rem to be a pure pull-and-run copy for certification, not a place to keep
rem uncommitted local edits. Never hard-fails the whole run over this: a
rem network hiccup or detached HEAD just means the run proceeds with
rem whatever is already on disk, with a clear warning printed either way.
echo Updating repository to latest...
set "CURRENT_BRANCH="
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "CURRENT_BRANCH=%%B"

if not defined CURRENT_BRANCH (
    echo WARNING: Could not determine the current git branch -- skipping auto-update.
    echo Running with whatever is currently checked out.
    echo.
) else (
    git fetch origin
    if errorlevel 1 (
        echo WARNING: git fetch failed -- no network, or remote unreachable.
        echo Running with whatever is currently checked out.
        echo.
    ) else (
        git reset --hard origin/%CURRENT_BRANCH%
        if errorlevel 1 (
            echo WARNING: git reset failed -- running with whatever is currently checked out.
            echo.
        ) else (
            echo Repository updated to latest origin/%CURRENT_BRANCH%.
            echo.
        )
    )
)

echo Default TeknoParrot root:
echo   %DEFAULT_TP_ROOT%
echo.
set /p "TP_ROOT=Press Enter to use default, or paste TeknoParrot root path: "

if "%TP_ROOT%"=="" set "TP_ROOT=%DEFAULT_TP_ROOT%"

echo.
echo Running certification suite...
echo TeknoParrot root:
echo   %TP_ROOT%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Run-TPM-Tests.ps1" -TeknoParrotRoot "%TP_ROOT%"
set "RUN_EXIT=%ERRORLEVEL%"

echo.
echo ============================================
echo  Certification run finished
echo ============================================
echo.

if not "%RUN_EXIT%"=="0" (
    echo Exit code: %RUN_EXIT%  ^(see output above for details^)
    echo.
)

rem Run-TPM-Tests.ps1 / Invoke-TPM-RealInstanceSmoke.ps1 place reports under
rem TPM-TestHarness\Reports\<timestamp>, as a sibling of the repo folder by
rem default -- find the most recently created one and point the user at it.
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
    if exist "%LATEST_REPORT%\TPM-Certification-Scorecard.md" (
        echo Certification scorecard:
        echo   %LATEST_REPORT%\TPM-Certification-Scorecard.md
        echo.
    )
    if exist "%LATEST_REPORT%\TPM-Validation-Report.md" (
        echo Validation report:
        echo   %LATEST_REPORT%\TPM-Validation-Report.md
        echo.
    )
    echo Opening report folder...
    start "" explorer.exe "%LATEST_REPORT%"
) else (
    echo Report folder not found under:
    echo   %HARNESS_REPORTS%
    echo.
)

echo Review the output above and the report files for full details.
echo.
pause
endlocal
