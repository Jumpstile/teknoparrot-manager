#Requires -Module Pester

# RC8 #347: progress counts show FINISHED work. Isolated, fake-only tests: temp directories, tiny synthetic
# files, and recording stand-ins for the progress module. The production script is parsed and only the
# functions under test are dot-sourced; nothing here starts the product, imports TpmProgress.psm1 or
# touches a real install.

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:sourcePath = Join-Path $script:repoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }

    function Get-Rc8S3FunctionText {
        param([string[]]$Name)
        $found = @($script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $Name
        }, $true))
        if ($found.Count -ne $Name.Count) { throw "Expected $($Name -join ', '); found $(@($found | ForEach-Object { $_.Name }) -join ', ')." }
        return (($found | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")
    }
}

Describe 'Write-TpmCompactExtractionProgress finished-count contract' {
    BeforeAll {
        # Recording stand-ins for the progress module; the real wrapper is the unit under test.
        function Import-TpmProgressModule {}
        function Test-TpmProgressActive { return [bool]$script:wrapperActive }
        function Test-TpmProgressGroupOwned { return [bool]$script:wrapperGroup }
        function Get-TpmProgressTitle { return $script:wrapperTitle }
        function Register-TpmProgressOutcome { param($State) }
        function Start-TpmProgressOperation {
            param($Title, $Stage, $Total, $Width, [switch]$Group)
            $script:wrapperActive = $true
            $script:wrapperTitle = $Title
            [void]$script:wrapperEvents.Add([pscustomobject]@{ Kind = 'Start'; Stage = $Stage; Current = $null; Total = $Total; State = $null })
        }
        function Set-TpmProgressStage {
            param([string]$Stage, [int]$Current, [int]$Total, [switch]$StageOnly, [switch]$SameStage)
            [void]$script:wrapperEvents.Add([pscustomobject]@{ Kind = 'Stage'; Stage = $Stage; Current = $Current; Total = $Total; State = $null })
        }
        function Complete-TpmProgressOperation {
            param($State = 'Final', $Message = '')
            [void]$script:wrapperEvents.Add([pscustomobject]@{ Kind = 'Complete'; Stage = $null; Current = $null; Total = $null; State = $State })
            $script:wrapperActive = $false
        }
        function Get-TpmProgressWidth {
            param([int]$Requested)
            if ($Requested -gt 0) { return $Requested }
            return 79
        }
        function Format-TpmProgressLine {
            param($Title, $Stage, $Current, $Total, $ElapsedSeconds, $Width)
            return ('{0}/{1}' -f $Current, $Total)
        }
        . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'Write-TpmCompactExtractionProgress')))
    }
    BeforeEach {
        $script:wrapperEvents = New-Object System.Collections.Generic.List[object]
        $script:wrapperActive = $false
        $script:wrapperGroup = $false
        $script:wrapperTitle = $null
    }

    It 'shows zero finished for the first item of a one-item loop instead of 100 percent' {
        Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Fixture' -Current 1 -Total 1
        $stage = @($script:wrapperEvents | Where-Object Kind -eq 'Stage')
        $stage.Count | Should -Be 1
        $stage[0].Current | Should -Be 0
        $stage[0].Total | Should -Be 1
    }

    It 'shows items-before-this-one as finished while item N of M is starting' {
        foreach ($n in 1..4) { Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current $n -Total 4 }
        @($script:wrapperEvents | Where-Object Kind -eq 'Stage' | ForEach-Object { $_.Current }) -join ',' | Should -Be '0,1,2,3'
    }

    It 'records a count that is already a finished count unchanged when -Completed is used' {
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Bytes' -Current 4096 -Total 8192 -Completed
        @($script:wrapperEvents | Where-Object Kind -eq 'Stage')[0].Current | Should -Be 4096
    }

    It 'does not interpret -Current when the total is unknown' {
        Write-TpmCompactExtractionProgress -Phase Scanning -Label 'Discovery' -Current 7 -Total 0
        $stage = @($script:wrapperEvents | Where-Object Kind -eq 'Stage')[0]
        $stage.Current | Should -Be 7
        $stage.Total | Should -Be 0
    }

    It 'never reports a negative finished count' {
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current 0 -Total 5
        @($script:wrapperEvents | Where-Object Kind -eq 'Stage')[0].Current | Should -Be 0
    }

    It 'records the full count only when a Final completion is reached, then closes Final' {
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current 3 -Total 3
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current 3 -Total 3 -Complete
        $kinds = @($script:wrapperEvents | ForEach-Object { $_.Kind })
        $kinds | Should -Be @('Start', 'Stage', 'Stage', 'Complete')
        $script:wrapperEvents[1].Current | Should -Be 2
        $script:wrapperEvents[2].Current | Should -Be 3
        $script:wrapperEvents[3].State | Should -Be 'Final'
    }

    It 'leaves the finished count short when the stage is closed as Error' {
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current 3 -Total 3
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Fixture' -Current 3 -Total 3 -Complete -Outcome Error
        @($script:wrapperEvents | Where-Object Kind -eq 'Stage' | ForEach-Object { $_.Current }) -join ',' | Should -Be '2'
        @($script:wrapperEvents | Where-Object Kind -eq 'Complete')[0].State | Should -Be 'Error'
    }

    It 'gives a group-owned stage its own finished count and total instead of text-only counts' {
        $script:wrapperActive = $true
        $script:wrapperGroup = $true
        Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Fixture' -Current 2 -Total 5
        $stage = @($script:wrapperEvents | Where-Object Kind -eq 'Stage')[0]
        $stage.Stage | Should -Be 'Repairing Fixture'
        $stage.Current | Should -Be 1
        $stage.Total | Should -Be 5
    }

    It 'returns display text built from the finished count' {
        (Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Fixture' -Current 2 -Total 5 -ReturnText) | Should -Be '1/5'
    }
}

Describe 'Invoke-TpmTransactionalPromote progress timing' {
    BeforeAll {
        function Write-Log { param([string]$Message) }
        function Assert-TpmNoReparseWriteTarget { param([string]$Path, [string]$Operation) }
        function Write-TpmCompactExtractionProgress {
            param([string]$Phase, [string]$Label, [int]$Current, [int]$Total, [datetime]$StartedAt, [int]$Width, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed)
            $present = $null
            if ($script:promoteProbeNames -and $script:promoteProbeDest) {
                $present = @($script:promoteProbeNames | Where-Object { Test-Path -LiteralPath (Join-Path $script:promoteProbeDest $_) }).Count
            }
            [void]$script:promoteEvents.Add([pscustomobject]@{ Kind = 'Progress'; Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome; PromotedPresent = $present })
        }
        # FIX29: rollback ownership proof uses the real identity/state helpers (no stand-ins).
        . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'Test-PathInside', 'Test-ExtractedFolderHasContent', 'Invoke-TpmTransactionalPromote', 'Assert-TpmWritePathsShortEnough', 'Test-TpmPathLengthAllowed', 'New-TpmNoChangeException', 'Get-TpmFileState', 'Get-TpmFileIdentityString', 'Resolve-TpmPromotedIdentity', 'Remove-TpmTreeOwnedFile', 'Clear-TpmTreeReadOnly', 'Get-TpmSupportNativeType', 'Remove-TpmSupportHandle')))

        function New-Rc8S3File {
            param([string]$Dir, [string]$Name, [string]$Content)
            [void][System.IO.Directory]::CreateDirectory($Dir)
            [System.IO.File]::WriteAllText((Join-Path $Dir $Name), $Content)
        }
    }
    BeforeEach {
        $script:promoteEvents = New-Object System.Collections.Generic.List[object]
        $script:promoteProbeNames = $null
        $script:promoteProbeDest = $null
    }

    It 'starts each staging item before its file is promoted, so the wrapper can show only finished items' {
        $staging = Join-Path $TestDrive ('rc8s3-stage-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ('rc8s3-dest-' + [guid]::NewGuid().ToString('N'))
        $names = @('a.txt', 'b.txt', 'c.txt')
        foreach ($n in $names) { New-Rc8S3File -Dir $staging -Name $n -Content ('NEW-' + $n) }
        $script:promoteProbeNames = $names
        $script:promoteProbeDest = $dest

        Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames $names | Should -BeTrue

        $starts = @($script:promoteEvents | Where-Object { $_.Label -eq 'Promotion staging' -and -not $_.Complete })
        $starts.Count | Should -Be 3
        foreach ($start in $starts) { $start.PromotedPresent | Should -Be ($start.Current - 1) }
        $done = @($script:promoteEvents | Where-Object { $_.Label -eq 'Promotion staging' -and $_.Complete })
        $done.Count | Should -Be 1
        $done[0].Outcome | Should -Be 'Final'
        $done[0].PromotedPresent | Should -Be 3
    }

    It 'runs the commit callback inside its own stage that completes only after the callback succeeds' {
        $staging = Join-Path $TestDrive ('rc8s3-stage-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ('rc8s3-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3File -Dir $staging -Name 'a.txt' -Content 'NEW-A'
        $commit = { [void]$script:promoteEvents.Add([pscustomobject]@{ Kind = 'Commit' }) }

        Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt') -CommitAction $commit | Should -BeTrue

        $order = @($script:promoteEvents | ForEach-Object {
            if ($_.Kind -eq 'Commit') { 'commit-ran' }
            elseif ($_.Label -eq 'Promotion staging' -and $_.Complete) { 'staging-done' }
            elseif ($_.Label -eq 'Promotion commit' -and -not $_.Complete) { 'commit-stage-open' }
            elseif ($_.Label -eq 'Promotion commit' -and $_.Complete) { 'commit-stage-' + $_.Outcome }
        })
        $order | Should -Be @('staging-done', 'commit-stage-open', 'commit-ran', 'commit-stage-Final')
    }

    It 'closes the commit stage as Error and restores the destination when the commit callback fails' {
        $staging = Join-Path $TestDrive ('rc8s3-stage-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ('rc8s3-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3File -Dir $dest -Name 'a.txt' -Content 'OLD-A'
        New-Rc8S3File -Dir $staging -Name 'a.txt' -Content 'NEW-A'
        $commit = { throw 'fixture commit failure' }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt') -CommitAction $commit } | Should -Throw '*fixture commit failure*'

        [System.IO.File]::ReadAllText((Join-Path $dest 'a.txt')) | Should -Be 'OLD-A'
        $commitClose = @($script:promoteEvents | Where-Object { $_.Label -eq 'Promotion commit' -and $_.Complete })
        $commitClose.Count | Should -Be 1
        $commitClose[0].Outcome | Should -Be 'Error'
    }

    It 'closes the failed promotion stage as Error and never completes it as Final' {
        $staging = Join-Path $TestDrive ('rc8s3-stage-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ('rc8s3-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3File -Dir $dest -Name 'a.txt' -Content 'OLD-A'
        New-Rc8S3File -Dir $staging -Name 'a.txt' -Content 'NEW-A'
        New-Rc8S3File -Dir $staging -Name 'b.txt' -Content 'NEW-B'
        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like '*b.txt') { throw 'simulated promotion failure on b.txt' }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt') } | Should -Throw '*simulated promotion failure on b.txt*'

        [System.IO.File]::ReadAllText((Join-Path $dest 'a.txt')) | Should -Be 'OLD-A'
        $stagingClose = @($script:promoteEvents | Where-Object { $_.Label -eq 'Promotion staging' -and $_.Complete })
        $stagingClose.Count | Should -Be 1
        $stagingClose[0].Outcome | Should -Be 'Error'
    }

    It 'does not report a failed rollback when the copy landed but the original could not be removed' {
        # Mutation: record the file as moved aside when only the copy succeeded -> rollback finds the original still in place and throws "ROLLBACK FAILED ... INCONSISTENT".
        $staging = Join-Path $TestDrive ('rc8s3-stage-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ('rc8s3-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3File -Dir $dest -Name 'a.txt' -Content 'OLD-A'
        New-Rc8S3File -Dir $staging -Name 'a.txt' -Content 'NEW-A'
        # A move across drives is copy then delete: the copy is made, the delete fails.
        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($Destination -like '*.tpm-rollback-backup*') {
                [System.IO.File]::Copy($LiteralPath, $Destination, $true)
                throw 'simulated: the original could not be deleted'
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        $thrown = $null
        try { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt') } catch { $thrown = [string]$_.Exception.Message }

        $thrown | Should -Match 'the original could not be deleted'
        $thrown | Should -Not -Match 'ROLLBACK FAILED|INCONSISTENT'
        [System.IO.File]::ReadAllText((Join-Path $dest 'a.txt')) | Should -Be 'OLD-A'
    }
}

Describe 'Expand-ZipFileSafe progress close count' {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function Write-TpmCompactExtractionProgress {
            param([string]$Phase, [string]$Label, [int]$Current, [int]$Total, [datetime]$StartedAt, [int]$Width, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed)
            [void]$script:zipProgressEvents.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome })
        }
        . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'ConvertTo-SafeZipEntryRelativePath', 'Expand-ZipFileSafe')))

        function New-Rc8S3Zip {
            param([string]$Path, [string[]]$Names)
            $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($n in $Names) {
                    $entry = $zip.CreateEntry($n)
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write('x-' + $n) } finally { $writer.Dispose() }
                }
            } finally { $zip.Dispose() }
        }
    }
    BeforeEach { $script:zipProgressEvents = New-Object System.Collections.Generic.List[object] }

    It 'closes with every file counted after a complete extraction' {
        $zipPath = Join-Path $TestDrive ('rc8s3-ok-' + [guid]::NewGuid().ToString('N') + '.zip')
        $dest = Join-Path $TestDrive ('rc8s3-ok-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3Zip -Path $zipPath -Names @('a.txt', 'b.txt')

        Expand-ZipFileSafe -ZipPath $zipPath -DestDir $dest -GameName 'Fixture'

        $close = @($script:zipProgressEvents | Where-Object Complete)
        $close.Count | Should -Be 1
        $close[0].Current | Should -Be 2
        $close[0].Total | Should -Be 2
    }

    It 'closes one short when the second file cannot be written' {
        $zipPath = Join-Path $TestDrive ('rc8s3-fail-' + [guid]::NewGuid().ToString('N') + '.zip')
        $dest = Join-Path $TestDrive ('rc8s3-fail-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8S3Zip -Path $zipPath -Names @('a.txt', 'b.txt')
        [void][System.IO.Directory]::CreateDirectory($dest)
        $lock = [System.IO.File]::Open((Join-Path $dest 'b.txt'), [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            { Expand-ZipFileSafe -ZipPath $zipPath -DestDir $dest -GameName 'Fixture' } | Should -Throw
        } finally { $lock.Dispose() }

        $close = @($script:zipProgressEvents | Where-Object Complete)
        $close.Count | Should -Be 1
        $close[0].Current | Should -Be 1
        $close[0].Total | Should -Be 2
    }
}

Describe 'ConvertTo-TpmLegacyTransactionResult error count' {
    BeforeAll {
        function New-TpmProfileTransactionResult {
            param([Parameter(ValueFromRemainingArguments = $true)]$Ignored)
            $tx = [pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; Errors = [string[]]@() }
            $tx.PSObject.TypeNames.Insert(0, 'TPM.TransactionResult.v1')
            return $tx
        }
        . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'ConvertTo-TpmLegacyTransactionResult')))
    }

    It 'exposes a legacy integer Errors as ErrorCount and never formats the string[] Errors' {
        $tx = ConvertTo-TpmLegacyTransactionResult -Legacy ([pscustomobject]@{ Succeeded = $false; Errors = 3 }) -WorkflowKey 'W' -OperationKey 'O'
        $tx.ErrorCount | Should -Be 3
        ('{0}' -f $tx.ErrorCount) | Should -Be '3'
    }
    It 'counts an array-valued legacy Errors' {
        $tx = ConvertTo-TpmLegacyTransactionResult -Legacy ([pscustomobject]@{ Succeeded = $false; Errors = @('a', 'b') }) -WorkflowKey 'W' -OperationKey 'O'
        $tx.ErrorCount | Should -Be 2
    }
    It 'reports zero when the legacy result has no Errors' {
        $tx = ConvertTo-TpmLegacyTransactionResult -Legacy ([pscustomobject]@{ Succeeded = $true }) -WorkflowKey 'W' -OperationKey 'O'
        $tx.ErrorCount | Should -Be 0
    }
}

Describe 'Test-TpmGameMutationPath empty path' {
    BeforeAll { . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'Test-TpmGameMutationPath'))) }

    It 'returns an EMPTY_PATH result instead of a parameter-binding exception' {
        $result = Test-TpmGameMutationPath -GamePath ''
        $result.Valid | Should -BeFalse
        $result.ReasonCode | Should -Be 'EMPTY_PATH'
    }
}

Describe 'Get-BepInExInspectionFailure technical detail' {
    BeforeAll { . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'Get-BepInExInspectionFailure'))) }

    It 'carries the message, not a raw .NET type name' {
        $failure = Get-BepInExInspectionFailure -ErrorRecord ([System.Exception]::new('The executable is missing or unreadable.')) -ArchitectureState UNKNOWN
        $failure.Code | Should -Be 'UNKNOWN_ARCHITECTURE'
        $failure.Technical | Should -Be 'The executable is missing or unreadable.'
        $failure.Technical | Should -Not -Match 'System\.'
    }
}

Describe 'Set-TpmLaunchBoxFile concurrent-edit guard' {
    BeforeAll {
        function Write-Log { param([string]$Message) }
        function Assert-TpmNoReparseWriteTarget { param([string]$Path, [string]$Operation) }
        . ([scriptblock]::Create((Get-Rc8S3FunctionText -Name 'Restore-TpmLaunchBoxReplacedFile', 'Invoke-TpmLaunchBoxReplace', 'Restore-TpmLaunchBoxDisplacedFile', 'Set-TpmLaunchBoxFile')))
    }

    It 'replaces the file when the replaced bytes are the verified original' {
        $dir = Join-Path $TestDrive ('rc8s3-lb-ok-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        $target = Join-Path $dir 'Platforms.xml'; $stage = Join-Path $dir 'stage.tmp'
        [System.IO.File]::WriteAllText($target, 'ORIGINAL'); [System.IO.File]::WriteAllText($stage, 'NEW')
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

        Set-TpmLaunchBoxFile -StagePath $stage -Path $target -Exists $true -ExpectedOriginalHash $hash

        [System.IO.File]::ReadAllText($target) | Should -Be 'NEW'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.replaced').Count | Should -Be 0
    }

    It 'keeps the replaced bytes and fails when the file differs from the verified original' {
        $dir = Join-Path $TestDrive ('rc8s3-lb-race-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        $target = Join-Path $dir 'Platforms.xml'; $stage = Join-Path $dir 'stage.tmp'
        [System.IO.File]::WriteAllText($target, 'EDITED-BY-LAUNCHBOX'); [System.IO.File]::WriteAllText($stage, 'NEW')
        $staleHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes('ORIGINAL'))) -Algorithm SHA256).Hash

        { Set-TpmLaunchBoxFile -StagePath $stage -Path $target -Exists $true -ExpectedOriginalHash $staleHash } | Should -Throw '*retained at*'

        $kept = @(Get-ChildItem -LiteralPath $dir -Filter '*.replaced')
        $kept.Count | Should -Be 1
        [System.IO.File]::ReadAllText($kept[0].FullName) | Should -Be 'EDITED-BY-LAUNCHBOX'
    }
}
