#Requires -Module Pester

# #385: what a player sees when a PostgreSQL recovery stops, and when TeknoParrot has not made its first game profile yet.
# Everything is synthetic (TestDrive). No service, no PostgreSQL, no TeknoParrot install is touched.

BeforeAll {
    $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
    $names = @('Get-PostgresResetFailureGuidance', 'Write-PostgresRecoveryStageFailure', 'Wait-TpmForFirstTeknoParrotProfile')
    $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $names }, $true)
    foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
    function Write-Log { param($m) $script:LogLines += [string]$m }
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) $script:Screen += (($a | Where-Object { $_ -is [string] -and $_ -notmatch '^(Yellow|Red|DarkGray)$' }) -join ' ') }
}

Describe 'PostgreSQL recovery names the part that stopped' {
    BeforeEach { $script:LogLines = @(); $script:Screen = @(); $script:PostgresRecoveryFailureStage = $null }

    It 'says in plain words that starting PostgreSQL again stopped, and what to do next' {
        $script:PostgresRecoveryFailureStage = 'RecoveryServiceStart'
        Write-PostgresRecoveryStageFailure
        ($script:Screen -join ' ') | Should -Match 'starting PostgreSQL again'
        ($script:Screen -join ' ') | Should -Match 'RecoveryServiceStart'
        ($script:Screen -join ' ') | Should -Match 'Next:'
        ($script:LogLines -join ' ') | Should -Match 'RecoveryServiceStart'
    }

    It 'says in plain words that putting the login settings file back stopped' {
        $g = Get-PostgresResetFailureGuidance -Stage 'RecoveryPolicyApply'
        $g.Screen | Should -Match 'login settings file'
        $g.Screen | Should -Match 'RecoveryPolicyApply'
        $g.Log | Should -Match 'RecoveryPolicyApply'
    }

    It 'prints nothing when no stage was reached, so the generic message stays alone' {
        Write-PostgresRecoveryStageFailure
        $script:Screen | Should -BeNullOrEmpty
        $script:LogLines | Should -BeNullOrEmpty
        Get-PostgresResetFailureGuidance -Stage 'SomethingElse' | Should -BeNullOrEmpty
    }
}

Describe 'Waiting for the first TeknoParrot profile' {
    BeforeEach { $script:LogLines = @(); $script:Screen = @(); $script:Slept = 0 }

    It 'does not wait or print when a profile is already there' {
        $dir = Join-Path $TestDrive 'has'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'Game.xml') -Value '<GameProfile />'
        (Wait-TpmForFirstTeknoParrotProfile -GameProfilesDir $dir -Sleep { param($s) $script:Slept += $s }) | Should -BeTrue
        $script:Slept | Should -Be 0
        $script:Screen | Should -BeNullOrEmpty
    }

    It 'stops waiting when the first profile appears' {
        $dir = Join-Path $TestDrive 'appears'
        $sleeper = { param($s) $script:Slept += $s; New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Content -LiteralPath (Join-Path $dir 'Game.xml') -Value '<GameProfile />' }
        (Wait-TpmForFirstTeknoParrotProfile -GameProfilesDir $dir -TimeoutSeconds 30 -PollSeconds 2 -Sleep $sleeper) | Should -BeTrue
        $script:Slept | Should -Be 2
        ($script:Screen -join ' ') | Should -Match 'Waiting up to 30 seconds'
    }

    It 'gives up after the time limit and tells the player to open TeknoParrot once' {
        $dir = Join-Path $TestDrive 'never'
        (Wait-TpmForFirstTeknoParrotProfile -GameProfilesDir $dir -TimeoutSeconds 6 -PollSeconds 2 -Sleep { param($s) $script:Slept += $s }) | Should -BeFalse
        $script:Slept | Should -Be 6
        ($script:Screen -join ' ') | Should -Match 'Open TeknoParrot once'
    }

    It 'does not wait at all with a zero time limit (unattended runs)' {
        $dir = Join-Path $TestDrive 'unattended'
        (Wait-TpmForFirstTeknoParrotProfile -GameProfilesDir $dir -TimeoutSeconds 0 -Sleep { param($s) $script:Slept += $s }) | Should -BeFalse
        $script:Slept | Should -Be 0
        $script:Screen | Should -BeNullOrEmpty
    }
}
