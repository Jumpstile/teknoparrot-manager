#Requires -Module Pester

# FIX110A (S-3): Reset and Restore never loses a newer save.
#   1. Invoke-TpmVerifiedFileSwap keeps the bytes the replace removed and compares them with the bytes that were checked.
#      A save made between the check and the replace is put back (or kept in a named file when it cannot be put back).
#   2. The undo of a file that was absent before (the settings file here) deletes only the exact file the restore wrote:
#      identity, write time and bytes are checked on the same open file that is deleted. Anything else is kept.
#   3. The undo that puts the previous settings back replaces only the bytes it just read.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. Races are simulated at the exact point between the check and the use.
# Each It names the product change that makes it fail.
# What this CANNOT prove: a real second program racing in real time, or the full Restore-TpmRestorePointGame flow
# (its absent-file undo is covered by a source guard below and by the same Remove-TpmTreeOwnedFile call the settings undo uses).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:F110Ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($script:F110Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix110a-swap-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function New-F110Folder {
        $folder = Join-Path $TestDrive ('f110-swap-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($folder)
        return $folder
    }

    function Set-F110Text {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    # A swap fixture: a saved copy (the bytes to put back), a target that holds other bytes (or is absent).
    function New-F110SwapFixture {
        param([string]$TargetText = 'current-bytes', [switch]$AbsentTarget)
        $folder = New-F110Folder
        $source = Join-Path $folder 'saved-copy.json'
        $target = Join-Path $folder 'target.json'
        Set-F110Text -Path $source -Text 'restored-bytes'
        if (-not $AbsentTarget) { Set-F110Text -Path $target -Text $TargetText }
        $sourceState = Get-TpmRestorePointFileState -Path $source
        $targetState = Get-TpmRestorePointFileState -Path $target
        return [pscustomobject]@{ Folder = $folder; Source = $source; Target = $target; SourceSha = [string]$sourceState.Sha256; SourceLength = [int64]$sourceState.Length; TargetSha = $(if ($targetState.Present) { [string]$targetState.Sha256 } else { '' }) }
    }

    function Get-F110Residue {
        param([string]$Folder)
        return @(Get-ChildItem -LiteralPath $Folder -Force | Where-Object { $_.Name -match '\.(tpm-restore|tpm-replace)$' })
    }

    # A restore point object as far as the settings undo reads it: the folder holds the settings copy, the record names its bytes.
    function New-F110SettingsPoint {
        param([Parameter(Mandatory)][string]$Folder, [string]$Text = '', [bool]$Present = $true)
        if ($Present) { Set-F110Text -Path (Join-Path $Folder (Get-TpmRestorePointSettingsCopyName)) -Text $Text }
        $state = Get-TpmRestorePointFileState -Path (Join-Path $Folder (Get-TpmRestorePointSettingsCopyName))
        $config = [pscustomobject]@{ Present = $Present; Sha256 = $(if ($Present) { [string]$state.Sha256 } else { '' }); Length = $(if ($Present) { [int64]$state.Length } else { [int64]0 }) }
        return [pscustomobject]@{ Path = $Folder; Record = [pscustomobject]@{ Config = $config } }
    }
}

Describe 'FIX110A S-3: the file swap keeps the bytes it replaces' {
    BeforeEach {
        Mock Write-Log {}
        Mock Assert-TpmNoReparseWriteTarget {}
    }

    It 'replaces an unchanged file and leaves no staged or displaced file behind' {
        # Mutation: leave the displaced copy (or the staged copy) behind after a good swap -> residue files remain beside the target.
        $fx = New-F110SwapFixture
        Invoke-TpmVerifiedFileSwap -SourcePath $fx.Source -TargetPath $fx.Target -ExpectedSha256 $fx.SourceSha -ExpectedLength $fx.SourceLength -ExpectedCurrentSha256 $fx.TargetSha
        [System.IO.File]::ReadAllText($fx.Target) | Should -BeExactly 'restored-bytes'
        (Get-F110Residue -Folder $fx.Folder).Count | Should -Be 0
    }

    It 'puts back a newer save that arrived between the check and the replace' {
        # Mutation: replace without comparing the displaced bytes with the checked bytes -> the newer save is lost and the target holds the restored bytes.
        $fx = New-F110SwapFixture
        Mock Invoke-TpmAtomicFileReplace {
            [System.IO.File]::WriteAllText($Destination, 'newer-save')
            [System.IO.File]::Replace($Source, $Destination, $(if ($Backup) { $Backup } else { [NullString]::Value }))
        }
        $thrown = $null
        try { Invoke-TpmVerifiedFileSwap -SourcePath $fx.Source -TargetPath $fx.Target -ExpectedSha256 $fx.SourceSha -ExpectedLength $fx.SourceLength -ExpectedCurrentSha256 $fx.TargetSha } catch { $thrown = $_.Exception }
        ($null -ne $thrown) | Should -BeTrue
        $thrown.Data['TpmNoChange'] | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        [System.IO.File]::ReadAllText($fx.Target) | Should -BeExactly 'newer-save'
        (Get-F110Residue -Folder $fx.Folder).Count | Should -Be 0
    }

    It 'keeps the newer save in a named file and says so when it cannot be put back' {
        # Mutation: delete the displaced file when the put-back failed (or do not report TpmNewerKept) -> the newer save exists nowhere.
        $fx = New-F110SwapFixture
        Mock Invoke-TpmAtomicFileReplace {
            [System.IO.File]::WriteAllText($Destination, 'newer-save')
            [System.IO.File]::Replace($Source, $Destination, $(if ($Backup) { $Backup } else { [NullString]::Value }))
        }
        Mock Restore-TpmLaunchBoxDisplacedFile { $false }
        $thrown = $null
        try { Invoke-TpmVerifiedFileSwap -SourcePath $fx.Source -TargetPath $fx.Target -ExpectedSha256 $fx.SourceSha -ExpectedLength $fx.SourceLength -ExpectedCurrentSha256 $fx.TargetSha } catch { $thrown = $_.Exception }
        ($null -ne $thrown) | Should -BeTrue
        $thrown.Data.Contains('TpmNoChange') | Should -BeFalse
        $kept = [string]$thrown.Data['TpmNewerKept']
        $kept | Should -Not -BeNullOrEmpty
        [System.IO.File]::ReadAllText($kept) | Should -BeExactly 'newer-save'
        $thrown.Message | Should -Match 'newer file'
    }

    It 'records the identity and write time of the file it moves into an absent target' {
        # Mutation: record the identity of the wrong file (or none) -> a later undo cannot prove the file is the one this swap wrote.
        $fx = New-F110SwapFixture -AbsentTarget
        $placed = @{}
        Invoke-TpmVerifiedFileSwap -SourcePath $fx.Source -TargetPath $fx.Target -ExpectedSha256 $fx.SourceSha -ExpectedLength $fx.SourceLength -ExpectedCurrentSha256 '' -PlacedFile $placed
        [string]$placed['Identity'] | Should -Not -BeNullOrEmpty
        $placed['Identity'] | Should -BeExactly (Get-TpmFileIdentityString -Path $fx.Target)
        [System.IO.File]::GetLastWriteTimeUtc($fx.Target) | Should -Be $placed['LastWriteTimeUtc']
    }
}

Describe 'FIX110A S-3: the undo of a settings file that was absent deletes only the file the restore wrote' {
    BeforeEach {
        Mock Write-Log {}
        Mock Assert-TpmNoReparseWriteTarget {}
        $script:F110Folder = New-F110Folder
        $script:F110Config = Join-Path $script:F110Folder 'settings-target.json'
        # What the restore wrote: the saved copy goes into an absent settings path.
        $script:F110Written = New-F110SettingsPoint -Folder (New-F110Folder) -Text 'written-by-restore'
        $script:F110Safety = New-F110SettingsPoint -Folder (New-F110Folder) -Present $false
        $script:F110Placed = @{}
        Restore-TpmRestorePointSettingsFile -SourceRestorePoint $script:F110Written -ConfigPath $script:F110Config -ExpectedCurrentSha256 '' -PlacedFile $script:F110Placed
    }

    It 'removes the file when nobody touched it' {
        # Mutation: refuse every removal (for example a missing identity) -> the restored file stays after an undo.
        Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config -PlacedFile $script:F110Placed
        Test-Path -LiteralPath $script:F110Config | Should -BeFalse
    }

    It 'keeps a different file that has the same bytes and the same write time' {
        # Mutation: check only the bytes before the delete (delete by path) -> a file put there by someone else is deleted.
        $other = $script:F110Config + '.other'
        Set-F110Text -Path $other -Text 'written-by-restore'
        [System.IO.File]::SetLastWriteTimeUtc($other, $script:F110Placed['LastWriteTimeUtc'])
        [System.IO.File]::Replace($other, $script:F110Config, [NullString]::Value)
        { Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config -PlacedFile $script:F110Placed } | Should -Throw '*different file*'
        [System.IO.File]::ReadAllText($script:F110Config) | Should -BeExactly 'written-by-restore'
    }

    It 'keeps an in-place newer save that has the same bytes but a newer write time' {
        # Mutation: leave -ExpectedLastWriteTimeUtc out of the removal -> identity and bytes match and the newer save is deleted.
        Set-F110Text -Path $script:F110Config -Text 'written-by-restore'
        [System.IO.File]::SetLastWriteTimeUtc($script:F110Config, [datetime]::UtcNow.AddMinutes(10))
        { Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config -PlacedFile $script:F110Placed } | Should -Throw '*rewritten*'
        Test-Path -LiteralPath $script:F110Config | Should -BeTrue
    }

    It 'keeps a newer save with other bytes' {
        # Mutation: delete when the path exists, whatever it holds -> the newer settings are lost.
        Set-F110Text -Path $script:F110Config -Text 'newer-settings'
        { Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config -PlacedFile $script:F110Placed } | Should -Throw '*unexpected settings file*'
        [System.IO.File]::ReadAllText($script:F110Config) | Should -BeExactly 'newer-settings'
    }

    It 'keeps the file when no identity was recorded for it' {
        # Mutation: delete by path when no identity is known -> a file that cannot be proven to be ours is deleted.
        { Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config } | Should -Throw '*no creation identity*'
        Test-Path -LiteralPath $script:F110Config | Should -BeTrue
    }
}

Describe 'FIX110A S-3: the undo that puts the previous settings back replaces only the bytes it read' {
    BeforeEach {
        Mock Write-Log {}
        Mock Assert-TpmNoReparseWriteTarget {}
        $script:F110Folder = New-F110Folder
        $script:F110Config = Join-Path $script:F110Folder 'settings-target.json'
        Set-F110Text -Path $script:F110Config -Text 'written-by-restore'
        $script:F110Written = New-F110SettingsPoint -Folder (New-F110Folder) -Text 'written-by-restore'
        $script:F110Safety = New-F110SettingsPoint -Folder (New-F110Folder) -Text 'previous-settings'
    }

    It 'puts the previous settings back when nothing else changed' {
        # Mutation: skip the swap -> the restored settings stay.
        Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config
        [System.IO.File]::ReadAllText($script:F110Config) | Should -BeExactly 'previous-settings'
        (Get-F110Residue -Folder $script:F110Folder).Count | Should -Be 0
    }

    It 'keeps a newer save that arrives between reading the file and replacing it' {
        # Mutation: replace without the displaced-bytes check (no ExpectedCurrentSha256 on the undo) -> the newer save is overwritten and lost.
        Mock Invoke-TpmAtomicFileReplace {
            [System.IO.File]::WriteAllText($Destination, 'newer-settings')
            [System.IO.File]::Replace($Source, $Destination, $(if ($Backup) { $Backup } else { [NullString]::Value }))
        }
        { Undo-TpmRestorePointSettingsFile -SafetyRestorePoint $script:F110Safety -WrittenRestorePoint $script:F110Written -ConfigPath $script:F110Config } | Should -Throw '*newer file was kept*'
        [System.IO.File]::ReadAllText($script:F110Config) | Should -BeExactly 'newer-settings'
    }
}

Describe 'FIX110A S-3: the game-file undo of Restore-TpmRestorePointGame uses the guarded deletion' {
    It 'removes a file that was absent only through Remove-TpmTreeOwnedFile and never through Remove-Item' {
        # Mutation: put Remove-Item back into the absent-file branch of the rollback -> a newer save at that path is deleted by path.
        $function = @($script:F110Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Restore-TpmRestorePointGame' }, $true))
        $function.Count | Should -Be 1
        $commands = @($function[0].FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $commands | Should -Contain 'Remove-TpmTreeOwnedFile'
        $commands | Should -Not -Contain 'Remove-Item'
    }
}
