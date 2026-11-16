#Requires -Module Pester

# FIX16A state and flow regressions. The production script is parsed and only
# the functions under test (plus their real safety/transaction helpers) are
# dot-sourced. Network, process, ledger and discovery dependencies are stubs.
# Fixes that live only in top-level script code are checked with narrowly
# scoped AST queries; those tests are labeled "(structural)".
BeforeAll {
    $script:fix16RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:fix16SourcePath = Join-Path $script:fix16RepoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:fix16Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:fix16SourcePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $script:fix16SourceText = [System.IO.File]::ReadAllText($script:fix16SourcePath)

    $wanted = @(
        'Test-TpmAutoSyncStateFile', 'Save-TpmInvalidAutoSyncStateCopy', 'Invoke-AutoSync', 'Write-TpmSkippedArchiveNotice',
        'Test-TpmNoReparsePath', 'Assert-TpmNoReparseWriteTarget', 'Test-PathInside',
        'Get-TpmTransactionOutcomeNames', 'Get-TpmTransactionProductStateNames', 'Get-TpmTransactionField',
        'Get-TpmTransactionItemKey', 'Get-TpmTransactionItemKeys', 'Test-TpmTransactionUserSafeSummary',
        'Assert-TpmTransactionItemSets', 'Assert-TpmTransactionResult', 'New-TpmTransactionResult',
        'New-TpmProfileTransactionResult', 'Get-TpmUserProfilesBackupManifest', 'New-TpmVerifiedUserProfilesBackup',
        'Get-TpmUserProfilesBackupMarkerName', 'Get-TpmUserProfilesBackupStagingPrefix', 'Get-TpmUserProfilesBackupStagingPath',
        'Get-TpmUserProfilesBackupInventoryKeys', 'Get-TpmUserProfilesBackupInventory', 'Complete-TpmUserProfilesBackupFolder', 'Move-TpmDirectoryWithRetry',
        'Test-TpmRegistrationLedgerStopped', 'ConvertTo-TpmRegistrationResult', 'Confirm-TpmRegistrationSafetyBackup',
        'Get-TpmRegistrationBackupEvidence', 'Backfill-SecondaryExecutablePath', 'Set-SecondaryExecutablePath',
        'Test-TpmGameMutationPath', 'Add-TpmUnavailableDriveGame',
        'Read-Xml', 'Save-XmlMaybe', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure',
        'Register-Games', 'Get-TeknoParrotProfileSet', 'Get-TpmDirectoryEntriesWithDiscoveryProgress',
        'Get-TpmOwnedLayout', 'Get-TpmOwnedConfigPathForRoot', 'Find-TpmSavedConfigPath', 'Get-TpmDetectedRootList', 'Write-TpmConfigLocator',
        'Invoke-TpmAtomicFileReplace', 'Write-TpmAtomicTextFile', 'Get-TpmConfigLocatorPath', 'Backup-LaunchBoxFiles', 'Get-TpmLaunchBoxPath',
        'Get-TpmLaunchBoxFileState', 'Assert-TpmLaunchBoxState',
        'Resolve-TpmStartupConfigPath', 'Get-PostgresRecoveryResumeConfigPath', 'New-TpmStartupRow', 'Show-TpmStartupSummary',
        'Write-TpmText', 'Get-TpmResetRestoreLineWidth'
    )
    $functions = @(
        $script:fix16Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | Where-Object { $wanted -contains $_.Name }
    )
    foreach ($name in $wanted) {
        $found = @($functions | Where-Object { $_.Name -eq $name }).Count
        if ($found -ne 1) { throw "Expected exactly one definition of $name; found $found." }
    }

    $functionPath = Join-Path $TestDrive ('f16sf-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    # Exact initial script-scope values production assigns before use.
    $script:TpmRegistrationLedger = $null
    $script:TpmRegistrationLedgerStopLatch = $null
    $script:TpmProfileSetSource = $null
    $script:ScriptVersion = 'fix16a-test'

    $script:fix16Progress = New-Object System.Collections.Generic.List[object]
    $script:fix16Log = New-Object System.Collections.Generic.List[string]

    # Inert dependencies (not under test). Network/process/ledger stubs throw
    # or return neutral values unless a test mocks them.
    function Write-Log {
        param([string]$Message, [Parameter(ValueFromRemainingArguments = $true)]$Rest)
        [void]$script:fix16Log.Add([string]$Message)
    }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase = 'Extracting', [string]$Label, [long]$Current, [long]$Total, [datetime]$StartedAt = (Get-Date), [int]$Width = 0, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed, [string]$Unit = 'Items')
        [void]$script:fix16Progress.Add([pscustomobject]@{ Phase = $Phase; Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome })
    }
    function Get-TpmTopLevelZipSourceFiles {
        param([Parameter(Mandatory)][string]$ZipSource, [Parameter(Mandatory)][string]$ProgressLabel, [switch]$ExcludeCollectionArchives, [switch]$SortByBaseName)
        throw 'Get-TpmTopLevelZipSourceFiles must be mocked by the test.'
    }
    function Get-TpmImmediateZipSubdirectorySummary {
        param([Parameter(Mandatory)][string]$ZipSource)
        return @()
    }
    function Test-TpmRegistrationLedgerReady {
        param([bool]$AdoptActive = $false, [string]$Path = '', [int]$MaximumBytes = 1048576)
        throw 'Test-TpmRegistrationLedgerReady must be mocked by the test.'
    }
    function Close-TpmRegistrationLedgerOperations {
        param([AllowNull()][object]$Legacy = $null, [AllowNull()][object]$Result = $null, [string]$Reason = 'REGISTRATION_NOT_ATTEMPTED', [string]$InstallBase = '')
        throw 'Close-TpmRegistrationLedgerOperations must be mocked by the test.'
    }
    # No ledger is active in these tests: Backfill-SecondaryExecutablePath records nothing.
    function Start-TpmRegistrationMapping {
        param([string]$Folder, [string]$Code, [string]$Match, [string]$IntendedPath, [string]$TemplatePath, [bool]$DryRun = $false)
        return $null
    }
    function Complete-TpmRegistrationMapping {
        param([AllowNull()][AllowEmptyString()][string]$MappingId, [string]$Outcome, [bool]$WriteAttempted = $false, [string]$Reason = '')
    }
    function Register-GamesLegacy {
        param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex,
              [string]$gameProfilesDir = '', [hashtable]$datIndex = $null,
              [System.Collections.Generic.HashSet[string]]$profileSet = $null,
              [bool]$DryRun = $false,
              [string]$tpRootDir = '', [hashtable]$subFolderMap = $null,
              [string[]]$GameFolders = $null, [hashtable]$BackupState = $null)
        throw 'Register-GamesLegacy must be mocked by the test.'
    }
    function Set-TpmLedgerField {
        param($Object, [string]$Name, $Value)
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    function Assert-TpmRegisteredGamePath {
        param([string]$ProfilePath, [string]$ExpectedGamePath, [string]$ExpectedSecondaryPath = '', [object]$RegistrationState = $null)
    }
    function Save-Xml {
        param([System.Xml.XmlDocument]$doc, [string]$path)
        throw 'Save-Xml must not run in these tests; Save-XmlMaybe is mocked.'
    }
    function Invoke-TpmWebRequestSilently {
        param([Parameter(Mandatory)][string]$Uri, [switch]$UseBasicParsing, [int]$TimeoutSec = 0, [hashtable]$Headers = $null, [string]$OutFile = '', [System.Management.Automation.ActionPreference]$RequestErrorAction = 'Stop')
        throw 'Network access is disabled in these tests.'
    }
    function Get-TpmHttpStatusCodeFromError {
        param($ErrorRecord)
        return $null
    }
    function Find-TeknoParrotRoot {
        return @()
    }
    function Test-LaunchBoxRunning {
        return $false
    }
    function Get-TpmLaunchBoxBackupRoot {
        param([string]$BackupRoot, [string]$LaunchBoxRoot)
        return $BackupRoot
    }
    function Get-PostgresRecoveryStateDirectory {
        throw 'Get-PostgresRecoveryStateDirectory must be mocked by the test.'
    }
    function Unprotect-PostgresRecoveryEnvelope {
        param([Parameter(Mandatory)][string]$ProtectedText)
        throw 'Unprotect-PostgresRecoveryEnvelope must be mocked by the test.'
    }
    function Read-TpmYesNo {
        param([Parameter(Mandatory)][string]$Prompt, [string]$Default = '', [object]$WorkflowContext = $null, [scriptblock]$DetailsAction = $null)
        throw 'Read-TpmYesNo must be mocked by the test.'
    }

    # Short, unique fixture folders under $TestDrive.
    function New-Fix16Dir {
        param([Parameter(Mandatory)][string]$Prefix)
        $path = Join-Path $TestDrive ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($path)
        return $path
    }
    function Get-Fix16FileSnapshot {
        param([Parameter(Mandatory)][string]$Path)
        $item = Get-Item -LiteralPath $Path -Force
        return ('{0}|{1}|{2}' -f (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash, $item.Length, $item.LastWriteTimeUtc.Ticks)
    }
    function New-Fix16UserProfiles {
        param([Parameter(Mandatory)][string]$Root)
        $up = Join-Path $Root 'UP'
        [void][System.IO.Directory]::CreateDirectory($up)
        [System.IO.File]::WriteAllText((Join-Path $up 'GameA.xml'), '<GameProfile><GamePath>C:\G\a.exe</GamePath></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $up 'GameB.xml'), '<GameProfile><GamePath>C:\G\b.exe</GamePath></GameProfile>')
        return $up
    }
    # Shape of a failed New-TpmVerifiedUserProfilesBackup result (its folder
    # was cleaned up, so Path does not exist).
    function New-Fix16UnverifiedBackup {
        param([string]$UserProfilesDir)
        return [pscustomobject]@{
            Required = $true; Attempted = $true; Created = $false; Succeeded = $false; Verified = $false
            Path = (Join-Path $UserProfilesDir 'FullBackup\failed'); Manifest = @()
            FailureStage = 'BackupCreationOrCopy'; Reason = 'fixture backup failure'; ResiduePaths = @()
        }
    }
    function New-Fix16Legacy {
        param([string[]]$Already = @(), [object[]]$Failures = @())
        $alreadyList = New-Object System.Collections.ArrayList
        foreach ($code in $Already) { [void]$alreadyList.Add($code) }
        $failureList = New-Object System.Collections.ArrayList
        foreach ($failure in $Failures) { [void]$failureList.Add($failure) }
        return [pscustomobject]@{
            Registered = (New-Object System.Collections.ArrayList)
            Already = $alreadyList
            Ambiguous = @()
            Unmatched = @()
            MutationRecords = [pscustomobject]@{ Changed = (New-Object System.Collections.ArrayList); Failures = $failureList }
            Decisions = (New-Object System.Collections.ArrayList)
        }
    }

    # AST helpers for the structural checks.
    function Test-Fix16InsideFunction {
        param([Parameter(Mandatory)]$Node)
        $parent = $Node.Parent
        while ($null -ne $parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $true }
            $parent = $parent.Parent
        }
        return $false
    }
    function Test-Fix16Within {
        param([Parameter(Mandatory)]$Node, [Parameter(Mandatory)]$Container)
        $cursor = $Node
        while ($null -ne $cursor) {
            if ([object]::ReferenceEquals($cursor, $Container)) { return $true }
            $cursor = $cursor.Parent
        }
        return $false
    }
    function Get-Fix16Nodes {
        param([Parameter(Mandatory)]$Root, [Parameter(Mandatory)][type]$Type)
        $predicate = { param($node) $node -is $Type }.GetNewClosure()
        return @($Root.FindAll($predicate, $true))
    }
    # Top-level script code only: searches the root statements that are not
    # function definitions, and drops anything nested in a function.
    $script:fix16TopLevelStatements = @($script:fix16Ast.EndBlock.Statements | Where-Object {
        $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst]
    })
    function Get-Fix16TopLevelNodes {
        param([Parameter(Mandatory)][type]$Type)
        $nodes = New-Object System.Collections.Generic.List[object]
        foreach ($statement in $script:fix16TopLevelStatements) {
            foreach ($node in @(Get-Fix16Nodes -Root $statement -Type $Type)) {
                if (-not (Test-Fix16InsideFunction -Node $node)) { [void]$nodes.Add($node) }
            }
        }
        return @($nodes.ToArray())
    }
    function New-Fix16ManagedConfig {
        param([Parameter(Mandatory)][string]$TeknoParrotRoot)
        $state = Join-Path $TeknoParrotRoot 'TeknoParrotManager\State'
        [void][System.IO.Directory]::CreateDirectory($state)
        $config = Join-Path $state 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($config, '{"tpRoot":"x"}')
        return $config
    }
    function Set-Fix16Locator {
        param([Parameter(Mandatory)][string]$TeknoParrotRoot)
        [System.IO.File]::WriteAllText($script:f16Locator, ([pscustomobject]@{ Schema = 1; TeknoParrotRoot = $TeknoParrotRoot } | ConvertTo-Json))
    }
    function Get-Fix16Commands {
        param([Parameter(Mandatory)]$Root, [Parameter(Mandatory)][string]$Name)
        return @(Get-Fix16Nodes -Root $Root -Type ([System.Management.Automation.Language.CommandAst]) |
            Where-Object { $_.GetCommandName() -eq $Name })
    }
    function Get-Fix16ParameterArgumentText {
        param([Parameter(Mandatory)]$Command, [Parameter(Mandatory)][string]$Name)
        $elements = @($Command.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -ieq $Name) {
                if ($null -ne $element.Argument) { return $element.Argument.Extent.Text }
                if ($i + 1 -lt $elements.Count) { return $elements[$i + 1].Extent.Text }
                return ''
            }
        }
        return $null
    }
    function Test-Fix16HasParameter {
        param([Parameter(Mandatory)]$Command, [Parameter(Mandatory)][string]$Name)
        return (@($Command.CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ieq $Name
        }).Count -gt 0)
    }
    function Get-Fix16AndOperandTexts {
        param([Parameter(Mandatory)]$Expression)
        if ($Expression -is [System.Management.Automation.Language.PipelineAst] -and
            @($Expression.PipelineElements).Count -eq 1 -and
            $Expression.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return @(Get-Fix16AndOperandTexts -Expression $Expression.PipelineElements[0].Expression)
        }
        if ($Expression -is [System.Management.Automation.Language.BinaryExpressionAst] -and
            $Expression.Operator -eq [System.Management.Automation.Language.TokenKind]::And) {
            return @(@(Get-Fix16AndOperandTexts -Expression $Expression.Left) + @(Get-Fix16AndOperandTexts -Expression $Expression.Right))
        }
        return @($Expression.Extent.Text)
    }
    function Get-Fix16StringValues {
        param([Parameter(Mandatory)]$Root)
        return @(Get-Fix16Nodes -Root $Root -Type ([System.Management.Automation.Language.StringConstantExpressionAst]) | ForEach-Object { [string]$_.Value })
    }
}

Describe 'Test-TpmAutoSyncStateFile (ASTRA-08)' {
    BeforeEach {
        $script:f16Dir = New-Fix16Dir -Prefix 'ss'
    }

    It 'reports an absent sync-state file as Absent with an empty state' {
        $path = Join-Path $script:f16Dir 'sync.json'

        $r = Test-TpmAutoSyncStateFile -Path $path

        $r.Status | Should -Be 'Absent'
        $r.State.Count | Should -Be 0
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'loads a JSON object as Valid without modifying the file' {
        $path = Join-Path $script:f16Dir 'sync.json'
        [System.IO.File]::WriteAllText($path, '{"A":{"x":1}}')
        $before = Get-Fix16FileSnapshot -Path $path

        $r = Test-TpmAutoSyncStateFile -Path $path

        $r.Status | Should -Be 'Valid'
        $r.Reason | Should -BeNullOrEmpty
        $r.State | Should -BeOfType ([hashtable])
        $r.State.ContainsKey('A') | Should -BeTrue
        $r.State['A'].x | Should -Be 1
        Get-Fix16FileSnapshot -Path $path | Should -Be $before
    }

    It 'reports <Case> as Invalid with a reason and leaves the bytes unchanged' -TestCases @(
        @{ Case = 'malformed JSON'; Content = '{"A":{"x":1}' }
        @{ Case = 'a JSON array'; Content = '[1]' }
        @{ Case = 'an empty file'; Content = '' }
    ) {
        param($Case, $Content)
        $path = Join-Path $script:f16Dir 'sync.json'
        [System.IO.File]::WriteAllText($path, $Content)
        $before = Get-Fix16FileSnapshot -Path $path

        $r = Test-TpmAutoSyncStateFile -Path $path

        $r.Status | Should -Be 'Invalid'
        $r.Reason | Should -Not -BeNullOrEmpty
        $r.State.Count | Should -Be 0
        Get-Fix16FileSnapshot -Path $path | Should -Be $before
    }

    It 'reports a directory at the sync-state path as Invalid and leaves it in place' {
        $path = Join-Path $script:f16Dir 'sync.json'
        [void][System.IO.Directory]::CreateDirectory($path)

        $r = Test-TpmAutoSyncStateFile -Path $path

        $r.Status | Should -Be 'Invalid'
        $r.Reason | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $path -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $path -Force).Count | Should -Be 0
    }
}

Describe 'Save-TpmInvalidAutoSyncStateCopy (ASTRA-08)' {
    It 'creates a uniquely named sibling with identical bytes and leaves the original untouched' {
        $dir = New-Fix16Dir -Prefix 'sc'
        $path = Join-Path $dir 'sync.json'
        [System.IO.File]::WriteAllBytes($path, [byte[]](123, 34, 65, 34, 58, 123, 125, 0, 255, 10))
        $before = Get-Fix16FileSnapshot -Path $path

        $copy = Save-TpmInvalidAutoSyncStateCopy -Path $path

        @($copy).Count | Should -Be 1
        Test-Path -LiteralPath $copy -PathType Leaf | Should -BeTrue
        [System.IO.Path]::GetDirectoryName($copy) | Should -Be ([System.IO.Path]::GetFullPath($dir))
        [System.IO.Path]::GetFileName($copy) | Should -Match '^sync\.invalid-\d{8}-\d{6}-[0-9a-f]{32}\.json$'
        (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Get-Fix16FileSnapshot -Path $path | Should -Be $before
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 2
    }

    It 'creates nothing and throws when the write target fails the reparse check' {
        $dir = New-Fix16Dir -Prefix 'sr'
        $path = Join-Path $dir 'sync.json'
        [System.IO.File]::WriteAllText($path, '{broken')
        $before = Get-Fix16FileSnapshot -Path $path
        Mock Assert-TpmNoReparseWriteTarget { throw 'reparse target refused' }

        { Save-TpmInvalidAutoSyncStateCopy -Path $path } | Should -Throw '*reparse target refused*'

        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object Name) -join '|') | Should -Be 'sync.json'
        Get-Fix16FileSnapshot -Path $path | Should -Be $before
    }
}

Describe 'Invoke-AutoSync invalid sync state (ASTRA-08)' {
    BeforeEach {
        $script:f16Dir = New-Fix16Dir -Prefix 'as'
        $script:f16State = Join-Path $script:f16Dir 'sync.json'
        [System.IO.File]::WriteAllText($script:f16State, '{"A":{"x":1}')
        $script:f16Before = Get-Fix16FileSnapshot -Path $script:f16State
        Mock Get-TpmTopLevelZipSourceFiles { @() }
        Mock Get-TpmImmediateZipSubdirectorySummary { @() }
        Mock Write-Host {}
    }

    It 'refuses before any ZIP discovery when no rebuild was authorized' {
        $r = Invoke-AutoSync -zipSource $script:f16Dir -installFolder (Join-Path $script:f16Dir 'G') -syncStatePath $script:f16State

        $r | Should -BeOfType ([hashtable])
        $r.StateRefused | Should -BeTrue
        $r.Failed | Should -Be 1
        $r.Synced | Should -Be 0
        $r.StateReason | Should -Not -BeNullOrEmpty
        Should -Invoke Get-TpmTopLevelZipSourceFiles -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $script:f16State | Should -Be $script:f16Before
        Test-Path -LiteralPath (Join-Path $script:f16Dir 'G') | Should -BeFalse
    }

    It 'still refuses when rebuild is requested but the preserved copy does not exist' {
        $missingCopy = Join-Path $script:f16Dir 'sync.invalid-missing.json'

        $r = Invoke-AutoSync -zipSource $script:f16Dir -installFolder (Join-Path $script:f16Dir 'G') -syncStatePath $script:f16State -RebuildInvalidState $true -InvalidStatePreservedCopy $missingCopy

        $r.StateRefused | Should -BeTrue
        $r.Failed | Should -Be 1
        $r.Synced | Should -Be 0
        Should -Invoke Get-TpmTopLevelZipSourceFiles -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $script:f16State | Should -Be $script:f16Before
    }

    It 'still refuses when a preserved copy exists but rebuild was not chosen' {
        $copy = Save-TpmInvalidAutoSyncStateCopy -Path $script:f16State

        $r = Invoke-AutoSync -zipSource $script:f16Dir -installFolder (Join-Path $script:f16Dir 'G') -syncStatePath $script:f16State -InvalidStatePreservedCopy $copy

        $r.StateRefused | Should -BeTrue
        Should -Invoke Get-TpmTopLevelZipSourceFiles -Times 0 -Exactly
    }

    It 'proceeds past the state check with an authorized rebuild and a real preserved copy' {
        $copy = Save-TpmInvalidAutoSyncStateCopy -Path $script:f16State

        $r = Invoke-AutoSync -zipSource $script:f16Dir -installFolder (Join-Path $script:f16Dir 'G') -syncStatePath $script:f16State -RebuildInvalidState $true -InvalidStatePreservedCopy $copy

        Should -Invoke Get-TpmTopLevelZipSourceFiles -Times 1 -Exactly
        $r.ContainsKey('StateRefused') | Should -BeFalse
        $r.Failed | Should -Be 0
        $r.Synced | Should -Be 0
        (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $script:f16State -Algorithm SHA256).Hash
    }
}

Describe 'Lazy registration safety backup (Finding A)' {
    BeforeEach {
        $script:f16Root = New-Fix16Dir -Prefix 'lz'
        $script:f16Up = New-Fix16UserProfiles -Root $script:f16Root
        $script:f16BackupState = @{ Backup = $null; Done = $false; Error = $null }
    }

    It 'Confirm-TpmRegistrationSafetyBackup creates exactly one verified backup across two calls and returns the same object' {
        $first = Confirm-TpmRegistrationSafetyBackup -State $script:f16BackupState -UserProfilesDir $script:f16Up
        $second = Confirm-TpmRegistrationSafetyBackup -State $script:f16BackupState -UserProfilesDir $script:f16Up

        [object]::ReferenceEquals($first, $second) | Should -BeTrue
        [object]::ReferenceEquals($first, $script:f16BackupState['Backup']) | Should -BeTrue
        $first.Verified | Should -BeTrue
        $script:f16BackupState['Done'] | Should -BeTrue
        $script:f16BackupState['Error'] | Should -BeNullOrEmpty
        $children = @(Get-ChildItem -LiteralPath (Join-Path $script:f16Up 'FullBackup') -Directory -Force)
        $children.Count | Should -Be 1
        $children[0].Name | Should -Be ([System.IO.Path]::GetFileName([string]$first.Path))
        $children[0].Name | Should -BeLike 'RegisterGames_*'
        (Get-FileHash -LiteralPath (Join-Path $children[0].FullName 'GameA.xml') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $script:f16Up 'GameA.xml') -Algorithm SHA256).Hash
    }

    It 'Confirm-TpmRegistrationSafetyBackup fails sticky when the backup is not verified' {
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix16UnverifiedBackup -UserProfilesDir $UserProfilesDir }

        { Confirm-TpmRegistrationSafetyBackup -State $script:f16BackupState -UserProfilesDir $script:f16Up } | Should -Throw '*safety backup could not be verified*'
        $script:f16BackupState['Error'] | Should -Not -BeNullOrEmpty
        $script:f16BackupState['Done'] | Should -BeFalse
        { Confirm-TpmRegistrationSafetyBackup -State $script:f16BackupState -UserProfilesDir $script:f16Up } | Should -Throw '*safety backup could not be verified*'

        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 1 -Exactly
        Test-Path -LiteralPath (Join-Path $script:f16Up 'FullBackup') | Should -BeFalse
    }

    It 'Get-TpmRegistrationBackupEvidence reports no backup when the run tracked state but created none' {
        $carried = [pscustomobject]@{ Attempted = $true; Created = $true; Verified = $true; Path = 'carried' }
        $result = [pscustomobject]@{ Backup = $carried; TechnicalDetails = [pscustomobject]@{ SafetyBackupState = @{ Backup = $null; Done = $false; Error = $null } } }

        $evidence = Get-TpmRegistrationBackupEvidence -Result $result

        $null -eq $evidence | Should -BeTrue
    }

    It 'Get-TpmRegistrationBackupEvidence prefers the tracked state backup over Result.Backup' {
        $carried = [pscustomobject]@{ Attempted = $true; Created = $true; Verified = $true; Path = 'carried' }
        $tracked = [pscustomobject]@{ Attempted = $true; Created = $true; Verified = $true; Path = 'tracked' }
        $result = [pscustomobject]@{ Backup = $carried; TechnicalDetails = [pscustomobject]@{ SafetyBackupState = @{ Backup = $tracked; Done = $true; Error = $null } } }

        $evidence = Get-TpmRegistrationBackupEvidence -Result $result

        $evidence.Path | Should -Be 'tracked'
    }

    It 'Get-TpmRegistrationBackupEvidence falls back to Result.Backup when no state was tracked' {
        $carried = [pscustomobject]@{ Attempted = $true; Created = $true; Verified = $true; Path = 'carried' }
        $result = [pscustomobject]@{ Backup = $carried; TechnicalDetails = [pscustomobject]@{ Registered = @() } }

        $evidence = Get-TpmRegistrationBackupEvidence -Result $result

        $evidence.Path | Should -Be 'carried'
    }

    It 'Finding A: registration no longer deletes backups and Register-Games makes no eager backup (structural)' {
        $script:fix16SourceText.Contains('Remove-TpmUnneededUserProfilesBackup') | Should -BeFalse
        $definitions = @($script:fix16Ast.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Register-Games'
        })
        $definitions.Count | Should -Be 1
        @(Get-Fix16Commands -Root $definitions[0].Body -Name 'New-TpmVerifiedUserProfilesBackup').Count | Should -Be 0
        $legacyCalls = @(Get-Fix16Commands -Root $definitions[0].Body -Name 'Register-GamesLegacy')
        $legacyCalls.Count | Should -Be 1
        (Get-Fix16ParameterArgumentText -Command $legacyCalls[0] -Name 'BackupState') | Should -Be '$backupState'
    }
}

Describe 'ConvertTo-TpmRegistrationResult already-registered outcome (Finding A)' {
    It 'reports all-already-registered with no backup as a clean NO_OP' {
        $legacy = New-Fix16Legacy -Already @('A', 'B')

        $r = ConvertTo-TpmRegistrationResult -Legacy $legacy -Backup $null -DryRun $false

        $r.Outcome | Should -Be 'NO_OP'
        $r.ProductState | Should -Be 'UNCHANGED'
        $r.Summary | Should -Be 'All selected games were already registered. No profile change was needed.'
        $r.Succeeded | Should -BeTrue
        (@($r.Already) -join '|') | Should -Be 'A|B'
        { Assert-TpmTransactionResult -Result $r } | Should -Not -Throw
    }

    It 'keeps the backup-retained ACTION_REQUIRED contract when a backup was touched' {
        $legacy = New-Fix16Legacy -Already @('A', 'B')
        $backup = [pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Verified = $true; Path = (Join-Path $TestDrive 'bk'); Manifest = @() }

        $r = ConvertTo-TpmRegistrationResult -Legacy $legacy -Backup $backup -DryRun $false

        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        $r.ReasonCode | Should -Be 'BACKUP_RETAINED_NO_PROFILE_CHANGE'
        { Assert-TpmTransactionResult -Result $r } | Should -Not -Throw
    }

    It 'does not hide a real pre-write failure behind already-registered games' {
        $legacy = New-Fix16Legacy -Already @('A') -Failures @([pscustomobject]@{ Code = 'C'; WriteAttempted = $false })

        $r = ConvertTo-TpmRegistrationResult -Legacy $legacy -Backup $null -DryRun $false

        $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $r.ReasonCode | Should -Be 'REGISTRATION_INCOMPLETE'
        $r.Summary | Should -Not -Be 'All selected games were already registered. No profile change was needed.'
        (@($r.Mutation.FailedItems) -join '|') | Should -Be 'C'
        { Assert-TpmTransactionResult -Result $r } | Should -Not -Throw
    }
}

Describe 'Register-Games lazy safety backup (Finding A)' {
    BeforeEach {
        $script:f16Root = New-Fix16Dir -Prefix 'rg'
        $script:f16Up = New-Fix16UserProfiles -Root $script:f16Root
        $script:f16ABefore = Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameA.xml')
        $script:f16BBefore = Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameB.xml')
        $script:f16WriteReached = $false
        Mock Write-Host {}
        Mock Test-TpmRegistrationLedgerReady { [pscustomobject]@{ Ready = $true; Message = '' } }
        Mock Close-TpmRegistrationLedgerOperations { [pscustomobject]@{ Stopped = $false; Status = 'OK'; Message = ''; OperationIds = @() } }
    }

    It 'returns NO_OP without creating a safety backup when every candidate is already registered' {
        Mock New-TpmVerifiedUserProfilesBackup { throw 'No safety backup is expected for an already-registered run.' }
        Mock Register-GamesLegacy { New-Fix16Legacy -Already @('A') }

        $r = Register-Games -userProfilesDir $script:f16Up -installFolder (Join-Path $script:f16Root 'G') -profileIndex @{}

        $r.Outcome | Should -Be 'NO_OP'
        $r.Summary | Should -Be 'All selected games were already registered. No profile change was needed.'
        { Assert-TpmTransactionResult -Result $r } | Should -Not -Throw
        $r.Backup.Attempted | Should -BeFalse
        $r.Backup.Created | Should -BeFalse
        $null -eq (Get-TpmRegistrationBackupEvidence -Result $r) | Should -BeTrue
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $script:f16Up 'FullBackup') | Should -BeFalse
        Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameA.xml') | Should -Be $script:f16ABefore
        Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameB.xml') | Should -Be $script:f16BBefore
        Should -Invoke Close-TpmRegistrationLedgerOperations -Times 1 -Exactly -ParameterFilter { $Result.Outcome -eq 'NO_OP' }
    }

    It 'reports truthful unverified backup evidence and changes no profile when the lazy backup fails before the first write' {
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix16UnverifiedBackup -UserProfilesDir $UserProfilesDir }
        Mock Register-GamesLegacy {
            $legacy = New-Fix16Legacy
            try {
                [void](Confirm-TpmRegistrationSafetyBackup -State $BackupState -UserProfilesDir $userProfilesDir)
                $script:f16WriteReached = $true
            } catch {
                [void]$legacy.MutationRecords.Failures.Add([pscustomobject]@{ Code = 'A'; WriteAttempted = $false })
            }
            $legacy
        }

        $r = Register-Games -userProfilesDir $script:f16Up -installFolder (Join-Path $script:f16Root 'G') -profileIndex @{}

        $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $r.ProductState | Should -Be 'UNCHANGED'
        { Assert-TpmTransactionResult -Result $r } | Should -Not -Throw
        $r.Backup.Attempted | Should -BeTrue
        $r.Backup.Verified | Should -BeFalse
        (@($r.Mutation.FailedItems) -join '|') | Should -Be 'A'
        $script:f16WriteReached | Should -BeFalse
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 1 -Exactly
        Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameA.xml') | Should -Be $script:f16ABefore
        Get-Fix16FileSnapshot -Path (Join-Path $script:f16Up 'GameB.xml') | Should -Be $script:f16BBefore
    }
}

Describe 'Backfill-SecondaryExecutablePath lazy safety backup (Finding A)' {
    BeforeEach {
        $script:f16Root = New-Fix16Dir -Prefix 'bf'
        $script:f16Up = Join-Path $script:f16Root 'UP'
        $game = Join-Path $script:f16Root 'G'
        [void][System.IO.Directory]::CreateDirectory($script:f16Up)
        [void][System.IO.Directory]::CreateDirectory($game)
        [System.IO.File]::WriteAllText((Join-Path $game 'a.exe'), 'primary')
        [System.IO.File]::WriteAllText((Join-Path $game 'b.exe'), 'secondary')
        $script:f16Profile = Join-Path $script:f16Up 'GameA.xml'
        [System.IO.File]::WriteAllText($script:f16Profile, ('<GameProfile><GamePath>{0}</GamePath><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>b.exe</ExecutableName2></GameProfile>' -f (Join-Path $game 'a.exe')))
        $script:f16ProfileBefore = Get-Fix16FileSnapshot -Path $script:f16Profile
        $script:f16BackupState = @{ Backup = $null; Done = $false; Error = $null }
        $script:f16RegState = [pscustomobject]@{ Changed = (New-Object System.Collections.ArrayList); Failures = (New-Object System.Collections.ArrayList) }
        $script:f16BackupsAtSave = -1
        Mock Save-XmlMaybe {
            $script:f16BackupsAtSave = @(Get-ChildItem -LiteralPath (Join-Path $script:f16Up 'FullBackup') -Directory -Force -ErrorAction SilentlyContinue).Count
        }
    }

    It 'creates the verified safety backup before the GamePath2 save' {
        Backfill-SecondaryExecutablePath -UserProfilePath $script:f16Profile -DryRun $false -RegistrationState $script:f16RegState -BackupState $script:f16BackupState -UserProfilesDir $script:f16Up

        Should -Invoke Save-XmlMaybe -Times 1 -Exactly
        $script:f16BackupsAtSave | Should -Be 1
        $script:f16BackupState['Done'] | Should -BeTrue
        $script:f16BackupState['Backup'].Verified | Should -BeTrue
        (Get-FileHash -LiteralPath (Join-Path $script:f16BackupState['Backup'].Path 'GameA.xml') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $script:f16Profile -Algorithm SHA256).Hash
        @($script:f16RegState.Changed) -contains 'GameA' | Should -BeTrue
        $script:f16RegState.Failures.Count | Should -Be 0
    }

    It 'never saves and records an unattempted failure when the safety backup fails' {
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix16UnverifiedBackup -UserProfilesDir $UserProfilesDir }

        Backfill-SecondaryExecutablePath -UserProfilePath $script:f16Profile -DryRun $false -RegistrationState $script:f16RegState -BackupState $script:f16BackupState -UserProfilesDir $script:f16Up

        Should -Invoke Save-XmlMaybe -Times 0 -Exactly
        $script:f16RegState.Failures.Count | Should -Be 1
        $script:f16RegState.Failures[0].Code | Should -Be 'GameA'
        $script:f16RegState.Failures[0].WriteAttempted | Should -BeFalse
        $script:f16RegState.Failures[0].Reason | Should -Be 'PROFILE_BACKFILL_NOT_VERIFIED'
        $script:f16RegState.Changed.Count | Should -Be 0
        $script:f16BackupState['Error'] | Should -Not -BeNullOrEmpty
        Get-Fix16FileSnapshot -Path $script:f16Profile | Should -Be $script:f16ProfileBefore
    }
}

Describe 'Get-TeknoParrotProfileSet live/local fallback (Finding B)' {
    BeforeEach {
        $script:f16Gp = New-Fix16Dir -Prefix 'gp'
        [System.IO.File]::WriteAllText((Join-Path $script:f16Gp 'LocalOne.xml'), '<GameProfile />')
        [System.IO.File]::WriteAllText((Join-Path $script:f16Gp 'LocalTwo.xml'), '<GameProfile />')
        $script:fix16Progress.Clear()
        $script:TpmProfileSetSource = $null
        $script:f16RepoUri = 'https://api.github.com/repos/teknogods/TeknoParrotUI'
        $script:f16Tree = @{
            truncated = $false
            tree = @(
                @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/LiveOne.xml' }
                @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/LiveTwo.xml' }
                @{ type = 'tree'; path = 'TeknoParrotUi.Common/GameProfiles' }
            )
        }
        Mock Start-Sleep {}
    }

    It 'skips the tree request after a repository 404 and reports local templates as the source' {
        Mock Invoke-TpmWebRequestSilently { throw 'The remote server returned an error: (404) Not Found.' }
        Mock Get-TpmHttpStatusCodeFromError { 404 }

        $set = @(Get-TeknoParrotProfileSet -localGameProfilesDir $script:f16Gp)

        (@($set | Sort-Object) -join '|') | Should -Be 'LocalOne|LocalTwo'
        Should -Invoke Invoke-TpmWebRequestSilently -Times 0 -Exactly -ParameterFilter { $Uri -like '*/git/trees/*' }
        Should -Invoke Invoke-TpmWebRequestSilently -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:f16RepoUri }
        $script:TpmProfileSetSource.Source | Should -Be 'LocalTemplates'
        $script:TpmProfileSetSource.LiveCount | Should -Be 0
        $script:TpmProfileSetSource.Count | Should -Be 2
        @($script:fix16Progress | Where-Object { $_.Complete -and $_.Outcome -ne 'Final' }).Count | Should -Be 0
        @($script:fix16Progress | Where-Object { $_.Label -eq 'GitHub profile query' }).Count | Should -Be 0
        @($script:fix16Progress | Where-Object { $_.Complete -and $_.Label -eq 'TeknoParrot profile list' }).Count | Should -Be 1
    }

    It 'reports Live when the live tree is complete and does not merge local templates' {
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = '{"default_branch":"main"}' } } -ParameterFilter { $Uri -eq $script:f16RepoUri }
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = ($script:f16Tree | ConvertTo-Json -Depth 5) } } -ParameterFilter { $Uri -like '*/git/trees/*' }

        $set = @(Get-TeknoParrotProfileSet -localGameProfilesDir $script:f16Gp)

        (@($set | Sort-Object) -join '|') | Should -Be 'LiveOne|LiveTwo'
        Should -Invoke Invoke-TpmWebRequestSilently -Times 1 -Exactly -ParameterFilter { $Uri -like '*/git/trees/main?recursive=1' }
        $script:TpmProfileSetSource.Source | Should -Be 'Live'
        $script:TpmProfileSetSource.LiveCount | Should -Be 2
    }

    It 'merges local template stems into a truncated live tree' {
        $script:f16Tree.truncated = $true
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = '{"default_branch":"master"}' } } -ParameterFilter { $Uri -eq $script:f16RepoUri }
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = ($script:f16Tree | ConvertTo-Json -Depth 5) } } -ParameterFilter { $Uri -like '*/git/trees/*' }

        $set = @(Get-TeknoParrotProfileSet -localGameProfilesDir $script:f16Gp)

        (@($set | Sort-Object) -join '|') | Should -Be 'LiveOne|LiveTwo|LocalOne|LocalTwo'
        $script:TpmProfileSetSource.Source | Should -Be 'Live'
        $script:TpmProfileSetSource.LiveCount | Should -Be 2
        $script:TpmProfileSetSource.Count | Should -Be 4
    }
}

Describe 'Saved-settings locator (Finding K)' {
    BeforeEach {
        $script:f16Base = New-Fix16Dir -Prefix 'cf'
        $script:f16ScriptRoot = Join-Path $script:f16Base 'S'
        [void][System.IO.Directory]::CreateDirectory($script:f16ScriptRoot)
        $script:f16Legacy = Join-Path $script:f16ScriptRoot 'TeknoParrot-Manager.config.json'
        $script:f16Locator = Join-Path $script:f16Base 'L.json'
        $script:fix16Log.Clear()
    }

    It 'returns the managed config of the root remembered by the locator' {
        $tp = Join-Path $script:f16Base 'TP'
        $managed = New-Fix16ManagedConfig -TeknoParrotRoot $tp
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }

        $r = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $r | Should -Be ([System.IO.Path]::GetFullPath($managed))
    }

    It 'prefers the locator root over an auto-detected root that also has settings' {
        $tp = Join-Path $script:f16Base 'TP'
        $managed = New-Fix16ManagedConfig -TeknoParrotRoot $tp
        $script:f16Detected = Join-Path $script:f16Base 'TD'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $script:f16Detected)
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @($script:f16Detected) }

        $r = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $r | Should -Be ([System.IO.Path]::GetFullPath($managed))
    }

    It 'gives the legacy script-folder config precedence over the locator' {
        $tp = Join-Path $script:f16Base 'TP'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $tp)
        Set-Fix16Locator -TeknoParrotRoot $tp
        [System.IO.File]::WriteAllText($script:f16Legacy, '{}')
        Mock Find-TeknoParrotRoot { @() }

        $r = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $r | Should -Be $script:f16Legacy
    }

    It 'falls back to auto-detected roots when the locator root has no settings' {
        Set-Fix16Locator -TeknoParrotRoot (Join-Path $script:f16Base 'TPE')
        $script:f16Detected = Join-Path $script:f16Base 'TD'
        $detectedConfig = New-Fix16ManagedConfig -TeknoParrotRoot $script:f16Detected
        Mock Find-TeknoParrotRoot { @($script:f16Detected) }

        $r = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $r | Should -Be ([System.IO.Path]::GetFullPath($detectedConfig))
    }

    It 'returns the legacy path when no settings exist anywhere' {
        Mock Find-TeknoParrotRoot { @() }

        $r = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $r | Should -Be $script:f16Legacy
        Test-Path -LiteralPath $script:f16Legacy | Should -BeFalse
    }

    It 'ignores a corrupt locator file without throwing' {
        [System.IO.File]::WriteAllText($script:f16Locator, '{"TeknoParrotRoot":')
        $locatorBefore = Get-Fix16FileSnapshot -Path $script:f16Locator
        Mock Find-TeknoParrotRoot { @() }

        $script:f16Result = $null
        { $script:f16Result = Find-TpmSavedConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator } | Should -Not -Throw
        $r = $script:f16Result

        $r | Should -Be $script:f16Legacy
        @($script:fix16Log | Where-Object { $_ -like '*settings locator could not be read*' }).Count | Should -Be 1
        Get-Fix16FileSnapshot -Path $script:f16Locator | Should -Be $locatorBefore
    }

    It 'writes the locator folder and a JSON file holding the full TeknoParrot root' {
        $locatorPath = Join-Path $script:f16Base 'L\State\ConfigLocator.json'
        $rootInput = Join-Path $script:f16Base 'X\..\TP'

        $r = Write-TpmConfigLocator -TeknoParrotRoot $rootInput -LocatorPath $locatorPath

        @($r).Count | Should -Be 1
        $r | Should -BeTrue
        Test-Path -LiteralPath $locatorPath -PathType Leaf | Should -BeTrue
        $saved = [System.IO.File]::ReadAllText($locatorPath) | ConvertFrom-Json
        $saved.TeknoParrotRoot | Should -Be ([System.IO.Path]::GetFullPath($rootInput))
        $saved.TeknoParrotRoot | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $script:f16Base 'TP')))
        (@(Get-ChildItem -LiteralPath (Join-Path $script:f16Base 'L\State') -Force | ForEach-Object Name) -join '|') | Should -Be 'ConfigLocator.json'
    }

    It 'returns false without throwing or creating anything when the folder fails the reparse check' {
        $locatorPath = Join-Path $script:f16Base 'L\State\ConfigLocator.json'
        Mock Assert-TpmNoReparseWriteTarget { throw 'reparse locator refused' }

        $script:f16Result = $null
        { $script:f16Result = Write-TpmConfigLocator -TeknoParrotRoot (Join-Path $script:f16Base 'TP') -LocatorPath $locatorPath } | Should -Not -Throw

        $script:f16Result | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:f16Base 'L') | Should -BeFalse
        @($script:fix16Log | Where-Object { $_ -like '*settings locator could not be saved*' }).Count | Should -Be 1
    }
}

Describe 'Startup settings selection (FIX21A R3)' {
    BeforeAll {
        function New-Fix21ResumeToken {
            param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Leaf)
            $path = Join-Path $Directory $Leaf
            [System.IO.File]::WriteAllText($path, ([pscustomobject]@{ SchemaVersion = 4; Purpose = 'TeknoParrotManager.PostgresRecovery'; CipherText = 'fixture-cipher' } | ConvertTo-Json))
            return $path
        }
        # ConfigSha256 is added only when passed, so a test can omit it.
        function Set-Fix21ResumePayload {
            param([Parameter(Mandatory)][string]$TpRoot, [Parameter(Mandatory)][string]$ConfigPath, [AllowEmptyString()][string]$ConfigSha256)
            $payload = [ordered]@{ SchemaVersion = 4; Purpose = 'TeknoParrotManager.PostgresRecovery'; TpRoot = $TpRoot; ConfigPath = $ConfigPath }
            if ($PSBoundParameters.ContainsKey('ConfigSha256')) { $payload['ConfigSha256'] = $ConfigSha256 }
            $script:f16Payload = ([pscustomobject]$payload | ConvertTo-Json)
        }
        # Lower-case hex SHA-256 of the file bytes (production compares case-insensitively).
        function Get-Fix21Sha256 {
            param([Parameter(Mandatory)][string]$Path)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))) -replace '-', '').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
        }
        function Get-Fix21DirectoryListing {
            param([Parameter(Mandatory)][string]$Path)
            return (@(Get-ChildItem -LiteralPath $Path -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|')
        }
    }
    BeforeEach {
        $script:f16Base = New-Fix16Dir -Prefix 'su'
        $script:f16ScriptRoot = Join-Path $script:f16Base 'S'
        [void][System.IO.Directory]::CreateDirectory($script:f16ScriptRoot)
        $script:f16Legacy = Join-Path $script:f16ScriptRoot 'TeknoParrot-Manager.config.json'
        $script:f16Locator = Join-Path $script:f16Base 'L.json'
        $script:f16StateDir = Join-Path $script:f16Base 'R'
        [void][System.IO.Directory]::CreateDirectory($script:f16StateDir)
        $script:f16TokenLeaf = '.tpm-postgres-recovery-' + [guid]::NewGuid().ToString('N') + '.json'
        $script:f16Payload = $null
        $script:fix16Log.Clear()
        Mock Get-PostgresRecoveryStateDirectory { $script:f16StateDir }
        Mock Unprotect-PostgresRecoveryEnvelope { $script:f16Payload }
    }

    It 'Resolve-TpmStartupConfigPath gives the remembered TeknoParrot folder settings when there is no resume token' {
        $tp = Join-Path $script:f16Base 'TP'
        $locatorConfig = New-Fix16ManagedConfig -TeknoParrotRoot $tp
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }

        $interactive = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator

        $interactive | Should -Be ([System.IO.Path]::GetFullPath($locatorConfig))
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 0 -Exactly
    }

    It 'a resume token loads only the recorded owned config even when the locator and detection name other roots, and leaves the token in place' {
        $tp = Join-Path $script:f16Base 'TP'
        $locatorConfig = New-Fix16ManagedConfig -TeknoParrotRoot $tp
        Set-Fix16Locator -TeknoParrotRoot $tp
        $script:f16Detected = Join-Path $script:f16Base 'TD'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $script:f16Detected)
        Mock Find-TeknoParrotRoot { @($script:f16Detected) }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        $recordedConfig = New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot
        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig -ConfigSha256 (Get-Fix21Sha256 -Path $recordedConfig)
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf
        $tokenBefore = Get-Fix16FileSnapshot -Path $token
        $listingBefore = Get-Fix21DirectoryListing -Path $script:f16StateDir

        $first = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token
        $second = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        $first | Should -Be ([System.IO.Path]::GetFullPath($recordedConfig))
        $first | Should -Not -Be ([System.IO.Path]::GetFullPath($locatorConfig))
        $second | Should -Be ([System.IO.Path]::GetFullPath($recordedConfig))
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 2 -Exactly -ParameterFilter { $ProtectedText -eq 'fixture-cipher' }
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $token | Should -Be $tokenBefore
        Get-Fix21DirectoryListing -Path $script:f16StateDir | Should -BeExactly $listingBefore
        $listingBefore | Should -BeExactly $script:f16TokenLeaf
    }

    It 'a resume token returns null when the recorded ConfigPath is the owned config of another root' {
        $tp = Join-Path $script:f16Base 'TP'
        $otherRootConfig = New-Fix16ManagedConfig -TeknoParrotRoot $tp
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot)
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf
        $tokenBefore = Get-Fix16FileSnapshot -Path $token

        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $otherRootConfig -ConfigSha256 (Get-Fix21Sha256 -Path $otherRootConfig)
        $otherRoot = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        ($null -eq $otherRoot) | Should -BeTrue
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $token | Should -Be $tokenBefore
    }

    # The settings file next to the script is a supported layout (the user answered N to moving it). The elevated child must accept
    # it, or the administrator window opens and closes without doing anything.
    It 'a resume token loads the settings file next to the script when that is the file the parent recorded and its hash still matches' {
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot)
        [System.IO.File]::WriteAllText($script:f16Legacy, '{"tpRoot":"x"}')
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf

        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $script:f16Legacy -ConfigSha256 (Get-Fix21Sha256 -Path $script:f16Legacy)
        $accepted = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token
        [System.IO.File]::WriteAllText($script:f16Legacy, '{"tpRoot":"changed"}')
        $changed = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token
        $elsewhere = Resolve-TpmStartupConfigPath -ScriptRoot (Join-Path $script:f16Base 'OtherScriptFolder') -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        $accepted | Should -Be ([System.IO.Path]::GetFullPath($script:f16Legacy))
        ($null -eq $changed) | Should -BeTrue -Because 'the file changed after the handoff'
        ($null -eq $elsewhere) | Should -BeTrue -Because 'a settings file beside a different script is not the recorded one'
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
    }

    It 'a resume token returns null without decrypting when the token name or folder is wrong' {
        $tp = Join-Path $script:f16Base 'TP'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $tp)
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        $recordedConfig = New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot
        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig -ConfigSha256 (Get-Fix21Sha256 -Path $recordedConfig)
        $badLeaf = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf ('.tpm-postgres-recovery-' + ('z' * 32) + '.json')
        $otherDir = Join-Path $script:f16Base 'X'
        [void][System.IO.Directory]::CreateDirectory($otherDir)
        $badDir = New-Fix21ResumeToken -Directory $otherDir -Leaf $script:f16TokenLeaf
        $missing = Join-Path $script:f16StateDir ('.tpm-postgres-recovery-' + [guid]::NewGuid().ToString('N') + '.json')
        $badLeafBefore = Get-Fix16FileSnapshot -Path $badLeaf
        $badDirBefore = Get-Fix16FileSnapshot -Path $badDir

        $r1 = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $badLeaf
        $r2 = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $badDir
        $r3 = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $missing

        ($null -eq $r1) | Should -BeTrue
        ($null -eq $r2) | Should -BeTrue
        ($null -eq $r3) | Should -BeTrue
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 0 -Exactly
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $badLeaf | Should -Be $badLeafBefore
        Get-Fix16FileSnapshot -Path $badDir | Should -Be $badDirBefore
        Test-Path -LiteralPath $missing | Should -BeFalse
    }

    It 'a resume token returns null when the recorded owned config file is missing' {
        $tp = Join-Path $script:f16Base 'TP'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $tp)
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        $recordedConfig = Join-Path $recordedRoot 'TeknoParrotManager\State\TeknoParrot-Manager.config.json'
        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig -ConfigSha256 ('0' * 64)
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf
        $tokenBefore = Get-Fix16FileSnapshot -Path $token

        $r = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        ($null -eq $r) | Should -BeTrue
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 1 -Exactly -ParameterFilter { $ProtectedText -eq 'fixture-cipher' }
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Test-Path -LiteralPath $recordedRoot | Should -BeFalse
        Get-Fix16FileSnapshot -Path $token | Should -Be $tokenBefore
    }

    It 'a resume token returns null once the owned config bytes changed after the handoff, and leaves the token in place' {
        $tp = Join-Path $script:f16Base 'TP'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $tp)
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        $recordedConfig = New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot
        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig -ConfigSha256 (Get-Fix21Sha256 -Path $recordedConfig)
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf
        $tokenBefore = Get-Fix16FileSnapshot -Path $token

        $beforeChange = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token
        [System.IO.File]::WriteAllText($recordedConfig, '{"TeknoParrotRoot":"D:\\Other","GamesInstallFolder":"D:\\Games"}')
        $afterChange = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        $beforeChange | Should -Be ([System.IO.Path]::GetFullPath($recordedConfig))
        ($null -eq $afterChange) | Should -BeTrue
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 2 -Exactly -ParameterFilter { $ProtectedText -eq 'fixture-cipher' }
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $token | Should -Be $tokenBefore
        Get-Fix21DirectoryListing -Path $script:f16StateDir | Should -BeExactly $script:f16TokenLeaf
    }

    It 'a resume token returns null when the recorded ConfigSha256 is missing or empty' {
        $tp = Join-Path $script:f16Base 'TP'
        [void](New-Fix16ManagedConfig -TeknoParrotRoot $tp)
        Set-Fix16Locator -TeknoParrotRoot $tp
        Mock Find-TeknoParrotRoot { @() }
        $recordedRoot = Join-Path $script:f16Base 'TR'
        $recordedConfig = New-Fix16ManagedConfig -TeknoParrotRoot $recordedRoot
        $token = New-Fix21ResumeToken -Directory $script:f16StateDir -Leaf $script:f16TokenLeaf
        $tokenBefore = Get-Fix16FileSnapshot -Path $token

        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig
        $missingHash = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token
        Set-Fix21ResumePayload -TpRoot $recordedRoot -ConfigPath $recordedConfig -ConfigSha256 ''
        $emptyHash = Resolve-TpmStartupConfigPath -ScriptRoot $script:f16ScriptRoot -LocatorPath $script:f16Locator -PostgresRecoveryResumeToken $token

        ($null -eq $missingHash) | Should -BeTrue
        ($null -eq $emptyHash) | Should -BeTrue
        Should -Invoke Unprotect-PostgresRecoveryEnvelope -Times 2 -Exactly -ParameterFilter { $ProtectedText -eq 'fixture-cipher' }
        Should -Invoke Find-TeknoParrotRoot -Times 0 -Exactly
        Get-Fix16FileSnapshot -Path $token | Should -Be $tokenBefore
    }

    It 'startup resolves the settings path through Resolve-TpmStartupConfigPath with the resume token bound (structural)' {
        $assigns = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.AssignmentStatementAst]) | Where-Object {
            $_.Left.Extent.Text -eq '$configPath' -and @(Get-Fix16Commands -Root $_.Right -Name 'Resolve-TpmStartupConfigPath').Count -eq 1
        })
        $assigns.Count | Should -Be 1
        $call = @(Get-Fix16Commands -Root $assigns[0].Right -Name 'Resolve-TpmStartupConfigPath')[0]
        (Get-Fix16ParameterArgumentText -Command $call -Name 'ScriptRoot') | Should -BeExactly '$PSScriptRoot'
        Test-Fix16HasParameter -Command $call -Name 'Unattended' | Should -BeFalse
        (Get-Fix16ParameterArgumentText -Command $call -Name 'PostgresRecoveryResumeToken') | Should -BeExactly '$PostgresRecoveryResumeToken'
        Test-Fix16HasParameter -Command $call -Name 'LocatorPath' | Should -BeFalse
        @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.CommandAst]) | Where-Object { $_.GetCommandName() -eq 'Find-TpmSavedConfigPath' }).Count | Should -Be 0

        $resumeAssigns = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.AssignmentStatementAst]) | Where-Object { $_.Left.Extent.Text -eq '$isPostgresRecoveryResume' })
        $resumeAssigns.Count | Should -Be 1
        $resumeAssigns[0].Extent.StartOffset | Should -BeLessThan $assigns[0].Extent.StartOffset

        $stops = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            (@(Get-Fix16AndOperandTexts -Expression $_.Clauses[0].Item1) -join '|') -eq '$isPostgresRecoveryResume|-not $configPath'
        })
        $stops.Count | Should -Be 1
        $stops[0].Extent.StartOffset | Should -BeGreaterThan $assigns[0].Extent.StartOffset
        @(Get-Fix16Commands -Root $stops[0].Clauses[0].Item2 -Name 'Exit-PostgresRecoveryResume').Count | Should -Be 1
    }

    Context 'saved-settings offer' {
        BeforeAll {
            $offerAssigns = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.AssignmentStatementAst]) | Where-Object { $_.Left.Extent.Text -eq '$tpmOfferSavedConfig' })
            if ($offerAssigns.Count -ne 1) { throw "Expected exactly one top-level `$tpmOfferSavedConfig assignment; found $($offerAssigns.Count)." }
            $offerBlock = @(Get-Fix16Nodes -Root $offerAssigns[0].Right -Type ([System.Management.Automation.Language.ScriptBlockExpressionAst]))[0]
            $offerText = $offerBlock.Extent.Text
            $script:f16OfferBody = $offerText.Substring(1, $offerText.Length - 2)
        }
        BeforeEach {
            $script:f16OfferConfig = Join-Path $script:f16Base 'offer.json'
            [System.IO.File]::WriteAllText($script:f16OfferConfig, ([pscustomobject]@{ TeknoParrotRoot = 'D:\TPX'; GamesInstallFolder = 'D:\GamesX' } | ConvertTo-Json))
            Mock Write-Host {}
        }

        It 'interactive startup offers the saved settings and applies them only after Y' {
            $script:f16Answers = New-Object 'System.Collections.Generic.Queue[string]'
            $script:f16Answers.Enqueue('N')
            $script:f16Answers.Enqueue('Y')
            Mock Read-TpmYesNo { $script:f16Answers.Dequeue() }
            $offer = [scriptblock]::Create($script:f16OfferBody)
            $configPath = $script:f16OfferConfig
            $Unattended = $false
            $isPostgresRecoveryResume = $false
            $tpRoot = $null
            $gamesInstallFolder = $null
            $configAccepted = $false
            $pendingApplyMode = $null

            . $offer

            Should -Invoke Read-TpmYesNo -Times 1 -Exactly -ParameterFilter { $Prompt -eq 'Use these settings? (Y/N, D = show them)' }
            # The saved settings are no longer listed on screen (they are in the log and behind the D key).
            Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -eq 'Saved configuration found:' -or $Object -like '*TeknoParrot root*' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'TeknoParrot Manager found your saved settings.' }
            @($script:fix16Log | Where-Object { $_ -eq 'Startup settings -   TeknoParrot root : D:\TPX' }).Count | Should -Be 1
            @($script:fix16Log | Where-Object { $_ -eq 'Startup settings -   Games install folder : D:\GamesX' }).Count | Should -Be 1
            $configAccepted | Should -BeFalse
            ($null -eq $tpRoot) | Should -BeTrue
            ($null -eq $gamesInstallFolder) | Should -BeTrue

            . $offer

            Should -Invoke Read-TpmYesNo -Times 2 -Exactly -ParameterFilter { $Prompt -eq 'Use these settings? (Y/N, D = show them)' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Using your saved settings.' }
            $configAccepted | Should -BeTrue
            $tpRoot | Should -BeExactly 'D:\TPX'
            $gamesInstallFolder | Should -BeExactly 'D:\GamesX'
            ($null -eq $pendingApplyMode) | Should -BeTrue
            $script:f16Answers.Count | Should -Be 0
            @($script:fix16Log | Where-Object { $_ -like '*could not parse config.json*' }).Count | Should -Be 0
            @($script:fix16Log | Where-Object { $_ -like '*auto-accepted saved settings*' }).Count | Should -Be 0
        }

        It 'unattended and protected-resume startups accept the saved settings without prompting' {
            Mock Read-TpmYesNo { 'N' }
            $offer = [scriptblock]::Create($script:f16OfferBody)
            $configPath = $script:f16OfferConfig
            $Unattended = $true
            $isPostgresRecoveryResume = $false
            $tpRoot = $null
            $configAccepted = $false
            $pendingApplyMode = $null

            . $offer

            $configAccepted | Should -BeTrue
            $tpRoot | Should -BeExactly 'D:\TPX'
            ($null -eq $pendingApplyMode) | Should -BeTrue
            @($script:fix16Log | Where-Object { $_ -eq 'Unattended: auto-accepted saved settings.' }).Count | Should -Be 1

            $Unattended = $false
            $isPostgresRecoveryResume = $true
            $tpRoot = $null
            $configAccepted = $false

            . $offer

            $configAccepted | Should -BeTrue
            $tpRoot | Should -BeExactly 'D:\TPX'
            $pendingApplyMode | Should -BeExactly 'PostgresSetup'
            @($script:fix16Log | Where-Object { $_ -eq 'Postgres recovery: auto-accepted saved settings for the protected resume.' }).Count | Should -Be 1
            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
            @($script:fix16Log | Where-Object { $_ -like '*could not parse config.json*' }).Count | Should -Be 0
        }
    }
}

Describe 'Backup-LaunchBoxFiles staging parent cleanup (Finding L)' {
    BeforeEach {
        $script:f16Base = New-Fix16Dir -Prefix 'lb'
        $script:f16LbRoot = Join-Path $script:f16Base 'LB'
        $script:f16BackupRoot = Join-Path $script:f16Base 'BK'
        $script:f16Source = Join-Path $script:f16LbRoot 'Data\Platforms\Arcade.xml'
        $script:f16SourceXml = '<LaunchBox><Game><Title>source</Title></Game></LaunchBox>'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:f16Source))
        [System.IO.File]::WriteAllText($script:f16Source, $script:f16SourceXml)
        $script:f16Items = @([pscustomobject]@{ RelativePath = 'Data\Platforms\Arcade.xml'; Before = (Get-TpmLaunchBoxFileState $script:f16Source); AfterHash = $null })
        $script:f16Incomplete = Join-Path $script:f16BackupRoot '.tpm-incomplete'
        Mock Test-LaunchBoxRunning { $false }
        Mock Get-TpmLaunchBoxBackupRoot { $BackupRoot }
    }

    It 'leaves no .tpm-incomplete folder after a successful snapshot when it did not exist before' {
        $backup = Backup-LaunchBoxFiles -lbRoot $script:f16LbRoot -Items $script:f16Items -BackupRoot $script:f16BackupRoot

        $backup.Verified | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $backup.Path 'Data\Platforms\Arcade.xml')) | Should -Be $script:f16SourceXml
        Test-Path -LiteralPath (Join-Path $backup.Path 'manifest.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:f16Incomplete | Should -BeFalse
        (@(Get-ChildItem -LiteralPath $script:f16BackupRoot -Force | ForEach-Object Name) -join '|') | Should -Be ([System.IO.Path]::GetFileName([string]$backup.Path))
    }

    It 'leaves a pre-existing empty .tpm-incomplete folder in place' {
        [void][System.IO.Directory]::CreateDirectory($script:f16Incomplete)

        $backup = Backup-LaunchBoxFiles -lbRoot $script:f16LbRoot -Items $script:f16Items -BackupRoot $script:f16BackupRoot

        $backup.Verified | Should -BeTrue
        Test-Path -LiteralPath $script:f16Incomplete -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:f16Incomplete -Force).Count | Should -Be 0
    }

    It 'leaves a pre-existing .tpm-incomplete folder and its evidence in place' {
        $attempt = Join-Path $script:f16Incomplete 'attempt'
        [void][System.IO.Directory]::CreateDirectory($attempt)
        $evidence = Join-Path $attempt 'evidence.txt'
        [System.IO.File]::WriteAllText($evidence, 'failed attempt evidence')
        $evidenceBefore = Get-Fix16FileSnapshot -Path $evidence

        $backup = Backup-LaunchBoxFiles -lbRoot $script:f16LbRoot -Items $script:f16Items -BackupRoot $script:f16BackupRoot

        $backup.Verified | Should -BeTrue
        (@(Get-ChildItem -LiteralPath $script:f16Incomplete -Force | ForEach-Object Name) -join '|') | Should -Be 'attempt'
        Get-Fix16FileSnapshot -Path $evidence | Should -Be $evidenceBefore
    }
}

Describe 'Top-level FIX16A flows' {
    It 'Finding D: first-run staging text no longer promises folder creation and Register only re-validates a chosen existing folder (structural)' {
        $script:fix16SourceText.Contains('will create the accepted folder') | Should -BeFalse

        $firstRunIfs = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            $_.Clauses[0].Item1.Extent.Text -eq '-not $gamesInstallFolder' -and
                (@(Get-Fix16StringValues -Root $_.Clauses[0].Item2) -match 'AutoSync creates it when it first extracts a game').Count -gt 0
        })
        $firstRunIfs.Count | Should -Be 1
        (@(Get-Fix16StringValues -Root $firstRunIfs[0].Clauses[0].Item2) -match 'Register only does not create it').Count | Should -BeGreaterThan 0

        # The Register only re-ask loop sits inside the top-level main menu
        # `while ($true)` loop, whose body also contains the R) string. Keep
        # only the innermost matching loop(s); a second, separate R) loop
        # would still fail the count below.
        $rLoops = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.WhileStatementAst]) | Where-Object {
            (@(Get-Fix16StringValues -Root $_.Body) | Where-Object { $_.Trim() -eq 'R) Choose an existing games folder' }).Count -gt 0
        })
        $loops = @($rLoops | Where-Object {
            $outer = $_
            @($rLoops | Where-Object {
                -not [object]::ReferenceEquals($_, $outer) -and (Test-Fix16Within -Node $_ -Container $outer.Body)
            }).Count -eq 0
        })
        $loops.Count | Should -Be 1
        $loop = $loops[0]
        $conditionTests = @(Get-Fix16Commands -Root $loop.Condition -Name 'Test-Path' | Where-Object {
            (Get-Fix16ParameterArgumentText -Command $_ -Name 'LiteralPath') -eq '$gamesInstallFolder' -and
                (Get-Fix16ParameterArgumentText -Command $_ -Name 'PathType') -eq 'Container'
        })
        $conditionTests.Count | Should -Be 1
        $choices = @(Get-Fix16Commands -Root $loop.Body -Name 'Read-TpmChoice')
        $choices.Count | Should -Be 1
        (Get-Fix16ParameterArgumentText -Command $choices[0] -Name 'Choices') | Should -Be "@('R', 'Q')"
        @(Get-Fix16Commands -Root $loop.Body -Name 'Read-TpmStagingFolder').Count | Should -Be 1
        @(Get-Fix16Commands -Root $loop.Body -Name 'New-Item').Count | Should -Be 0
        @(Get-Fix16Nodes -Root $loop.Body -Type ([System.Management.Automation.Language.InvokeMemberExpressionAst]) |
            Where-Object { $_.Member.Extent.Text -eq 'CreateDirectory' }).Count | Should -Be 0
    }

    It 'Finding E: LaunchBox [A] reuses the previewed folder and platform as defaults and still requires the exact-write Y/N (structural)' {
        $aBranches = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            $_.Clauses[0].Item1.Extent.Text -eq "`$lbChoice -eq 'A'"
        })
        $aBranches.Count | Should -Be 1
        $body = $aBranches[0].Clauses[0].Item2

        @(Get-Fix16Commands -Root $body -Name 'Read-HostSafe' | Where-Object {
            (Get-Fix16ParameterArgumentText -Command $_ -Name 'Default') -eq '$lbPreviewRoot'
        }).Count | Should -Be 1
        @(Get-Fix16Commands -Root $body -Name 'Read-TpmChoice' | Where-Object {
            (Get-Fix16ParameterArgumentText -Command $_ -Name 'Default') -eq '$platformDefault'
        }).Count | Should -Be 1

        $consentIfs = @(Get-Fix16Nodes -Root $body -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            @(Get-Fix16Commands -Root $_.Clauses[0].Item1 -Name 'Read-TpmYesNo' | Where-Object {
                (Get-Fix16ParameterArgumentText -Command $_ -Name 'Prompt') -eq "'Write exactly these changes after a verified backup? (Y/N)'" -and
                    (Get-Fix16ParameterArgumentText -Command $_ -Name 'Default') -eq "'N'"
            }).Count -eq 1
        })
        $consentIfs.Count | Should -Be 1
        $consentBody = $consentIfs[0].Clauses[0].Item2
        $writes = @(Get-Fix16Commands -Root $body -Name 'Invoke-LaunchBoxDirectWrite' | Where-Object { -not (Test-Fix16HasParameter -Command $_ -Name 'PlanOnly') })
        $writes.Count | Should -BeGreaterThan 0
        foreach ($write in $writes) {
            Test-Fix16Within -Node $write -Container $consentBody | Should -BeTrue
        }
    }

    It 'Finding K: startup re-offers saved settings only for a true first run without accepted settings and not unattended (structural)' {
        $dotSources = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.CommandAst]) | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot -and
                $_.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $_.CommandElements[0].VariablePath.UserPath -eq 'tpmOfferSavedConfig'
        })
        $unconditional = @($dotSources | Where-Object { $_.Parent.Parent -is [System.Management.Automation.Language.NamedBlockAst] })
        $unconditional.Count | Should -Be 1
        $reOffers = @($dotSources | Where-Object { $_.Parent.Parent -isnot [System.Management.Automation.Language.NamedBlockAst] })
        $reOffers.Count | Should -BeGreaterThan 0

        $guards = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            $operands = @(Get-Fix16AndOperandTexts -Expression $_.Clauses[0].Item1)
            ($operands -contains '$isTrueFirstRun') -and ($operands -contains '-not $configAccepted') -and ($operands -contains '-not $Unattended')
        })
        $guards.Count | Should -BeGreaterThan 0
        foreach ($reOffer in $reOffers) {
            @($guards | Where-Object { Test-Fix16Within -Node $reOffer -Container $_.Clauses[0].Item2 }).Count | Should -BeGreaterThan 0
        }
    }

    It 'ASTRA-08 caller: the invalid sync-state [K]/[R] prompt defaults to K and is skipped when unattended or previewing (structural)' {
        $prompts = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.IfStatementAst]) | Where-Object {
            @(Get-Fix16AndOperandTexts -Expression $_.Clauses[0].Item1) -contains "`$autoSyncStateCheck.Status -eq 'Invalid'"
        })
        $prompts.Count | Should -Be 1
        $prompt = $prompts[0]
        $operands = @(Get-Fix16AndOperandTexts -Expression $prompt.Clauses[0].Item1)
        $operands | Should -Contain '-not $Unattended'
        $operands | Should -Contain '-not $dryRunActive'

        $choices = @(Get-Fix16Commands -Root $prompt.Clauses[0].Item2 -Name 'Read-TpmChoice')
        $choices.Count | Should -Be 1
        (Get-Fix16ParameterArgumentText -Command $choices[0] -Name 'Choices') | Should -Be "@('K', 'R')"
        (Get-Fix16ParameterArgumentText -Command $choices[0] -Name 'Default') | Should -Be "'K'"

        $copies = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.CommandAst]) | Where-Object { $_.GetCommandName() -eq 'Save-TpmInvalidAutoSyncStateCopy' })
        $copies.Count | Should -BeGreaterThan 0
        foreach ($copy in $copies) { Test-Fix16Within -Node $copy -Container $prompt.Clauses[0].Item2 | Should -BeTrue }
        $authorizations = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.AssignmentStatementAst]) | Where-Object {
            $_.Left.Extent.Text -eq '$autoSyncRebuildInvalidState' -and $_.Right.Extent.Text -eq '$true'
        })
        $authorizations.Count | Should -BeGreaterThan 0
        foreach ($authorization in $authorizations) { Test-Fix16Within -Node $authorization -Container $prompt.Clauses[0].Item2 | Should -BeTrue }

        $syncCalls = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.CommandAst]) | Where-Object { $_.GetCommandName() -eq 'Invoke-AutoSync' })
        $syncCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $syncCalls) {
            (Get-Fix16ParameterArgumentText -Command $call -Name 'RebuildInvalidState') | Should -Be '$autoSyncRebuildInvalidState'
        }
    }
}

Describe 'FIX31e backup folder publish rename retries briefly held folders' {
    BeforeEach {
        $script:fx31eDir = Join-Path $TestDrive ('fx31e-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:fx31eDir -Force | Out-Null
        $script:fx31eSource = Join-Path $script:fx31eDir 'INCOMPLETE_Backup'
        $script:fx31eDestination = Join-Path $script:fx31eDir 'Backup'
        New-Item -ItemType Directory -Path $script:fx31eSource -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fx31eSource 'held.txt') -Value 'x' -Encoding ascii
    }

    It 'publishes the folder under its final name once a short-lived handle is released' {
        $held = Join-Path $script:fx31eSource 'held.txt'
        $ready = Join-Path $script:fx31eDir 'ready.flag'
        $job = Start-Job -ArgumentList $held, $ready -ScriptBlock {
            param($heldPath, $readyPath)
            $stream = [System.IO.File]::Open($heldPath, 'Open', 'Read', 'None')
            Set-Content -LiteralPath $readyPath -Value 'ready' -Encoding ascii
            Start-Sleep -Milliseconds 1500
            $stream.Dispose()
        }
        try {
            $deadline = (Get-Date).AddSeconds(30)
            while (-not (Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Test-Path -LiteralPath $ready | Should -BeTrue
            { Move-TpmDirectoryWithRetry -Source $script:fx31eSource -Destination $script:fx31eDestination -Attempts 60 -DelayMilliseconds 250 } | Should -Not -Throw
        }
        finally {
            Wait-Job -Job $job -Timeout 30 | Out-Null
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        Test-Path -LiteralPath $script:fx31eDestination | Should -BeTrue
        Test-Path -LiteralPath $script:fx31eSource | Should -BeFalse
    }

    It 'fails closed and leaves the folder under its INCOMPLETE_ name when the handle is never released' {
        $stream = [System.IO.File]::Open((Join-Path $script:fx31eSource 'held.txt'), 'Open', 'Read', 'None')
        try {
            { Move-TpmDirectoryWithRetry -Source $script:fx31eSource -Destination $script:fx31eDestination -Attempts 3 -DelayMilliseconds 10 } | Should -Throw
        }
        finally {
            $stream.Dispose()
        }
        Test-Path -LiteralPath $script:fx31eDestination | Should -BeFalse
        Test-Path -LiteralPath $script:fx31eSource | Should -BeTrue
    }
}

Describe 'FIX31i backup folder name stays short enough for long install paths (structural)' {
    It 'builds the backup folder name with an 8-character unique piece, not a full 32-character GUID' {
        $fn = @($script:fix16Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-TpmVerifiedUserProfilesBackup'
        }, $true))
        $fn.Count | Should -Be 1
        $text = $fn[0].Extent.Text
        $text | Should -Match "\[guid\]::NewGuid\(\)\.ToString\('N'\)\.Substring\(0,\s*8\)"
        $text | Should -Not -Match "\`$stamp,\[guid\]::NewGuid\(\)\.ToString\('N'\)\)"
    }
}

Describe 'FIX33 AutoSync moves and remaining backup names (structural)' {
    It 'routes the AutoSync move through the retry helper with both long paths' {
        $fn = @($script:fix16Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-TpmAutoSyncMovePath'
        }, $true))
        $fn.Count | Should -Be 1
        $calls = @(Get-Fix16Commands -Root $fn[0].Body -Name 'Move-TpmDirectoryWithRetry')
        $calls.Count | Should -Be 1
        (Get-Fix16ParameterArgumentText -Command $calls[0] -Name 'Source') | Should -Be '$sourceLong'
        (Get-Fix16ParameterArgumentText -Command $calls[0] -Name 'Destination') | Should -Be '$destinationLong'
        $fn[0].Extent.Text | Should -Not -Match '\[(?:System\.)?IO\.Directory\]::Move\s*\('
    }

    It 'builds the top-level AutoSync backup folder name with an 8-character unique piece' {
        $assignments = @(Get-Fix16TopLevelNodes -Type ([System.Management.Automation.Language.AssignmentStatementAst]) | Where-Object {
            $_.Left.Extent.Text -eq '$backupFinalPath'
        })
        $assignments.Count | Should -Be 1
        $text = $assignments[0].Right.Extent.Text
        $text | Should -Match "'AutoSync_\{0\}_\{1\}'"
        $text | Should -Match "\[guid\]::NewGuid\(\)\.ToString\('N'\)\.Substring\(0,\s*8\)"
        $text | Should -Not -Match "\`$timestamp,\s*\[guid\]::NewGuid\(\)\.ToString\('N'\)\)"
    }
}

Describe 'FIX33 verified backup short folder name behavior' {
    It 'creates a successful verified backup with the exact label, stamp and 8-hex leaf name' {
        $root = New-Fix16Dir -Prefix 'bn'
        $profiles = New-Fix16UserProfiles -Root $root

        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $profiles -Label 'ShortName'

        $backup.Succeeded | Should -BeTrue -Because ([string]$backup.Reason)
        $backup.Verified | Should -BeTrue
        $backup.Created | Should -BeTrue
        Test-Path -LiteralPath $backup.Path -PathType Container | Should -BeTrue
        [System.IO.Path]::GetDirectoryName([string]$backup.Path) | Should -Be (Join-Path $profiles 'FullBackup')
        [System.IO.Path]::GetFileName([string]$backup.Path) | Should -MatchExactly '^ShortName_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_\d{3}_[0-9a-f]{8}$'
    }
}