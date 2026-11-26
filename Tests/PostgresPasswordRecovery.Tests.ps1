#Requires -Module Pester

# A person who forgot the PostgreSQL password is told, in plain words, what to do by hand.
# The production script is parsed and only its function definitions are dot-sourced; no top-level
# product code runs and nothing touches PostgreSQL, a service, the registry or a user file.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The recovery tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-recovery-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $script:PostgresInstallDir = 'C:\Test\PostgreSQL\8.3'
    $script:PostgresBinDir = 'C:\Test\PostgreSQL\8.3\bin'
    $script:PostgresServiceName = 'pgsql-test'
}

Describe 'PostgreSQL password recovery steps' {
    It 'gives a short why, numbered steps, and the safety check back on as the last step' {
        $recovery = Get-PostgresPasswordRecoveryLines -EnterKey 'F'
        @($recovery.Why).Count | Should -BeGreaterOrEqual 3
        @($recovery.Why).Count | Should -BeLessOrEqual 5
        (@($recovery.Why) -join ' ') | Should -Match 'any program on this PC can open the database without a password'
        @($recovery.Steps)[0] | Should -Match '^Step 1:'
        @($recovery.Steps)[-1] | Should -Match '^Step 8: Check the safety check is back on'
        (@($recovery.Steps) -join "`n") | Should -Match 'C:\\Test\\PostgreSQL\\8\.3\\data\\pg_hba\.conf'
    }

    It 'shows the steps in the saved Action Required report when the password is not saved' {
        $text = New-TpmActionRequiredReportText -RunId 'test' -OnboardingFollowUp @((Get-PostgresRecoveryPointerLine))
        $text | Should -Match 'Appendix: PostgreSQL password recovery'
        $text | Should -Match 'Why TeknoParrot Manager cannot do this for you'
        $text | Should -Match 'Step 8: Check the safety check is back on'
    }

    It 'shows the steps in the saved validation report and never a password' {
        $script:postgresSuperPasswordEncrypted = 'SENTINEL-SECRET-VALUE'
        $report = [pscustomobject]@{
            Result = 'ActionRequired'; ExitCode = 3
            Manager = [pscustomobject]@{ Display = 'test'; ScriptSha256 = 'x' }
            Environment = [pscustomobject]@{ PowerShell = '5.1'; Edition = 'Desktop'; Os = 'test'; Administrator = $false }
            TeknoParrot = [pscustomobject]@{ Root = 'C:\TP'; RootSource = 'test'; RootProblem = ''; WizardState = 'Done'; GameTemplates = 1 }
            Settings = [pscustomobject]@{ Path = 'C:\TP\config.json'; State = 'Readable'; SavedPostgresPassword = $false }
            Library = [pscustomobject]@{ Registered = 1; Unreadable = 0; NoGameFile = 0; PostgresGames = 1; PostgresNotSetUp = 1 }
            RawInput = [pscustomobject]@{ RawInput = [pscustomobject]@{ Supported = 0; Unsupported = 0; Unknown = 0 }; RawInputTrackball = [pscustomobject]@{ Supported = 0; Unsupported = 0; Unknown = 0 } }
            Package = [pscustomobject]@{ ShippedFilesChecked = 1; ShippedFilesMissing = @(); Crosshairs = 0 }
            CompatibilityWarnings = [pscustomobject]@{ PathTooLong = 0; DllMismatch = 0; GpuIncompatible = 0; BiosMissing = 0; ComponentMissing = 0 }
            Failures = @(); ActionRequired = @((Get-PostgresRecoveryPointerLine)); FilesWritten = @()
        }
        $text = (Format-TpmValidationReportText -Report $report) -join "`n"
        $text | Should -Match 'Action required: PostgreSQL password is not saved'
        $text | Should -Match 'Step 8: Check the safety check is back on'
        $text | Should -Not -Match 'SENTINEL-SECRET-VALUE'
    }
}
