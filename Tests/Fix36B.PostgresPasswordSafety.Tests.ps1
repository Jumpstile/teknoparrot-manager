#Requires -Module Pester

# FIX36B PostgreSQL password safety, round 2 (PG-BLIND-astra-RESULT.md S2, S6,
# S7, N1, N2; PG-AUDIT-RESULT.md S8, S9, N7). The production script is parsed
# and only its function definitions are dot-sourced; no top-level product code
# runs in this process. Services, prompts and PostgreSQL tools are stubs. The
# repair lock tests start a plain child PowerShell process that only holds a
# test-named mutex. Every file lives under TestDrive.
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix36BPriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix36BPriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX36B tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix36b-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'fix36b.log'
    $script:PostgresServiceName = 'pgsql-fix36b'
    $script:Fix36BEngine = (Get-Process -Id $PID).Path
    $script:Fix36BCurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    function New-Fix36BSecureString {
        param([string]$Plain)
        $secureValue = New-Object System.Security.SecureString
        foreach ($character in $Plain.ToCharArray()) { $secureValue.AppendChar($character) }
        return $secureValue
    }

    # Starts a plain child PowerShell that takes the named mutex and keeps it.
    # Returns the process once the child confirms it holds the mutex.
    function Start-Fix36BLockHolder {
        param([Parameter(Mandatory)][string]$Name)
        $flag = Join-Path $TestDrive ('lock-held-' + [guid]::NewGuid().ToString('N'))
        $holderScript = Join-Path $TestDrive ('lock-holder-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $holderText = "`$m = New-Object System.Threading.Mutex(`$false, '" + $Name + "')`r`nif (`$m.WaitOne(0)) { [System.IO.File]::WriteAllText('" + $flag + "', 'held') }`r`nStart-Sleep -Seconds 120`r`n"
        [System.IO.File]::WriteAllText($holderScript, $holderText, (New-Object System.Text.UTF8Encoding $false))
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $script:Fix36BEngine
        $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $holderScript + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        for ($i = 0; $i -lt 300 -and -not (Test-Path -LiteralPath $flag -PathType Leaf); $i++) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath $flag -PathType Leaf)) {
            try { $process.Kill() } catch {}
            throw 'The child process could not take the test lock.'
        }
        return $process
    }

    function Stop-Fix36BProcess {
        param($Process)
        if ($null -eq $Process) { return }
        try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
        try { [void]$Process.WaitForExit(10000) } catch {}
    }

    function Get-Fix36BSha256 {
        param([byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') } finally { $sha.Dispose() }
    }

    # Since FIX95 no TeknoParrot Manager step writes the trust-rule marker; an
    # older build's interrupted reset could leave one. This writes that marker
    # document exactly as the older writer did: folder created and locked, file
    # created empty and locked to the current user, then the UTF-8 JSON bytes.
    function Write-Fix36BLegacyTrustRuleMarker {
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

    # Live pg_hba.conf back at its original bytes, an ACL-locked backup and a
    # durable marker as an older build's interrupted reset left it.
    function New-Fix36BOriginalMarkerFixture {
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
        $trustHash = Get-Fix36BSha256 -Bytes ($utf8.GetBytes('host all postgres 127.0.0.1/32 trust' + [Environment]::NewLine + $original))
        Write-Fix36BLegacyTrustRuleMarker -HbaPath $hba -BackupHbaPath $backupHba -OriginalSha256 $originalHash -TrustSha256 $trustHash
        return [pscustomobject]@{ Hba = $hba; Marker = (Get-PostgresTrustRuleMarkerPath) }
    }

    # A temporary-credential-shaped file in a test folder; -Lock applies the
    # production owner-only access list.
    function New-Fix36BPgPassFixture {
        param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Name, [switch]$Lock, [double]$AgeHours = 0)
        [void][System.IO.Directory]::CreateDirectory($Directory)
        $path = Join-Path $Directory $Name
        [System.IO.File]::WriteAllText($path, "127.0.0.1:5432:*:postgres:fixture`r`n")
        if ($Lock) {
            $locked = Set-PostgresOwnerOnlyAcl -Path $path
            if ($locked.Outcome -ne 'Success') { throw 'The fixture file could not be locked.' }
        }
        if ($AgeHours -gt 0) { [System.IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddHours(-$AgeHours)) }
        return $path
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix36BPriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX36B PostgreSQL password safety' {
    BeforeEach {
        $script:Fix36BOut = New-Object System.Collections.Generic.List[string]
        $script:Fix36BServiceStatus = 'Running'
        $script:PostgresRecoveryLockName = 'Local\TpmFix36BTest-' + [guid]::NewGuid().ToString('N')
        Mock Write-Host { [void]$script:Fix36BOut.Add([string]$Object) }
        Mock Write-Log {}
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = $script:Fix36BServiceStatus } }
    }
    AfterEach {
        try { Remove-PostgresTrustRuleMarker } catch {}
        for ($i = 0; $i -lt 10 -and $script:PostgresRecoveryLockHeld; $i++) { Exit-PostgresRecoveryLock }
        $script:PostgresRecoveryLockName = $null
    }

    Context 'S2 owner-only access lists by SID, three outcomes' {
        # Mutation: drop the IsInherited check, the other-account check, or the
        # Unknown return in the read catch of Get-PostgresOwnerOnlyAclState.
        It 'S2: only an access list with explicit entries for the current SID alone is Success' {
            $folder = Join-Path $TestDrive ('acl-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($folder)
            $inherited = Join-Path $folder 'inherited.conf'
            [System.IO.File]::WriteAllText($inherited, 'x')
            $owned = Join-Path $folder 'owned.conf'
            [System.IO.File]::WriteAllText($owned, 'x')
            $shared = Join-Path $folder 'shared.conf'
            [System.IO.File]::WriteAllText($shared, 'x')

            (Set-PostgresOwnerOnlyAcl -Path $owned).Outcome | Should -BeExactly 'Success'
            (Set-PostgresOwnerOnlyAcl -Path $shared).Outcome | Should -BeExactly 'Success'
            & icacls $shared /grant '*S-1-1-0:(R)' 1>$null 2>$null
            $LASTEXITCODE | Should -Be 0

            (Get-PostgresOwnerOnlyAclState -Path $owned).Outcome | Should -BeExactly 'Success'
            (@((Get-Acl -LiteralPath $owned).Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } | Where-Object { $_ -notin @('S-1-5-32-544', 'S-1-5-18') } | Select-Object -Unique) -join ',') | Should -BeExactly $script:Fix36BCurrentSid
            (Get-PostgresOwnerOnlyAclState -Path $inherited).Outcome | Should -BeExactly 'Failed'
            (Get-PostgresOwnerOnlyAclState -Path $shared).Outcome | Should -BeExactly 'Failed'
            (Get-PostgresOwnerOnlyAclState -Path (Join-Path $folder 'missing.conf')).Outcome | Should -BeExactly 'Unknown'
        }

        # Mutation: reject an Administrators or SYSTEM entry (elevated accounts keep one), or accept any other
        # account, a deny entry, or an inherited entry because Administrators is present.
        It 'S2: an Administrators or SYSTEM entry beside the current user passes; other accounts, deny and inherited entries still fail' {
            $folder = Join-Path $TestDrive ('acl-admin-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($folder)
            $paths = @{}
            foreach ($name in @('admin', 'system', 'other', 'deny', 'inherited')) {
                $paths[$name] = Join-Path $folder ($name + '.conf')
                [System.IO.File]::WriteAllText($paths[$name], 'x')
            }
            foreach ($name in @('admin', 'system', 'other', 'deny')) { (Set-PostgresOwnerOnlyAcl -Path $paths[$name]).Outcome | Should -BeExactly 'Success' }
            & icacls $paths['admin'] /grant '*S-1-5-32-544:(F)' 1>$null 2>$null; $LASTEXITCODE | Should -Be 0
            & icacls $paths['system'] /grant '*S-1-5-18:(F)' 1>$null 2>$null; $LASTEXITCODE | Should -Be 0
            & icacls $paths['other'] /grant '*S-1-5-32-544:(F)' '*S-1-1-0:(R)' 1>$null 2>$null; $LASTEXITCODE | Should -Be 0
            & icacls $paths['deny'] /grant '*S-1-5-32-544:(F)' 1>$null 2>$null; $LASTEXITCODE | Should -Be 0
            & icacls $paths['deny'] /deny '*S-1-1-0:(R)' 1>$null 2>$null; $LASTEXITCODE | Should -Be 0

            (Get-PostgresOwnerOnlyAclState -Path $paths['admin']).Outcome | Should -BeExactly 'Success'
            (Get-PostgresOwnerOnlyAclState -Path $paths['system']).Outcome | Should -BeExactly 'Success'
            (Get-PostgresOwnerOnlyAclState -Path $paths['other']).Outcome | Should -BeExactly 'Failed'
            (Get-PostgresOwnerOnlyAclState -Path $paths['deny']).Outcome | Should -BeExactly 'Failed'
            (Get-PostgresOwnerOnlyAclState -Path $paths['inherited']).Outcome | Should -BeExactly 'Failed'
        }

        # Mutation: return Success whenever icacls ran, or map a nonzero exit to Success.
        It 'S2: locking a path that cannot be locked is never reported as Success' {
            $result = Set-PostgresOwnerOnlyAcl -Path (Join-Path $TestDrive ('missing-' + [guid]::NewGuid().ToString('N') + '.conf'))
            $result.Outcome | Should -BeIn @('Failed', 'Unknown')
        }

        # Mutation: test "-eq 'Failed'" instead of "-ne 'Success'" in
        # Lock-PostgresRecoveryDirectory or Lock-PostgresRecoveryFile.
        It 'S2: a <Outcome> lock result stops the recovery folder and file locks' -TestCases @(
            @{ Outcome = 'Failed' }
            @{ Outcome = 'Unknown' }
        ) {
            param($Outcome)
            $script:Fix36BLockOutcome = $Outcome
            Mock Set-PostgresOwnerOnlyAcl { [pscustomobject]@{ Outcome = $script:Fix36BLockOutcome; Detail = 'fixture' } }
            $folder = Join-Path $TestDrive ('lockdir-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($folder)
            $file = Join-Path $folder 'evidence.conf'
            [System.IO.File]::WriteAllText($file, 'x')

            { Lock-PostgresRecoveryDirectory -Path $folder } | Should -Throw
            { Lock-PostgresRecoveryFile -Path $file } | Should -Throw
            Should -Invoke Set-PostgresOwnerOnlyAcl -Times 2 -Exactly
        }
    }

    Context 'S6 new-password rules' {
        # Mutation: allow code 127 or above, allow control characters, or raise the length limit.
        It 'S6: a new password with <Label> is refused' -TestCases @(
            @{ Label = 'no characters'; Password = '' }
            @{ Label = 'a NUL'; Password = ('ab' + [char]0 + 'cd') }
            @{ Label = 'a tab'; Password = ('ab' + [char]9 + 'cd') }
            @{ Label = 'DEL (127)'; Password = ('ab' + [char]127 + 'cd') }
            @{ Label = 'an accented letter'; Password = ('caf' + [char]0xE9) }
            @{ Label = 'an emoji'; Password = ('pw' + [char]0xD83D + [char]0xDE00) }
            @{ Label = '101 characters'; Password = ('a' * 101) }
        ) {
            param($Label, $Password)
            Get-PostgresNewPasswordProblem -Password $Password | Should -Not -BeNullOrEmpty
        }

        # Mutation: refuse a printable ASCII symbol (quote, backslash, space) or 100 characters.
        It 'S6: every printable ASCII character and exactly 100 characters are accepted' {
            $printable = -join (32..126 | ForEach-Object { [char]$_ })
            Get-PostgresNewPasswordProblem -Password $printable | Should -BeNullOrEmpty
            Get-PostgresNewPasswordProblem -Password ('b' * 100) | Should -BeNullOrEmpty
        }

        # Mutation: include the password in the returned sentence.
        It 'S6: the refusal text never contains the password' {
            $secret = 'Fix36B-Secret-Marker' + [char]0xE9
            $problem = Get-PostgresNewPasswordProblem -Password $secret
            $problem | Should -Not -BeNullOrEmpty
            $problem | Should -Not -Match 'Fix36B-Secret-Marker'
        }

        # Mutation: ignore -RequireSafeNewPassword, or apply the rule without the switch.
        It 'S6: the new-password prompt asks again for an unsafe password; other prompts do not' {
            $unsafe = 'Fix36B-Prompt-Secret' + [char]0xE9
            $script:Fix36BSecureAnswers = New-Object 'System.Collections.Generic.Queue[System.Security.SecureString]'
            foreach ($plain in @($unsafe, $unsafe, 'Fix36B-Good-Pw', 'Fix36B-Good-Pw')) { $script:Fix36BSecureAnswers.Enqueue((New-Fix36BSecureString -Plain $plain)) }
            Mock Read-Host { $script:Fix36BSecureAnswers.Dequeue() }

            $approved = Read-ConfirmedPostgresPassword 'the NEW PostgreSQL password' -RequireSafeNewPassword

            $approved | Should -BeExactly 'Fix36B-Good-Pw'
            Should -Invoke Read-Host -Times 4 -Exactly
            @($script:Fix36BOut | Where-Object { $_ -like '*cannot use that password*' }).Count | Should -Be 1
            @($script:Fix36BOut | Where-Object { $_ -like '*Fix36B-Prompt-Secret*' }).Count | Should -Be 0

            foreach ($plain in @($unsafe, $unsafe)) { $script:Fix36BSecureAnswers.Enqueue((New-Fix36BSecureString -Plain $plain)) }
            Read-ConfirmedPostgresPassword 'the SERVICE ACCOUNT password' | Should -BeExactly $unsafe
        }

        # Mutation: drop -RequireSafeNewPassword from the DATABASE prompt, or add it to the
        # SERVICE ACCOUNT prompt.
        It 'S6: only the installer DATABASE password prompt applies the new-password rules' {
            Mock Test-RunningAsAdministrator { $true }
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
            Mock Read-ConfirmedPostgresPassword { 'Fix36B-Install-Pw' }
            Mock Get-PostgresGuideRelease { $null }

            Install-Postgres83 -OutSuperPasswordPlain ([ref]$null) | Should -BeFalse

            Should -Invoke Read-ConfirmedPostgresPassword -Times 1 -Exactly -ParameterFilter { $WhatFor -eq 'the DATABASE password' -and $RequireSafeNewPassword.IsPresent }
            Should -Invoke Read-ConfirmedPostgresPassword -Times 1 -Exactly -ParameterFilter { $WhatFor -eq 'the SERVICE ACCOUNT password' -and -not $RequireSafeNewPassword.IsPresent }
        }
    }

    Context 'S6 and N7 installer outcomes' {
        BeforeEach {
            $script:Fix36BPriorTemp = $env:TEMP
            $env:TEMP = Join-Path $TestDrive ('install-temp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($env:TEMP)
            Mock Test-RunningAsAdministrator { $true }
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false } }
            Mock Get-PostgresGuideRelease { [pscustomobject]@{ DownloadUrl = 'https://example.invalid/guide.zip'; SizeBytes = 1; SizeMB = 1 } }
            Mock Invoke-PostgresGuideDownload { $true }
            Mock Expand-ZipFileSafe { [System.IO.File]::WriteAllText((Join-Path $DestDir 'postgresql-8.3-int.msi'), 'fixture') }
            Mock Test-PostgresInstalled { $true }
        }
        AfterEach {
            $env:TEMP = $script:Fix36BPriorTemp
        }

        # Mutation: drop the pre-installer Get-PostgresNewPasswordProblem check.
        It 'S6: an unsafe DATABASE password that reaches the installer step is refused before the installer runs' {
            Mock Read-ConfirmedPostgresPassword { if ($WhatFor -eq 'the DATABASE password') { 'Fix36B-Db-Secret' + [char]0xE9 } else { 'svc-ok' } }
            Mock Invoke-PostgresMsiPackage { throw 'The installer must not run with an unsafe database password.' }
            $outPassword = [ref]$null

            Install-Postgres83 -OutSuperPasswordPlain $outPassword | Should -BeFalse

            $outPassword.Value | Should -BeNullOrEmpty
            Should -Invoke Invoke-PostgresMsiPackage -Times 0 -Exactly
            $script:Fix36BOut | Should -Contain '  PostgreSQL was not installed: the database password cannot be used safely. Nothing was changed.'
        }

        # Mutation: always print "installed and running" after the installer.
        It 'N7: the install says "running" only when the service is seen <Status>' -TestCases @(
            @{ Status = 'Running'; ClaimsRunning = $true }
            @{ Status = 'Stopped'; ClaimsRunning = $false }
        ) {
            param($Status, $ClaimsRunning)
            $script:Fix36BServiceStatus = $Status
            Mock Read-ConfirmedPostgresPassword { 'Fix36B-Install-Ok' }
            Mock Invoke-PostgresMsiPackage { $true }
            $outPassword = [ref]$null

            Install-Postgres83 -OutSuperPasswordPlain $outPassword | Should -BeTrue

            $outPassword.Value | Should -BeExactly 'Fix36B-Install-Ok'
            ($script:Fix36BOut -contains '  PostgreSQL 8.3 installed and running.') | Should -Be $ClaimsRunning
            (@($script:Fix36BOut | Where-Object { $_ -like '*is not running yet (state: Stopped)*' }).Count -eq 1) | Should -Be (-not $ClaimsRunning)
        }

        # FIX123. Mutation: drop -LongStep (a silent installer then reads "stalled" after 60 s), or end the step before the
        # installer returns, or leave it open after a failed install.
        It 'FIX123: the installer runs as one marked long step that is ended with the installer result (<Installer>)' -TestCases @(
            @{ Installer = $true; Expected = 'long-step,installer,complete:Final' }
            @{ Installer = $false; Expected = 'long-step,installer,complete:Error' }
        ) {
            param($Installer, $Expected)
            $script:Fix36BServiceStatus = 'Running'
            $script:Fix123Installer = $Installer
            $script:Fix123Events = New-Object System.Collections.Generic.List[string]
            Mock Read-ConfirmedPostgresPassword { 'Fix36B-Install-Ok' }
            Mock Write-TpmCompactExtractionProgress {
                if ($LongStep) { [void]$script:Fix123Events.Add('long-step') }
                elseif ($Complete) { [void]$script:Fix123Events.Add('complete:' + $Outcome) }
            }
            Mock Invoke-PostgresMsiPackage { [void]$script:Fix123Events.Add('installer'); $script:Fix123Installer }

            [void](Install-Postgres83 -OutSuperPasswordPlain ([ref]$null))

            ($script:Fix123Events -join ',') | Should -BeExactly $Expected
        }
    }

    Context 'S7 one PostgreSQL repair at a time' {
        # Mutation: drop the depth count (release on the first Exit).
        It 'S7: the lock is re-entrant inside one process and released by the last exit' {
            Enter-PostgresRecoveryLock | Should -BeTrue
            Enter-PostgresRecoveryLock | Should -BeTrue
            Exit-PostgresRecoveryLock
            $script:PostgresRecoveryLockHeld | Should -Not -BeNullOrEmpty
            Exit-PostgresRecoveryLock
            $script:PostgresRecoveryLockHeld | Should -BeNullOrEmpty
            $holder = Start-Fix36BLockHolder -Name $script:PostgresRecoveryLockName
            Stop-Fix36BProcess -Process $holder
        }

        # Mutation: name the lock without the install folder, or skip the path normalization.
        It 'S7: the default lock name follows the PostgreSQL install folder' {
            $script:PostgresRecoveryLockName = $null
            $priorInstallDir = $script:PostgresInstallDir
            try {
                $script:PostgresInstallDir = 'C:\Fix36B\PostgreSQL\8.3'
                $first = Get-PostgresRecoveryLockName
                $script:PostgresInstallDir = 'c:\fix36b\postgresql\8.3\'
                $same = Get-PostgresRecoveryLockName
                $script:PostgresInstallDir = 'C:\Fix36B\PostgreSQL\9.0'
                $other = Get-PostgresRecoveryLockName
            } finally {
                $script:PostgresInstallDir = $priorInstallDir
            }
            $first | Should -BeLike 'Global\TeknoParrotManager.PostgresPasswordRepair.*'
            $same | Should -BeExactly $first
            $other | Should -Not -Be $first
        }

        # Mutation: treat a timed-out wait as acquired in Enter-PostgresRecoveryLock (drop
        # the "-not $acquired" return), or record the lock as held before it is acquired.
        It 'S7: the lock is refused while another process holds it and taken once it is free' {
            $holder = Start-Fix36BLockHolder -Name $script:PostgresRecoveryLockName
            try {
                $acquiredWhileHeld = Enter-PostgresRecoveryLock
                $heldWhileBusy = $script:PostgresRecoveryLockHeld
            } finally {
                Stop-Fix36BProcess -Process $holder
            }
            $acquiredWhileHeld | Should -BeFalse
            $heldWhileBusy | Should -BeNullOrEmpty

            Enter-PostgresRecoveryLock | Should -BeTrue
            $script:PostgresRecoveryLockHeld | Should -Not -BeNullOrEmpty
            Exit-PostgresRecoveryLock
            $script:PostgresRecoveryLockHeld | Should -BeNullOrEmpty
        }

        # Mutation: drop the finally that calls Exit-PostgresRecoveryLock in
        # Get-PostgresTrustRuleMarkerState.
        It 'S7: the marker check releases the lock when it returns' {
            $state = Get-PostgresTrustRuleMarkerState

            $state.State | Should -BeExactly 'None'
            $state.Busy | Should -BeFalse
            $script:PostgresRecoveryLockHeld | Should -BeNullOrEmpty
            $holder = Start-Fix36BLockHolder -Name $script:PostgresRecoveryLockName
            Stop-Fix36BProcess -Process $holder
        }

        # Mutation: drop the lock from Get-PostgresTrustRuleMarkerState (the marker is then
        # removed while the other process holds the lock).
        It 'S7: the marker is not cleared while another process holds the lock, and is cleared once it is free' {
            $fixture = New-Fix36BOriginalMarkerFixture
            $script:Fix36BServiceStatus = 'Stopped'
            $holder = Start-Fix36BLockHolder -Name $script:PostgresRecoveryLockName
            try {
                $busy = Test-PostgresManualRecoveryRequired
                $busyDetail = Get-PostgresManualRecoveryDetail
            } finally {
                Stop-Fix36BProcess -Process $holder
            }
            $busy | Should -BeTrue
            $script:PostgresTrustRuleMarkerState.Busy | Should -BeTrue
            $busyDetail | Should -Match 'Another TeknoParrot Manager window is changing PostgreSQL'
            Test-Path -LiteralPath $fixture.Marker -PathType Leaf | Should -BeTrue

            Test-PostgresManualRecoveryRequired | Should -BeFalse
            $script:PostgresTrustRuleMarkerState.State | Should -BeExactly 'None'
            Test-Path -LiteralPath $fixture.Marker -PathType Leaf | Should -BeFalse
        }

        It 'an unreadable recovery check blocks setup only when a repair marker file really exists' {
            $markerFile = Join-Path $TestDrive 'fix36b-gate-marker.json'
            Mock Get-PostgresTrustRuleMarkerState { [pscustomobject]@{ State = 'Error'; MarkerPath = $script:Fix36BGateMarker; Reason = 'fixture read problem' } }
            $script:Fix36BGateMarker = $markerFile
            Test-PostgresManualRecoveryRequired | Should -BeFalse
            [System.IO.File]::WriteAllText($markerFile, '{}')
            Test-PostgresManualRecoveryRequired | Should -BeTrue
        }
    }

    Context 'S8 and N1 failure classification' {
        # Mutation: restore the old "authentication failed|password" match to
        # PasswordAuthenticationFailed, or drop the role check before DatabaseMissing.
        It 'S8: "<Detail>" is classified <Category>' -TestCases @(
            @{ Detail = 'psql: FATAL:  password authentication failed for user "postgres"'; Category = 'PasswordAuthenticationFailed' }
            @{ Detail = 'psql: FATAL:  28P01: login rejected'; Category = 'PasswordAuthenticationFailed' }
            @{ Detail = 'psql: fe_sendauth: no password supplied'; Category = 'CannotConnect' }
            @{ Detail = 'psql: FATAL:  Ident authentication failed for user "postgres"'; Category = 'CannotConnect' }
            @{ Detail = 'psql: FATAL:  role "gtuser" does not exist'; Category = 'CannotConnect' }
            @{ Detail = 'psql: FATAL:  database "GameDB01" does not exist'; Category = 'DatabaseMissing' }
            @{ Detail = 'psql: FATAL:  Passwort-Authentifizierung fuer Benutzer "postgres" fehlgeschlagen'; Category = 'UnknownQueryFailure' }
        ) {
            param($Detail, $Category)
            (Get-PostgresFailureDiagnosis -GameLabel 'Fix36B Game' -DbName 'GameDB01' -Detail $Detail).Category | Should -BeExactly $Category
        }
    }

    Context 'S9 temporary credential files left by a killed run' {
        # FIX110A B-1: the start-up check only reports old-looking files; it never deletes, even a file that looks stale.
        # Mutation: delete a candidate again (by path or after any check) in Get-PostgresLeftoverPgPassFiles.
        It 'S9: old-looking leftovers are counted and every file is kept' {
            $folder = Join-Path $TestDrive ('sweep-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $hex = [guid]::NewGuid().ToString('N')
            $deadLocked = New-Fix36BPgPassFixture -Directory $folder -Name ('tpm-pgpass-2147483644-' + $hex + '.conf') -Lock
            $own = New-Fix36BPgPassFixture -Directory $folder -Name ('tpm-pgpass-' + $PID + '-' + $hex + '.conf') -Lock
            $legacyOld = New-Fix36BPgPassFixture -Directory $folder -Name ('tpm-pgpass-' + [guid]::NewGuid().ToString('N') + '.conf') -Lock -AgeHours 25
            # A different length (31 hex digits, not 32) is not the exact name shape, so it is not counted.
            $otherName = New-Fix36BPgPassFixture -Directory $folder -Name ('tpm-pgpass-2147483644-' + $hex.Substring(0, 31) + '.conf') -Lock

            $summary = Get-PostgresLeftoverPgPassFiles -Directory $folder

            $summary.Found | Should -Be 3
            foreach ($kept in @($deadLocked, $own, $legacyOld, $otherName)) { Test-Path -LiteralPath $kept | Should -BeTrue }
        }

        # Mutation: let a listing failure throw out of Get-PostgresLeftoverPgPassFiles.
        It 'S9: a folder that cannot be listed finds nothing and does not throw' {
            $summary = Get-PostgresLeftoverPgPassFiles -Directory (Join-Path $TestDrive ('missing-' + [guid]::NewGuid().ToString('N')))
            $summary.Found | Should -Be 0
        }
    }

    Context 'N2 incomplete PostgreSQL backups' {
        BeforeEach {
            $script:Fix36BProfiles = Join-Path $TestDrive ('n2-profiles-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $script:Fix36BBin = Join-Path $script:Fix36BProfiles 'bin'
            [void][System.IO.Directory]::CreateDirectory($script:Fix36BBin)
            $xml = '<GameProfile><GameName>Fix36B</GameName><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation></ConfigValues></GameProfile>'
            [System.IO.File]::WriteAllText((Join-Path $script:Fix36BProfiles 'Fix36B.xml'), $xml)
            $script:PostgresBinDir = $script:Fix36BBin
            Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { @(Get-Item -LiteralPath (Join-Path $script:Fix36BProfiles 'Fix36B.xml')) }
            Mock Get-PostgresProfileDisplayMetadata { [pscustomobject]@{ DisplayName = 'Fix36B Game'; ProfileKey = 'Fix36B' } }
            Mock Test-PostgresInstalled { $true }
            Mock Get-PostgresDatabaseState { [pscustomobject]@{ Exists = $true; Verified = $true } }
            Mock Write-TpmCompactExtractionProgress {}
        }

        # Mutation: drop the incomplete-label write in Backup-PostgresDatabases, or write it on success.
        It 'N2: a backup that did not finish is labeled; a complete one is not' {
            $failed = Backup-PostgresDatabases -UserProfilesDir $script:Fix36BProfiles -SuperPasswordPlain 'fixture-password'
            $failed.Succeeded | Should -BeFalse
            $failedLabel = Get-PostgresIncompleteBackupMarkerPath -BackupFolder $failed.Path
            Test-Path -LiteralPath $failedLabel -PathType Leaf | Should -BeTrue
            [System.IO.File]::ReadAllText($failedLabel) | Should -Match 'GameDB01'

            New-Item -ItemType File -Path (Join-Path $script:Fix36BBin 'pg_dump.exe') -Force | Out-Null
            Mock Invoke-PostgresNativeCommand {
                param([string]$FilePath, [string[]]$Arguments, [string[]]$Secrets, [string]$PasswordPlain)
                $outputIndex = [Array]::IndexOf($Arguments, '-f')
                [System.IO.File]::WriteAllText($Arguments[$outputIndex + 1], 'fixture backup')
                [pscustomobject]@{ ExitCode = 0; Output = '' }
            }
            $complete = Backup-PostgresDatabases -UserProfilesDir $script:Fix36BProfiles -SuperPasswordPlain 'fixture-password'
            $complete.Succeeded | Should -BeTrue
            Test-Path -LiteralPath (Get-PostgresIncompleteBackupMarkerPath -BackupFolder $complete.Path) | Should -BeFalse
        }

        # Mutation: drop the refusal after the selection in Invoke-RestorePostgresBackup.
        It 'N2: the restore menu marks a labeled backup and refuses to restore it' {
            $root = Join-Path $TestDrive ('n2-restore-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $folder = Join-Path $root '2026-11-01_10-00-00_000_fixture'
            [void][System.IO.Directory]::CreateDirectory($folder)
            [System.IO.File]::WriteAllText((Join-Path $folder 'GameDB01.backup'), 'partial')
            [System.IO.File]::WriteAllText((Get-PostgresIncompleteBackupMarkerPath -BackupFolder $folder), 'incomplete')
            Mock Test-PostgresManualRecoveryRequired { $false }
            Mock Read-TpmChoice { '1' }
            Mock Invoke-PostgresRestoreTransaction { throw 'An incomplete backup must not be restored.' }

            $result = Invoke-RestorePostgresBackup -BackupRoot $root

            $result.Succeeded | Should -BeFalse
            $result.Reason | Should -BeExactly 'INCOMPLETE_POSTGRES_BACKUP'
            @($script:Fix36BOut | Where-Object { $_ -like '*2026-11-01_10-00-00_000_fixture*INCOMPLETE - cannot be restored*' }).Count | Should -Be 1
            Should -Invoke Invoke-PostgresRestoreTransaction -Times 0 -Exactly
        }
    }
}
