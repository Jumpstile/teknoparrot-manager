@echo off
setlocal enabledelayedexpansion
title TPM: Sync main and run

cd /d "%~dp0"

if not exist ".git" (
    echo ERROR: This folder is not a git repository. Expected to find .git here:
    echo   %~dp0
    echo This launcher must be run from inside the TeknoParrot Manager repo clone.
    pause
    exit /b 1
)

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set CURRENT_BRANCH=%%b
if not defined CURRENT_BRANCH (
    echo ERROR: Could not determine the current git branch. Is git installed and on PATH?
    pause
    exit /b 1
)
echo Current branch: %CURRENT_BRANCH%

if not "%CURRENT_BRANCH%"=="main" (
    echo.
    echo This launcher only auto-syncs the "main" branch -- you are on
    echo "%CURRENT_BRANCH%". Switching branches automatically is not safe
    echo ^(it could discard work in progress on this branch^), so it stops here.
    echo.
    echo To sync and run: git checkout main, then run this again.
    echo To just run the script on this branch, with no sync: double-click
    echo TeknoParrot-Manager.bat instead.
    pause
    exit /b 1
)

set DIRTY=
rem Untracked files are deliberately not checked here -- a fast-forward
rem merge never touches them, so they are not a safety concern for this
rem launcher. Only modified/staged changes to already-tracked files (which
rem a merge could conflict with) block the sync.
for /f "delims=" %%s in ('git status --porcelain --untracked-files=no 2^>nul') do set DIRTY=1
if defined DIRTY (
    echo.
    echo ERROR: You have uncommitted changes to tracked files. Refusing to
    echo sync automatically -- this launcher never discards or overwrites
    echo local work.
    echo.
    git status --short --untracked-files=no
    echo.
    echo Commit or stash your changes, then run this again.
    pause
    exit /b 1
)

echo.
echo Fetching latest from origin...
git fetch origin
if errorlevel 1 (
    echo.
    echo WARNING: git fetch failed -- check your network connection.
    echo Continuing with whatever local main you already have.
    goto :run
)

echo Updating local main ^(fast-forward only -- never force resets^)...
git merge --ff-only origin/main
if errorlevel 1 (
    echo.
    echo ERROR: main could not be fast-forwarded to origin/main.
    echo This usually means local main has commits origin doesn't have,
    echo or origin/main moved in a way that isn't a simple fast-forward.
    echo Resolve this manually ^(git status, git log^) before re-running --
    echo this launcher will not force-reset or discard anything for you.
    pause
    exit /b 1
)

:run
echo.
echo ===============================================================
echo  main is up to date. Running TeknoParrot-Manager.ps1
echo ===============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TeknoParrot-Manager.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Script exited with an error. Check TeknoParrot-Manager.log for details.
)
pause
