@echo off
setlocal EnableDelayedExpansion

title TeknoParrot Manager Certification Suite

echo.
echo ============================================
echo  TeknoParrot Manager Certification Suite
echo ============================================
echo.

rem Default to the checked-out repo that contains this scripts\ folder. If
rem this .bat was copied elsewhere, pass the repo path as the first argument
rem or set TPM_REPO_ROOT before running it.
set "REPO_ROOT=%TPM_REPO_ROOT%"
if not "%~1"=="" set "REPO_ROOT=%~1"
if not defined REPO_ROOT (
    pushd "%~dp0.." >nul 2>nul
    if errorlevel 1 (
        echo ERROR: Could not resolve the repository root from:
        echo   %~dp0..
        echo.
        echo Run this launcher from scripts\ inside a TPM git checkout,
        echo pass the repo path as the first argument, or set TPM_REPO_ROOT.
        echo.
        pause
        exit /b 1
    )
    set "REPO_ROOT=!CD!"
    popd >nul
)
set "DEFAULT_TP_ROOT=C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot"

if not exist "%REPO_ROOT%\scripts\Run-TPM-Tests.ps1" (
    echo ERROR: Repository not found at:
    echo   %REPO_ROOT%
    echo.
    echo Run this launcher from scripts\ inside a TPM git checkout,
    echo pass the repo path as the first argument, or set TPM_REPO_ROOT.
    echo.
    pause
    exit /b 1
)

pushd "%REPO_ROOT%"
if errorlevel 1 (
    echo ERROR: Could not enter repository folder:
    echo   %REPO_ROOT%
    echo.
    pause
    exit /b 1
)

echo Repository:
echo   %REPO_ROOT%
echo.

rem Auto-update to the latest pushed commit on whatever branch is currently
rem checked out, before running. This is fast-forward only: it never force
rem resets or discards local work. A network hiccup or detached HEAD just
rem means the run proceeds with whatever is already on disk, with a clear
rem warning printed either way.
echo Updating repository to latest...
set "CURRENT_BRANCH="
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "CURRENT_BRANCH=%%B"
set "COMMIT_BEFORE="
for /f "delims=" %%C in ('git rev-parse --short HEAD 2^>nul') do set "COMMIT_BEFORE=%%C"
echo Commit before sync: %COMMIT_BEFORE%

if not defined CURRENT_BRANCH (
    echo WARNING: Could not determine the current git branch -- skipping auto-update.
    echo Running with whatever is currently checked out.
    echo.
) else (
    set "DIRTY_TRACKED="
    for /f "delims=" %%S in ('git status --porcelain --untracked-files=no 2^>nul') do set "DIRTY_TRACKED=1"
    if defined DIRTY_TRACKED (
        echo WARNING: Tracked files have local changes -- skipping auto-update.
        echo Commit or stash tracked changes before using this as release evidence.
        echo Running with whatever is currently checked out ^(commit %COMMIT_BEFORE%^).
        echo.
    ) else (
        git fetch origin
        if errorlevel 1 (
            echo WARNING: git fetch failed -- no network, or remote unreachable.
            echo Running with whatever is currently checked out ^(commit %COMMIT_BEFORE%^).
            echo.
        ) else (
            git merge --ff-only origin/%CURRENT_BRANCH%
            if errorlevel 1 (
                echo WARNING: Repository could not fast-forward to origin/%CURRENT_BRANCH%.
                echo Resolve this manually before using the run as release evidence.
                echo Running with whatever is currently checked out.
                echo.
            ) else (
                set "COMMIT_AFTER="
                for /f "delims=" %%D in ('git rev-parse --short HEAD 2^>nul') do set "COMMIT_AFTER=%%D"
                echo Commit after sync:  !COMMIT_AFTER!
                if "!COMMIT_BEFORE!"=="!COMMIT_AFTER!" (
                    echo Repository already at latest origin/%CURRENT_BRANCH% -- no new commits pulled.
                ) else (
                    echo Repository updated to latest origin/%CURRENT_BRANCH% -- !COMMIT_BEFORE! -^> !COMMIT_AFTER!.
                )
                echo.
            )
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
popd >nul
endlocal
