#Requires -Module Pester

# FIX127: progress bars on the PostgreSQL and download paths.
#   B1  A blocking call that reports nothing while it runs (a PostgreSQL tool, a web request, a service change, the administrator
#       window) is marked as a long wait, so the bar reads "still working" and never "stalled". An ordinary silent step still stalls.
#   S9  A rollback or scan that finished with a failed or partial result is closed as failed, never green.
#   N8  A finished row with no known size is a full bar; a download answered "not found" does not read "done"; the installer step
#       closes only after the service check; each step has its own plain label.
#   Labels  Every progress label and group title on the PostgreSQL and download paths has a plain mapping (or is plain already).
# The production script is parsed and its functions are dot-sourced; no top-level product code runs. Every console write is a mock
# and the clock is a variable. No PostgreSQL, network, sandbox or real data is used (TPM_REAL_DATA_TESTS is not touched).
# What this CANNOT prove: how a real console draws the bar, the real UAC prompt, a real pg_restore or a real web server.

BeforeAll {
    $script:F127ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:F127ModuleSource = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1'))
    $tokens = $null
    $parseErrors = $null
    $script:F127Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F127ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX127 tests could not parse the production script.' }
    $functionText = @($script:F127Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F127FunctionFile = Join-Path $TestDrive 'tpm-fix127-functions.ps1'
    [System.IO.File]::WriteAllText($script:F127FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F127FunctionFile
    # The product imports the module from <script folder>\scripts; the functions above live in TestDrive, so a copy goes there.
    New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $script:F127ModuleSource -Destination (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force -ErrorAction Stop

    # A stand-in for a PostgreSQL tool process (FIX129: Invoke-PostgresToolProcess is mocked to call it; the tools are real child
    # processes now): it records the bar while it "runs", moves the clock past the stall time, and records how the bar would look
    # then (the renderer's own decision: Waiting is "still working", Stalled is the warning). It returns the raw process result.
    function Fake127PgTool {
        $global:F127During = [pscustomobject]@{ State = (Get-TpmProgressState); Silent = $null }
        if (Test-TpmProgressActive) {
            $global:F127Now = $global:F127Now.AddSeconds(107)
            $global:F127During.Silent = InModuleScope TpmProgress { Get-TpmProgressSilentState -Op $script:TpmProgressOp }
        }
        [pscustomobject]@{ Started = $true; ExitCode = 0; StdOut = 'tool output'; StdErr = ''; TimedOut = $false; Stopped = $true; Problem = '' }
    }
    function Set-F127ProgressMocks {
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:F127Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:F127Lines.Add($Text) } -ModuleName TpmProgress
    }
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name F127Now, F127Lines, F127During -Scope Global -ErrorAction SilentlyContinue
}

Describe 'FIX127 B1 a long silent wait inside a step reads "still working", never "stalled"' {
    BeforeEach {
        $global:F127Now = [datetime]'2026-01-01T00:00:00'
        $global:F127Lines = New-Object System.Collections.Generic.List[string]
        $global:F127During = $null
        Set-F127ProgressMocks
        Mock Write-Log {}
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
    }

    It 'keeps the count and shows "still working" for a long wait inside a counted step' {
        # Mutation: Start-TpmProgressLongWait does not set the mark (the wait reads stalled), or it hides the count.
        Start-TpmProgressOperation -Title 'Setting up' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Creating databases' -Current 1 -Total 5
        Start-TpmProgressLongWait | Should -BeTrue
        $global:F127Now = $global:F127Now.AddSeconds(107)
        $global:F127Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $last = $global:F127Lines[$global:F127Lines.Count - 1]
        $last | Should -Match 'still working'
        $last | Should -Match '1/5'
        $last | Should -Not -Match 'stalled|\(!\)'
        Test-TpmProgressStalled | Should -BeFalse
        (Get-TpmProgressState).NoCount | Should -BeFalse
    }

    It 'ends the mark when the call returns, and the silence clock starts again from that moment' {
        # Mutation: Stop-TpmProgressLongWait leaves the mark on, or keeps the clock from before the wait (an instant false stall).
        Start-TpmProgressOperation -Title 'Setting up' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Creating databases' -Current 1 -Total 5
        [void](Start-TpmProgressLongWait)
        $global:F127Now = $global:F127Now.AddSeconds(107)
        Stop-TpmProgressLongWait
        (Get-TpmProgressState).LongStep | Should -BeFalse
        Test-TpmProgressStalled | Should -BeFalse
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
        $global:F127Now = $global:F127Now.AddSeconds(75)
        Test-TpmProgressStalled | Should -BeTrue
        Set-TpmProgressStage -Stage 'Creating databases' -Current 2 -Total 5
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Stalled'
    }

    It 'leaves a step that already is a long step to its owner' {
        # Mutation: the wait takes over (and later ends) the mark of a step the product marked with -LongStep (the installer).
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        Start-TpmProgressLongWait | Should -BeFalse
        (Get-TpmProgressState).LongStep | Should -BeTrue
    }

    It 'does nothing when no bar is open' {
        Stop-TpmProgressAbandoned
        Start-TpmProgressLongWait | Should -BeFalse
        { Stop-TpmProgressLongWait } | Should -Not -Throw
    }
}

Describe 'FIX127 B1 every blocking call the product makes marks the open step' {
    BeforeEach {
        $global:F127Now = [datetime]'2026-01-01T00:00:00'
        $global:F127Lines = New-Object System.Collections.Generic.List[string]
        $global:F127During = $null
        Set-F127ProgressMocks
        Mock Write-Log {}
        Mock Write-Host {}
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
    }

    It 'a PostgreSQL tool call (createdb, psql, pg_restore, pg_dump) is a long wait, and the mark ends with the call' {
        # Mutation: Invoke-PostgresNativeCommand stops marking the step -> the bar reads "stalled" while pg_restore runs.
        Mock Test-PostgresToolExecutable { $true }
        Mock Invoke-PostgresToolProcess { Fake127PgTool }
        Start-TpmProgressOperation -Title 'Setting up PostgreSQL' -Group | Out-Null
        Set-TpmProgressStage -Stage 'Creating databases' -Current 1 -Total 3
        $result = Invoke-PostgresNativeCommand -FilePath 'Fake127PgTool' -Arguments @('--version')
        $result.Output | Should -BeExactly 'tool output'
        $global:F127During.State.LongStep | Should -BeTrue
        $global:F127During.Silent | Should -BeExactly 'Waiting'
        (Get-TpmProgressState).LongStep | Should -BeFalse
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
        (Get-TpmProgressState).Current | Should -Be 1
    }

    It 'a PostgreSQL tool call with no bar open works as before' {
        Mock Test-PostgresToolExecutable { $true }
        Mock Invoke-PostgresToolProcess { Fake127PgTool }
        Stop-TpmProgressAbandoned
        $result = Invoke-PostgresNativeCommand -FilePath 'Fake127PgTool' -Arguments @('--version')
        $result.Output | Should -BeExactly 'tool output'
        $result.ExitCode | Should -Be 0
    }

    It 'a web request is a long wait (a slow server, or the whole transfer of the web fallback)' {
        # Mutation: Invoke-TpmWebRequestSilently stops marking the step.
        Mock Invoke-WebRequest {
            $global:F127During = [pscustomobject]@{ State = (Get-TpmProgressState) }
            $global:F127Now = $global:F127Now.AddSeconds(107)
            [pscustomobject]@{ Content = 'ok' }
        }
        Start-TpmProgressOperation -Title 'Download' -Group | Out-Null
        Set-TpmProgressStage -Stage 'Downloading the PostgreSQL installer' -Current 0 -Total 0 -Unit Bytes
        $response = Invoke-TpmWebRequestSilently -Uri 'https://example.invalid/guide.zip' -UseBasicParsing
        $response.Content | Should -BeExactly 'ok'
        $global:F127During.State.LongStep | Should -BeTrue
        (Get-TpmProgressState).LongStep | Should -BeFalse
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
    }

    It 'a wait for the PostgreSQL service to start or stop is a long wait' {
        # Mutation: Wait-PostgresServiceState stops marking the step.
        $script:PostgresServiceName = 'fake127-service'
        $script:F127Service = [pscustomobject]@{ Status = 'Running' }
        $script:F127Service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
            param($Desired, $Timeout)
            $global:F127During = [pscustomobject]@{ State = (Get-TpmProgressState) }
        }
        Mock Get-Service { $script:F127Service }
        Start-TpmProgressOperation -Title 'Setting up PostgreSQL' -Group | Out-Null
        Set-TpmProgressStage -Stage 'Preparing' -Current 0 -Total 0
        $observed = Wait-PostgresServiceState -DesiredStatus 'Running'
        $observed.Status | Should -BeExactly 'Running'
        $global:F127During.State.LongStep | Should -BeTrue
        (Get-TpmProgressState).LongStep | Should -BeFalse
    }

    It 'the wait for the administrator window (Windows permission question, then the whole elevated setup) reads "still working"' {
        # Mutation: the group action stops setting a long step before it waits, so the bar reads "stalled" after 60 seconds.
        $stateDir = Join-Path $TestDrive ('f127-state-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($stateDir)
        $statePath = Join-Path $stateDir ('.tpm-postgres-recovery-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:F127StatePath = $statePath
        $script:postgresSuperPasswordEncrypted = 'enc'
        $child = [pscustomobject]@{ ExitCode = 1; Id = $PID }
        $child | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param($Milliseconds)
            if ($null -eq $global:F127During) {
                $global:F127During = [pscustomobject]@{ State = (Get-TpmProgressState); Silent = $null }
                $global:F127Now = $global:F127Now.AddSeconds(107)
                $global:F127During.Silent = InModuleScope TpmProgress { Get-TpmProgressSilentState -Op $script:TpmProgressOp }
                return $false
            }
            return $true
        }
        $script:F127Child = $child
        Mock Get-PostgresRecoveryStateDirectory { $stateDir }
        Mock New-PostgresRecoveryState { $script:F127StatePath }
        Mock Find-PostgresRecoveryRetryState { $null }
        Mock Get-PostgresSavedCredentialFromConfig { 'enc' }
        Mock Request-TpmConsoleForeground { $false }
        Mock Get-PostgresTrustRuleMarkerState { [pscustomobject]@{ State = 'None'; LiveState = 'Original'; HbaPath = 'x'; BackupHbaPath = 'x'; OriginalSha256 = 'x'; MarkerPath = 'x'; Reason = 'x' } }
        Mock Read-TpmYesNo { 'N' }
        Mock Read-HostSafe { '' }
        Mock Start-Process { $script:F127Child }

        $elevated = Start-PostgresRecoveryAsAdministrator -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'TeknoParrot-Manager.ps1') `
            -TpRoot $TestDrive -UserProfilesDir (Join-Path $TestDrive 'UserProfiles') -Operation Recovery -PasswordPlain 'Fixture-New-Pass-1'

        $elevated | Should -BeFalse
        $global:F127During | Should -Not -BeNullOrEmpty
        $global:F127During.State.Stage | Should -BeExactly 'Waiting for the administrator window'
        $global:F127During.State.LongStep | Should -BeTrue
        $global:F127During.Silent | Should -BeExactly 'Waiting'
    }
}

Describe 'FIX127 S9 a rollback or scan with a failed or partial result is never closed green' {
    BeforeEach {
        $script:F127Calls = New-Object System.Collections.Generic.List[object]
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {
            [void]$script:F127Calls.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome })
        }
    }

    It 'closes the database rollback step as <Expected> when <Case>' -ForEach @(
        @{ Case = 'one database could not be removed'; FailDb = 'GameDB02'; Expected = 'Error' }
        @{ Case = 'every database was removed and checked'; FailDb = ''; Expected = 'Final' }
    ) {
        # Mutation: Restore-PostgresSetupCreatedDatabases closes with the default Final outcome again (green after a failed rollback).
        $script:F127FailDb = $FailDb
        Mock Invoke-Postgres83DropDatabaseVerified { [pscustomobject]@{ Verified = ($DbName -cne $script:F127FailDb); Error = 'drop failed' } }
        $databases = @([pscustomobject]@{ DbName = 'GameDB01' }, [pscustomobject]@{ DbName = 'GameDB02' })
        $result = Restore-PostgresSetupCreatedDatabases -Databases $databases -SuperPasswordPlain 'x'
        $result.Verified | Should -Be ($FailDb -eq '')
        $close = @($script:F127Calls | Where-Object { $_.Label -eq 'PostgreSQL database rollback' -and $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -BeExactly $Expected
    }

    It 'closes the backup profile scan as <Expected> when <Case>' -ForEach @(
        @{ Case = 'one profile could not be checked'; Broken = 'GameDB02'; Expected = 'Error' }
        @{ Case = 'every profile was checked'; Broken = ''; Expected = 'Final' }
    ) {
        # Mutation: Backup-PostgresDatabases closes the scan with the default Final outcome again (green with a database left out).
        $profiles = Join-Path $TestDrive ('f127-backup-scan-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        foreach ($entry in @('GameDB01', 'GameDB02')) {
            $xml = '<GameProfile><GameName>Game {0}</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>{0}</FieldValue></FieldInformation></ConfigValues></GameProfile>' -f $entry
            Set-Content -LiteralPath (Join-Path $profiles ($entry + '.xml')) -Value $xml
        }
        $script:F127Broken = $Broken
        Mock Test-PostgresInstalled { $true }
        Mock Get-PostgresDatabaseState { if ($DbName -ceq $script:F127Broken) { throw 'database state could not be verified' }; [pscustomobject]@{ Exists = $false; Verified = $true } }
        [void](Backup-PostgresDatabases -UserProfilesDir $profiles -SuperPasswordPlain 'x')
        $close = @($script:F127Calls | Where-Object { $_.Label -eq 'PostgreSQL backup profile scan' -and $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -BeExactly $Expected
    }

    It 'closes the recovery profile scan as <Expected> when <Case>' -ForEach @(
        @{ Case = 'no profile needed a recovery copy'; ProfileXml = '<GameProfile><GameName>Other</GameName></GameProfile>'; Expected = 'Error' }
        @{ Case = 'a profile was copied'; ProfileXml = '<GameProfile><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation></ConfigValues></GameProfile>'; Expected = 'Final' }
    ) {
        # Mutation: New-PostgresRecoveryBackup closes the scan Final although it found nothing to back up (the backup is then refused).
        $root = Join-Path $TestDrive ('f127-recovery-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $data = Join-Path $root 'data'
        $profiles = Join-Path $root 'profiles'
        New-Item -ItemType Directory -Path $data, $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $data 'pg_hba.conf') -Value 'hba'
        Set-Content -LiteralPath (Join-Path $data 'postgresql.conf') -Value 'postgresql'
        Set-Content -LiteralPath (Join-Path $profiles 'Game.xml') -Value $ProfileXml
        $script:PostgresInstallDir = $root
        $script:F127RecoveryRoot = Join-Path $root 'recovery'
        Mock Get-PostgresRecoveryBackupRoot { $script:F127RecoveryRoot }
        Mock Lock-PostgresRecoveryDirectory { $global:LASTEXITCODE = 0 }
        Mock Copy-PostgresRecoveryEvidenceFile { [pscustomobject]@{ Source = $Source; Backup = $Destination; Sha256 = 'hash' } }
        $backup = New-PostgresRecoveryBackup -UserProfilesDir $profiles
        $backup.Verified | Should -Be ($Expected -eq 'Final')
        $close = @($script:F127Calls | Where-Object { $_.Label -eq 'PostgreSQL recovery profile scan' -and $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -BeExactly $Expected
    }

    It 'closes the setup profile check as failed when a profile is blocked' {
        # Mutation: Invoke-PostgresGameSetup closes the check with the default Final outcome although a profile was blocked.
        $profiles = Join-Path $TestDrive ('f127-setup-blocked-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $xml = '<GameProfile><GameName>Blocked Game</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>bad name!</FieldValue></FieldInformation></ConfigValues></GameProfile>'
        Set-Content -LiteralPath (Join-Path $profiles 'Blocked.xml') -Value $xml
        $script:PostgresBinDir = 'C:\PostgreSQL\bin'
        $result = Invoke-PostgresGameSetup -UserProfilesDir $profiles -SuperPasswordPlain 'x'
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $close = @($script:F127Calls | Where-Object { $_.Label -eq 'PostgreSQL profile setup' -and $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -BeExactly 'Error'
    }

    It 'closes the setup profile check as failed when an error ends it early (the catch path)' {
        # Mutation: the catch path of Invoke-PostgresGameSetup leaves the open step without a close.
        $profiles = Join-Path $TestDrive ('f127-setup-catch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $xml = '<GameProfile><GameName>Blocked Game</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>bad name!</FieldValue></FieldInformation></ConfigValues></GameProfile>'
        Set-Content -LiteralPath (Join-Path $profiles 'Blocked.xml') -Value $xml
        $script:PostgresBinDir = 'C:\PostgreSQL\bin'
        # The handler of a blocked profile looks the game name up; a failure there leaves the profile loop for the outer catch,
        # with the step already open.
        Mock Get-TpmGameDisplayLabel { throw 'forced failure while handling a blocked profile' }
        $result = Invoke-PostgresGameSetup -UserProfilesDir $profiles -SuperPasswordPlain 'x'
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $close = @($script:F127Calls | Where-Object { $_.Label -eq 'PostgreSQL profile setup' -and $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -BeExactly 'Error'
    }
}

Describe 'FIX127 N8 the installer step closes only after the service check, and has its own plain label' {
    BeforeEach {
        $script:F127Events = New-Object System.Collections.Generic.List[string]
        $script:F127ZipLabel = $null
        $script:F127ServiceThere = $false
        $script:F127SavedTemp = $env:TEMP
        $env:TEMP = Join-Path $TestDrive ('f127-install-temp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($env:TEMP)
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Test-RunningAsAdministrator { $true }
        Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
        Mock Read-ConfirmedPostgresPassword { 'Fix127-Install-Pw1' }
        Mock Get-PostgresGuideRelease { [pscustomobject]@{ DownloadUrl = 'https://example.invalid/guide.zip'; SizeBytes = 1; SizeMB = 1 } }
        Mock Invoke-PostgresGuideDownload { $true }
        Mock Expand-ZipFileSafe {
            $script:F127ZipLabel = $GameName
            [System.IO.File]::WriteAllText((Join-Path $DestDir 'postgresql-8.3-int.msi'), 'fixture')
        }
        Mock Invoke-PostgresMsiPackage { [void]$script:F127Events.Add('msi'); $true }
        Mock Test-PostgresInstalled { [void]$script:F127Events.Add('service check'); $script:F127ServiceThere }
        Mock Get-PostgresServiceStatusText { 'Running' }
        Mock Write-TpmCompactExtractionProgress {
            if ($Label -eq 'PostgreSQL installer') {
                [void]$script:F127Events.Add($(if ($Complete) { 'installer step closed ' + $Outcome } else { 'installer step started' }))
            }
        }
    }
    AfterEach { $env:TEMP = $script:F127SavedTemp }

    It 'closes the installer step <Expected> after the service check when the service is <State>' -ForEach @(
        @{ State = 'missing'; There = $false; Expected = 'Error' }
        @{ State = 'present'; There = $true; Expected = 'Final' }
    ) {
        # Mutation: the step is closed Final as soon as the installer returns, before Test-PostgresInstalled has looked.
        $script:F127ServiceThere = $There
        $out = $null
        $installed = Install-Postgres83 -OutSuperPasswordPlain ([ref]$out)
        $installed | Should -Be $There
        @($script:F127Events) | Should -Be @('installer step started', 'msi', 'service check', ('installer step closed ' + $Expected))
    }

    It 'gives the ZIP extraction its own step name, plain and different from the installer step' {
        # Mutation: the extraction goes back to the name "PostgreSQL installer", so two steps read "Running the PostgreSQL installer".
        $out = $null
        [void](Install-Postgres83 -OutSuperPasswordPlain ([ref]$out))
        $script:F127ZipLabel | Should -Not -BeNullOrEmpty
        $zipText = Get-TpmFriendlyProgressLabel -Label $script:F127ZipLabel
        $installerText = Get-TpmFriendlyProgressLabel -Label 'PostgreSQL installer'
        $zipText | Should -BeExactly 'Unpacking the PostgreSQL installer'
        $installerText | Should -BeExactly 'Running the PostgreSQL installer'
        $zipText | Should -Not -BeExactly $installerText
    }
}

Describe 'FIX127 N8 a finished row with no known size is a full bar, never an empty bar with a check mark' {
    BeforeEach {
        # The "line" look draws other glyphs; the default looks are the ones checked here.
        $script:F127SavedBarStyle = $env:TPM_PROGRESS_BAR_STYLE
        $env:TPM_PROGRESS_BAR_STYLE = $null
    }
    AfterEach { $env:TPM_PROGRESS_BAR_STYLE = $script:F127SavedBarStyle }

    It 'draws a full bar for <State> in the <Style> look' -ForEach @(
        @{ State = 'Final'; Style = 'Block'; Fill = [string][char]0x2588 }, @{ State = 'No-op'; Style = 'Block'; Fill = [string][char]0x2588 },
        @{ State = 'Final'; Style = 'Unicode'; Fill = [string][char]0x2588 }, @{ State = 'Final'; Style = 'Ascii'; Fill = '#' }
    ) {
        # Mutation: the unknown-total branch of New-TpmProgressBarSegments draws only the empty glyph for a finished row.
        $bar = Format-TpmProgressBar -Current 17 -Total 0 -BarWidth 12 -State $State -Style $Style
        $bar | Should -BeExactly ('|' + ($Fill * 10) + '|')
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Discovery' -Current 17 -Total 0 -State $State -ElapsedSeconds 30 -Width 100 -Style $Style
        $line | Should -Match 'done'
    }

    It 'keeps a row that ended <State> without a known size from looking finished' -ForEach @(
        @{ State = 'Error' }, @{ State = 'Cancelled' }, @{ State = 'Incomplete' }
    ) {
        # The full bar is only for work that is done. A failed or unfinished row must not get it.
        (Format-TpmProgressBar -Current 17 -Total 0 -BarWidth 12 -State $State -Style 'Block') | Should -Not -Match ([regex]::Escape([string][char]0x2588))
    }
}

Describe 'FIX127 N8 a download that was answered "not found" does not read "done"' {
    BeforeEach {
        $global:F127Now = [datetime]'2026-01-01T00:00:00'
        $global:F127Lines = New-Object System.Collections.Generic.List[string]
        Set-F127ProgressMocks
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Test-TpmDownloadBitsAvailable { $false }
        $script:F127SavedTemp = $env:TEMP
        $script:F127SavedTmp = $env:TMP
        $env:TEMP = Join-Path $TestDrive ('f127-dl-temp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($env:TEMP)
        $env:TMP = $env:TEMP
        $script:TpmLastLoggedProgressLabel = $null
        Start-TpmProgressOperation -Title 'Thumbnail download' -Group | Out-Null
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
        $env:TEMP = $script:F127SavedTemp
        $env:TMP = $script:F127SavedTmp
    }

    It 'says "not found online" and does not mark the group failed for a definitive 404' {
        # Mutation: the 404 close goes back to Final, so the step reads "<label> done" although nothing was downloaded.
        Mock Invoke-TpmDownloadHttpClient { throw 'Response status code does not indicate success: 404 (Not Found).' }
        Mock Invoke-TpmDownloadWebRequest { throw 'Response status code does not indicate success: 404 (Not Found).' }
        $status = 0
        $ok = Invoke-TpmDownload -DownloadUrl 'https://example.invalid/a.png' -DestinationPath (Join-Path $TestDrive 'f127-icon.png') -Label 'Thumbnail ABC [1/2]' -Quiet -LastStatusCode ([ref]$status)
        $ok | Should -BeFalse
        $status | Should -Be 404
        $state = Get-TpmProgressState
        $state.Stage | Should -BeExactly 'Downloading Thumbnail ABC [1/2]: not found online'
        $state.Stage | Should -Not -Match 'done'
        $state.Outcome | Should -BeNullOrEmpty
    }

    It 'marks the group failed for any other failure' {
        Mock Invoke-TpmDownloadHttpClient { throw 'Response status code does not indicate success: 500 (Server Error).' }
        Mock Invoke-TpmDownloadWebRequest { throw 'Response status code does not indicate success: 500 (Server Error).' }
        $ok = Invoke-TpmDownload -DownloadUrl 'https://example.invalid/a.png' -DestinationPath (Join-Path $TestDrive 'f127-icon2.png') -Label 'Thumbnail ABC [1/2]' -Quiet
        $ok | Should -BeFalse
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Error'
        (Get-TpmProgressState).Stage | Should -Match 'failed'
    }

    It 'still reads "done" for a download that was verified' {
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value 'fake zip content' -NoNewline }
        $ok = Invoke-TpmDownload -DownloadUrl 'https://example.invalid/guide.zip' -DestinationPath (Join-Path $TestDrive 'f127-guide.zip') -Label 'PostgresGuide'
        $ok | Should -BeTrue
        (Get-TpmProgressState).Stage | Should -BeExactly 'Downloading the PostgreSQL installer done'
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
    }
}

Describe 'FIX127 labels the screen shows on the PostgreSQL and download paths are plain' {
    BeforeEach {
        $global:F127Now = [datetime]'2026-01-01T00:00:00'
        $global:F127Lines = New-Object System.Collections.Generic.List[string]
        $script:F127Log = New-Object System.Collections.Generic.List[string]
        Set-F127ProgressMocks
        Mock Write-Log { [void]$script:F127Log.Add([string]$msg) }
        $script:TpmLastLoggedProgressLabel = $null
        $script:ActiveTpmWorkflowStatus = $null
        Start-TpmProgressOperation -Title 'Download' -Group | Out-Null
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
    }

    It 'maps the group titles to plain words' -ForEach @(
        @{ Title = 'PostgreSQL elevated setup'; Plain = 'Setting up PostgreSQL as administrator' }
        @{ Title = 'PostgreSQL reinitialize'; Plain = 'Rebuilding PostgreSQL data' }
        @{ Title = 'PostgreSQL install'; Plain = 'Installing PostgreSQL' }
        @{ Title = 'Eggman DAT download'; Plain = 'Downloading the DAT index' }
        @{ Title = 'Thumbnail download'; Plain = 'Downloading game icons' }
        @{ Title = 'Manager update install'; Plain = 'Updating TeknoParrot Manager' }
    ) {
        # Mutation: a title is left out of the plain-label table, so the developer name reaches the screen.
        Get-TpmFriendlyProgressLabel -Label $Title | Should -BeExactly $Plain
    }

    It 'shows a download in plain words while it transfers (<Method>), while it is checked and when it closes, and logs the method' -ForEach @(
        @{ Method = 'BITS'; Internal = 'PostgresGuide via BITS' }
        @{ Method = 'HttpClient'; Internal = 'PostgresGuide via HttpClient' }
        @{ Method = 'Invoke-WebRequest'; Internal = 'PostgresGuide via web fallback' }
    ) {
        # Mutation: the three labels are left out of the mapping, so "PostgresGuide via BITS", "Verifying PostgresGuide" and
        # "Downloading PostgresGuide" reach the screen.
        Write-TpmDownloadProgress -Label 'PostgresGuide' -Method $Method -DownloadedBytes 1048576 -TotalBytes 10485760 -Elapsed ([TimeSpan]::FromSeconds(2))
        (Get-TpmProgressState).Stage | Should -BeExactly 'Downloading the PostgreSQL installer'
        Write-TpmDownloadProgress -Label 'PostgresGuide' -Method $Method -DownloadedBytes 10485760 -TotalBytes 10485760 -Elapsed ([TimeSpan]::FromSeconds(9)) -Complete
        (Get-TpmProgressState).Stage | Should -BeExactly 'Checking the PostgreSQL installer'
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Downloading PostgresGuide' -Current 0 -Total 0 -Complete
        (Get-TpmProgressState).Stage | Should -BeExactly 'Downloading the PostgreSQL installer done'
        (@($script:F127Lines) -join "`n") | Should -Not -Match 'BITS|HttpClient|PostgresGuide|fallback'
        @($script:F127Log) | Should -Contain ('Progress step: {0} (shown as "Downloading the PostgreSQL installer")' -f $Internal)
    }

    It 'covers every progress label and group title on the PostgreSQL and download paths' {
        # Mutation: a new label or title (or one of these) is written without a plain mapping, or maps to developer words.
        # In scope: anything inside a PostgreSQL or download function, anything whose own text names PostgreSQL, a download or an
        # installer, every label of Invoke-TpmDownload, and every group title about an install or an update.
        $inScope = {
            param([string]$CommandName, [string]$FunctionName, [string]$Text)
            if ($CommandName -eq 'Invoke-TpmDownload') { return $true }
            if ($CommandName -eq 'Invoke-TpmProgressGroup') { return ($FunctionName -match '(?i)postgres|download' -or $Text -match '(?i)postgres|download|install') }
            return ($FunctionName -match '(?i)postgres|download' -or $Text -match '(?i)postgres|download|installer')
        }
        $literal = New-Object System.Collections.Generic.List[object]
        $dynamic = New-Object System.Collections.Generic.List[object]
        $parameterOf = @{ 'Write-TpmCompactExtractionProgress' = 'Label'; 'Invoke-TpmProgressGroup' = 'Title'; 'Invoke-TpmDownload' = 'Label'; 'Expand-ZipFileSafe' = 'GameName' }
        $enclosing = {
            param($Node)
            $parent = $Node.Parent
            while ($null -ne $parent) {
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return [string]$parent.Name }
                $parent = $parent.Parent
            }
            return ''
        }
        foreach ($command in @($script:F127Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $commandName = [string]$command.GetCommandName()
            if (-not $commandName) { continue }
            $elements = @($command.CommandElements)
            for ($i = 0; $i -lt $elements.Count; $i++) {
                $element = $elements[$i]
                if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                $wanted = ($element.ParameterName -eq 'ProgressLabel') -or ($parameterOf.ContainsKey($commandName) -and $parameterOf[$commandName] -eq $element.ParameterName)
                if (-not $wanted) { continue }
                $value = if ($null -ne $element.Argument) { $element.Argument } elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
                if ($null -eq $value) { continue }
                $functionName = & $enclosing $command
                if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    if (& $inScope $commandName $functionName ([string]$value.Value)) { [void]$literal.Add([pscustomobject]@{ Command = $commandName; Text = [string]$value.Value; Function = $functionName }) }
                } elseif (& $inScope $commandName $functionName '') {
                    [void]$dynamic.Add([pscustomobject]@{ Command = $commandName; Text = $value.Extent.Text; Function = $functionName })
                }
            }
        }
        foreach ($assignment in @($script:F127Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -match 'ProgressLabel$' -and $n.Right.Extent.Text -match "^'[^']*'$" }, $true))) {
            $functionName = & $enclosing $assignment
            $text = $assignment.Right.Extent.Text.Trim("'")
            if (& $inScope 'assignment' $functionName $text) { [void]$literal.Add([pscustomobject]@{ Command = 'assignment'; Text = $text; Function = $functionName }) }
        }

        # The scan must really see the paths: these are known to be there.
        $texts = @($literal | ForEach-Object { $_.Text } | Select-Object -Unique)
        foreach ($known in @('PostgreSQL leftover check', 'PostgreSQL elevated setup', 'PostgreSQL reinitialize', 'PostgreSQL install', 'PostgreSQL installer', 'PostgreSQL installer files', 'PostgreSQL administrator window', 'PostgresGuide', 'PostgreSQL database creation', 'PostgreSQL database rollback')) {
            $texts | Should -Contain $known -Because 'the scan must see this label'
        }

        $plainAlready = @('Restore PostgreSQL backup', 'PostgreSQL backup', 'PostgreSQL game setup')
        $productNames = @('BepInEx', 'dgVoodoo2')
        $technical = '(?i)\bBITS\b|HttpClient|PostgresGuide|EggmanDat|FFBPlugin|CheckForUpdates|ReShadeSetup|elevated|reinitialize|leftover|pg_\w+|exit code|Invoke-\w+|web fallback| via '
        $problems = New-Object System.Collections.Generic.List[string]
        $downloadLabels = @($literal | Where-Object { $_.Command -eq 'Invoke-TpmDownload' } | ForEach-Object { $_.Text } | Select-Object -Unique)
        $downloadLabels.Count | Should -BeGreaterThan 3
        foreach ($text in $texts) {
            if ($downloadLabels -contains $text) {
                foreach ($form in @(('{0} via BITS' -f $text), ('{0} via HttpClient' -f $text), ('{0} via web fallback' -f $text), ('Verifying {0}' -f $text), ('Downloading {0}' -f $text))) {
                    $shown = Get-TpmFriendlyProgressLabel -Label $form
                    if ($shown -notmatch '^(Downloading|Checking) ') { [void]$problems.Add(('"{0}" shows as "{1}"' -f $form, $shown)) }
                    if ($shown -match $technical) { [void]$problems.Add(('"{0}" shows developer words: "{1}"' -f $form, $shown)) }
                    if ($productNames -notcontains $text -and $shown.Contains($text)) { [void]$problems.Add(('"{0}" still shows the raw name: "{1}"' -f $form, $shown)) }
                }
                continue
            }
            $shown = Get-TpmFriendlyProgressLabel -Label $text
            if ($shown -ceq $text -and $plainAlready -notcontains $text) { [void]$problems.Add(('"{0}" has no plain mapping' -f $text)) }
            if ($shown -match $technical) { [void]$problems.Add(('"{0}" shows developer words: "{1}"' -f $text, $shown)) }
        }
        # A label that is built at run time cannot be read here: each one must be a known case, so a new one is looked at by a person.
        # The three download forms are built from the label of Invoke-TpmDownload and are checked above for every such label;
        # $inventoryProgressLabel is read from its assignment above; $thumbnailLabel is "Thumbnail <code> [n/m]" (plain).
        $knownDynamic = @('("Verifying {0}" -f $Label)', '("{0} via {1}" -f $Label, $displayMethod)', '("Downloading {0}" -f $Label)', '$inventoryProgressLabel', '$thumbnailLabel')
        foreach ($item in $dynamic.ToArray()) {
            if ($knownDynamic -notcontains $item.Text) { [void]$problems.Add(('{0} in {1} passes a label built at run time ({2}); add it to the known cases after checking it is plain' -f $item.Command, $item.Function, $item.Text)) }
        }
        $problems | Should -BeNullOrEmpty -Because (@($problems) -join '; ')
    }
}
