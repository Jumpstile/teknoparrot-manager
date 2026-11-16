#Requires -Module Pester

# Issue 368: a registered game whose program sits in a subfolder (Game\bin\game.exe), with no stored local
# path and no folder-map entry, must never be extracted into a doubled Game\bin\bin folder. Isolated fake
# ZIPs and folders under $TestDrive only; run on the test PC by the coordinator.
BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX402 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix402-autosync-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    # Exactly one TpmProgress per session: an earlier test file can leave its own copy (from a removed $TestDrive)
    # loaded, so the first real extraction here would start from that foreign module state.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix402-autosync.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # Root\Games is the install folder (as configured), Root\Zips the source,
    # Root\State the owned State folder that enables the registration ledger.
    function New-Fix402Fixture {
        $root = Join-Path $TestDrive ('f402-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips')
            Profiles = (Join-Path $root 'UserProfiles'); State = (Join-Path $root 'State')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
            Ledger = (Join-Path $root 'State\TPM-RegistrationLedger.json'); Backups = (Join-Path $root 'Backups')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Zips, $fx.Profiles, $fx.State -Force | Out-Null
        New-Item -ItemType Directory -Path $fx.Backups -Force | Out-Null
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State; Backups = $fx.Backups }
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = $null
        $script:TpmRegistrationLedgerStopLatch = $null
        return $fx
    }

    function New-Fix402Zip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
                    try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }

    function Invoke-Fix402AutoSync {
        param($Fixture, [bool]$DryRun = $false, [bool]$RetroBat = $false, [hashtable]$DatIndex = @{})
        return (Invoke-AutoSync -zipSource $Fixture.Zips -installFolder $Fixture.Games -syncStatePath $Fixture.SyncState `
            -DryRun $DryRun -retroBat $RetroBat -datIndex $DatIndex -userProfilesDir $Fixture.Profiles)
    }

    function Get-Fix402TreeDigest {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length)
            if ($_.PSIsContainer) { $relative + '|dir' } else { $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n")
    }

    function Get-Fix402Residue {
        param($Fixture)
        return @(Get-ChildItem -LiteralPath $Fixture.Root -Force -Filter '.tpm-autosync-*') +
            @(Get-ChildItem -LiteralPath $Fixture.Games -Force -Filter '*.extracting')
    }

    function Get-Fix402LedgerUnit {
        param($Fixture, [string]$SourceName)
        $read = Read-TpmRegistrationLedger -Path $Fixture.Ledger
        if ($read.Status -ne 'Ok') { throw ('Ledger was {0}' -f $read.Status) }
        $units = @(@($read.Document.Operations)[-1].Units)
        return @($units | Where-Object { [string]$_.Folder -eq $SourceName })[0]
    }

    # Result detail for -Because: shows which refusal or transaction failure produced an unexpected count or
    # outcome. Never throws, so a missing property cannot hide the real result.
    function Get-Fix402Diagnostic {
        param($Result)
        try {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($name in @('Synced', 'Failed', 'UnsafePathSkipped', 'Skipped', 'UpToDate', 'WouldSync', 'EvidenceRefused', 'EvidenceMessage', 'EvidenceStopped')) {
                if ($Result -is [System.Collections.IDictionary] -and $Result.Contains($name)) { [void]$parts.Add(('{0}={1}' -f $name, $Result[$name])) }
            }
            foreach ($tx in @($Result.TransactionResults)) {
                if ($null -eq $tx) { continue }
                $technical = Get-TpmTransactionField -Object $tx -Name 'TechnicalDetails'
                $cleanup = Get-TpmTransactionField -Object $tx -Name 'Cleanup'
                [void]$parts.Add(('tx: Outcome={0} Reason={1} Stage={2} Error={3} Errors={4} Residue={5}' -f
                    (Get-TpmTransactionField -Object $tx -Name 'Outcome'),
                    (Get-TpmTransactionField -Object $tx -Name 'ReasonCode'),
                    (Get-TpmTransactionField -Object $technical -Name 'Stage'),
                    (Get-TpmTransactionField -Object $technical -Name 'Error'),
                    (@(Get-TpmTransactionField -Object $tx -Name 'Errors' -Default @()) -join ' | '),
                    (@(Get-TpmTransactionField -Object $cleanup -Name 'ResiduePaths' -Default @()) -join ';')))
            }
            return ($parts -join '; ')
        } catch { return ('diagnostic unavailable: ' + $_.Exception.Message) }
    }
    # A renamed, registered game: Games\Renamed Papa\bin\game.exe is the registered program. The ZIP name does not
    # match the folder name, there is no sync state (no stored LocalPath) and no folder map.
    function New-Fix402NestedGame {
        param($Fixture, [string]$ZipName, [System.Collections.IDictionary]$ZipEntries)
        New-Fix402Zip -Path (Join-Path $Fixture.Zips ($ZipName + '.zip')) -Entries $ZipEntries
        $root = Join-Path $Fixture.Games 'Renamed Papa'
        $exe = Join-Path $root 'bin\game.exe'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $exe))
        [IO.File]::WriteAllText($exe, 'old exe')
        [IO.File]::WriteAllText((Join-Path $root 'bin\save.dat'), 'my-save')
        $dat = @{ (Get-NormalizedGameKey $ZipName) = [pscustomobject]@{ ProfileCode = 'PAPA'; OriginalName = $ZipName; Executable = 'game.exe' } }
        [IO.File]::WriteAllText((Join-Path $Fixture.Profiles 'PAPA.xml'), ('<GameProfile><GamePath>' + $exe + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{ Root = $root; Exe = $exe; Dat = $dat }
    }

}

AfterAll {
    $script:TpmOwnedLayout = $null
    $script:TpmRegistrationLedger = $null
    $script:TpmRegistrationLedgerStopLatch = $null
    # The progress module was imported from this file's $TestDrive; do not leave it loaded for the next file.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'Issue 368 AutoSync root for a registered game whose program is in a subfolder' {
    AfterEach {
        $script:TpmOwnedLayout = $null
        $script:TpmRegistrationLedger = $null
    }

    It 'never creates bin\bin when the archive has the same nested layout; extracts into the proven root' {
        # Mutation: make AutoSync extract into the program's parent (Game\bin) -> Game\bin\bin\game.exe appears.
        $fx = New-Fix402Fixture
        $g = New-Fix402NestedGame -Fixture $fx -ZipName 'Papa Game (1.0)[TP]' -ZipEntries ([ordered]@{ 'bin/game.exe' = 'new exe'; 'bin/data.bin' = 'new data' })

        $result = Invoke-Fix402AutoSync -Fixture $fx -DatIndex $g.Dat

        # (1) no doubled folder anywhere under the install folder
        @(Get-ChildItem -LiteralPath $fx.Games -Recurse -Force -Filter 'game.exe' | Where-Object { $_.FullName -match '[\\/]bin[\\/]bin[\\/]' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $g.Root 'bin\bin') | Should -BeFalse
        # (2) correct extraction into the proven root: the registered program is the updated file
        $result.Synced | Should -Be 1 -Because (Get-Fix402Diagnostic $result)
        [IO.File]::ReadAllText($g.Exe) | Should -BeExactly 'new exe'
        [IO.File]::ReadAllText((Join-Path $g.Root 'bin\data.bin')) | Should -BeExactly 'new data'
    }

    It 'refuses safely and leaves every original byte alone when the archive does not prove the root' {
        # Mutation: remove the registered-executable binding in Invoke-TpmAutoSyncDirectoryTransaction -> the
        # ZIP is extracted anyway and the game folder changes or a doubled folder appears.
        $fx = New-Fix402Fixture
        $g = New-Fix402NestedGame -Fixture $fx -ZipName 'Quebec Game (1.0)[TP]' -ZipEntries ([ordered]@{ 'game.exe' = 'new exe'; 'data/level.bin' = 'new level' })
        $before = Get-Fix402TreeDigest $g.Root

        $result = Invoke-Fix402AutoSync -Fixture $fx -DatIndex $g.Dat

        $result.Synced | Should -Be 0 -Because (Get-Fix402Diagnostic $result)
        Test-Path -LiteralPath (Join-Path $g.Root 'bin\bin') | Should -BeFalse
        Get-Fix402TreeDigest $g.Root | Should -Be $before
        [IO.File]::ReadAllText($g.Exe) | Should -BeExactly 'old exe'
        foreach ($tx in @($result.TransactionResults)) { [string]$tx.ReasonCode | Should -Be 'AMBIGUOUS_EXTRACTION_ROOT' }
        @(Get-Fix402Residue $fx).Count | Should -Be 0
    }

    It 'copies the saves and changed settings of the old folder to Backups before replacing it' {
        # Mutation: skip the copy to Backups\AutoSyncReplaced -> the old save and old settings are gone after the run.
        $fx = New-Fix402Fixture
        $name = 'Romeo Game (1.0)[TP]'
        $g = New-Fix402NestedGame -Fixture $fx -ZipName $name -ZipEntries ([ordered]@{ 'bin/game.exe' = 'new exe'; 'bin/data.bin' = 'new data' })

        $result = Invoke-Fix402AutoSync -Fixture $fx -DatIndex $g.Dat

        $result.Synced | Should -Be 1 -Because (Get-Fix402Diagnostic $result)
        $saved = [string]@($result.TransactionResults)[0].TechnicalDetails.ExtraFilesSavedTo
        $saved | Should -Not -BeNullOrEmpty
        $saved.StartsWith(((Join-Path $fx.Backups 'AutoSyncReplaced') + '\' + $name + '_'), [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $saved 'bin\save.dat')) | Should -BeExactly 'my-save'
        [IO.File]::ReadAllText((Join-Path $saved 'bin\game.exe')) | Should -BeExactly 'old exe'
        [IO.File]::ReadAllText($g.Exe) | Should -BeExactly 'new exe'
    }

    It 'refuses to replace the old folder and keeps it unchanged when there is no Backups folder to keep the saves in' {
        # Mutation: continue when TpmOwnedLayout is missing -> the old folder and the player's save are deleted silently.
        $fx = New-Fix402Fixture
        $g = New-Fix402NestedGame -Fixture $fx -ZipName 'Sierra Game (1.0)[TP]' -ZipEntries ([ordered]@{ 'bin/game.exe' = 'new exe'; 'bin/data.bin' = 'new data' })
        $script:TpmOwnedLayout = $null
        $before = Get-Fix402TreeDigest $g.Root

        $result = Invoke-Fix402AutoSync -Fixture $fx -DatIndex $g.Dat

        $result.Synced | Should -Be 0 -Because (Get-Fix402Diagnostic $result)
        $result.Failed | Should -Be 1
        Get-Fix402TreeDigest $g.Root | Should -Be $before
        [IO.File]::ReadAllText((Join-Path $g.Root 'bin\save.dat')) | Should -BeExactly 'my-save'
        Test-Path -LiteralPath (Join-Path $g.Root 'bin\data.bin') | Should -BeFalse
    }
}

Describe 'First-run TeknoParrot folder question' {
    BeforeEach {
        $script:rootAnswers = [System.Collections.Generic.Queue[string]]::new()
        Mock Read-PathWithBrowse { $script:rootAnswers.Dequeue() }
        Mock Exit-TpmProcess { }
    }

    It 'asks again after a closed window, a missing folder and a folder without TeknoParrotUi.exe, then returns the good folder' {
        # Mutation: take the first answer unchecked (the old single call) -> returns '' after one ask, or exits.
        $noExe = Join-Path $TestDrive 'ask-noexe'
        $good = Join-Path $TestDrive 'ask-good'
        New-Item -ItemType Directory -Path $noExe, $good -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $good 'TeknoParrotUi.exe'), [byte[]]@())
        foreach ($a in @('', (Join-Path $TestDrive 'ask-missing'), $noExe, $good)) { $script:rootAnswers.Enqueue($a) }

        $result = Read-TpmTeknoParrotRoot

        $result | Should -Be $good
        Should -Invoke Read-PathWithBrowse -Times 4 -Exactly -Scope It
        Should -Invoke Exit-TpmProcess -Times 0 -Exactly -Scope It
    }

    It 'quits on purpose with Q after an empty answer and creates nothing on disk' {
        # Mutation: treat Q as a path (asks again forever) or never call the exit -> the quit request is not seen.
        $work = Join-Path $TestDrive 'ask-quit'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $before = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force).Count
        foreach ($a in @('', 'Q')) { $script:rootAnswers.Enqueue($a) }

        $result = Read-TpmTeknoParrotRoot

        $result | Should -BeNullOrEmpty
        Should -Invoke Read-PathWithBrowse -Times 2 -Exactly -Scope It
        Should -Invoke Exit-TpmProcess -Times 1 -Exactly -Scope It -ParameterFilter { $Code -eq 0 }
        @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force).Count | Should -Be $before
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should -Be 0
    }
}
