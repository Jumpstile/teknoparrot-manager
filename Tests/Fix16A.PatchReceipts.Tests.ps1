#Requires -Module Pester

# FIX16A / ASTRA-07: required-patch receipts are published atomically and follow
# a grouped transaction from Prepared to Applied to Restored. The engine is
# dot-sourced like the other TpmRequiredPatch tests; manager helpers are
# extracted from the parsed script.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for receipt tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    function Get-Fix16AIdentity {
        param([Parameter(Mandatory)][string]$Path)
        $stream = Open-TpmPatchCreationFile $Path
        try { return [TpmSupportNativeMethods]::PatchFileIdentity($stream.SafeFileHandle) } finally { $stream.Dispose() }
    }

    function Get-Fix16ATemps {
        param([Parameter(Mandatory)][string]$Directory)
        return @(Get-ChildItem -LiteralPath $Directory -File -Filter 'receipt.json.*.tmp' -ErrorAction Stop)
    }

    function New-Fix16ARunDirectory {
        param([Parameter(Mandatory)][string]$Name)
        $directory = Join-Path (Join-Path $TestDrive $Name) ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        return $directory
    }

    function Get-Fix16ABytesSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }

    # Reads the on-disk State of the single transaction run under a recovery root.
    # Used from ValidationAction callbacks, which the engine invokes between its
    # receipt revisions, so the published Prepared revision can be observed.
    function Get-Fix16ARunReceiptState {
        param([Parameter(Mandatory)][string]$Root)
        $runs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop | Where-Object { $_.Name -cmatch '^[a-f0-9]{32}$' })
        if ($runs.Count -eq 0) { return 'NoRun' }
        if ($runs.Count -ne 1) { return 'MultipleRuns' }
        $path = Join-Path $runs[0].FullName 'receipt.json'
        if (-not [IO.File]::Exists($path)) { return 'NoReceipt' }
        return [string]([IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop).State
    }

    # Smallest real catalog fixture: schema 3 with one ReplaceFile plus one CreateFile (grouped MultiFile lane).
    function New-Fix16ACatalogCase {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'
        $parent = Join-Path $game 'd'
        $payload = Join-Path $root 'p'
        $recovery = Join-Path $root 'r'
        $protected = Join-Path $root 'x'
        foreach ($directory in @($parent,$payload,$recovery,$protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exeBytes = [Text.Encoding]::ASCII.GetBytes('fix16a synthetic executable; never run')
        [IO.File]::WriteAllBytes((Join-Path $game 's.exe'), $exeBytes)
        $createBytes = [Text.Encoding]::ASCII.GetBytes('fix16a cycle created payload')
        [IO.File]::WriteAllBytes((Join-Path $payload 'c.bin'), $createBytes)
        $createHash = Get-Fix16ABytesSha256 $createBytes
        $create = [pscustomobject]@{Type='CreateFile'; Target='d/c.bin'; BeforeState='Absent'; AfterSha256=$createHash; Payload='c.bin'; PayloadSha256=$createHash}
        $beforeBytes = [Text.Encoding]::ASCII.GetBytes('fix16a cycle settings before')
        $afterBytes = [Text.Encoding]::ASCII.GetBytes('fix16a cycle settings after')
        [IO.File]::WriteAllBytes((Join-Path $parent 's.ini'), $beforeBytes)
        [IO.File]::WriteAllBytes((Join-Path $payload 's.new'), $afterBytes)
        $beforeHash = Get-Fix16ABytesSha256 $beforeBytes
        $afterHash = Get-Fix16ABytesSha256 $afterBytes
        $replace = [pscustomobject]@{Type='ReplaceFile'; Target='d/s.ini'; BeforeSha256=$beforeHash; AfterSha256=$afterHash; Payload='s.new'; PayloadSha256=$afterHash}
        $entry = [pscustomobject]@{
            Id='fix16a.cycle.group'; ProfileId='Fix16A'; Executable='s.exe'; ExecutableSha256=(Get-Fix16ABytesSha256 $exeBytes)
            SourceUrl='https://example.invalid/fix16a'; SourceRevision=('B' * 40); ExclusiveGroup=''; Operations=@($replace,$create)
        }
        $content = [pscustomobject]@{Schema=3; Entries=@($entry)} | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); PatchId=$entry.Id; ProfileId='Fix16A'
            GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected)
        }
        return [pscustomobject]@{
            Inputs=$inputs; Recovery=$recovery; Parent=$parent; CreateTarget=(Join-Path $parent 'c.bin'); CreateHash=$createHash
            SettingsTarget=(Join-Path $parent 's.ini'); BeforeHash=$beforeHash; AfterHash=$afterHash
        }
    }
}

Describe 'FIX16A atomic receipt publication' {
    It 'publishes a first receipt without overwrite and leaves no temporary file' {
        $run = New-Fix16ARunDirectory 'w1'
        Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w1'; State='Prepared'})
        $published = [IO.File]::ReadAllText((Join-Path $run 'receipt.json')) | ConvertFrom-Json
        $published.State | Should -BeExactly 'Prepared'
        @(Get-Fix16ATemps $run).Count | Should -Be 0
    }

    It 'replaces an existing receipt through Prepared, Applied and Restored revisions and leaves no temporary file' {
        $run = New-Fix16ARunDirectory 'w2'
        $path = Join-Path $run 'receipt.json'
        foreach ($state in @('Prepared','Applied','Restored')) {
            Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w2'; State=$state})
            $published = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            $published.State | Should -BeExactly $state -Because ('the ' + $state + ' revision must be the published receipt')
            $published.TransactionId | Should -BeExactly 'w2'
            @(Get-Fix16ATemps $run).Count | Should -Be 0 -Because ('no temp may remain after the ' + $state + ' revision')
            (@(Get-ChildItem -LiteralPath $run -Force | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly 'receipt.json'
        }
    }

    It 'keeps the previous receipt when serialization fails' {
        $run = New-Fix16ARunDirectory 'w4'
        Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w4'; State='Prepared'})
        $before = [IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))
        Mock ConvertTo-Json { throw 'injected serialization failure' }
        { Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w4'; State='Applied'}) } | Should -Throw -ExpectedMessage '*injected serialization failure*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($before))
        @(Get-Fix16ATemps $run).Count | Should -Be 0
    }

    It 'keeps the previous receipt and deletes only its own temp when readback validation fails' {
        $run = New-Fix16ARunDirectory 'w5'
        Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w5'; State='Prepared'})
        $before = [IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))
        Mock ConvertFrom-Json { [pscustomobject]@{State='Tampered'} }
        { Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w5'; State='Applied'}) } | Should -Throw -ExpectedMessage '*readback validation*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($before))
        @(Get-Fix16ATemps $run).Count | Should -Be 0
    }

    It 'keeps the previous receipt and deletes only its own temp when the atomic replace fails' {
        $run = New-Fix16ARunDirectory 'w6'
        $path = Join-Path $run 'receipt.json'
        Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w6'; State='Prepared'})
        $before = [IO.File]::ReadAllBytes($path)
        $failure = $null
        $holder = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            try { Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w6'; State='Applied'}) } catch { $failure = $_ }
        } finally { $holder.Dispose() }
        $failure | Should -Not -BeNullOrEmpty -Because 'a receipt held open without sharing must refuse the replace'
        # The refusal must come from the locked target (sharing violation), not from
        # argument validation before File.Replace touches any file.
        $baseException = $failure.Exception.GetBaseException()
        $baseException | Should -Not -BeOfType ([System.ArgumentException])
        $baseException | Should -BeOfType ([System.IO.IOException])
        $baseException.HResult | Should -Be (-2147024864)
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly ([Convert]::ToBase64String($before))
        @(Get-Fix16ATemps $run).Count | Should -Be 0
    }

    It 'never overwrites or deletes a pre-existing colliding temporary file' {
        $run = New-Fix16ARunDirectory 'w7'
        $path = Join-Path $run 'receipt.json'
        Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w7'; State='Prepared'})
        $before = [IO.File]::ReadAllBytes($path)
        $script:fix16aCollision = Join-Path $run ('receipt.json.' + ('a' * 32) + '.tmp')
        [IO.File]::WriteAllText($script:fix16aCollision, 'foreign temp', (New-Object Text.UTF8Encoding($false)))
        Mock Join-Path -ParameterFilter { $ChildPath -like 'receipt.json.*.tmp' } -MockWith { $script:fix16aCollision }
        { Write-TpmPatchCreationReceipt $run ([ordered]@{Schema=2; TransactionId='w7'; State='Applied'}) } | Should -Throw
        [IO.File]::ReadAllText($script:fix16aCollision) | Should -BeExactly 'foreign temp'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly ([Convert]::ToBase64String($before))
        @(Get-Fix16ATemps $run).Count | Should -Be 1
    }
}

Describe 'FIX16A receipt revisions through a real grouped transaction' {
    It 'publishes Prepared then Applied for a real grouped apply and Restored for its undo' {
        $case = New-Fix16ACatalogCase 'm1'
        $inputs = $case.Inputs
        $fix16aRecovery = $case.Recovery
        $fix16aSeen = New-Object 'System.Collections.Generic.List[string]'
        $recorder = { $fix16aSeen.Add((Get-Fix16ARunReceiptState -Root $fix16aRecovery)) }
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse

        $applied = Invoke-TpmCatalogPatch @inputs -ValidationAction $recorder -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        $run = $applied.RecoveryDirectory
        $receiptPath = Join-Path $run 'receipt.json'
        # Preflight may run before any run folder exists; later validations see the published
        # Prepared receipt first and the Applied revision that replaced it last.
        (@($fix16aSeen | Where-Object { $_ -cne 'NoRun' } | Select-Object -Unique) -join ',') | Should -BeExactly 'Prepared,Applied'
        $fix16aSeen[$fix16aSeen.Count - 1] | Should -BeExactly 'Applied'
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        $receipt.State | Should -BeExactly 'Applied'
        $receipt.Schema | Should -Be 3
        $receipt.TransactionId | Should -BeExactly ([IO.Path]::GetFileName($run))
        @($receipt.Operations).Count | Should -Be 2
        $receipt.Operations[0].Type | Should -BeExactly 'ReplaceFile'
        $receipt.Operations[1].Type | Should -BeExactly 'CreateFile'
        $receipt.Operations[0].AfterFileIdentity | Should -BeExactly (Get-Fix16AIdentity $case.SettingsTarget)
        $receipt.Operations[1].AfterFileIdentity | Should -BeExactly (Get-Fix16AIdentity $case.CreateTarget)
        (Get-FileHash -LiteralPath $receipt.Operations[0].Backup -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.AfterHash
        (Get-FileHash -LiteralPath $case.CreateTarget -Algorithm SHA256).Hash | Should -BeExactly $case.CreateHash
        @(Get-Fix16ATemps $run).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $run -File -Filter 'receipt.json*' -Force).Count | Should -Be 1
        (@(Get-ChildItem -LiteralPath $case.Parent -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|') | Should -BeExactly 'c.bin|s.ini'
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'AlreadyApplied'

        $fix16aSeen.Clear()
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $run -ValidationAction $recorder -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        (@($fix16aSeen | Select-Object -Unique) -join ',') | Should -BeExactly 'Applied,Restored'
        $restored = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        $restored.State | Should -BeExactly 'Restored'
        $restored.TransactionId | Should -BeExactly $receipt.TransactionId
        $restored.Operations[0].RestoredFileIdentity | Should -BeExactly (Get-Fix16AIdentity $case.SettingsTarget)
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse
        (@(Get-ChildItem -LiteralPath $case.Parent -Force | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly 's.ini'
        (Get-FileHash -LiteralPath $restored.Operations[0].Backup -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        @(Get-Fix16ATemps $run).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $run -File -Filter 'receipt.json*' -Force).Count | Should -Be 1
        $manifestPath = Join-Path (Join-Path (Join-Path (Join-Path $case.Recovery 'ReceiptHistory') 'Snapshots') ($receipt.TransactionId + '_Restored')) 'manifest.json'
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        @($manifest.Paths)[0].Sha256 | Should -BeExactly (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
    }
}
