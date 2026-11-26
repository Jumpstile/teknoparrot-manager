#Requires -Module Pester

# FIX131 N10: the real-install smoke harness (scripts\Invoke-TPM-RealInstanceSmoke.ps1).
#   1. Its unattended run changes TeknoParrot-Manager.config.json for the length of the run. The old restore lived only in memory plus a
#      try/finally, so a killed process (closed window, crash, power cut) left the override in place AND the next run took the override as
#      "the original" and kept it for ever. Now a restore record (original bytes, their SHA-256, the SHA-256 of the override) is written
#      atomically BEFORE the file is changed, deleted only after a verified restore, and the next run puts the original back first, but
#      never over a file that someone changed since.
#   2. Its backup copy of UserProfiles kept every saved PostgreSQL password (the Pass field) in plain text. The copy is now blanked, or
#      deleted when it cannot be blanked.
# The harness has top-level code that needs a real TeknoParrot folder, so only its function definitions are extracted (the same way
# Tests\TPMCertificationHarness.Tests.ps1 does); nothing outside TestDrive is touched and the product is never run.
# What this CANNOT prove: a real process kill or power cut. The "died" runs below stop after the override was written and start a new run.
# Each It names the mutation that makes it fail.

BeforeAll {
    $harnessPath = Join-Path $PSScriptRoot '..\scripts\Invoke-TPM-RealInstanceSmoke.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX131 tests could not parse the smoke harness.' }
    $wanted = @(
        'Copy-IfExists', 'Copy-TPMXmlWithoutPass', 'Write-TPMBytesAtomic', 'Write-TPMTextAtomic', 'Get-TPMConfigJsonWithRootText',
        'Get-TPMTemporaryUnattendedConfigText', 'Get-TPMConfigJsonSnapshot', 'Set-TPMConfigJsonRoot', 'New-TPMTemporaryUnattendedConfig',
        'Restore-TPMConfigJsonSnapshot', 'Test-TPMConfigRestored', 'Get-TPMConfigRestoreRecordPath', 'Get-TPMBytesSha256',
        'Write-TPMConfigRestoreRecord', 'Remove-TPMConfigRestoreRecord', 'Restore-TPMInterruptedConfigOverride',
        'Invoke-TPMUnattendedRootBinding', 'Get-TPMEffectiveRootFromUnattendedLog', 'Test-TPMUnattendedRootMatch', 'Get-TreeHash'
    )
    $found = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    if ($found.Count -ne $wanted.Count) { throw ('FIX131 tests expected {0} harness functions, found {1}.' -f $wanted.Count, $found.Count) }
    $functionFile = Join-Path $TestDrive ('f131-harness-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    [System.IO.File]::WriteAllText($functionFile, (($found | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $script:backupDir = Join-Path $TestDrive 'unset-backups'

    $script:F131Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $script:F131ConfigText = "{`r`n  `"TeknoParrotRoot`": `"C:\\Saved\\TeknoParrot`",`r`n  `"GamesInstallFolder`": `"C:\\Saved\\Games`",`r`n  `"Theme`": `"dark`"`r`n}"

    function New-F131Folder {
        param([Parameter(Mandatory)][string]$Name)
        $folder = Join-Path $TestDrive ('f131-' + $Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($folder)
        return $folder
    }
    function Get-F131Base64 {
        param([Parameter(Mandatory)][string]$Path)
        return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    # A settings file whose exact bytes the tests compare: with a BOM and Windows line endings, because the in-memory snapshot loses the BOM.
    function New-F131ConfigWithBom {
        param([Parameter(Mandatory)][string]$Folder)
        $path = Join-Path $Folder 'TeknoParrot-Manager.config.json'
        $bytes = [byte[]]@(0xEF, 0xBB, 0xBF) + $script:F131Utf8NoBom.GetBytes($script:F131ConfigText)
        [System.IO.File]::WriteAllBytes($path, $bytes)
        return $path
    }
    # What a run that died while the override was in place leaves behind: the restore record and the changed settings file.
    function Set-F131DiedWithOverride {
        param([Parameter(Mandatory)][string]$ConfigPath, [string]$Root = 'X:\Requested')
        $overrideText = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { Get-TPMConfigJsonWithRootText -Text ([System.IO.File]::ReadAllText($ConfigPath)) -TeknoParrotRoot $Root } else { Get-TPMTemporaryUnattendedConfigText -TeknoParrotRoot $Root }
        Write-TPMConfigRestoreRecord -ConfigPath $ConfigPath -OverrideText $overrideText
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { [void](Set-TPMConfigJsonRoot -ConfigPath $ConfigPath -TeknoParrotRoot $Root) } else { [void](New-TPMTemporaryUnattendedConfig -ConfigPath $ConfigPath -TeknoParrotRoot $Root) }
    }
    function New-F131UnattendedLog {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
        [System.IO.File]::WriteAllText($Path, ((@('Configuration:', ('  TeknoParrot root     : ' + $Root), '', 'Loading collection dat from ZIP...')) -join [Environment]::NewLine), $script:F131Utf8NoBom)
    }
}

Describe 'FIX131 N10 the settings override is restored even when a run died' {
    It 'puts the exact original bytes back after a run that died while the override was in place' {
        # Mutation: write no restore record (or do not read it at the start of the next run) -> the override stays in the file.
        $folder = New-F131Folder -Name 'died'
        $path = New-F131ConfigWithBom -Folder $folder
        $originalBase64 = Get-F131Base64 -Path $path
        Set-F131DiedWithOverride -ConfigPath $path
        (Get-F131Base64 -Path $path) | Should -Not -BeExactly $originalBase64
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf | Should -BeTrue

        $result = Restore-TPMInterruptedConfigOverride -ConfigPath $path
        $result.State | Should -BeExactly 'Restored'
        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) | Should -BeFalse
    }

    It 'removes the temporary settings file that a dead run created when none existed before' {
        # Mutation: record only a file that existed (no record for a created file) -> the temporary settings file stays and is taken as the user's own.
        $folder = New-F131Folder -Name 'created'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        Set-F131DiedWithOverride -ConfigPath $path
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        (Restore-TPMInterruptedConfigOverride -ConfigPath $path).State | Should -BeExactly 'Restored'
        Test-Path -LiteralPath $path | Should -BeFalse
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) | Should -BeFalse
    }

    It 'never overwrites a settings file that someone changed after the run died' {
        # Mutation: restore whenever a record exists, without comparing the file with the override that was written -> the edit below is lost.
        $folder = New-F131Folder -Name 'edited'
        $path = New-F131ConfigWithBom -Folder $folder
        Set-F131DiedWithOverride -ConfigPath $path
        [System.IO.File]::WriteAllText($path, '{"TeknoParrotRoot":"D:\\Edited by the user"}', $script:F131Utf8NoBom)
        $editedBase64 = Get-F131Base64 -Path $path

        $result = Restore-TPMInterruptedConfigOverride -ConfigPath $path
        $result.State | Should -BeExactly 'Refused'
        $result.Reason | Should -Match 'changed after the interrupted run'
        (Get-F131Base64 -Path $path) | Should -BeExactly $editedBase64
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf | Should -BeTrue -Because 'the record is kept so nothing is forgotten'
    }

    It 'only deletes the record when the file is already the original' {
        # Mutation: treat "already the original" as a failure, or rewrite the file anyway.
        $folder = New-F131Folder -Name 'original'
        $path = New-F131ConfigWithBom -Folder $folder
        Set-F131DiedWithOverride -ConfigPath $path
        [System.IO.File]::WriteAllBytes($path, [System.Convert]::FromBase64String(([System.IO.File]::ReadAllText((Get-TPMConfigRestoreRecordPath -ConfigPath $path)) | ConvertFrom-Json).OriginalBase64))
        $before = Get-F131Base64 -Path $path
        (Restore-TPMInterruptedConfigOverride -ConfigPath $path).State | Should -BeExactly 'AlreadyOriginal'
        (Get-F131Base64 -Path $path) | Should -BeExactly $before
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) | Should -BeFalse
    }

    It 'refuses and changes nothing when the record is damaged, is for another file or its saved original fails its checksum' {
        # Mutation: trust the record without checking the file path or the checksum of the saved original.
        $folder = New-F131Folder -Name 'damaged'
        $path = New-F131ConfigWithBom -Folder $folder
        Set-F131DiedWithOverride -ConfigPath $path
        $recordPath = Get-TPMConfigRestoreRecordPath -ConfigPath $path
        $goodRecord = [System.IO.File]::ReadAllText($recordPath)
        $overriddenBase64 = Get-F131Base64 -Path $path

        $variants = [ordered]@{
            'not JSON'       = 'this is not json'
            'other file'     = ($goodRecord -replace [regex]::Escape((($path -replace '\\', '\\'))), 'D:\\Other\\TeknoParrot-Manager.config.json')
            'bad checksum'   = ($goodRecord -replace '"OriginalSha256":\s*"[0-9A-F]{8}', '"OriginalSha256": "00000000')
        }
        foreach ($name in $variants.Keys) {
            [System.IO.File]::WriteAllText($recordPath, [string]$variants[$name], $script:F131Utf8NoBom)
            $result = Restore-TPMInterruptedConfigOverride -ConfigPath $path
            $result.State | Should -BeExactly 'Refused' -Because $name
            (Get-F131Base64 -Path $path) | Should -BeExactly $overriddenBase64 -Because $name
            Test-Path -LiteralPath $recordPath -PathType Leaf | Should -BeTrue -Because $name
        }
    }

    It 'writes a file by swapping in a complete copy: exact bytes, no temporary file left, the old file kept when the swap fails' {
        # Mutation: write the bytes straight into the target (a crash then leaves a half-written file) or leave the temporary copy behind.
        # (A real crash cannot be simulated here; the failing swap below proves the old file stays whole and no temporary copy is left.)
        $folder = New-F131Folder -Name 'atomic'
        $path = Join-Path $folder 'target.json'
        [System.IO.File]::WriteAllText($path, 'old', $script:F131Utf8NoBom)
        Write-TPMBytesAtomic -Path $path -Bytes ([byte[]]@(0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A))
        (Get-F131Base64 -Path $path) | Should -BeExactly ([Convert]::ToBase64String([byte[]]@(0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A)))
        @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name }) | Should -Be @('target.json')

        $held = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            { Write-TPMBytesAtomic -Path $path -Bytes ([byte[]]@(0x42, 0x42, 0x42)) } | Should -Throw
        } finally { $held.Dispose() }
        (Get-F131Base64 -Path $path) | Should -BeExactly ([Convert]::ToBase64String([byte[]]@(0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A)))
        @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name }) | Should -Be @('target.json')
    }
}

Describe 'FIX131 N10 the unattended root binding repairs and protects the settings file' {
    It 'repairs what a dead earlier run left before it takes its own snapshot, and ends with the original settings' {
        # Mutation: take the snapshot first (skip Restore-TPMInterruptedConfigOverride) -> the stale override becomes "the original" and is kept for ever.
        $folder = New-F131Folder -Name 'bind-repair'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $originalBase64 = Get-F131Base64 -Path $path
        Set-F131DiedWithOverride -ConfigPath $path -Root 'X:\StaleRoot'
        $log = Join-Path $folder 'unattended.log'

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended { New-F131UnattendedLog -Path $log -Root 'X:\Requested' }

        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
        $binding.PriorConfigExisted | Should -BeTrue
        $binding.RestoreAttempted | Should -BeTrue
        $binding.VerificationSucceeded | Should -BeTrue
        @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }).Passed | Should -BeTrue
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) | Should -BeFalse
    }

    It 'removes the settings copy that TPM moved into the TeknoParrot folder during the run, and puts the original back' {
        # Mutation: drop the cleanup in Invoke-TPMUnattendedRootBinding -> the harness settings stay in the real install and the check still says "restored".
        $folder = New-F131Folder -Name 'bind-moved'
        $root = New-F131Folder -Name 'bind-moved-root'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $originalBase64 = Get-F131Base64 -Path $path
        $log = Join-Path $folder 'unattended.log'
        $moved = Join-Path $root 'TeknoParrotManager\State\TeknoParrot-Manager.config.json'
        $backupCopy = Join-Path $root 'TeknoParrotManager\Backups\LegacyMig_test\TeknoParrot-Manager.config.json'
        $script:F131MoveSource = $path; $script:F131MoveTarget = $moved; $script:F131MoveRoot = $root; $script:F131MoveLog = $log; $script:F131MoveBackup = $backupCopy

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot $root -LogPath $log -InvokeUnattended {
            # What an unattended TPM start does with a program-folder settings file.
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:F131MoveTarget))
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:F131MoveBackup))
            Copy-Item -LiteralPath $script:F131MoveSource -Destination $script:F131MoveBackup
            Move-Item -LiteralPath $script:F131MoveSource -Destination $script:F131MoveTarget
            New-F131UnattendedLog -Path $script:F131MoveLog -Root $script:F131MoveRoot
        }

        Test-Path -LiteralPath $moved | Should -BeFalse
        Test-Path -LiteralPath $backupCopy | Should -BeFalse
        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
        @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }).Passed | Should -BeTrue
    }

    It 'keeps the moved settings copy when someone edited it during the run' {
        # Mutation: delete the moved copy without comparing its bytes to the override -> the edited settings are lost.
        $folder = New-F131Folder -Name 'bind-edited'
        $root = New-F131Folder -Name 'bind-edited-root'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $log = Join-Path $folder 'unattended.log'
        $moved = Join-Path $root 'TeknoParrotManager\State\TeknoParrot-Manager.config.json'
        $script:F131MoveSource = $path; $script:F131MoveTarget = $moved; $script:F131MoveRoot = $root; $script:F131MoveLog = $log
        $null = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot $root -LogPath $log -InvokeUnattended {
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:F131MoveTarget))
            Move-Item -LiteralPath $script:F131MoveSource -Destination $script:F131MoveTarget
            [System.IO.File]::WriteAllText($script:F131MoveTarget, '{ "Theme": "edited by the user" }', $script:F131Utf8NoBom)
            New-F131UnattendedLog -Path $script:F131MoveLog -Root $script:F131MoveRoot
        }
        [System.IO.File]::ReadAllText($moved) | Should -Match 'edited by the user'
    }

    It 'refuses the run and changes nothing when an earlier override cannot be undone safely' {
        # Mutation: carry on after a refused repair -> the run snapshots the edited file, overrides it and "restores" it, hiding the problem.
        $folder = New-F131Folder -Name 'bind-refuse'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        Set-F131DiedWithOverride -ConfigPath $path
        [System.IO.File]::WriteAllText($path, '{"TeknoParrotRoot":"D:\\Edited by the user"}', $script:F131Utf8NoBom)
        $editedBase64 = Get-F131Base64 -Path $path
        $log = Join-Path $folder 'unattended.log'
        $script:F131Invoked = $false

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended { $script:F131Invoked = $true }

        $script:F131Invoked | Should -BeFalse
        (Get-F131Base64 -Path $path) | Should -BeExactly $editedBase64
        $binding.RestoreAttempted | Should -BeFalse
        $binding.RestorationFailureReason | Should -Match 'could not be undone'
        @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }).Passed | Should -BeFalse
        @($binding.Checks | Where-Object { $_.Name -ceq 'TPM unattended run' }).Passed | Should -BeFalse
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf | Should -BeTrue
    }

    It 'has the restore record on disk before the settings file is changed, and removes it after a verified restore' {
        # Mutation: write the record after the override, or never delete it after a good restore.
        $folder = New-F131Folder -Name 'bind-order'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $originalBase64 = Get-F131Base64 -Path $path
        $log = Join-Path $folder 'unattended.log'
        $script:F131Seen = $null

        [void](Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended {
                $script:F131Seen = [pscustomobject]@{
                    RecordExists = (Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf)
                    Overridden   = ((Get-F131Base64 -Path $path) -cne $originalBase64)
                }
                New-F131UnattendedLog -Path $log -Root 'X:\Requested'
            })

        $script:F131Seen.RecordExists | Should -BeTrue
        $script:F131Seen.Overridden | Should -BeTrue
        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
        @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('TeknoParrot-Manager.config.json', 'unattended.log')
    }

    It 'leaves the settings file alone and says so when the restore record cannot be written' {
        # Mutation: change the settings file even though the record could not be saved -> a crash then could not be repaired.
        $folder = New-F131Folder -Name 'bind-norecord'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $originalBase64 = Get-F131Base64 -Path $path
        [void][System.IO.Directory]::CreateDirectory((Get-TPMConfigRestoreRecordPath -ConfigPath $path))
        $log = Join-Path $folder 'unattended.log'
        $script:F131Invoked = $false

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended { $script:F131Invoked = $true }

        $script:F131Invoked | Should -BeFalse
        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
        (@($binding.Checks | Where-Object { $_.Name -ceq 'TPM unattended run' }).Details) | Should -Match 'restore record could not be written'
    }

    It 'keeps the record when the restore cannot be read back, so the next run can finish it' {
        # Mutation: delete the record whether or not the restore was verified -> a failed restore could never be repaired later.
        $folder = New-F131Folder -Name 'bind-lockedrestore'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $originalBase64 = Get-F131Base64 -Path $path
        $log = Join-Path $folder 'unattended.log'
        $script:F131Held = $null
        try {
            $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended {
                New-F131UnattendedLog -Path $log -Root 'X:\Requested'
                $script:F131Held = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            }
        } finally {
            if ($null -ne $script:F131Held) { $script:F131Held.Dispose() }
        }
        @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }).Passed | Should -BeFalse
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf | Should -BeTrue
        (Get-F131Base64 -Path $path) | Should -Not -BeExactly $originalBase64

        (Restore-TPMInterruptedConfigOverride -ConfigPath $path).State | Should -BeExactly 'Restored'
        (Get-F131Base64 -Path $path) | Should -BeExactly $originalBase64
    }

    It 'does not overwrite a settings file that someone edited while the run was in progress, and keeps the record' {
        # Mutation: restore the pre-run snapshot in finally without checking the file is still the override this run wrote -> the edit is lost.
        $folder = New-F131Folder -Name 'bind-editduring'
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($path, $script:F131ConfigText, $script:F131Utf8NoBom)
        $log = Join-Path $folder 'unattended.log'
        $script:F131EditedBase64 = $null

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended {
            New-F131UnattendedLog -Path $log -Root 'X:\Requested'
            [System.IO.File]::WriteAllText($path, '{"TeknoParrotRoot":"D:\\Edited during the run"}', $script:F131Utf8NoBom)
            $script:F131EditedBase64 = Get-F131Base64 -Path $path
        }

        (Get-F131Base64 -Path $path) | Should -BeExactly $script:F131EditedBase64
        $restoration = @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' })
        $restoration.Passed | Should -BeFalse
        $restoration.Details | Should -Match 'was changed while the run was in progress'
        $binding.RestoreSucceeded | Should -BeFalse
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) -PathType Leaf | Should -BeTrue
    }
}

Describe 'FIX131 N10 the UserProfiles backup copy keeps no saved password' {
    BeforeEach {
        Mock Write-Host {}
        $script:F131Secret = 'F131-secret-value'
        $script:F131Profiles = New-F131Folder -Name 'profiles'
        $script:backupDir = New-F131Folder -Name 'backupdir'
        $xml = {
            param($Db, $Pass)
            '<?xml version="1.0" encoding="utf-8"?><GameProfile><GameName>G</GameName><ConfigValues>' +
            '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>' + $Db + '</FieldValue></FieldInformation>' +
            '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>User</FieldName><FieldValue>postgres</FieldValue></FieldInformation>' +
            '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Pass</FieldName><FieldValue>' + $Pass + '</FieldValue></FieldInformation>' +
            '</ConfigValues></GameProfile>'
        }
        [System.IO.File]::WriteAllText((Join-Path $script:F131Profiles 'G1.xml'), (& $xml 'GameDB1' $script:F131Secret), $script:F131Utf8NoBom)
        $nested = Join-Path $script:F131Profiles 'FullBackup\Startup_1'
        [void][System.IO.Directory]::CreateDirectory($nested)
        [System.IO.File]::WriteAllText((Join-Path $nested 'G2.xml'), (& $xml 'GameDB2' $script:F131Secret), $script:F131Utf8NoBom)
        [System.IO.File]::WriteAllText((Join-Path $script:F131Profiles 'broken.xml'), ('<GameProfile><FieldName>Pass</FieldName><FieldValue>' + $script:F131Secret), $script:F131Utf8NoBom)
    }

    It 'blanks the Pass value in every XML file of the copy and keeps every other field' {
        # Mutation: copy UserProfiles without blanking (copy the XML files with Copy-Item) -> the password is in the copy.
        (Copy-IfExists $script:F131Profiles 'UserProfiles') | Should -BeTrue
        $copy = Join-Path $script:backupDir 'UserProfiles'
        $all = (@(Get-ChildItem -LiteralPath $copy -Recurse -File -Force | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
        $all | Should -Not -Match ([regex]::Escape($script:F131Secret))
        [System.IO.File]::ReadAllText((Join-Path $copy 'G1.xml')) | Should -Match '<FieldName>DbName</FieldName><FieldValue>GameDB1</FieldValue>'
        [System.IO.File]::ReadAllText((Join-Path $copy 'G1.xml')) | Should -Match '<FieldName>User</FieldName><FieldValue>postgres</FieldValue>'
        [System.IO.File]::ReadAllText((Join-Path $copy 'FullBackup\Startup_1\G2.xml')) | Should -Match '<FieldName>DbName</FieldName><FieldValue>GameDB2</FieldValue>'
    }

    It 'leaves the live folder untouched' {
        # Mutation: blank the Pass values in the source folder instead of the copy.
        $before = [System.IO.File]::ReadAllText((Join-Path $script:F131Profiles 'G1.xml'))
        [void](Copy-IfExists $script:F131Profiles 'UserProfiles')
        [System.IO.File]::ReadAllText((Join-Path $script:F131Profiles 'G1.xml')) | Should -BeExactly $before
        $before | Should -Match ([regex]::Escape($script:F131Secret))
        Test-Path -LiteralPath (Join-Path $script:F131Profiles 'broken.xml') | Should -BeTrue
    }

    It 'leaves out an XML file that cannot be read, because it cannot be shown to be free of passwords' {
        # Mutation: keep unreadable XML files in the copy -> broken.xml (which holds the password) is in the backup.
        [void](Copy-IfExists $script:F131Profiles 'UserProfiles')
        Test-Path -LiteralPath (Join-Path (Join-Path $script:backupDir 'UserProfiles') 'broken.xml') | Should -BeFalse
        (Get-ChildItem -LiteralPath (Join-Path $script:backupDir 'UserProfiles') -Recurse -File -Force | Where-Object { $_.Extension -ieq '.xml' }).Count | Should -Be 2 -Because 'only G1.xml and G2.xml were readable'
    }

    It 'deletes the copy and reports it as not made when the passwords cannot be blanked' {
        # Mutation: ignore a failed blanking and keep the copy -> a copy with passwords is reported as a good backup.
        Mock Copy-TPMXmlWithoutPass { throw 'blanking failed' }
        (Copy-IfExists $script:F131Profiles 'UserProfiles') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:backupDir 'UserProfiles') | Should -BeFalse
    }

    It 'stops the run with the path when a failed copy cannot be deleted, and the copy that is left holds no password' {
        # Mutation: discard the delete error and report "copy was not made" -> no throw, a partial copy is left without a word.
        # Mutation: copy the XML files raw and blank them afterwards -> the surviving copy holds the password.
        $folder = New-F131Folder -Name 'stuck'
        foreach ($name in 'a.xml', 'b.xml') {
            [System.IO.File]::WriteAllText((Join-Path $folder $name), ('<GameProfile><ConfigValues><FieldInformation><FieldName>Pass</FieldName><FieldValue>' + $script:F131Secret + '</FieldValue></FieldInformation></ConfigValues></GameProfile>'), $script:F131Utf8NoBom)
        }
        $copy = Join-Path $script:backupDir 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $copy 'b.xml'))   # a folder where a file must go: writing b.xml fails
        Mock Remove-Item {}
        { Copy-IfExists $folder 'UserProfiles' } | Should -Throw -ExpectedMessage ('*' + $copy + '*')
        $left = (@(Get-ChildItem -LiteralPath $copy -Recurse -File -Force | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
        $left | Should -Not -Match ([regex]::Escape($script:F131Secret))
    }

    It 'reports no copy, and not a failed copy, when the folder to copy does not exist' {
        # Mutation: report a missing folder as a backup that was made ($true) or as a copy that failed ($false).
        $absent = Copy-IfExists (Join-Path $TestDrive 'no-such-profiles') 'UserProfiles'
        $null -eq $absent | Should -BeTrue
    }
}

Describe 'Smoke harness file snapshot' {
    It 'sees hidden files, so editing one is noticed' {
        # Mutation: list files without -Force -> a hidden profile can change between snapshots and the safety check still passes.
        $folder = New-F131Folder -Name 'hidden-snapshot'
        $hidden = Join-Path $folder 'Hidden.xml'
        [System.IO.File]::WriteAllText($hidden, 'one', $script:F131Utf8NoBom)
        (Get-Item -LiteralPath $hidden).Attributes = [System.IO.FileAttributes]::Hidden
        $before = @(Get-TreeHash -Path $folder)
        $before.Count | Should -Be 1
        (Get-Item -LiteralPath $hidden -Force).Attributes = [System.IO.FileAttributes]::Normal
        [System.IO.File]::WriteAllText($hidden, 'two', $script:F131Utf8NoBom)
        (Get-Item -LiteralPath $hidden).Attributes = [System.IO.FileAttributes]::Hidden
        @(Get-TreeHash -Path $folder)[0].Hash | Should -Not -Be $before[0].Hash
    }
}
