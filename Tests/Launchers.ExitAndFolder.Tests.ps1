BeforeAll {
    $repoRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
    $managerBat = Join-Path $repoRoot 'TeknoParrot-Manager.bat'
    $syncBat = Join-Path $repoRoot 'Sync-And-Run.bat'
}

Describe 'TeknoParrot-Manager.bat' {
    It 'passes TPM exit code on to the caller' {
        # Mutation: remove the exit line -> the launcher ends with code 0 even when TPM failed.
        $dir = Join-Path $TestDrive 'launcher-exit'
        [void][IO.Directory]::CreateDirectory($dir)
        Copy-Item -LiteralPath $managerBat -Destination $dir
        [IO.File]::WriteAllText((Join-Path $dir 'TeknoParrot-Manager.ps1'), 'exit 3')
        & cmd.exe /c ('"' + (Join-Path $dir 'TeknoParrot-Manager.bat') + '" < nul') | Out-Null
        $LASTEXITCODE | Should -Be 3
        [IO.File]::WriteAllText((Join-Path $dir 'TeknoParrot-Manager.ps1'), 'exit 0')
        & cmd.exe /c ('"' + (Join-Path $dir 'TeknoParrot-Manager.bat') + '" < nul') | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'shows no false error when an update replaces the launcher while TPM is running' {
        # Mutation: put the exit-code lines back on their own lines -> cmd re-reads the changed file at the old position and prints
        # "'rrorlevel' is not recognized" plus "Script exited with an error" after a successful update.
        $dir = Join-Path $TestDrive 'launcher-replaced'
        [void][IO.Directory]::CreateDirectory($dir)
        $launcher = Join-Path $dir 'TeknoParrot-Manager.bat'
        Copy-Item -LiteralPath $managerBat -Destination $launcher
        # A stand-in manager that does what the update does to the running launcher: moves it aside, then moves a longer new
        # launcher into its place (Invoke-TpmTransactionalPromote), and ends normally.
        [IO.File]::WriteAllText((Join-Path $dir 'staged-launcher.bat'), ([IO.File]::ReadAllText($launcher).Replace('Manager launcher.', 'Manager launcher for testers.')))
        $manager = '$bat = Join-Path $PSScriptRoot ''TeknoParrot-Manager.bat''' + "`r`n" +
            'Move-Item -LiteralPath $bat -Destination (Join-Path $PSScriptRoot ''rollback-copy.bat'') -Force -ErrorAction Stop' + "`r`n" +
            'Move-Item -LiteralPath (Join-Path $PSScriptRoot ''staged-launcher.bat'') -Destination $bat -ErrorAction Stop' + "`r`n" + 'exit 0'
        [IO.File]::WriteAllText((Join-Path $dir 'TeknoParrot-Manager.ps1'), $manager)
        $output = (& cmd.exe /c ('"' + $launcher + '" < nul 2>&1')) -join "`n"
        $LASTEXITCODE | Should -Be 0
        $output | Should -Not -Match 'Script exited with an error'
        $output | Should -Not -Match 'not recognized'
    }
}

Describe 'Sync-And-Run.bat' {
    It 'stops when its own folder cannot be opened and leaves the repo it was started from alone' {
        # Mutation: remove the pushd check -> the launcher fetches and merges in whatever repo the caller was in.
        $root = Join-Path $TestDrive 'sync'
        [void][IO.Directory]::CreateDirectory($root)
        $git = @('-c', 'user.name=t', '-c', 'user.email=t@t')
        Push-Location $root
        try {
            git init -q --bare origin.git 2>&1 | Out-Null
            git clone -q origin.git work 2>&1 | Out-Null
            git clone -q origin.git other 2>&1 | Out-Null
            foreach ($name in @('work', 'other')) {
                Push-Location (Join-Path $root $name)
                git checkout -q -b main 2>&1 | Out-Null
                Pop-Location
            }
            Push-Location (Join-Path $root 'work')
            Set-Content -LiteralPath 'f.txt' -Value 'one'
            git add f.txt; git @git commit -q -m one; git push -q origin main 2>&1 | Out-Null
            Pop-Location
            Push-Location (Join-Path $root 'other')
            git pull -q origin main 2>&1 | Out-Null
            Add-Content -LiteralPath 'f.txt' -Value 'two'
            git @git commit -q -am two; git push -q origin main 2>&1 | Out-Null
            Pop-Location

            # A copy of the launcher whose own folder is an unreachable share; TPM call is harmless.
            $text = [IO.File]::ReadAllText($syncBat)
            $text = $text.Replace('pushd "%~dp0"', 'pushd "\\localhost\NO_SUCH_SHARE_FOR_TEST\x"').Replace('"%~dp0TeknoParrot-Manager.ps1"', '"' + (Join-Path $root 'none.ps1') + '"')
            $probe = Join-Path $root 'probe.bat'
            [IO.File]::WriteAllText($probe, $text)

            Push-Location (Join-Path $root 'work')
            $before = (git rev-parse HEAD)
            $output = (& cmd.exe /c ('"' + $probe + '" < nul 2>&1')) -join "`n"
            $code = $LASTEXITCODE
            $after = (git rev-parse HEAD)
            Pop-Location
        } finally { Pop-Location }
        $after | Should -BeExactly $before
        $code | Should -Be 1
        $output | Should -Match 'Could not open the folder this launcher is in'
        $output | Should -Not -Match 'Fetching latest'
    }
}
