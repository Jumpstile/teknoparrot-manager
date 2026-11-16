@echo off
setlocal
title TPM: Sync main and run

rem pushd, not cd: cd cannot enter a network share (UNC) path, pushd maps it to a temporary drive letter.
pushd "%~dp0"
if errorlevel 1 (
    echo ERROR: Could not open the folder this launcher is in:
    echo   "%~dp0"
    echo If it is on a network share, check that the share is reachable, then run this again.
    pause
    exit /b 1
)

if not exist ".git" (
    echo ERROR: This folder is not a git repository. Expected to find .git here:
    echo   "%~dp0"
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
    goto :runold
)

echo Updating local main ^(fast-forward only -- never force resets^)...
rem The merge can replace this very file, and cmd reads a batch file while it runs it. So the jump to :run is on the
rem same line as the merge: nothing is read from the old file position afterwards.
git merge --ff-only origin/main && goto :run
echo.
echo ERROR: main could not be fast-forwarded to origin/main.
echo This usually means local main has commits origin doesn't have,
echo or origin/main moved in a way that isn't a simple fast-forward.
echo Resolve this manually ^(git status, git log^) before re-running --
echo this launcher will not force-reset or discard anything for you.
pause
exit /b 1

:run
echo.
echo ===============================================================
echo  main is up to date. Running TeknoParrot-Manager.ps1
echo ===============================================================
echo.
goto :launch

:runold
echo.
echo ===============================================================
echo  Could not check for updates. This may NOT be the newest copy.
echo  Running TeknoParrot-Manager.ps1 from what you already have.
echo ===============================================================
echo.

:launch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TeknoParrot-Manager.ps1" %*
set "TPM_EXIT=%errorlevel%"
if not "%TPM_EXIT%"=="0" (
    echo.
    echo Script exited with an error. Read the message above this line.
    echo The log is TeknoParrot-Manager.log, in the TeknoParrotManager\Logs folder inside your TeknoParrot folder.
    echo If that folder is not set up yet, the log is next to this launcher.
)
pause
exit /b %TPM_EXIT%
