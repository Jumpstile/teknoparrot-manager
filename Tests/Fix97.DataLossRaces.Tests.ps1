#Requires -Module Pester

# FIX97: two data-loss races found by an independent read-only audit.
#   S2 - LaunchBox: a save made by another program between the library check and the file replace must never be
#        thrown away by the commit or by the rollback, and the rollback must not be called verified.
#   S4 - Settings: a save from a stale window must not revert what another TeknoParrot Manager window saved,
#        including the saved PostgreSQL password.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code
# runs. Everything lives under TestDrive with synthetic files. The races are simulated by changing a file at the
# exact point between the check and the replace. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX97 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix97FunctionFile = Join-Path $TestDrive 'tpm-fix97-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix97FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix97FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    # ---- S2 fixture -------------------------------------------------------------------------------------------
    function New-Fix97LaunchBox {
        $root = Join-Path $TestDrive ('f97-lb-' + [guid]::NewGuid().ToString('N'))
        $library = Join-Path $root 'LaunchBox'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $library 'Data'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'Source'))
        [System.IO.File]::WriteAllText((Join-Path $library 'Data\Emulators.xml'), '<LaunchBox><Emulator><ID>original-emulator</ID></Emulator></LaunchBox>')
        [System.IO.File]::WriteAllText((Join-Path $library 'Data\Platforms.xml'), '<LaunchBox><Platform><Name>Original</Name></Platform></LaunchBox>')
        return [pscustomobject]@{ Root = $library; Backups = (Join-Path $root 'Backups'); Source = (Join-Path $root 'Source') }
    }

    function New-Fix97Plan {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)][string]$NewText)
        $source = Join-Path $Fixture.Source ([System.IO.Path]::GetFileName($RelativePath))
        [System.IO.File]::WriteAllText($source, $NewText)
        return [pscustomobject]@{
            RelativePath = $RelativePath; Changed = $true; Delete = $false
            Before = (Get-TpmLaunchBoxFileState -Path (Join-Path $Fixture.Root $RelativePath))
            Document = $null; Source = $source; SourceHash = ''; AfterHash = ''; BaseChildCount = 0
        }
    }

    # ---- S4 fixture -------------------------------------------------------------------------------------------
    # Settings name in the file -> the script variable a TeknoParrot Manager window keeps it in.
    $script:Fix97Variables = [ordered]@{
        TeknoParrotRoot = 'tpRoot'; ZipSourceFolder = 'zipSource'; ZipSourceSupplementaryFolder = 'zipSourceSupplementary'
        GamesInstallFolder = 'gamesInstallFolder'; RetroBat = 'retroBat'; ReShadeSourceDll = 'rsSourceDll'
        DgVoodoo2SourceDir = 'dgSourceDir'; EggmanDatZip = 'eggmanDatZip'
        DatFilePath = 'datFilePath'; SupplementaryDatPath = 'supplementaryDatPath'; IncludeSupplementary = 'includeSupplementary'
        LaunchBoxRoot = 'lbRoot'; PostgresSuperPasswordEncrypted = 'postgresSuperPasswordEncrypted'
        CheckForUpdatesOnStartup = 'checkForUpdatesOnStartup'
    }

    function Update-Fix97Window {
        param([Parameter(Mandatory)][hashtable]$Changes)
        foreach ($key in $Changes.Keys) { Set-Variable -Name $script:Fix97Variables[$key] -Scope Script -Value $Changes[$key] }
    }

    # What start-up does: read the settings file, take its values, remember the file as the baseline.
    function Open-Fix97Window {
        $parsed = Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json
        foreach ($key in $script:Fix97Variables.Keys) {
            $property = $parsed.PSObject.Properties[$key]
            Set-Variable -Name $script:Fix97Variables[$key] -Scope Script -Value $(if ($property) { $property.Value } else { $null })
        }
        Set-TpmConfigBaseline -Path ([string]$script:configPath) -OnDisk $parsed -Document (Get-TpmConfigDocument)
    }

    function Get-Fix97WindowState {
        $values = @{}
        foreach ($key in $script:Fix97Variables.Keys) { $values[$key] = Get-Variable -Name $script:Fix97Variables[$key] -Scope Script -ValueOnly -ErrorAction SilentlyContinue }
        return @{ Values = $values; Baseline = (Get-Variable -Name TpmConfigBaseline -Scope Script -ValueOnly -ErrorAction SilentlyContinue) }
    }

    function Resume-Fix97Window {
        param([Parameter(Mandatory)]$State)
        Update-Fix97Window -Changes $State.Values
        $script:TpmConfigBaseline = $State.Baseline
    }

    function Read-Fix97Settings { return (Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json) }

    # Two windows that both opened the same settings file (zip folder, dat file, optional saved password).
    function Start-Fix97TwoWindows {
        param([string]$SavedPassword = '')
        $script:TpmConfigBaseline = $null
        $initial = @{ TeknoParrotRoot = 'C:\TP'; GamesInstallFolder = 'C:\Games'; ZipSourceFolder = 'C:\Zip0'; DatFilePath = 'C:\Dat0'; CheckForUpdatesOnStartup = $true }
        if ($SavedPassword) { $initial['PostgresSuperPasswordEncrypted'] = $SavedPassword }
        foreach ($key in $script:Fix97Variables.Keys) { Set-Variable -Name $script:Fix97Variables[$key] -Scope Script -Value $null }
        Update-Fix97Window -Changes $initial
        if (-not (Save-Config)) { throw 'The starting settings file could not be written.' }
        Open-Fix97Window
        $windowA = Get-Fix97WindowState
        Open-Fix97Window
        $windowB = Get-Fix97WindowState
        return @{ A = $windowA; B = $windowB }
    }
}

Describe 'S2: LaunchBox commit and rollback never destroy a newer save by another program' {
    BeforeEach {
        $script:Fix97Hook = $null
        $script:Fix97Seen = @{}
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Write-TpmCompactExtractionProgress {}
        # The simulated race: change a file at the point where the product has just checked it and is about to replace it.
        Mock Assert-TpmNoReparseWriteTarget {
            if ($Operation -ne 'LaunchBox commit' -or $null -eq $script:Fix97Hook) { return }
            $script:Fix97Seen[$Path] = 1 + [int]$script:Fix97Seen[$Path]
            & $script:Fix97Hook $Path $script:Fix97Seen[$Path]
        }
        Mock Backup-LaunchBoxFiles {
            $backupDir = Join-Path $BackupRoot 'saved-copy'
            foreach ($item in $Items) {
                $from = Join-Path $lbRoot $item.RelativePath
                $to = Join-Path $backupDir $item.RelativePath
                [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($to))
                if (Test-Path -LiteralPath $from) { [System.IO.File]::Copy($from, $to) }
            }
            return [pscustomobject]@{ Path = $backupDir; Verified = $true }
        }
    }

    It 'puts a newer save back when it lands between the check and the replace, and keeps a copy' {
        # Mutation: drop the put-back in Set-TpmLaunchBoxFile -> the live file keeps this run's bytes and the newer save is only in the .replaced copy.
        $dir = Join-Path $TestDrive ('f97-set-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        $target = Join-Path $dir 'Platforms.xml'; $stage = Join-Path $dir 'stage.tmp'
        [System.IO.File]::WriteAllText($target, 'SAVED-BY-LAUNCHBOX'); [System.IO.File]::WriteAllText($stage, 'MINE')
        $checkedHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes('ORIGINAL'))) -Algorithm SHA256).Hash

        $thrown = $null
        try { Set-TpmLaunchBoxFile -StagePath $stage -Path $target -Exists $true -ExpectedOriginalHash $checkedHash } catch { $thrown = $_ }

        $thrown | Should -Not -BeNullOrEmpty
        $thrown.Exception.Message | Should -BeLike '*retained at*'
        [System.IO.File]::ReadAllText($target) | Should -BeExactly 'SAVED-BY-LAUNCHBOX'
        $kept = @(Get-ChildItem -LiteralPath $dir -Filter '*.replaced')
        $kept.Count | Should -Be 1
        [System.IO.File]::ReadAllText($kept[0].FullName) | Should -BeExactly 'SAVED-BY-LAUNCHBOX'
        $thrown.Exception.Data['TpmLaunchBoxKeptCopy'] | Should -BeExactly $kept[0].FullName
        $thrown.Exception.Data['TpmLaunchBoxPutBack'] | Should -BeTrue
        @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp').Count | Should -Be 0
    }

    It 'does not call the rollback verified when a newer save lands before the forward replace' {
        # Mutation: restore the older saved copy over a file whose replaced bytes were someone else's save -> the live file ends as the old original and RollbackVerified is true.
        $fx = New-Fix97LaunchBox
        $plan = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Platforms.xml' -NewText '<LaunchBox><Platform><Name>Mine</Name></Platform></LaunchBox>'
        $target = Join-Path $fx.Root 'Data\Platforms.xml'
        $script:Fix97Foreign = '<LaunchBox><Platform><Name>Saved by LaunchBox meanwhile</Name></Platform></LaunchBox>'
        $script:Fix97Target = $target
        $script:Fix97Hook = { param($Path, $Seen) if ($Path -ieq $script:Fix97Target -and $Seen -eq 1) { [System.IO.File]::WriteAllText($Path, $script:Fix97Foreign) } }

        $r = Invoke-TpmLaunchBoxFileTransaction -lbRoot $fx.Root -Plans @($plan) -BackupRoot $fx.Backups

        $r.Outcome | Should -BeExactly 'PARTIAL'
        $r.RollbackVerified | Should -BeFalse
        [System.IO.File]::ReadAllText($target) | Should -BeExactly $script:Fix97Foreign
        @($r.ChangedByOther).Count | Should -Be 1
        $r.ChangedByOther[0].Path | Should -BeExactly 'Data\Platforms.xml'
        [System.IO.File]::ReadAllText($r.ChangedByOther[0].SavedCopy) | Should -BeExactly $script:Fix97Foreign
        $r.Summary | Should -BeLike '*changed by another program*'
        [System.IO.File]::ReadAllText((Join-Path $r.BackupPath 'Data\Platforms.xml')) | Should -BeLike '*Original*'
    }

    It 'leaves the file alone and keeps the newer bytes when they could not be put back' {
        # Mutation: let the rollback restore the older copy when the put-back failed -> the live file becomes the old original and the newer save is only in the kept copy.
        Mock Restore-TpmLaunchBoxDisplacedFile { $false }
        $fx = New-Fix97LaunchBox
        $mine = '<LaunchBox><Platform><Name>Mine</Name></Platform></LaunchBox>'
        $plan = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Platforms.xml' -NewText $mine
        $target = Join-Path $fx.Root 'Data\Platforms.xml'
        $script:Fix97Foreign = '<LaunchBox><Platform><Name>Saved by LaunchBox meanwhile</Name></Platform></LaunchBox>'
        $script:Fix97Target = $target
        $script:Fix97Hook = { param($Path, $Seen) if ($Path -ieq $script:Fix97Target -and $Seen -eq 1) { [System.IO.File]::WriteAllText($Path, $script:Fix97Foreign) } }

        $r = Invoke-TpmLaunchBoxFileTransaction -lbRoot $fx.Root -Plans @($plan) -BackupRoot $fx.Backups

        $r.RollbackVerified | Should -BeFalse
        [System.IO.File]::ReadAllText($target) | Should -BeExactly $mine
        $r.ChangedByOther[0].PutBack | Should -BeFalse
        [System.IO.File]::ReadAllText($r.ChangedByOther[0].SavedCopy) | Should -BeExactly $script:Fix97Foreign
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Platforms.xml'
    }

    It 'keeps a save made by another program during the rollback and does not call it verified' {
        # Mutation: call Set-TpmLaunchBoxFile in the rollback without -ExpectedOriginalHash -> the newer save is deleted as the replaced copy and the file ends as the old original.
        $fx = New-Fix97LaunchBox
        $emulators = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Emulators.xml' -NewText '<LaunchBox><Emulator><ID>mine</ID></Emulator></LaunchBox>'
        $platforms = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Platforms.xml' -NewText '<LaunchBox><Platform><Name>Mine</Name></Platform></LaunchBox>'
        $emulatorsPath = Join-Path $fx.Root 'Data\Emulators.xml'
        $platformsPath = Join-Path $fx.Root 'Data\Platforms.xml'
        $platformsBefore = [System.IO.File]::ReadAllText($platformsPath)
        $script:Fix97Foreign = '<LaunchBox><Emulator><ID>saved-by-launchbox-during-rollback</ID></Emulator></LaunchBox>'
        $script:Fix97Target = $emulatorsPath
        $script:Fix97Root = $fx.Root
        # First commit of Emulators.xml: spoil the staged second file so the run fails and has to roll back.
        # Second commit of Emulators.xml (the rollback): another program saves the file.
        $script:Fix97Hook = {
            param($Path, $Seen)
            if ($Path -ine $script:Fix97Target) { return }
            if ($Seen -eq 1) {
                foreach ($staged in @(Get-ChildItem -LiteralPath (Join-Path $script:Fix97Root 'Data') -Filter 'Platforms.xml.*.tmp')) { [System.IO.File]::AppendAllText($staged.FullName, ' ') }
            }
            if ($Seen -eq 2) { [System.IO.File]::WriteAllText($Path, $script:Fix97Foreign) }
        }

        $r = Invoke-TpmLaunchBoxFileTransaction -lbRoot $fx.Root -Plans @($emulators, $platforms) -BackupRoot $fx.Backups

        $r.RollbackVerified | Should -BeFalse
        [System.IO.File]::ReadAllText($emulatorsPath) | Should -BeExactly $script:Fix97Foreign
        [System.IO.File]::ReadAllText($platformsPath) | Should -BeExactly $platformsBefore
        @($r.ChangedByOther).Count | Should -Be 1
        $r.ChangedByOther[0].Path | Should -BeExactly 'Data\Emulators.xml'
        $r.ChangedByOther[0].PutBack | Should -BeTrue
        [System.IO.File]::ReadAllText($r.ChangedByOther[0].SavedCopy) | Should -BeExactly $script:Fix97Foreign
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Emulators.xml'
    }

    It 'still reports a normal failed save as verified when nobody else touched the file' {
        # Mutation: treat every rollback as changed by another program -> RollbackVerified false and an unexpected ChangedByOther entry.
        $fx = New-Fix97LaunchBox
        $emulators = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Emulators.xml' -NewText '<LaunchBox><Emulator><ID>mine</ID></Emulator></LaunchBox>'
        $platforms = New-Fix97Plan -Fixture $fx -RelativePath 'Data\Platforms.xml' -NewText '<LaunchBox><Platform><Name>Mine</Name></Platform></LaunchBox>'
        $emulatorsPath = Join-Path $fx.Root 'Data\Emulators.xml'
        $emulatorsBefore = [System.IO.File]::ReadAllText($emulatorsPath)
        $script:Fix97Target = $emulatorsPath
        $script:Fix97Root = $fx.Root
        $script:Fix97Hook = {
            param($Path, $Seen)
            if ($Path -ieq $script:Fix97Target -and $Seen -eq 1) {
                foreach ($staged in @(Get-ChildItem -LiteralPath (Join-Path $script:Fix97Root 'Data') -Filter 'Platforms.xml.*.tmp')) { [System.IO.File]::AppendAllText($staged.FullName, ' ') }
            }
        }

        $r = Invoke-TpmLaunchBoxFileTransaction -lbRoot $fx.Root -Plans @($emulators, $platforms) -BackupRoot $fx.Backups

        $r.Outcome | Should -BeExactly 'FAILED'
        $r.RollbackVerified | Should -BeTrue
        [System.IO.File]::ReadAllText($emulatorsPath) | Should -BeExactly $emulatorsBefore
        @($r.ChangedByOther).Count | Should -Be 0
    }

    It 'shows what another program changed and where the newer copy is, under Details' {
        # Mutation: leave ChangedByOther out of Get-TpmLaunchBoxDetailBlocks -> the Details view does not name the file or the kept copy.
        $result = New-TpmLaunchBoxResult PARTIAL 'LaunchBox was changed by another program while TeknoParrot Manager was saving.'
        $result.ChangedByOther += [pscustomobject]@{ Path = 'Data\Platforms.xml'; SavedCopy = 'C:\LB\Data\Platforms.xml.abc.replaced'; PutBack = $false }

        $blocks = Get-TpmLaunchBoxDetailBlocks -Result $result

        $lines = @($blocks[0].Lines)
        $lines | Should -Contain 'Changed by another program: Data\Platforms.xml'
        $lines | Should -Contain 'Newer copy kept at: C:\LB\Data\Platforms.xml.abc.replaced'
        @($lines | Where-Object { $_ -like 'The newer version could not be put back*' }).Count | Should -Be 1
    }
}

Describe 'S4: a stale settings save does not revert another window' {
    BeforeEach {
        $script:Fix97Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:Fix97Log.Add([string]$msg) }
        $script:configPath = Join-Path $TestDrive ('f97-cfg-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:unattendedModeSaved = $null
        $script:TpmConfigRestoreRestartRequired = $false
    }

    It 'keeps the other window''s path and saved password when this window saves something unrelated' {
        # Mutation: write this window's whole document without comparing it to the file -> ZipSourceFolder and the saved password revert.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-A'; PostgresSuperPasswordEncrypted = 'ENC-A' }
        Save-Config | Should -BeTrue
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ RetroBat = $true }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.ZipSourceFolder | Should -BeExactly 'C:\Zip-A'
        $saved.PostgresSuperPasswordEncrypted | Should -BeExactly 'ENC-A'
        $saved.RetroBat | Should -BeTrue
        $saved.DatFilePath | Should -BeExactly 'C:\Dat0'
        @($script:Fix97Log | Where-Object { $_ -like '*another TeknoParrot Manager window*' }).Count | Should -Be 1
    }

    It 'never drops a saved PostgreSQL password the other window saved after this window loaded' {
        # Mutation: fall back to this window's empty credential for keys it did not change -> the file loses PostgresSuperPasswordEncrypted.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ PostgresSuperPasswordEncrypted = 'ENC-CHILD' }
        Save-Config | Should -BeTrue
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ DatFilePath = 'C:\Dat-B' }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.PostgresSuperPasswordEncrypted | Should -BeExactly 'ENC-CHILD'
        $saved.DatFilePath | Should -BeExactly 'C:\Dat-B'
    }

    It 'never replaces a saved PostgreSQL password in the file with an empty one' {
        # Mutation: remove the empty-credential guard in Merge-TpmConfigFileChanges -> the file ends with a null PostgresSuperPasswordEncrypted.
        $windows = Start-Fix97TwoWindows -SavedPassword 'ENC-OLD'
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ PostgresSuperPasswordEncrypted = 'ENC-NEW' }
        Save-Config | Should -BeTrue
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ PostgresSuperPasswordEncrypted = $null }

        Save-Config | Should -BeTrue

        (Read-Fix97Settings).PostgresSuperPasswordEncrypted | Should -BeExactly 'ENC-NEW'
    }

    It 'keeps this window''s own change when both windows changed the same setting, and still keeps the other changes' {
        # Mutation: take the file's value even for a setting this window changed -> ZipSourceFolder shows the other window's value.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-A'; DatFilePath = 'C:\Dat-A' }
        Save-Config | Should -BeTrue
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-B' }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.ZipSourceFolder | Should -BeExactly 'C:\Zip-B'
        $saved.DatFilePath | Should -BeExactly 'C:\Dat-A'
    }

    It 'saves this window''s changes as before when the file is still the one it read' {
        # Mutation: always prefer the file's values -> the change this window just made is lost.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-New' }

        Save-Config | Should -BeTrue
        Update-Fix97Window -Changes @{ DatFilePath = 'C:\Dat-New' }
        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.ZipSourceFolder | Should -BeExactly 'C:\Zip-New'
        $saved.DatFilePath | Should -BeExactly 'C:\Dat-New'
        @($script:Fix97Log | Where-Object { $_ -like '*another TeknoParrot Manager window*' }).Count | Should -Be 0
    }

    It 'keeps a setting that only the other window wrote, such as the unattended selector' {
        # Mutation: carry the other window's key only on the first save -> UnattendedMode is dropped by this window's second save.
        $windows = Start-Fix97TwoWindows
        $edited = Read-Fix97Settings
        $edited | Add-Member -NotePropertyName UnattendedMode -NotePropertyValue 'HealthCheck'
        [System.IO.File]::WriteAllText($script:configPath, ($edited | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ RetroBat = $true }

        Save-Config | Should -BeTrue
        Update-Fix97Window -Changes @{ DatFilePath = 'C:\Dat-B2' }
        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.UnattendedMode | Should -BeExactly 'HealthCheck'
        $saved.RetroBat | Should -BeTrue
        $saved.DatFilePath | Should -BeExactly 'C:\Dat-B2'
    }

    It 'does not write the old LaunchBox platform settings back when it saves a settings file that still has them' {
        # Mutation: put LaunchBoxPlatformMode back into Get-TpmConfigDocument -> the file still holds the old key after this save.
        $windows = Start-Fix97TwoWindows
        $old = Read-Fix97Settings
        $old | Add-Member -NotePropertyName LaunchBoxPlatformMode -NotePropertyValue 'Both'
        $old | Add-Member -NotePropertyName LaunchBoxCustomPlatformName -NotePropertyValue 'My Games'
        $old | Add-Member -NotePropertyName LaunchBoxEmulatorId -NotePropertyValue 'old-emulator-id'
        [System.IO.File]::WriteAllText($script:configPath, ($old | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
        Open-Fix97Window
        Update-Fix97Window -Changes @{ RetroBat = $true }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.PSObject.Properties.Name | Should -Not -Contain 'LaunchBoxPlatformMode'
        $saved.PSObject.Properties.Name | Should -Not -Contain 'LaunchBoxCustomPlatformName'
        $saved.PSObject.Properties.Name | Should -Not -Contain 'LaunchBoxEmulatorId'
        $saved.RetroBat | Should -BeTrue
        $saved.DatFilePath | Should -BeExactly 'C:\Dat0'
    }

    It 'keeps the other window''s password and path through two successive saves of this window' {
        # Mutation: build the document from this window's older memory once the file matches the last baseline -> the second save writes the old password and path back.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-A'; PostgresSuperPasswordEncrypted = 'ENC-A' }
        Save-Config | Should -BeTrue
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ RetroBat = $true }
        Save-Config | Should -BeTrue
        Update-Fix97Window -Changes @{ DatFilePath = 'C:\Dat-B2' }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.PostgresSuperPasswordEncrypted | Should -BeExactly 'ENC-A'
        $saved.ZipSourceFolder | Should -BeExactly 'C:\Zip-A'
        $saved.RetroBat | Should -BeTrue
        $saved.DatFilePath | Should -BeExactly 'C:\Dat-B2'
    }

    It 'merges a save that another window makes between the read and the replace instead of overwriting it' {
        # Mutation: replace without keeping and checking the removed bytes -> the other window's ZipSourceFolder is silently destroyed.
        # Mutation: keep the displaced copies after a successful merge (skip the Remove-Item in Publish-TpmConfigDocument) -> '<settings>.<guid>.replaced' files stay beside the settings and the leftover list is not empty.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ RetroBat = $true }
        $script:Fix97RealReplace = ${function:Invoke-TpmAtomicFileReplace}
        $script:Fix97Replaces = 0
        Mock Invoke-TpmAtomicFileReplace {
            $script:Fix97Replaces++
            if ($script:Fix97Replaces -eq 1) {
                $other = Read-Fix97Settings
                $other.ZipSourceFolder = 'C:\Zip-Race'
                [System.IO.File]::WriteAllText($script:configPath, ($other | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
            }
            & $script:Fix97RealReplace -Source $Source -Destination $Destination -Backup $Backup
        }

        Save-Config | Should -BeTrue

        $saved = Read-Fix97Settings
        $saved.ZipSourceFolder | Should -BeExactly 'C:\Zip-Race'
        $saved.RetroBat | Should -BeTrue
        $script:Fix97Replaces | Should -Be 2
        # Not -Filter '<name>.*': on Windows that pattern also matches '<name>' itself, so it always counted the settings file.
        $settingsName = Split-Path -Leaf $script:configPath
        $leftovers = @(Get-ChildItem -LiteralPath $TestDrive -File | Where-Object { $_.Name.StartsWith($settingsName + '.', [System.StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $_.Name })
        ($leftovers -join ', ') | Should -BeExactly ''
    }

    It 'reports a failed save and keeps every other-window copy when the file keeps changing' {
        # Mutation: retry forever or drop the removed bytes after the last try -> the newest other-window save is lost or the save never ends.
        $windows = Start-Fix97TwoWindows
        Resume-Fix97Window $windows.B
        Update-Fix97Window -Changes @{ RetroBat = $true }
        $script:Fix97RealReplace = ${function:Invoke-TpmAtomicFileReplace}
        $script:Fix97Replaces = 0
        Mock Invoke-TpmAtomicFileReplace {
            $script:Fix97Replaces++
            $other = Read-Fix97Settings
            $other.ZipSourceFolder = 'C:\Zip-Race-' + $script:Fix97Replaces
            [System.IO.File]::WriteAllText($script:configPath, ($other | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
            & $script:Fix97RealReplace -Source $Source -Destination $Destination -Backup $Backup
        }

        Save-Config | Should -BeFalse

        $script:Fix97Replaces | Should -Be 3
        $kept = @(Get-ChildItem -LiteralPath $TestDrive -Filter ((Split-Path -Leaf $script:configPath) + '.*.replaced'))
        $kept.Count | Should -Be 3
        (@($kept | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join '|') | Should -BeLike '*C:\\Zip-Race-3*'
    }

    It 'does not replace a settings file that exists but cannot be read, and tells the player what to do' {
        # Mutation: publish over an unreadable settings file -> the player's hand-edited paths and saved password are replaced by this window's memory.
        $windows = Start-Fix97TwoWindows
        $bad = '{ this is not json'
        [System.IO.File]::WriteAllText($script:configPath, $bad)
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-A' }
        $script:TpmConfigUnreadableShown = $false
        $script:Fix97Shown = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:Fix97Shown.Add([string]$Object) }

        Save-Config | Should -BeFalse

        [System.IO.File]::ReadAllText($script:configPath) | Should -BeExactly $bad
        @(Get-ChildItem -LiteralPath $TestDrive -Filter ((Split-Path -Leaf $script:configPath) + '.*') | Where-Object { $_.Name -cne (Split-Path -Leaf $script:configPath) }).Count | Should -Be 0
        ($script:Fix97Shown -join ' ') | Should -BeLike '*left as it is*Next step*'
    }

    It 'does not save stale settings after a config restore' {
        # Mutation: remove the restart latch check in Save-Config -> the stale window overwrites the restored file.
        $windows = Start-Fix97TwoWindows
        $before = [System.IO.File]::ReadAllText($script:configPath)
        Resume-Fix97Window $windows.A
        Update-Fix97Window -Changes @{ ZipSourceFolder = 'C:\Zip-Stale' }
        $script:TpmConfigRestoreRestartRequired = $true

        Save-Config | Should -BeFalse

        [System.IO.File]::ReadAllText($script:configPath) | Should -BeExactly $before
    }
}
