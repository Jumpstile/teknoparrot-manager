#Requires -Module Pester

# FIX36 PostgreSQL password safety (owner rules R1-R5; PG-AUDIT-RESULT.md
# B1-B5, S2, S4-S6). The production script is parsed and only its function
# definitions are dot-sourced; no top-level product code runs in this process.
# psql is a synthetic console program, and services, prompts and the elevated
# handoff are stubs. Scenarios that need top-level option-13 code run in a
# child PowerShell process built from the parsed
# source. Nothing touches a real PostgreSQL server, service, registry or user
# configuration; every file lives under TestDrive.

BeforeAll {
    $script:Fix36PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix36PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $script:Fix36ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:Fix36ProductionSource = [System.IO.File]::ReadAllText($script:Fix36ProductionPath)
    $tokens = $null
    $parseErrors = $null
    $script:Fix36Ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Fix36ProductionSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX36 tests could not parse the production script.' }
    $script:Fix36FunctionText = @($script:Fix36Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix36-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $script:Fix36FunctionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'fix36.log'
    $script:PostgresServiceName = 'pgsql-fix36'
    $script:Fix36Engine = (Get-Process -Id $PID).Path

    # One synthetic console program, copied as psql.exe. Exit code and stdout
    # come from FAKE_PSQL_EXIT / FAKE_PSQL_OUT (same tool as the #370 tests).
    $script:Fix36FakeBin = Join-Path $TestDrive 'fakepg'
    [void][System.IO.Directory]::CreateDirectory($script:Fix36FakeBin)
    $fakeSource = Join-Path $TestDrive 'Fix36FakePsql.cs'
    $fakeCode = @'
using System;
public static class Fix36FakePsql {
  public static int Main(string[] args) {
    string output = Environment.GetEnvironmentVariable("FAKE_PSQL_OUT");
    if (!String.IsNullOrEmpty(output)) { Console.WriteLine(output); }
    string exit = Environment.GetEnvironmentVariable("FAKE_PSQL_EXIT");
    return String.IsNullOrEmpty(exit) ? 0 : Int32.Parse(exit);
  }
}
'@
    [System.IO.File]::WriteAllText($fakeSource, $fakeCode, (New-Object System.Text.UTF8Encoding $false))
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "The .NET Framework C# compiler was not found at $csc." }
    & $csc /nologo /target:exe ("/out:" + (Join-Path $script:Fix36FakeBin 'psql.exe')) $fakeSource | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The synthetic psql could not be compiled.' }

    function Set-Fix36FakePsql {
        param([string]$Exit = '', [string]$Out = '')
        [Environment]::SetEnvironmentVariable('FAKE_PSQL_EXIT', $Exit, 'Process')
        [Environment]::SetEnvironmentVariable('FAKE_PSQL_OUT', $Out, 'Process')
    }

    function Get-Fix36Sha256 {
        param([byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') } finally { $sha.Dispose() }
    }

    # Since FIX95 no TeknoParrot Manager step writes the trust-rule marker; an
    # older build's interrupted reset could leave one. This writes that marker
    # document exactly as the older writer did: folder created and locked, file
    # created empty and locked to the current user, then the UTF-8 JSON bytes.
    function Write-Fix36LegacyTrustRuleMarker {
        param([string]$HbaPath, [string]$BackupHbaPath, [string]$OriginalSha256, [string]$TrustSha256)
        $markerPath = Get-PostgresTrustRuleMarkerPath
        $directory = [System.IO.Path]::GetDirectoryName($markerPath)
        [void][System.IO.Directory]::CreateDirectory($directory)
        Lock-PostgresRecoveryDirectory -Path $directory
        $marker = [pscustomobject]@{
            Schema = 'TPM.PostgresTrustRuleMarker.v1'
            Guid = [guid]::NewGuid().ToString()
            HbaPath = $HbaPath
            BackupHbaPath = $BackupHbaPath
            OriginalSha256 = $OriginalSha256.ToUpperInvariant()
            TrustSha256 = $TrustSha256.ToUpperInvariant()
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        }
        $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes(($marker | ConvertTo-Json))
        ([System.IO.File]::Open($markerPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)).Dispose()
        Lock-PostgresRecoveryFile -Path $markerPath
        $stream = [System.IO.File]::Open($markerPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        [void](Read-PostgresTrustRuleMarkerFile -MarkerPath $markerPath)
    }

    # Live pg_hba.conf, ACL-locked backup and a durable marker as an older
    # build's interrupted reset left it. Live: TPM's exact trust version, a later
    # user edit of it, or the original file.
    function New-Fix36TrustMarkerFixture {
        param([ValidateSet('TemporaryTrust', 'Changed', 'Original')][string]$Live)
        $root = Join-Path $TestDrive ('pg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $data = Join-Path $root 'data'
        [void][System.IO.Directory]::CreateDirectory($data)
        $script:PostgresInstallDir = $root
        $script:PostgresBinDir = Join-Path $root 'bin'
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $hba = Join-Path $data 'pg_hba.conf'
        $original = "host all all 127.0.0.1/32 md5`r`n"
        [System.IO.File]::WriteAllText($hba, $original, $utf8)
        $recoveryRoot = Join-Path $TestDrive 'PostgresRecoveryBackups'
        $evidence = Join-Path $recoveryRoot ('evidence-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $backupHba = Join-Path (Join-Path $evidence 'PostgreSQL') 'pg_hba.conf'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $backupHba))
        [System.IO.File]::Copy($hba, $backupHba)
        Lock-PostgresRecoveryFile -Path $backupHba
        Lock-PostgresRecoveryDirectory -Path $recoveryRoot
        $originalHash = (Get-FileHash -LiteralPath $hba -Algorithm SHA256).Hash
        $trustBytes = $utf8.GetBytes('host all postgres 127.0.0.1/32 trust' + [Environment]::NewLine + $original)
        $trustHash = Get-Fix36Sha256 -Bytes $trustBytes
        Write-Fix36LegacyTrustRuleMarker -HbaPath $hba -BackupHbaPath $backupHba -OriginalSha256 $originalHash -TrustSha256 $trustHash
        if ($Live -eq 'TemporaryTrust') { [System.IO.File]::WriteAllBytes($hba, $trustBytes) }
        if ($Live -eq 'Changed') { [System.IO.File]::WriteAllBytes($hba, $trustBytes + $utf8.GetBytes("# local edit made after the repair`r`n")) }
        return [pscustomobject]@{ Hba = $hba; Backup = $backupHba; OriginalHash = $originalHash; TrustHash = $trustHash; Marker = (Get-PostgresTrustRuleMarkerPath) }
    }

    # Runs the real top-level option-13 branch in a child PowerShell process with
    # every function definition from the parsed source, then stubs for psql,
    # services, prompts, the database backup and saving. Stubs print
    # EVENT:<name> lines so the test can assert what ran and in which order.
    $script:InvokeFix36TopLevel = {
        param(
            [string]$ResumeOperation = '',
            [string]$Saved = '',
            [string]$Probes = '',
            [string]$Answers = '',
            [string]$Typed = '',
            [string]$Backup = 'Succeed',
            [string]$Service = 'Running',
            [string]$StartOnC = ''
        )
        $branchAst = @($script:Fix36Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Extent.Text.TrimStart() -match '^if \(\$mode -eq "PostgresSetup"\)'
        }, $true))[0]
        if (-not $branchAst) { throw 'The top-level PostgreSQL branch was not found.' }
        $fixtureRoot = Join-Path $TestDrive ('f36top-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profilesRoot = Join-Path $fixtureRoot 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($profilesRoot)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'scripts'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'bin'))
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $fixtureRoot 'scripts\TpmProgress.psm1') -Force
        $profileXml = '<GameProfile><GameName>FIX36 PostgreSQL Fixture</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation></ConfigValues></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $profilesRoot 'Game1.xml'), $profileXml, (New-Object System.Text.UTF8Encoding $false))
        $harnessTemplate = @'
$ErrorActionPreference = 'Stop'
$script:FixtureRoot = $PSScriptRoot
function Add-Fix36Event { param([string]$Name) [Console]::Out.WriteLine('EVENT:' + $Name) }
$script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($answer in @(([string]$env:TPM_FIX36_ANSWERS) -split '\|' | Where-Object { $_ })) { $script:Answers.Enqueue($answer) }
$script:Probes = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($probeState in @(([string]$env:TPM_FIX36_PROBES) -split '\|' | Where-Object { $_ })) { $script:Probes.Enqueue($probeState) }
$script:BackupFails = ([string]$env:TPM_FIX36_BACKUP -eq 'Fail')
$script:ResumeOperation = [string]$env:TPM_FIX36_RESUME_OP
$script:SavedOnDisk = $null
$script:ServiceStatus = if ([string]::IsNullOrEmpty([string]$env:TPM_FIX36_SERVICE)) { 'Running' } else { [string]$env:TPM_FIX36_SERVICE }
$script:StartOnC = ([string]$env:TPM_FIX36_START_ON_C -eq '1')
$script:ActiveTpmWorkflowStatus = $null
$script:TpmWorkflowRendering = $false
$script:PostgresRecoveryStatus = $null
$script:PostgresRecoveryResumeState = $null
$script:logPath = Join-Path $script:FixtureRoot 'fixture.log'
$script:PostgresServiceName = 'pgsql-fix36'
$script:PostgresBinDir = Join-Path $script:FixtureRoot 'bin'
$script:PostgresInstallDir = $script:FixtureRoot
$Unattended = $true
$DryRun = $false
$isPostgresRecoveryResume = -not [string]::IsNullOrEmpty($script:ResumeOperation)
$PostgresRecoveryResumeToken = if ($isPostgresRecoveryResume) { 'protected-state' } else { '' }
$tpRoot = $script:FixtureRoot
$userProfilesDir = Join-Path $script:FixtureRoot 'UserProfiles'
$gamesInstallFolder = Join-Path $script:FixtureRoot 'Games'
$configPath = Join-Path $script:FixtureRoot 'TeknoParrot-Manager.config.json'
$zipSource = ''
$zipSourceSupplementary = ''
$postgresSuperPasswordEncrypted = [string]$env:TPM_FIX36_SAVED

__FUNCTIONS__

function Write-Log { param([object]$Message) }
function Test-RunningAsAdministrator { return $true }
function Test-PostgresInstalled { return $true }
function Test-PostgresManualRecoveryRequired { return $false }
function Get-Service { [CmdletBinding()] param([string]$Name) return [pscustomobject]@{ Name = $Name; Status = $script:ServiceStatus } }
function Start-Service { [CmdletBinding()] param([string]$Name) $script:ServiceStatus = 'Running'; Add-Fix36Event 'SERVICE_START' }
function Stop-Service { [CmdletBinding()] param([string]$Name, [switch]$Force) $script:ServiceStatus = 'Stopped'; Add-Fix36Event 'SERVICE_STOP' }
function Wait-PostgresServiceState { param([string]$DesiredStatus, [int]$TimeoutSeconds = 30) }
function Read-HostSafe {
    param([string]$Prompt, [string]$Default = $null)
    if ($isPostgresRecoveryResume) { Add-Fix36Event 'PROMPT_IN_CHILD' }
    if ($Prompt -notlike '*Press Enter*' -and $script:Answers.Count -gt 0) {
        $scripted = $script:Answers.Dequeue()
        # The user starts PostgreSQL outside TPM, then chooses C (check again).
        if ($scripted -eq 'C' -and $script:StartOnC) { $script:ServiceStatus = 'Running'; Add-Fix36Event 'USER_STARTED_SERVICE' }
        return $scripted
    }
    if ($null -ne $Default) { return $Default }
    return ''
}
function Read-Host { param([string]$Prompt) Add-Fix36Event 'RAW_READ_HOST'; return '' }
function Read-ConfirmedPostgresPassword { param([string]$WhatFor, [switch]$RejectDoubleQuote) return [string]$env:TPM_FIX36_TYPED }
function ConvertTo-PostgresEncryptedPassword { param([string]$PlainText) return ('enc:' + $PlainText) }
function ConvertTo-SecureString { param([string]$String) return [pscustomobject]@{ Value = $String } }
function ConvertFrom-SecureStringPlain { param([object]$Secure) return ([string]$Secure.Value -replace '^enc:', '') }
function Get-PostgresPasswordProbe {
    param([string]$SuperPasswordPlain)
    $state = if ($script:Probes.Count -gt 0) { $script:Probes.Dequeue() } else { 'Authenticated' }
    Add-Fix36Event ('PROBE:' + $state)
    $reason = switch ($state) { 'Authenticated' { 'LoginSucceeded' } 'Rejected' { 'PasswordRejected' } default { 'NotRecognized' } }
    return [pscustomobject]@{ State = $state; Reason = $reason; ServiceStatus = 'Running'; Detail = '' }
}
function Save-Config { Add-Fix36Event 'SAVE_CONFIG'; $script:SavedOnDisk = $postgresSuperPasswordEncrypted; return $true }
function Get-PostgresSavedCredentialFromConfig { return $script:SavedOnDisk }
function New-Fix36Bundle {
    $bundlePath = Join-Path $script:FixtureRoot 'recovery-evidence'
    [void][System.IO.Directory]::CreateDirectory($bundlePath)
    return [pscustomobject]@{ Path = $bundlePath; ConfigBackups = @([pscustomobject]@{ Source = 'pg_hba.conf'; Backup = 'evidence-pg_hba.conf' }); ProfileBackups = @([pscustomobject]@{ Source = 'Game1.xml'; Backup = 'evidence-Game1.xml' }); Verified = $true }
}
function New-PostgresRecoveryBackup { param([string]$UserProfilesDir) Add-Fix36Event 'RECOVERY_BACKUP'; return (New-Fix36Bundle) }
function Start-PostgresRecoveryAsAdministrator { Add-Fix36Event 'ELEVATED_HANDOFF'; return $false }
function Backup-PostgresDatabases {
    param([string]$UserProfilesDir, [string]$SuperPasswordPlain)
    Add-Fix36Event 'BACKUP_CALLED'
    if ($script:BackupFails) {
        return [pscustomobject]@{ Succeeded = $false; Path = $null; FailedDatabases = @('GameDB01'); FailureDetails = @('fixture backup failure'); FailureDiagnoses = @([pscustomobject]@{ GameLabel = 'Game1'; ProfileKey = 'Game1'; Database = 'GameDB01'; Category = 'BackupFailed'; Detail = 'fixture backup failure'; NextAction = 'Back' }) }
    }
    return [pscustomobject]@{ Succeeded = $true; Path = $null; NoOp = $true; FailedDatabases = @(); FailureDetails = @(); FailureDiagnoses = @() }
}
function Invoke-PostgresGameSetup {
    param([string]$UserProfilesDir, [string]$SuperPasswordPlain, [object]$RecoveryBackup, [string[]]$ApprovedPassReplacements = @())
    Add-Fix36Event 'SETUP_CALLED'
    $setup = New-TpmProfileTransactionResult -WorkflowKey 'PostgresSetup' -OperationKey 'ConfigureProfilesAndCreateMissingDatabases' -Outcome 'NO_OP' -ProductState 'UNCHANGED' -Summary 'Fixture PostgreSQL setup result.' -Items @('postgres-setup') -FinalChecks @('Fixture setup result was verified.')
    foreach ($pair in @(@('Configured', 0), @('DbCreated', 0), @('AlreadyConfigured', 1), @('Errors', 0), @('RecoveryBlocked', $false), @('BackupPath', $null), @('PassKeptProfiles', @()))) { $setup | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force }
    return $setup
}
if ($isPostgresRecoveryResume) {
    function Read-PostgresRecoveryState {
        param([string]$StatePath, [string]$ExpectedConfigPath, [string]$ExpectedScriptPath, [string]$ExpectedTpRoot, [string]$ExpectedUserProfilesDir)
        $plan = if ($script:ResumeOperation -eq 'Reinitialize') { '[{"Database":"GameDB01"}]' } else { '' }
        return [pscustomobject]@{ Path = $StatePath; ClaimPath = ($StatePath + '.claim'); Operation = $script:ResumeOperation; PasswordPlain = 'carried-pw'; PasswordOriginEncrypted = 'enc:carried-pw'; SelectionPlanJson = $plan; SelectionPlanHash = 'fixture-plan-hash' }
    }
    function Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) return @() }
    function Test-PostgresReinitializePlan { param([string]$ExpectedPlanJson, [string]$ExpectedPlanHash, [object[]]$CurrentPlans) return $true }
    function Invoke-PostgresReinitializePlan { param([string]$PlanJson, [string]$PlanHash, [string]$UserProfilesDir, [string]$SuperPasswordPlain, $RecoveryBackup) Add-Fix36Event 'REINITIALIZE_CALLED'; return [pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; Summary = 'fixture reinitialize stop' } }
    function New-PostgresRecoveryRetryState { param($State) Add-Fix36Event 'RETRY_STATE_ISSUED'; return 'retry-state' }
    function Remove-PostgresRecoveryState { param([string]$Path, [string]$ClaimPath = '') Add-Fix36Event 'STATE_REMOVED'; return $true }
    function Exit-PostgresRecoveryResumeSuccess { param($ResumeState) Add-Fix36Event 'RESUME_SUCCESS'; exit 0 }
}

$script:LoopCount = 0
while ($true) {
    [void]($script:LoopCount++)
    $mode = if ($script:LoopCount -eq 1) { 'PostgresSetup' } else { 'Exit' }
__BRANCH__
    if ($script:LoopCount -gt 1) { break }
}
Add-Fix36Event 'HARNESS_END'
'@
        $harness = $harnessTemplate.Replace('__FUNCTIONS__', $script:Fix36FunctionText).Replace('__BRANCH__', $branchAst.Extent.Text)
        $harnessPath = Join-Path $fixtureRoot 'Run-Fix36TopLevel.ps1'
        [System.IO.File]::WriteAllText($harnessPath, $harness, (New-Object System.Text.UTF8Encoding $false))
        $environment = @{
            TPM_FIX36_RESUME_OP = $ResumeOperation; TPM_FIX36_SAVED = $Saved; TPM_FIX36_PROBES = $Probes
            TPM_FIX36_ANSWERS = $Answers; TPM_FIX36_TYPED = $Typed; TPM_FIX36_BACKUP = $Backup
            TPM_FIX36_SERVICE = $Service; TPM_FIX36_START_ON_C = $StartOnC
        }
        $previous = @{}
        foreach ($key in $environment.Keys) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, [string]$environment[$key], 'Process')
        }
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $script:Fix36Engine
            $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $harnessPath + '"'
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(120000)) {
                try { $process.Kill() } catch {}
                throw 'The FIX36 top-level fixture did not exit within the timeout.'
            }
            $text = $stdoutTask.GetAwaiter().GetResult() + [Environment]::NewLine + $stderrTask.GetAwaiter().GetResult()
            $events = @($text -split '\r?\n' | Where-Object { $_ -like 'EVENT:*' } | ForEach-Object { $_.Substring(6).Trim() })
            return [pscustomobject]@{ ExitCode = [int]$process.ExitCode; Output = $text; Events = $events }
        } finally {
            foreach ($key in $environment.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
        }
    }
}

AfterAll {
    foreach ($name in @('FAKE_PSQL_EXIT', 'FAKE_PSQL_OUT')) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process') }
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix36PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX36 PostgreSQL password safety' {
    BeforeEach {
        Set-Fix36FakePsql
        $script:PostgresBinDir = $script:Fix36FakeBin
        $script:Fix36Out = New-Object System.Collections.Generic.List[string]
        $script:Fix36ServiceStatus = 'Running'
        Mock Write-Host { [void]$script:Fix36Out.Add([string]$Object) }
        Mock Write-Log {}
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = $script:Fix36ServiceStatus } }
    }
    AfterEach {
        Set-Fix36FakePsql
        try { Remove-PostgresTrustRuleMarker } catch {}
    }

    Context 'B1 three-state password probe' {
        It 'B1: classifies psql output <Out> with the service <Service> as <State>' -TestCases @(
            @{ Exit = '0'; Out = '1'; Service = 'Running'; State = 'Authenticated' }
            @{ Exit = '2'; Out = 'psql: FATAL:  password authentication failed for user "postgres"'; Service = 'Running'; State = 'Rejected' }
            @{ Exit = '2'; Out = 'psql: FATAL:  28P01: password authentication failed for user "postgres"'; Service = 'Running'; State = 'Rejected' }
            @{ Exit = '2'; Out = 'psql: FATAL:  password authentication failed for user "postgres"'; Service = 'Stopped'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: FATAL:  password authentication failed for user "postgres"'; Service = 'StartPending'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "postgres", SSL off'; Service = 'Running'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: could not connect to server: Connection refused (0x0000274D/10061)'; Service = 'Running'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: FATAL:  Passwort-Authentifizierung fuer Benutzer "postgres" fehlgeschlagen'; Service = 'Running'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: fe_sendauth: no password supplied'; Service = 'Running'; State = 'Unavailable' }
            @{ Exit = '2'; Out = 'psql: FATAL:  Ident authentication failed for user "postgres"'; Service = 'Running'; State = 'Unavailable' }
        ) {
            param($Exit, $Out, $Service, $State)
            Set-Fix36FakePsql -Exit $Exit -Out $Out
            $script:Fix36ServiceStatus = $Service
            $probe = @(Get-PostgresPasswordProbe -SuperPasswordPlain 'Fix36-Probe-Pw')
            $probe.Count | Should -Be 1
            $probe[0].State | Should -BeExactly $State
            $gate = @(Test-PostgresPassword -SuperPasswordPlain 'Fix36-Probe-Pw')
            $gate.Count | Should -Be 1
            $gate[0] | Should -BeOfType [bool]
            $gate[0] | Should -Be ($State -eq 'Authenticated')
        }
    }

    Context 'Option 13 password entry (Resolve-PostgresSetupPassword)' {
        BeforeAll {
            function Invoke-Fix36Entry {
                Resolve-PostgresSetupPassword -StatusContext $script:Fix36StatusContext
            }
            function Get-Fix36SavedOnDisk {
                if (-not (Test-Path -LiteralPath $script:configPath -PathType Leaf)) { return $null }
                return [string](Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json).PostgresSuperPasswordEncrypted
            }
        }
        BeforeEach {
            $script:configPath = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
            $script:postgresSuperPasswordEncrypted = $null
            $script:Fix36Answers = New-Object 'System.Collections.Generic.Queue[string]'
            $script:Fix36Typed = New-Object 'System.Collections.Generic.Queue[string]'
            $script:Fix36Menus = New-Object System.Collections.Generic.List[string]
            $script:Fix36Probed = New-Object System.Collections.Generic.List[string]
            $script:Fix36ProbeByPassword = @{}
            Mock Set-TpmWorkflowWaiting {}
            Mock Resume-TpmWorkflowStatus {}
            Mock Set-TpmWorkflowFailure {}
            Mock Acknowledge-TpmWorkflowFailure {}
            Mock Read-HostSafe { '' }
            Mock Write-PostgresAdministratorGuidance {}
            Mock Test-RunningAsAdministrator { $true }
            Mock Start-PostgresRecoveryAsAdministrator { throw 'Unexpected elevated handoff.' }
            Mock Start-Service { throw 'Unexpected service start.' }
            Mock Stop-Service { throw 'Unexpected service stop.' }
            Mock ConvertTo-PostgresEncryptedPassword { 'enc:' + $PlainText }
            Mock ConvertTo-SecureString {
                $secureValue = New-Object System.Security.SecureString
                foreach ($character in ([string]$String -replace '^enc:', '').ToCharArray()) { $secureValue.AppendChar($character) }
                $secureValue.MakeReadOnly()
                $secureValue
            }
            Mock Read-TpmChoice {
                [void]$script:Fix36Menus.Add((@($Choices) -join ','))
                if ($script:Fix36Answers.Count -eq 0) { throw 'No scripted menu answer is left.' }
                $script:Fix36Answers.Dequeue()
            }
            Mock Read-ConfirmedPostgresPassword {
                if ($script:Fix36Typed.Count -eq 0) { throw 'No scripted password is left.' }
                $script:Fix36Typed.Dequeue()
            }
            Mock Invoke-PostgresPasswordProbeSafely {
                [void]$script:Fix36Probed.Add($SuperPasswordPlain)
                if ($script:Fix36ServiceStatus -ne 'Running') {
                    return [pscustomobject]@{ State = 'Unavailable'; Reason = 'ServiceNotRunning'; ServiceStatus = $script:Fix36ServiceStatus; Detail = '' }
                }
                $state = [string]$script:Fix36ProbeByPassword[$SuperPasswordPlain]
                if (-not $state) { $state = 'Unavailable' }
                $reason = switch ($state) { 'Authenticated' { 'LoginSucceeded' } 'Rejected' { 'PasswordRejected' } default { 'NotRecognized' } }
                [pscustomobject]@{ State = $state; Reason = $reason; ServiceStatus = $script:Fix36ServiceStatus; Detail = '' }
            }
            $script:Fix36StatusContext = [pscustomobject]@{ Name = 'fix36-status' }
        }

        It 'B1(a): with no saved password the first and default offer is to enter the existing one; it is checked, saved and read back, and nothing is reset' {
            $script:Fix36ProbeByPassword['existing-pw'] = 'Authenticated'
            $script:Fix36Answers.Enqueue('F')
            $script:Fix36Typed.Enqueue('existing-pw')

            $entry = Invoke-Fix36Entry

            $entry.Outcome | Should -BeExactly 'Ready'
            $entry.PasswordPlain | Should -BeExactly 'existing-pw'
            $script:Fix36Menus[0] | Should -BeExactly 'F,B'
            Should -Invoke Read-TpmChoice -Times 1 -Exactly -ParameterFilter { $Default -eq 'F' }
            ($script:Fix36Out -join "`n") | Should -Match ([regex]::Escape('[F] Enter the existing PostgreSQL password (recommended). TeknoParrot Manager checks it and saves it. Nothing in PostgreSQL is changed.'))
            $script:Fix36Out | Should -Contain '  PostgreSQL accepted that password. TeknoParrot Manager saved it securely and checked the saved copy. Nothing in PostgreSQL was changed.'
            ($script:Fix36Out -join "`n") | Should -Not -Match ([regex]::Escape('[X] I do not know the password'))
            Get-Fix36SavedOnDisk | Should -BeExactly 'enc:existing-pw'
            Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
            Should -Invoke Start-Service -Times 0 -Exactly
        }

        It 'B1(b): a correct saved password while PostgreSQL is stopped offers only check-again or back and changes nothing' {
            $script:postgresSuperPasswordEncrypted = 'enc:saved-pw'
            $script:Fix36ServiceStatus = 'Stopped'
            $script:Fix36ProbeByPassword['saved-pw'] = 'Authenticated'
            $script:Fix36Answers.Enqueue('B')

            $entry = Invoke-Fix36Entry

            $entry.Outcome | Should -BeExactly 'Back'
            $script:Fix36Menus[0] | Should -BeExactly 'C,B'
            $script:Fix36Out | Should -Contain "  PostgreSQL is not running right now (the Windows service 'pgsql-fix36' is Stopped). TeknoParrot Manager cannot check any password until it runs."
            $script:Fix36Out | Should -Contain '  TeknoParrot Manager did not change anything. Start PostgreSQL, wait a few seconds, then choose C to check again.'
            $script:Fix36Out | Should -Contain '  Nothing was changed. The PostgreSQL setup was not completed.'
            $script:postgresSuperPasswordEncrypted | Should -BeExactly 'enc:saved-pw'
            Test-Path -LiteralPath $script:configPath | Should -BeFalse
            Should -Invoke Read-ConfirmedPostgresPassword -Times 0 -Exactly
            Should -Invoke Start-Service -Times 0 -Exactly
        }

        It 'B1(c): no 127.0.0.1 line in pg_hba.conf is reported as unavailable, never as a wrong password, and [X] is not offered' {
            # Real probe and real psql output classification; only the service state is a stub.
            Mock Invoke-PostgresPasswordProbeSafely { Get-PostgresPasswordProbe -SuperPasswordPlain $SuperPasswordPlain }
            Set-Fix36FakePsql -Exit '2' -Out 'psql: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "postgres", SSL off'
            $script:postgresSuperPasswordEncrypted = 'enc:saved-pw'
            $script:Fix36Answers.Enqueue('B')

            $entry = Invoke-Fix36Entry

            $entry.Outcome | Should -BeExactly 'Back'
            $script:Fix36Menus[0] | Should -BeExactly 'F,C,B'
            $script:Fix36Out | Should -Contain '  PostgreSQL did not accept the connection, and TeknoParrot Manager could not tell whether the password was the reason. This does not mean the password is wrong.'
            ($script:Fix36Out -join "`n") | Should -Not -Match ([regex]::Escape('[X] I do not know the password'))
            ($script:Fix36Out -join "`n") | Should -Match 'PostgreSQL gave a reason\. The exact reply is in View Log\.'
            ($script:Fix36Out -join "`n") | Should -Not -Match 'no pg_hba\.conf entry'
            $script:postgresSuperPasswordEncrypted | Should -BeExactly 'enc:saved-pw'
            Test-Path -LiteralPath $script:configPath | Should -BeFalse
            Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
        }

        # Mutation: let [X] change anything (ask for a new password, save, make a recovery
        # backup, write pg_hba.conf, start or stop the service, hand off to an elevated
        # window), skip Show-PostgresPasswordResetUnavailable or pass it -EnterKey 'P'.
        It 'B1: after PostgreSQL rejected the saved password, [X] only explains that TeknoParrot Manager cannot reset it and changes nothing' {
            $script:postgresSuperPasswordEncrypted = 'enc:old-pw'
            $script:Fix36ProbeByPassword['old-pw'] = 'Rejected'
            $script:Fix36Answers.Enqueue('X')
            $script:Fix36Answers.Enqueue('B')
            Mock Show-PostgresPasswordResetUnavailable {}
            Mock Save-Config { throw 'Nothing may be saved after [X].' }
            Mock New-PostgresRecoveryBackup { throw 'No recovery backup may be made after [X].' }
            Mock Set-PostgresHbaPolicyAtomically { throw 'pg_hba.conf must not be written after [X].' }

            $entry = Invoke-Fix36Entry

            $entry.Outcome | Should -BeExactly 'Back'
            $entry.PasswordPlain | Should -BeNullOrEmpty
            @($script:Fix36Menus) | Should -Be @('F,X,B', 'F,X,B')
            $script:Fix36Out | Should -Contain '  [X] I do not know the password'
            Should -Invoke Show-PostgresPasswordResetUnavailable -Times 1 -Exactly
            Should -Invoke Show-PostgresPasswordResetUnavailable -Times 1 -Exactly -ParameterFilter { $EnterKey -eq 'F' }
            Should -Invoke Read-ConfirmedPostgresPassword -Times 0 -Exactly
            Should -Invoke Save-Config -Times 0 -Exactly
            Should -Invoke New-PostgresRecoveryBackup -Times 0 -Exactly
            Should -Invoke Set-PostgresHbaPolicyAtomically -Times 0 -Exactly
            Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
            Should -Invoke Start-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
            $script:postgresSuperPasswordEncrypted | Should -BeExactly 'enc:old-pw'
            Test-Path -LiteralPath $script:configPath | Should -BeFalse
            $script:Fix36Out | Should -Contain '  Nothing was changed. The PostgreSQL setup was not completed.'
        }

        # Mutation: return or stop after Show-PostgresPasswordResetUnavailable instead of
        # going back to the choices, or offer [X] only after the saved password was rejected.
        It 'B1: [X] after a typed password was rejected returns to the choices, where F still checks and saves the right password' {
            $script:Fix36ProbeByPassword['wrong-pw'] = 'Rejected'
            $script:Fix36ProbeByPassword['right-pw'] = 'Authenticated'
            $script:Fix36Answers.Enqueue('F')
            $script:Fix36Answers.Enqueue('X')
            $script:Fix36Answers.Enqueue('F')
            $script:Fix36Typed.Enqueue('wrong-pw')
            $script:Fix36Typed.Enqueue('right-pw')
            Mock Show-PostgresPasswordResetUnavailable {}

            $entry = Invoke-Fix36Entry

            $entry.Outcome | Should -BeExactly 'Ready'
            $entry.PasswordPlain | Should -BeExactly 'right-pw'
            @($script:Fix36Menus) | Should -Be @('F,B', 'F,X,B', 'F,X,B')
            Should -Invoke Show-PostgresPasswordResetUnavailable -Times 1 -Exactly -ParameterFilter { $EnterKey -eq 'F' }
            Should -Invoke Read-ConfirmedPostgresPassword -Times 2 -Exactly
            Get-Fix36SavedOnDisk | Should -BeExactly 'enc:right-pw'
            Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
        }
    }

    Context 'R1, B1 and S2 in the real option-13 branch (child process)' {
        It 'R1/B2: when the user starts PostgreSQL during the password check, TeknoParrot Manager uses the saved password and leaves PostgreSQL running' {
            $run = & $script:InvokeFix36TopLevel -Saved 'enc:saved-pw' -Probes 'Unavailable|Authenticated' -Answers 'C' -Service 'Stopped' -StartOnC '1' -Backup 'Succeed'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Events | Should -Contain 'USER_STARTED_SERVICE'
            $run.Events | Should -Contain 'SETUP_CALLED'
            $run.Events | Should -Contain 'HARNESS_END'
            $run.Events | Should -Not -Contain 'SERVICE_STOP' -Because 'TeknoParrot Manager must not stop a PostgreSQL service the user started'
            $run.Events | Should -Not -Contain 'SERVICE_START'
            $run.Output | Should -Match ([regex]::Escape("PostgreSQL is not running right now (the Windows service 'pgsql-fix36' is Stopped)."))
        }

        # Mutation: let [X] in the real option-13 branch change anything (service, saved
        # credential, recovery or database backup, setup, elevated handoff), or drop the
        # explanation screen that says nothing was changed.
        It 'B1: in the real option-13 branch [X] says TeknoParrot Manager cannot reset the password, and Back then changes nothing' {
            $run = & $script:InvokeFix36TopLevel -Saved 'enc:old-pw' -Probes 'Rejected' -Answers 'X|B'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Events | Should -Contain 'HARNESS_END'
            $run.Output | Should -Match ([regex]::Escape('[X] I do not know the password'))
            $run.Output | Should -Match ([regex]::Escape('TeknoParrot Manager cannot reset the PostgreSQL password for you.'))
            $run.Output | Should -Match ([regex]::Escape('Not changed: PostgreSQL, its password and your games.'))
            $run.Output | Should -Match ([regex]::Escape('Nothing was changed. The PostgreSQL setup was not completed.'))
            foreach ($name in @('SERVICE_START', 'SERVICE_STOP', 'SAVE_CONFIG', 'RECOVERY_BACKUP', 'BACKUP_CALLED', 'SETUP_CALLED', 'ELEVATED_HANDOFF')) {
                $run.Events | Should -Not -Contain $name -Because $run.Output
            }
        }

        # Mutation: let a protected child whose password does not log in continue, prompt,
        # save, back up, reinitialize or touch the service, or drop the "did not change the
        # PostgreSQL password" sentence from its stop message.
        It 'S2/B1: the protected child stops without any change when the carried password does not log in (<ResumeOperation>, probe <Probe>)' -TestCases @(
            @{ ResumeOperation = 'Reinitialize'; Probe = 'Rejected' }
            @{ ResumeOperation = 'Reinitialize'; Probe = 'Unavailable' }
            @{ ResumeOperation = 'Recovery'; Probe = 'Unavailable' }
            @{ ResumeOperation = 'Recovery'; Probe = 'Rejected' }
        ) {
            param($ResumeOperation, $Probe)
            $run = & $script:InvokeFix36TopLevel -ResumeOperation $ResumeOperation -Probes $Probe -Backup 'Fail'

            $run.ExitCode | Should -Be 1 -Because $run.Output
            $run.Output | Should -Match ([regex]::Escape('TeknoParrot Manager could not log in to PostgreSQL. '))
            $run.Output | Should -Match ([regex]::Escape('TeknoParrot Manager did not change the PostgreSQL password.'))
            foreach ($name in @('PROMPT_IN_CHILD', 'SERVICE_START', 'SERVICE_STOP', 'SAVE_CONFIG', 'RECOVERY_BACKUP', 'BACKUP_CALLED', 'REINITIALIZE_CALLED', 'SETUP_CALLED')) {
                $run.Events | Should -Not -Contain $name -Because $run.Output
            }
        }
    }

    Context 'B4 temporary trust rule' {
        It 'B4(a): the startup check reports an unfinished repair read-only, even when PostgreSQL is stopped' {
            $fixture = New-Fix36TrustMarkerFixture -Live TemporaryTrust
            $script:Fix36ServiceStatus = 'Stopped'
            $liveBefore = (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash

            $warned = Write-PostgresTrustRuleStartupWarning

            $warned | Should -BeTrue
            (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash | Should -Be $liveBefore
            $liveBefore | Should -Be $fixture.TrustHash
            Test-Path -LiteralPath $fixture.Marker -PathType Leaf | Should -BeTrue
            $script:Fix36Out | Should -Contain '  WARNING: an earlier PostgreSQL password repair by TeknoParrot Manager did not finish.'
            $script:Fix36Out | Should -Contain ("  The file {0} still contains TeknoParrot Manager's temporary rule 'host all postgres 127.0.0.1/32 trust'." -f $fixture.Hba)
            $script:Fix36Out | Should -Contain '  While PostgreSQL runs with that rule, any program on this PC can log in to PostgreSQL as postgres without a password.'
            $script:Fix36Out | Should -Contain '  TeknoParrot Manager did not change any file, password or service during this check.'
        }

        It 'B4(c): Restore-PostgresServiceState refuses to start PostgreSQL while the trust-rule marker exists' {
            $fixture = New-Fix36TrustMarkerFixture -Live TemporaryTrust
            $script:Fix36ServiceStatus = 'Stopped'
            Mock Start-Service { throw 'PostgreSQL must not be started while the trust marker exists.' }

            $restored = Restore-PostgresServiceState -WasRunning $true

            $restored | Should -BeFalse
            $script:PostgresServiceStartRefusedByMarker | Should -BeTrue
            Should -Invoke Start-Service -Times 0 -Exactly
            (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash | Should -Be $fixture.TrustHash
            Test-Path -LiteralPath $fixture.Marker -PathType Leaf | Should -BeTrue
        }
    }

    Context 'B5 saved credential at startup' {
        BeforeAll {
            $offerAssign = @($script:Fix36Ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -eq '$tpmOfferSavedConfig'
            }, $true))
            if ($offerAssign.Count -ne 1) { throw 'Expected exactly one $tpmOfferSavedConfig assignment.' }
            $offerBlock = @($offerAssign[0].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true))[0]
            $offerText = $offerBlock.Extent.Text
            $script:Fix36OfferBody = $offerText.Substring(1, $offerText.Length - 2)
        }

        It 'B5: <Case> keeps the saved PostgreSQL credential and the next save writes it back' -TestCases @(
            @{ Case = 'answering N to Use these settings'; Settings = @{ TeknoParrotRoot = 'D:\TPX'; GamesInstallFolder = 'D:\GamesX'; PostgresSuperPasswordEncrypted = 'ENC-FIX36-B5' }; Prompted = 1 }
            @{ Case = 'an incomplete saved config'; Settings = @{ TeknoParrotRoot = 'D:\TPX'; PostgresSuperPasswordEncrypted = 'ENC-FIX36-B5' }; Prompted = 0 }
        ) {
            param($Case, $Settings, $Prompted)
            $configPath = Join-Path $TestDrive ('b5-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
            [System.IO.File]::WriteAllText($configPath, ([pscustomobject]$Settings | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
            Mock Read-TpmYesNo { 'N' }
            $Unattended = $false
            $isPostgresRecoveryResume = $false
            $postgresSuperPasswordEncrypted = $null
            $checkForUpdatesOnStartup = $true
            $unattendedModeSaved = $null
            $configAccepted = $false
            $tpRoot = $null
            $gamesInstallFolder = $null
            $pendingApplyMode = $null

            . ([scriptblock]::Create($script:Fix36OfferBody))

            Should -Invoke Read-TpmYesNo -Times $Prompted -Exactly
            $configAccepted | Should -BeFalse
            $postgresSuperPasswordEncrypted | Should -BeExactly 'ENC-FIX36-B5'
            $tpRoot = 'D:\TPY'
            Save-Config | Should -BeTrue
            (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).PostgresSuperPasswordEncrypted | Should -BeExactly 'ENC-FIX36-B5'
        }
    }

    Context 'S4 profile Pass fields' {
        BeforeEach {
            $script:Fix36Profiles = Join-Path $TestDrive ('s4-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($script:Fix36Profiles)
            $script:PostgresBinDir = 'C:\PostgreSQL\bin'
            $template = '<GameProfile><GameName>{0}</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Path</FieldName><FieldValue>C:\PostgreSQL\bin\</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Address</FieldName><FieldValue>{1}</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Port</FieldName><FieldValue>5432</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>User</FieldName><FieldValue>{2}</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Pass</FieldName><FieldValue>{3}</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Automatically create Database</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>'
            $script:Fix36Blank = Join-Path $script:Fix36Profiles 'BlankLocal.xml'
            $script:Fix36Different = Join-Path $script:Fix36Profiles 'DifferentPass.xml'
            $script:Fix36Custom = Join-Path $script:Fix36Profiles 'CustomUser.xml'
            Set-Content -LiteralPath $script:Fix36Blank -Value ($template -f 'Blank Local', '127.0.0.1', 'postgres', '')
            Set-Content -LiteralPath $script:Fix36Different -Value ($template -f 'Different Pass', '127.0.0.1', 'postgres', 'their-own-pw')
            Set-Content -LiteralPath $script:Fix36Custom -Value ($template -f 'Custom User', '127.0.0.1', 'gtuser', '')
            $script:Fix36SavedProfiles = New-Object System.Collections.Generic.List[string]
            Mock Get-PostgresDatabaseState { [pscustomobject]@{ Exists = $true; Verified = $true } }
            Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $true; TableCount = 24; Error = $null } }
            Mock Save-Xml { param($Doc, [string]$Path) [void]$script:Fix36SavedProfiles.Add([System.IO.Path]::GetFileName($Path)); $Doc.Save($Path) }
            $recoveryPath = Join-Path $TestDrive ('s4-recovery-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($recoveryPath)
            $script:Fix36S4Recovery = [pscustomobject]@{
                Path = $recoveryPath
                Verified = $true
                ProfileBackups = @($script:Fix36Blank, $script:Fix36Different, $script:Fix36Custom | ForEach-Object { [pscustomobject]@{ Source = $_; Backup = (Join-Path $recoveryPath ([System.IO.Path]::GetFileName($_))) } })
                ConfigBackups = @([pscustomobject]@{ Source = (Join-Path $TestDrive 'postgresql.conf'); Backup = (Join-Path $recoveryPath 'postgresql.conf') })
            }
        }

        It 'S4: without approval only a blank local Pass is filled; a different Pass and a custom user are listed and kept' {
            $conflicts = @(Get-PostgresProfilePassConflicts -ProfileFiles @(Get-ChildItem -LiteralPath $script:Fix36Profiles -Filter '*.xml') -SuperPasswordPlain 'local-postgres-pw')
            @($conflicts | ForEach-Object { $_.ProfileName } | Sort-Object) | Should -Be @('CustomUser', 'DifferentPass')
            @($conflicts | Where-Object { $_.ProfileName -eq 'DifferentPass' })[0].Reasons | Should -Contain 'it already has a different PostgreSQL password'
            @($conflicts | Where-Object { $_.ProfileName -eq 'CustomUser' })[0].Reasons | Should -Contain "it uses the database user 'gtuser'"

            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:Fix36Profiles -SuperPasswordPlain 'local-postgres-pw' -RecoveryBackup $script:Fix36S4Recovery

            (Test-TpmTransactionResult -Result $result) | Should -BeTrue
            $result.Outcome | Should -BeExactly 'SUCCEEDED' -Because 'kept profiles are verified against their own values, not rolled back'
            $result.Errors | Should -Be 0
            $result.RecoveryBlocked | Should -BeFalse
            @($script:Fix36SavedProfiles) | Should -Be @('BlankLocal.xml')
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Blank) 'Pass') | Should -BeExactly 'local-postgres-pw'
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Different) 'Pass') | Should -BeExactly 'their-own-pw'
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Custom) 'Pass') | Should -BeExactly ''
            @($result.PassKeptProfiles | Sort-Object) | Should -Be @('CustomUser', 'DifferentPass')
            @($result.Warnings) | Should -Contain 'Kept the existing PostgreSQL password or connection settings in 2 profile(s) because replacing them was not approved: CustomUser, DifferentPass.'
        }

        It 'S4: an approved profile with a different Pass is replaced and only that one' {
            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:Fix36Profiles -SuperPasswordPlain 'local-postgres-pw' -RecoveryBackup $script:Fix36S4Recovery -ApprovedPassReplacements @($script:Fix36Different)

            (Test-TpmTransactionResult -Result $result) | Should -BeTrue
            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.Errors | Should -Be 0
            @($script:Fix36SavedProfiles | Sort-Object) | Should -Be @('BlankLocal.xml', 'DifferentPass.xml')
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Different) 'Pass') | Should -BeExactly 'local-postgres-pw'
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Custom) 'Pass') | Should -BeExactly ''
            @($result.PassKeptProfiles) | Should -Be @('CustomUser')
        }

        It 'S4: a kept profile with another Path is left completely untouched, and only an approved one gets the local Path' {
            $content = [System.IO.File]::ReadAllText($script:Fix36Different).Replace('C:\PostgreSQL\bin\', 'D:\Other\bin\')
            [System.IO.File]::WriteAllText($script:Fix36Different, $content)
            $before = (Get-FileHash -LiteralPath $script:Fix36Different -Algorithm SHA256).Hash

            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:Fix36Profiles -SuperPasswordPlain 'local-postgres-pw' -RecoveryBackup $script:Fix36S4Recovery

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.Errors | Should -Be 0
            @($script:Fix36SavedProfiles) | Should -Not -Contain 'DifferentPass.xml'
            (Get-FileHash -LiteralPath $script:Fix36Different -Algorithm SHA256).Hash | Should -BeExactly $before
            @($result.PassKeptProfiles) | Should -Contain 'DifferentPass'

            $script:Fix36SavedProfiles.Clear()
            $approved = Invoke-PostgresGameSetup -UserProfilesDir $script:Fix36Profiles -SuperPasswordPlain 'local-postgres-pw' -RecoveryBackup $script:Fix36S4Recovery -ApprovedPassReplacements @($script:Fix36Different)
            $approved.Outcome | Should -BeExactly 'SUCCEEDED'
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Different) 'Path') | Should -BeExactly 'C:\PostgreSQL\bin\'
        }

        It 'S4: an approved custom-user profile gets the local password and keeps its own database user' {
            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:Fix36Profiles -SuperPasswordPlain 'local-postgres-pw' -RecoveryBackup $script:Fix36S4Recovery -ApprovedPassReplacements @($script:Fix36Custom)

            (Test-TpmTransactionResult -Result $result) | Should -BeTrue
            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.Errors | Should -Be 0
            @($script:Fix36SavedProfiles | Sort-Object) | Should -Be @('BlankLocal.xml', 'CustomUser.xml')
            $customDoc = Read-Xml $script:Fix36Custom
            (Get-PostgresFieldValue $customDoc 'Pass') | Should -BeExactly 'local-postgres-pw'
            (Get-PostgresFieldValue $customDoc 'User') | Should -BeExactly 'gtuser'
            (Get-PostgresFieldValue (Read-Xml $script:Fix36Different) 'Pass') | Should -BeExactly 'their-own-pw'
            @($result.PassKeptProfiles) | Should -Be @('DifferentPass')
        }
    }

    Context 'S5 marker auto-restore' {
        It 'S5: a stopped service and the exact trust-rule file are restored automatically, and TeknoParrot Manager says what it restored' {
            $fixture = New-Fix36TrustMarkerFixture -Live TemporaryTrust
            $script:Fix36ServiceStatus = 'Stopped'

            $state = Get-PostgresTrustRuleMarkerState

            $state.State | Should -BeExactly 'None'
            (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash | Should -Be $fixture.OriginalHash
            Test-Path -LiteralPath $fixture.Marker | Should -BeFalse
            $script:Fix36Out | Should -Contain ("  TeknoParrot Manager restored the PostgreSQL file {0} from its safety copy {1}. It still had TeknoParrot Manager's temporary rule 'host all postgres 127.0.0.1/32 trust' from an unfinished password repair. PostgreSQL was stopped while TeknoParrot Manager did this." -f $fixture.Hba, $fixture.Backup)
        }

        It 'S5: a file edited after the repair is never overwritten automatically' {
            $fixture = New-Fix36TrustMarkerFixture -Live Changed
            $script:Fix36ServiceStatus = 'Stopped'
            $liveBefore = (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash

            $required = Test-PostgresManualRecoveryRequired

            $required | Should -BeTrue
            $script:PostgresTrustRuleMarkerState.State | Should -BeExactly 'Required'
            $script:PostgresTrustRuleMarkerState.LiveState | Should -BeExactly 'Changed'
            (Get-FileHash -LiteralPath $fixture.Hba -Algorithm SHA256).Hash | Should -Be $liveBefore
            Test-Path -LiteralPath $fixture.Marker -PathType Leaf | Should -BeTrue
            (Get-PostgresManualRecoveryDetail) | Should -Match ([regex]::Escape('was changed after an unfinished TeknoParrot Manager password repair started, so TeknoParrot Manager will not overwrite it.'))
            @($script:Fix36Out | Where-Object { $_ -like '*TeknoParrot Manager restored the PostgreSQL file*' }).Count | Should -Be 0
        }
    }

    Context 'S6 PostgreSQL installer passwords' {
        It 'S6: a password containing a double quote is refused at the prompt and asked again' {
            $script:Fix36SecureAnswers = New-Object 'System.Collections.Generic.Queue[System.Security.SecureString]'
            foreach ($plain in @('quote"pw', 'quote"pw', 'Fix36-Good-Pw', 'Fix36-Good-Pw')) {
                $secureValue = New-Object System.Security.SecureString
                foreach ($character in $plain.ToCharArray()) { $secureValue.AppendChar($character) }
                $script:Fix36SecureAnswers.Enqueue($secureValue)
            }
            Mock Read-Host { $script:Fix36SecureAnswers.Dequeue() }

            $approved = Read-ConfirmedPostgresPassword 'the DATABASE password' -RejectDoubleQuote

            $approved | Should -BeExactly 'Fix36-Good-Pw'
            Should -Invoke Read-Host -Times 4 -Exactly
            $script:Fix36Out | Should -Contain '  This password cannot contain a double quote ("). Please choose a password without one.'
        }

        It 'S6: both installer password prompts refuse a double quote' {
            Mock Test-RunningAsAdministrator { $true }
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
            Mock Read-ConfirmedPostgresPassword { 'Fix36-Install-Pw' }
            Mock Get-PostgresGuideRelease { $null }

            $installed = Install-Postgres83 -OutSuperPasswordPlain ([ref]$null)

            $installed | Should -BeFalse
            Should -Invoke Read-ConfirmedPostgresPassword -Times 2 -Exactly -ParameterFilter { $RejectDoubleQuote.IsPresent }
            Should -Invoke Read-ConfirmedPostgresPassword -Times 1 -Exactly -ParameterFilter { $WhatFor -eq 'the SERVICE ACCOUNT password' -and $RejectDoubleQuote.IsPresent }
            Should -Invoke Read-ConfirmedPostgresPassword -Times 1 -Exactly -ParameterFilter { $WhatFor -eq 'the DATABASE password' -and $RejectDoubleQuote.IsPresent }
        }

        It 'tells "could not reach GitHub" apart from "GitHub answered but has no installer"' -ForEach @(
            @{ Reply = 'nothing'; Expect = 'Could not reach GitHub to download the installer'; Reject = 'GitHub answered' }
            @{ Reply = 'no installer'; Expect = 'GitHub answered, but it did not offer the PostgreSQL installer'; Reject = 'Could not reach GitHub' }
        ) {
            # Mutation: print the "could not reach GitHub, check your internet" line for every failed release lookup -> a user whose connection works is told to fix it.
            Mock Test-RunningAsAdministrator { $true }
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
            Mock Read-ConfirmedPostgresPassword { 'Fix36-Install-Pw' }
            $script:Fix36Reply = $Reply
            Mock Get-PostgresGuideRelease { if ($script:Fix36Reply -eq 'nothing') { $null } else { [pscustomobject]@{ DownloadUrl = '' } } }

            Install-Postgres83 -OutSuperPasswordPlain ([ref]$null) | Should -BeFalse

            ($script:Fix36Out -join "`n") | Should -Match ([regex]::Escape($Expect))
            ($script:Fix36Out -join "`n") | Should -Not -Match ([regex]::Escape($Reject))
        }

        It 'S6: a password with a double quote that reaches the installer step is refused before the installer runs' {
            $priorTemp = $env:TEMP
            $env:TEMP = Join-Path $TestDrive ('s6-temp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($env:TEMP)
            try {
                Mock Test-RunningAsAdministrator { $true }
                Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
                Mock Read-ConfirmedPostgresPassword { if ($WhatFor -eq 'the DATABASE password') { 'db"quote' } else { 'svc-ok' } }
                Mock Get-PostgresGuideRelease { [pscustomobject]@{ DownloadUrl = 'https://example.invalid/guide.zip'; SizeBytes = 1; SizeMB = 1 } }
                Mock Invoke-PostgresGuideDownload { $true }
                Mock Expand-ZipFileSafe { [System.IO.File]::WriteAllText((Join-Path $DestDir 'postgresql-8.3-int.msi'), 'fixture') }
                Mock Invoke-PostgresMsiPackage { throw 'The installer must not run with a double quote in a password.' }
                $outPassword = [ref]$null

                $installed = Install-Postgres83 -OutSuperPasswordPlain $outPassword

                $installed | Should -BeFalse
                $outPassword.Value | Should -BeNullOrEmpty
                Should -Invoke Expand-ZipFileSafe -Times 1 -Exactly
                Should -Invoke Invoke-PostgresMsiPackage -Times 0 -Exactly
                $script:Fix36Out | Should -Contain '  PostgreSQL was not installed: a password contained a double quote ("). Nothing was changed.'
            } finally {
                $env:TEMP = $priorTemp
            }
        }
    }
}
