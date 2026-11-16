#Requires -Module Pester
# FIX85: the safety review of the ReShade undo receipts (FIX68). An undo receipt is only trusted when it belongs to its game and lists
# only files inside the folders it recorded, with no link on any path; a receipt that is damaged, missing, empty, of an unknown format,
# foreign or pointing outside the game is refused and left as it is. A receipt of a change that went wrong after the deployment is
# finished (or removed when nothing changed), a game left half changed by a failed rollback is not called ready, a game with changed
# files can have only its unchanged files put back (typed YES, never overwriting a changed file), and the Undo list stays short.
# These tests drive the real product functions with synthetic game folders in $TestDrive; nothing touches TeknoParrot, LaunchBox, the
# registry, services or the network. The reparse-point tests use a real junction and do NOT mock Test-TpmNoReparsePath.
# Each It names the product change that makes it fail.
# What this CANNOT prove: how a real console paints the Undo list, and a real ReShade install with downloaded effects.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f85Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX85 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix85-functions.ps1'
    ($script:f85Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    # The caller's own global Unattended (if any) is put back after each test instead of being removed.
    $savedUnattended = Get-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
    $script:f85SavedUnattended = [pscustomobject]@{ Exists = ($null -ne $savedUnattended); Value = $(if ($null -ne $savedUnattended) { $savedUnattended.Value } else { $null }) }
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix85.log'
    $script:logWarnShown = $false
    $script:F85Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:f85RealSave = (Get-Command -Name Save-TpmReShadeUndoReceipt -CommandType Function).ScriptBlock
    $script:f85RealText = (Get-Command -Name Write-TpmText -CommandType Function).ScriptBlock

    function New-F85Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # Writes the text as UTF-8 bytes (no BOM); $null deletes the file.
    function Set-F85File {
        param([string]$Path, $Text)
        if ($null -eq $Text) {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            return
        }
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllBytes($Path, $script:F85Utf8.GetBytes([string]$Text))
    }
    function Get-F85Bytes {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<absent>' }
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    # One finished change of a game: Before (file name -> text, $null = absent) is written, the receipt is made, After is written, the
    # receipt is finished. The receipt may touch the game folder only.
    function New-F85Change {
        param(
            [string]$StateRoot, [string]$GameDir, [string]$GameId, [hashtable]$Before = @{}, [hashtable]$After = @{},
            [string]$Operation = 'Install', [string]$LookBefore = 'None', [string]$LookAfter = 'FastCrt', [string]$OwnerBefore = 'None'
        )
        foreach ($name in @($Before.Keys)) { Set-F85File -Path (Join-Path $GameDir $name) -Text $Before[$name] }
        $paths = @(@(@($Before.Keys) + @($After.Keys)) | Sort-Object -Unique | ForEach-Object { Join-Path $GameDir $_ })
        $request = New-TpmReShadeUndoRequest -GameId $GameId -GameName ('Game ' + $GameId) -Operation $Operation -LookBefore $LookBefore -LookAfter $LookAfter -OwnerBefore $OwnerBefore -StateRoot $StateRoot
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths $paths -Roots @($GameDir)
        if (-not $undo.Succeeded) { throw ('fixture: the receipt was not made: ' + $undo.Reason) }
        foreach ($name in @($After.Keys)) { Set-F85File -Path (Join-Path $GameDir $name) -Text $After[$name] }
        if ((Complete-TpmReShadeUndoReceipt -Undo $undo) -cne 'Ready') { throw 'fixture: the receipt was not finished' }
        # Receipt folders and rows are ordered by their time; keep two changes apart.
        Start-Sleep -Milliseconds 25
        return $undo
    }
    function Get-F85Entry {
        param([string]$StateRoot, [string]$GameId)
        return @(Get-TpmReShadeUndoEntries -StateRoot $StateRoot | Where-Object { $_.GameId -eq $GameId })[0]
    }
    # Damages receipt.json the way a failure or a hand edit would. Kind names the damage; Game and Outside are folders of the fixture.
    function Invoke-F85Damage {
        param([string]$Folder, [string]$Kind, [string]$Game = '', [string]$Outside = '')
        $path = Join-Path $Folder 'receipt.json'
        switch ($Kind) {
            'corrupt' { [IO.File]::WriteAllText($path, '{ not json at all'); return }
            'empty' { [IO.File]::WriteAllText($path, ''); return }
            'missing' { Remove-Item -LiteralPath $path -Force; return }
        }
        $receipt = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($Kind -in @('outside', 'dotdot')) {
            $victim = Join-Path $Outside 'victim.txt'
            $reach = [pscustomobject]@{ Path = $victim; BeforeExists = $false; BeforeSha256 = ''; BeforeLength = $null; Payload = ''; AfterExists = $true; AfterSha256 = ((Get-FileHash -LiteralPath $victim -Algorithm SHA256).Hash); AfterLength = 8 }
            if ($Kind -eq 'dotdot') { $reach.Path = (Join-Path $Game '..\..') + '\' + (Split-Path -Leaf $Outside) + '\victim.txt' }
            $receipt.Files = @($receipt.Files) + @($reach)
        }
        switch ($Kind) {
            'schema' { $receipt.Schema = 'TPM.ReShadeUndoReceipt.v2' }
            'state' { $receipt.State = 'Done' }
            'nofiles' { $receipt.Files = @() }
            'drive' { $receipt.Roots = @([IO.Path]::GetPathRoot([string]$receipt.Roots[0])) }
            'noroots' { $receipt.Roots = @() }
            'relative' { $receipt.Files[0].Path = 'dxgi.dll' }
        }
        [IO.File]::WriteAllText($path, ($receipt | ConvertTo-Json -Depth 6), $script:F85Utf8)
    }
    function Get-F85Text {
        param($Rows)
        return ((@($Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ')
    }
    # The most text lines in a row with no blank line between them. Every Write-TpmText call writes a '<<TEXT>>' marker row first (see the
    # mock in the width tests), so a wrapped sentence counts once, at any console width.
    function Get-F85TextRun {
        param([string[]]$Rows)
        $longest = 0
        $run = 0
        foreach ($row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($row)) { $run = 0; continue }
            if ($row.Trim() -ceq '<<TEXT>>') { $run++; if ($run -gt $longest) { $longest = $run } }
        }
        return $longest
    }
}

Describe 'FIX85 a receipt that cannot be trusted is refused and left as it is' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        $script:f85State = New-F85Root 'state'
        $script:f85Games = New-F85Root 'games'
        $script:f85Game = Join-Path $script:f85Games 'G'
        $script:f85Outside = New-F85Root 'outside'
        Set-F85File -Path (Join-Path $script:f85Outside 'victim.txt') -Text 'precious'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $script:f85Game -GameId 'G' -Before @{ 'ReShade.ini' = 'own'; 'dxgi.dll' = $null } -After @{ 'ReShade.ini' = 'tpm'; 'dxgi.dll' = 'tpm-dll' })
        $script:f85Entry = Get-F85Entry -StateRoot $script:f85State -GameId 'G'
    }

    It 'refuses a receipt that is <Case> and changes nothing' -ForEach @(
        @{ Case = 'corrupt'; Kind = 'corrupt' }
        @{ Case = 'empty'; Kind = 'empty' }
        @{ Case = 'missing its receipt.json'; Kind = 'missing' }
        @{ Case = 'of an unknown schema'; Kind = 'schema' }
        @{ Case = 'of an unknown state'; Kind = 'state' }
        @{ Case = 'listing no files'; Kind = 'nofiles' }
    ) {
        # Mutation: trust receipt.json without the checks (or treat a missing/empty file as "nothing to check") -> the status is not ReceiptDamaged, or a file changes.
        $folder = [string]$script:f85Entry.Folder
        Invoke-F85Damage -Folder $folder -Kind $Kind
        $iniBefore = Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')
        $dllBefore = Get-F85Bytes (Join-Path $script:f85Game 'dxgi.dll')
        $jsonBefore = Get-F85Bytes (Join-Path $folder 'receipt.json')
        (Read-TpmReShadeUndoReceipt -Folder $folder -VerifyPayload).Valid | Should -BeFalse
        $result = Invoke-TpmReShadeUndo -Entry $script:f85Entry
        $result.Status | Should -BeExactly 'ReceiptDamaged'
        $result.Code | Should -BeExactly 'UNDO_RECEIPT_DAMAGED'
        (Get-TpmPlainReason -Code $result.Code).Text | Should -BeExactly 'This undo copy cannot be used, so nothing was changed.'
        (Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly $iniBefore
        (Get-F85Bytes (Join-Path $script:f85Game 'dxgi.dll')) | Should -BeExactly $dllBefore
        (Get-F85Bytes (Join-Path $folder 'receipt.json')) | Should -BeExactly $jsonBefore -Because 'a refused receipt is left untouched'
        Test-Path -LiteralPath (Join-Path $folder 'payload') | Should -BeTrue
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f85State).Count | Should -Be 0 -Because 'a receipt that cannot be used is not offered'
    }

    It 'refuses a receipt with <Case> and does not touch the file outside the game' -ForEach @(
        @{ Case = 'a file outside the game folder'; Kind = 'outside'; Pattern = 'outside the folders' }
        @{ Case = 'a path that leaves the game folder with ..'; Kind = 'dotdot'; Pattern = 'outside the folders' }
        @{ Case = 'a whole drive as the recorded folder'; Kind = 'drive'; Pattern = 'whole drive' }
        @{ Case = 'no recorded folder'; Kind = 'noroots'; Pattern = 'records no folder' }
        @{ Case = 'a path that is not complete'; Kind = 'relative'; Pattern = 'not complete' }
    ) {
        # Mutation: check only that a path is rooted (the FIX68 behavior) -> the file outside the game is removed by the undo, or the receipt is trusted.
        $folder = [string]$script:f85Entry.Folder
        Invoke-F85Damage -Folder $folder -Kind $Kind -Game $script:f85Game -Outside $script:f85Outside
        $victim = Join-Path $script:f85Outside 'victim.txt'
        $read = Read-TpmReShadeUndoReceipt -Folder $folder
        $read.Valid | Should -BeFalse
        $read.Reason | Should -Match $Pattern
        $result = Invoke-TpmReShadeUndo -Entry $script:f85Entry
        $result.Status | Should -BeExactly 'ReceiptDamaged'
        [IO.File]::ReadAllText($victim) | Should -BeExactly 'precious'
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly 'tpm'
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
    }

    It 'refuses a receipt that belongs to another game, even when its files are valid' {
        # Mutation: do not compare the SHA-256 of the GameId with the name of the game folder -> the copied receipt of game G undoes G from the folder of game H.
        $other = Join-Path $script:f85Games 'H'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $other -GameId 'H' -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' })
        $foreign = Join-Path (Get-TpmReShadeUndoGameFolder -GameId 'H' -StateRoot $script:f85State) ('99990101T000000000Z_' + ('f' * 8))
        Copy-Item -LiteralPath ([string]$script:f85Entry.Folder) -Destination $foreign -Recurse
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f85State | ForEach-Object { $_.GameId } | Sort-Object) | Should -Be @('G', 'H') -Because 'the foreign copy is not offered'
        $read = Read-TpmReShadeUndoReceipt -Folder $foreign -VerifyPayload
        $read.Valid | Should -BeFalse
        $read.Reason | Should -Match 'another game'
        $fake = [pscustomobject]@{ GameId = 'H'; GameName = 'Game H'; Folder = $foreign; LookBefore = 'None'; LookAfter = 'FastCrt' }
        $result = Invoke-TpmReShadeUndo -Entry $fake
        $result.Status | Should -BeExactly 'ReceiptDamaged'
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly 'tpm'
        [IO.File]::ReadAllText((Join-Path $other 'ReShade.ini')) | Should -BeExactly 'tpm'
        Test-Path -LiteralPath $foreign | Should -BeTrue
    }

    It 'refuses a receipt whose file path now crosses a junction (no mock of Test-TpmNoReparsePath)' {
        # Mutation: leave the link check out of Get-TpmReShadeUndoReceiptProblem -> the receipt is trusted and the undo is tried through the junction (status NotChanged, not ReceiptDamaged).
        $game = Join-Path $script:f85Games 'J'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $game -GameId 'J' -Before @{ 'Shaders\x.fx' = 'own' } -After @{ 'Shaders\x.fx' = 'tpm' })
        $entry = Get-F85Entry -StateRoot $script:f85State -GameId 'J'
        $target = New-F85Root 'junction-target'
        Set-F85File -Path (Join-Path $target 'x.fx') -Text 'tpm'
        Remove-Item -LiteralPath (Join-Path $game 'Shaders') -Recurse -Force
        $link = Join-Path $game 'Shaders'
        [void](New-Item -ItemType Junction -Path $link -Target $target)
        try {
            $result = Invoke-TpmReShadeUndo -Entry $entry
            $result.Status | Should -BeExactly 'ReceiptDamaged'
            (Read-TpmReShadeUndoReceipt -Folder ([string]$entry.Folder)).Reason | Should -Match 'link'
            [IO.File]::ReadAllText((Join-Path $target 'x.fx')) | Should -BeExactly 'tpm'
            Test-Path -LiteralPath $entry.Folder | Should -BeTrue
        } finally {
            [IO.Directory]::Delete($link)
        }
    }
}

Describe 'FIX85 the receipt records its folders and passes them to the file transaction' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        $script:f85State = New-F85Root 'state'
        $script:f85Games = New-F85Root 'games'
    }

    It 'names the game folder after the SHA-256 of the game id, for the receipts and for the ownership record' {
        # Mutation: name the receipt folder after something else (for example the ownership file name of a mocked path) -> the folder name is not the SHA-256 of the id.
        $expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        (Split-Path -Leaf (Get-TpmReShadeUndoGameFolder -GameId 'abc' -StateRoot $script:f85State)) | Should -BeExactly $expected
        (Split-Path -Leaf (Get-TpmReShadeProfileOwnershipPath -GameId 'abc' -StateRoot $script:f85State)) | Should -BeExactly ($expected + '.json')
    }

    It 'records the game folder and the profile folder, and refuses a file outside them before anything is saved' {
        # Mutation: record no roots, or skip the check at creation -> Roots is empty, or the outside file gets a receipt.
        $game = Join-Path $script:f85Games 'R'
        $profiles = New-F85Root 'UserProfiles'
        $profilePath = Join-Path $profiles 'R.xml'
        Set-F85File -Path (Join-Path $game 'ReShade.ini') -Text 'own'
        Set-F85File -Path $profilePath -Text '<GameProfile />'
        $request = New-TpmReShadeUndoRequest -GameId 'R' -Operation 'Install' -ExtraPaths @($profilePath) -StateRoot $script:f85State
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $game 'ReShade.ini')) -Roots @($game)
        $undo.Succeeded | Should -BeTrue
        @($undo.Receipt.Roots) | Should -Be @([IO.Path]::GetFullPath($game), [IO.Path]::GetFullPath($profiles))
        $escape = New-TpmReShadeUndoReceipt -Request (New-TpmReShadeUndoRequest -GameId 'R2' -Operation 'Install' -StateRoot $script:f85State) -Paths @((Join-Path $game 'ReShade.ini'), (Join-Path $profiles 'other.xml')) -Roots @($game)
        $escape.Succeeded | Should -BeFalse
        $escape.Reason | Should -Match 'outside the folders'
        @(Get-ChildItem -LiteralPath (Get-TpmReShadeUndoGameFolder -GameId 'R2' -StateRoot $script:f85State) -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
        $none = New-TpmReShadeUndoReceipt -Request (New-TpmReShadeUndoRequest -GameId 'R3' -Operation 'Install' -StateRoot $script:f85State) -Paths @((Join-Path $game 'ReShade.ini'))
        $none.Succeeded | Should -BeFalse -Because 'a change that names no folder for the game gets no receipt'
    }

    It 'gives every undo operation the root that holds its file, and refuses a file outside every root' {
        # Mutation: leave RootPath out of Get-TpmReShadeUndoOperations -> the operations have no root and the transaction cannot refuse an escaping path.
        $game = Join-Path $script:f85Games 'Ops'
        $files = @(
            [pscustomobject]@{ Path = (Join-Path $game 'a.ini'); BeforeExists = $true; AfterExists = $true; Payload = 'payload\0.bin'; BeforeSha256 = 'AA'; AfterSha256 = 'BB' }
            [pscustomobject]@{ Path = (Join-Path $script:f85State 'Deployments\x.json'); BeforeExists = $false; AfterExists = $true; Payload = ''; BeforeSha256 = ''; AfterSha256 = 'CC' }
        )
        $roots = @($game, (Join-Path $script:f85State 'Deployments'))
        $operations = @(Get-TpmReShadeUndoOperations -Folder (Join-Path $script:f85State 'receipt') -Files $files -Roots $roots)
        $operations[0].RootPath | Should -BeExactly $game
        $operations[1].RootPath | Should -BeExactly (Join-Path $script:f85State 'Deployments')
        { Get-TpmReShadeUndoOperations -Folder (Join-Path $script:f85State 'receipt') -Files $files -Roots @($game) } | Should -Throw '*outside the folders*'
    }

    It 'hands the roots of the receipt to the file transaction when it undoes a game' {
        # Mutation: call Invoke-TpmTransactionalFileBatch with operations that have no RootPath -> a captured operation has an empty root.
        $game = Join-Path $script:f85Games 'Batch'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $game -GameId 'Batch' -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' })
        $entry = Get-F85Entry -StateRoot $script:f85State -GameId 'Batch'
        $script:f85Ops = @()
        Mock Invoke-TpmTransactionalFileBatch { $script:f85Ops = @($Operations); [pscustomobject]@{ Outcome = 'SUCCEEDED'; Errors = @(); Rollback = $null } }
        (Invoke-TpmReShadeUndo -Entry $entry).Status | Should -BeExactly 'Undone'
        $script:f85Ops.Count | Should -Be 1
        $script:f85Ops[0].RootPath | Should -BeExactly ([IO.Path]::GetFullPath($game))
    }
}

Describe 'FIX85 an unfinished receipt is never left behind' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        $script:f85State = New-F85Root 'state'
        $script:f85Games = New-F85Root 'games'
        $script:f85Game = Join-Path $script:f85Games 'P'
    }

    It 'does not offer an unfinished receipt, and an undo of it changes nothing and keeps it' {
        # Mutation: offer or undo a receipt whose State is Prepared -> an entry appears, or the files change.
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'own'
        $request = New-TpmReShadeUndoRequest -GameId 'P' -GameName 'Game P' -Operation 'Install' -StateRoot $script:f85State
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        $undo.Succeeded | Should -BeTrue
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'tpm'
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f85State).Count | Should -Be 0
        $jsonBefore = Get-F85Bytes (Join-Path $undo.Folder 'receipt.json')
        $result = Invoke-TpmReShadeUndo -Entry ([pscustomobject]@{ GameId = 'P'; GameName = 'Game P'; Folder = $undo.Folder; LookBefore = 'None'; LookAfter = 'FastCrt' })
        $result.Status | Should -BeExactly 'ReceiptDamaged'
        $result.Detail | Should -Match 'never finished'
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly 'tpm'
        (Get-F85Bytes (Join-Path $undo.Folder 'receipt.json')) | Should -BeExactly $jsonBefore
    }

    It 'removes an unfinished receipt when a newer change of the same game is finished' {
        # Mutation: leave Remove-TpmReShadeUnfinishedUndoReceipts out of Complete-TpmReShadeUndoReceipt -> the orphan stays next to the finished one.
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'own'
        $request = New-TpmReShadeUndoRequest -GameId 'P' -GameName 'Game P' -Operation 'Install' -StateRoot $script:f85State
        $orphan = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        Start-Sleep -Milliseconds 25
        [void](New-F85Change -StateRoot $script:f85State -GameDir $script:f85Game -GameId 'P' -Before @{ 'ReShade.ini' = 'own2' } -After @{ 'ReShade.ini' = 'tpm2' } -OwnerBefore 'TeknoParrotManager' -Operation 'Update')
        Test-Path -LiteralPath $orphan.Folder | Should -BeFalse
        $left = @(Get-TpmReShadeUndoReceipts -GameFolder (Get-TpmReShadeUndoGameFolder -GameId 'P' -StateRoot $script:f85State))
        $left.Count | Should -Be 1
        $left[0].Receipt.State | Should -BeExactly 'Applied'
    }

    It 'keeps an older unfinished receipt that holds a ReShade TeknoParrot Manager did not install, and a newer unfinished one' {
        # Mutation: remove every Prepared receipt -> the only copy of the user's own files, or a change that is just being made, is deleted.
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'own'
        $holds = New-TpmReShadeUndoReceipt -Request (New-TpmReShadeUndoRequest -GameId 'P' -Operation 'Adopt' -OwnerBefore 'Other' -StateRoot $script:f85State) -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        Start-Sleep -Milliseconds 25
        [void](New-F85Change -StateRoot $script:f85State -GameDir $script:f85Game -GameId 'P' -Before @{ 'ReShade.ini' = 'own2' } -After @{ 'ReShade.ini' = 'tpm2' } -OwnerBefore 'TeknoParrotManager' -Operation 'Update')
        Test-Path -LiteralPath $holds.Folder | Should -BeTrue
        Start-Sleep -Milliseconds 25
        $newer = New-TpmReShadeUndoReceipt -Request (New-TpmReShadeUndoRequest -GameId 'P' -Operation 'Update' -StateRoot $script:f85State) -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        Remove-TpmReShadeUnfinishedUndoReceipts -GameFolder (Get-TpmReShadeUndoGameFolder -GameId 'P' -StateRoot $script:f85State)
        Test-Path -LiteralPath $newer.Folder | Should -BeTrue
        Test-Path -LiteralPath $holds.Folder | Should -BeTrue
    }

    It 'removes the receipt of a change that left every file as it was, and finishes one that changed something' {
        # Mutation: always mark the receipt Applied -> Complete returns Ready for an empty change and its folder stays.
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'same'
        $request = New-TpmReShadeUndoRequest -GameId 'P' -Operation 'Update' -StateRoot $script:f85State
        $empty = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        (Complete-TpmReShadeUndoReceipt -Undo $empty) | Should -BeExactly 'None'
        Test-Path -LiteralPath $empty.Folder | Should -BeFalse
        $changed = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'different'
        (Complete-TpmReShadeUndoReceipt -Undo $changed) | Should -BeExactly 'Ready'
        (Read-TpmReShadeUndoReceipt -Folder $changed.Folder).Receipt.State | Should -BeExactly 'Applied'
    }

    It 'finishes a game that a failed rollback left half changed, but calls it Check and keeps it even when nothing differs' {
        # Mutation: return Ready for -Mixed, or remove an unchanged -Mixed receipt -> the game is called ready, or the only saved copy is deleted.
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'same'
        $request = New-TpmReShadeUndoRequest -GameId 'P' -Operation 'Update' -StateRoot $script:f85State
        $mixed = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        (Complete-TpmReShadeUndoReceipt -Undo $mixed -Mixed) | Should -BeExactly 'Check'
        $entry = Get-F85Entry -StateRoot $script:f85State -GameId 'P'
        $entry.Receipt.NeedsCheck | Should -BeTrue
        @(Get-TpmReShadeUndoDetailBlocks -Entries @($entry))[0].Lines | Should -Contain 'Check: Check this game before you play it. A failed rollback left it half changed.'
        $groups = @{ Ready = (New-Object 'System.Collections.Generic.List[string]'); Check = (New-Object 'System.Collections.Generic.List[string]'); Missing = (New-Object 'System.Collections.Generic.List[string]'); None = (New-Object 'System.Collections.Generic.List[string]') }
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'other'
        $second = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $script:f85Game 'ReShade.ini')) -Roots @($script:f85Game)
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'third'
        (Add-TpmReShadeUndoGameResult -Groups $groups -Game 'P' -Undo $second -Mixed) | Should -BeExactly 'Check'
        @($groups['Check']) | Should -Be @('P')
        $groups['Ready'].Count | Should -Be 0
        (Add-TpmReShadeUndoGameResult -Groups $groups -Game 'Q' -Undo $null) | Should -BeExactly 'None'
        @($groups['None']) | Should -Be @('Q')
    }
}

Describe 'FIX85 the setup flow finishes the undo receipt of every game it changed' {
    BeforeEach {
        $script:f85Root = New-F85Root 'flow'
        $script:f85Profiles = Join-Path $script:f85Root 'UserProfiles'
        [void][IO.Directory]::CreateDirectory($script:f85Profiles)
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:f85Root 'Assets'); State = (Join-Path $script:f85Root 'State') }
        $script:f85Names = @('GameA')
        foreach ($name in $script:f85Names) {
            $dir = Join-Path $script:f85Root ('Games\' + $name)
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::WriteAllText((Join-Path $script:f85Profiles ($name + '.xml')), ('<GameProfile><GameName>Fixture {0}</GameName><GamePath>{1}</GamePath></GameProfile>' -f $name, [System.Security.SecurityElement]::Escape((Join-Path $dir ($name + '.exe')))))
        }
        $script:f85SourceDll = Join-Path $script:f85Root 'ReShade64.dll'
        [IO.File]::WriteAllBytes($script:f85SourceDll, [byte[]](0x4d, 0x5a))
        $script:f85Profile = Get-TpmReShadeProfile -ProfileId 'FastCrt'
        $script:f85Mode = 'ok'
        $script:f85Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f85Rows.Add([string]$Object) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { 100 }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = 100; Left = 0; Top = 0; Height = 40; BufferWidth = 100; BufferHeight = 300 } }
        Mock Test-TpmNoReparsePath { $true }
        Mock Assert-TpmNoReparseWriteTarget {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Session = $null; Reason = 'fixture' } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'UnknownError'; Signer = '(none)'; Thumbprint = ('C3' * 20) } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Select-RegisteredGamesInteractive { @($script:f85Names | ForEach-Object { Get-Item -LiteralPath (Join-Path $script:f85Profiles ($_ + '.xml')) }) }
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = $script:f85Profile; PreviewSession = $null } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Test-TpmInteractiveInput { $false }
        Mock Read-HostSafe { return '' }
        Mock Read-TpmChoice { return 'Y' }
        Mock Read-TpmYesNo { return 'N' }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Get-TpmReShadeApplyPreflight {
            param($SelectedGames)
            $records = @($SelectedGames | ForEach-Object { [pscustomobject]@{ Game = $_.BaseName; Status = 'Ready'; Detail = '' } })
            [pscustomobject]@{ Total = $records.Count; Ready = $records.Count; Protected = 0; MissingPath = 0; Unsafe = 0; Failed = 0; Records = $records }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:f85Root ($GameId + '.ownership.json') }
        Mock Get-ReShadeTargetInfo { param($ExeDir) [pscustomobject]@{ TargetDir = $ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = 'NoReShadePresent'; Detail = 'fixture' } }
        Mock Test-TpmGameMutationPath { param($GamePath) [pscustomobject]@{ Valid = $true; ReasonCode = $null; Reason = 'valid'; ResolvedPath = $GamePath; GameDirectory = [IO.Path]::GetDirectoryName($GamePath) } }
        Mock New-TpmReShadePresetContent { '; fixture preset' }
        Mock Get-TpmReShadeProfileTechniqueDisplay { 'fixture' }
        # The deployment is a stand-in that does what the real one does around the receipt: receipt first, then the write. In mode 'mixed' it
        # ends like a failed rollback (ACTION_REQUIRED) and returns the receipt.
        Mock Install-TpmReShadeProfileDeployment {
            param($GamePath, $OwnershipPath, $UndoReceipt)
            $dir = [IO.Path]::GetDirectoryName($GamePath)
            $hook = Join-Path $dir 'dxgi.dll'
            $undo = New-TpmReShadeUndoReceipt -Request $UndoReceipt -Paths @($hook, $OwnershipPath) -Roots @($dir, [IO.Path]::GetDirectoryName($OwnershipPath))
            [IO.File]::WriteAllText($hook, 'tpm-reshade')
            [IO.File]::WriteAllText($OwnershipPath, '{}')
            if ($script:f85Mode -ceq 'mixed') { return [pscustomobject]@{ Succeeded = $false; State = 'ACTION_REQUIRED'; Reason = 'PROFILE_DEPLOYMENT_FAILED'; Error = 'ROLLBACK FAILED (simulated)'; RollbackVerified = $false; UndoReceipt = $undo } }
            [pscustomobject]@{ Succeeded = $true; State = 'INSTALLED'; TargetDir = $dir; DllName = 'dxgi.dll'; PresetApplied = $false; PresetSource = $null; ApiDetected = $true; UndoReceipt = $undo }
        }
        Mock Test-TpmReShadeDeploymentVerified { $true }
        Mock Add-TpmReShadeProfileHistory {}
        Set-Variable -Name Unattended -Scope Global -Value ([switch]$true)
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
        Remove-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
        if ($script:f85SavedUnattended.Exists) { Set-Variable -Name Unattended -Scope Global -Value $script:f85SavedUnattended.Value }
    }

    It 'finishes the receipt of a game even when something fails after its deployment' {
        # Mutation: take the Complete call out of the finally block of Invoke-ReShadeSetupLegacy -> the receipt stays Prepared: no entry, a leftover folder, not in UndoReceiptItems.
        Mock Write-Log { if ([string]$msg -match '^ReShade: \S+ -> ') { throw 'simulated failure after the deployment' } }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f85Profiles -SourceDll $script:f85SourceDll
        @($result.FailedItems) | Should -Be @('GameA')
        @($result.UndoReceiptItems) | Should -Be @('GameA')
        @($result.UndoReceiptMissingItems).Count | Should -Be 0
        $receipts = @(Get-TpmReShadeUndoReceipts -GameFolder (Get-TpmReShadeUndoGameFolder -GameId 'GameA'))
        $receipts.Count | Should -Be 1
        $receipts[0].Receipt.State | Should -BeExactly 'Applied'
        @(Get-TpmReShadeUndoEntries | ForEach-Object { $_.GameId }) | Should -Be @('GameA')
    }

    It 'says "Undo copy not finished" for a game whose receipt cannot be finished' {
        # Mutation: count an unfinished receipt as ready -> the game is in UndoReceiptItems and the screen promises an undo.
        Mock Save-TpmReShadeUndoReceipt {
            param($Folder, $Receipt)
            if ([string]$Receipt.State -ceq 'Applied') { throw 'simulated: the disk is full' }
            & $script:f85RealSave -Folder $Folder -Receipt $Receipt
        }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f85Profiles -SourceDll $script:f85SourceDll
        @($result.UndoReceiptMissingItems) | Should -Be @('GameA')
        @($result.UndoReceiptItems).Count | Should -Be 0
        @(Get-TpmReShadeUndoEntries).Count | Should -Be 0
        $screen = [pscustomobject]@{ Deployed = 1; Protected = 0; Unsafe = 0; MissingPath = 0; MissingDevice = 0; Unsupported = 0; KeptPrevious = 0; ErrorCount = 0; UnverifiedItems = @(); SelectedProfileName = 'Fast CRT'; ProtectedRecords = @(); UnsafeDetails = @(); SummaryDetails = @(); DetailNotes = @(); UndoReceiptItems = @($result.UndoReceiptItems); UndoReceiptMissingItems = @($result.UndoReceiptMissingItems) }
        $script:f85Rows.Clear()
        $null = Show-TpmReShadeSetupResult -Result $screen
        $text = Get-F85Text $script:f85Rows
        $text | Should -Match ([regex]::Escape('Undo copy not finished for 1 game. The log has the reason.'))
        $text | Should -Not -Match 'Next: You can undo'
    }

    It 'does not call a game ready after a failed rollback: Check this game before you play it' {
        # Mutation: complete the receipt without -Mixed -> the game is in UndoReceiptItems and the screen says "Next: You can undo this".
        $script:f85Mode = 'mixed'
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f85Profiles -SourceDll $script:f85SourceDll
        @($result.UndoReceiptCheckItems) | Should -Be @('GameA')
        @($result.UndoReceiptItems).Count | Should -Be 0
        @($result.UnverifiedItems) | Should -Contain 'GameA'
        (Get-F85Entry -StateRoot '' -GameId 'GameA').Receipt.NeedsCheck | Should -BeTrue
        $screen = [pscustomobject]@{ Deployed = 1; Protected = 0; Unsafe = 0; MissingPath = 0; MissingDevice = 0; Unsupported = 0; KeptPrevious = 0; ErrorCount = 0; UnverifiedItems = @(); SelectedProfileName = 'Fast CRT'; ProtectedRecords = @(); UnsafeDetails = @(); SummaryDetails = @(); DetailNotes = @(); UndoReceiptItems = @($result.UndoReceiptItems); UndoReceiptMissingItems = @(); UndoReceiptCheckItems = @($result.UndoReceiptCheckItems) }
        $script:f85Rows.Clear()
        $null = Show-TpmReShadeSetupResult -Result $screen
        $text = Get-F85Text $script:f85Rows
        $text | Should -Match ([regex]::Escape('Check this game before you play it.'))
        $text | Should -Not -Match 'Next: You can undo'
    }

    It 'counts one failed game, lists it and says so in plain words, in one place' {
        # Mutation: copy the branch again (or forget one of its four effects) -> the count, the list, the FAILED line or the note is missing.
        $errors = 0
        $failed = New-Object 'System.Collections.Generic.List[string]'
        $notes = New-Object 'System.Collections.Generic.List[string]'
        Register-TpmReShadeUndoReceiptFailure -Game 'GameB' -GameName 'Fixture GameB' -ErrorCount ([ref]$errors) -FailedGameIds $failed -DetailNotes $notes
        $errors | Should -Be 1
        @($failed) | Should -Be @('GameB')
        @($notes) | Should -Be @('GameB: no copy for undo could be saved -- unchanged')
        (Get-F85Text $script:f85Rows) | Should -Match ([regex]::Escape('FAILED Fixture GameB: not changed, because a copy for undo could not be saved.'))
    }
}

Describe 'FIX85 undo only the files that did not change' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f85Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f85Rows.Add([string]$Object) }
        Mock Get-ConsoleContentWidth { 100 }
        Mock Test-TpmInteractiveInput { $false }
        $script:f85Choices = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f85ChoiceCalls = [System.Collections.Generic.List[object]]::new()
        Mock Read-TpmChoice {
            [void]$script:f85ChoiceCalls.Add([pscustomobject]@{ Prompt = [string]$Prompt; Choices = @($Choices) })
            if ($script:f85Choices.Count -gt 0) { return $script:f85Choices.Dequeue() }
            return 'C'
        }
        $script:f85Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f85Prompts = New-Object 'System.Collections.Generic.List[string]'
        Mock Read-HostSafe {
            [void]$script:f85Prompts.Add([string]$Prompt)
            if ($script:f85Answers.Count -gt 0) { return $script:f85Answers.Dequeue() }
            return ''
        }
        $script:f85State = New-F85Root 'state'
        $script:f85Games = New-F85Root 'games'
        $script:f85Game = Join-Path $script:f85Games 'Part'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $script:f85Game -GameId 'Part' -Before @{ 'ReShade.ini' = 'own-ini'; 'dxgi.dll' = $null } -After @{ 'ReShade.ini' = 'tpm-ini'; 'dxgi.dll' = 'tpm-dll' })
        Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'my later edit'
        $script:f85Entry = Get-F85Entry -StateRoot $script:f85State -GameId 'Part'
        $script:f85IniEdit = Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')
    }

    It 'puts nothing back without the explicit choice, and never overwrites the changed file' {
        # Mutation: restore the unchanged files without -RestoreUnchanged -> ChangedSince becomes an undo and dxgi.dll disappears.
        $result = Invoke-TpmReShadeUndo -Entry $script:f85Entry
        $result.Status | Should -BeExactly 'ChangedSince'
        @($result.Changed) | Should -Be @((Join-Path $script:f85Game 'ReShade.ini'))
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        (Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly $script:f85IniEdit
    }

    It 'puts back only the unchanged files with -RestoreUnchanged, leaves the changed file byte for byte and keeps the receipt' {
        # Mutation: restore every file (or drop the receipt) when -RestoreUnchanged is given -> the user's edit is overwritten, or the receipt is gone.
        $result = Invoke-TpmReShadeUndo -Entry $script:f85Entry -RestoreUnchanged
        $result.Status | Should -BeExactly 'PartlyUndone'
        $result.Code | Should -BeExactly 'UNDO_PARTLY_DONE'
        @($result.Changed) | Should -Be @((Join-Path $script:f85Game 'ReShade.ini'))
        Test-Path -LiteralPath (Join-Path $script:f85Game 'dxgi.dll') | Should -BeFalse
        (Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly $script:f85IniEdit
        Test-Path -LiteralPath $script:f85Entry.Folder | Should -BeTrue
        (Get-TpmPlainReason -Code 'UNDO_PARTLY_DONE').Text | Should -BeExactly 'Only the files that did not change were put back. The others were left as they are.'
    }

    It 'checks again that a file left alone is still as it was found, and reports a problem when it is not' {
        # Mutation: skip the check of the files left alone -> the status stays PartlyUndone although a file changed during the undo.
        Mock Invoke-TpmReShadeUndoBatch {
            Set-F85File -Path (Join-Path $script:f85Game 'ReShade.ini') -Text 'changed while the undo ran'
            [pscustomobject]@{ Status = 'Undone'; Code = 'UNDO_DONE'; Detail = '' }
        }
        $result = Invoke-TpmReShadeUndo -Entry $script:f85Entry -RestoreUnchanged
        $result.Status | Should -BeExactly 'NeedsAttention'
        $result.Code | Should -BeExactly 'UNDO_NOT_FINISHED'
        $result.Detail | Should -Match 'ReShade\.ini'
    }

    It 'tells which kinds of file changed in plain words, never a path' {
        # Mutation: say "some files changed" or list the paths -> a kind line is missing or a path appears.
        $game = Join-Path $script:f85Games 'Kinds'
        [void](New-F85Change -StateRoot $script:f85State -GameDir $game -GameId 'Kinds' -Before @{ 'ReShade.ini' = 'a'; 'Profile.xml' = 'b'; 'Shaders\x.fx' = 'c' } -After @{ 'ReShade.ini' = 'a2'; 'Profile.xml' = 'b2'; 'Shaders\x.fx' = 'c2' })
        $entry = Get-F85Entry -StateRoot $script:f85State -GameId 'Kinds'
        foreach ($name in @('ReShade.ini', 'Profile.xml', 'Shaders\x.fx')) { Set-F85File -Path (Join-Path $game $name) -Text 'later' }
        $check = Get-TpmReShadeUndoCheck -Receipt $entry.Receipt
        @(Get-TpmReShadeUndoChangedKindLines -Changed $check.Changed) | Should -Be @('The ReShade settings file', 'The game profile', 'Some ReShade files')
        @($check.Changed | ForEach-Object { $_.Kind } | Sort-Object) | Should -Be @('ReShade settings file', 'ReShade files', 'game profile' | Sort-Object)
        Set-F85File -Path (Join-Path $game 'ReShade.ini') -Text 'a2'
        @(Get-TpmReShadeUndoChangedKindLines -Changed (Get-TpmReShadeUndoCheck -Receipt $entry.Receipt).Changed) | Should -Be @('The game profile', 'Some ReShade files')
    }

    It 'offers U, D and C for a game with files that can be put back, and undoes only after a typed YES' {
        # Mutation: undo on U without asking, or accept another word as YES -> the file is removed after "no", or nothing happens after YES.
        $script:f85Choices.Enqueue('U'); $script:f85Answers.Enqueue('no')
        Invoke-TpmReShadeUndoGameChoice -Entry $script:f85Entry
        @($script:f85ChoiceCalls[0].Choices) | Should -Be @('U', 'D', 'C')
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        (Get-F85Text $script:f85Rows) | Should -Match ([regex]::Escape('These files are different now: - The ReShade settings file The other files can still be undone.'))
        (Get-F85Text $script:f85Rows) | Should -Match ([regex]::Escape('[U] Undo only the files that did not change'))
        (Get-F85Text $script:f85Rows) | Should -Match ([regex]::Escape('Canceled. Nothing was changed.'))
        $script:f85Choices.Enqueue('U'); $script:f85Answers.Enqueue('YES')
        Invoke-TpmReShadeUndoGameChoice -Entry $script:f85Entry
        Test-Path -LiteralPath (Join-Path $script:f85Game 'dxgi.dll') | Should -BeFalse
        (Get-F85Bytes (Join-Path $script:f85Game 'ReShade.ini')) | Should -BeExactly $script:f85IniEdit
        (Get-F85Text $script:f85Rows) | Should -Match ([regex]::Escape('ReShade changes were partly undone for 1 game.'))
        @($script:f85Prompts | Where-Object { $_ -match 'Type YES to undo only those files' }).Count | Should -Be 2
    }

    It 'leaves everything as it is on C or Enter and shows the changed files on D first' {
        # Mutation: treat the default answer as U -> the unchanged file is undone without a choice.
        $script:f85Choices.Enqueue('D')
        Invoke-TpmReShadeUndoGameChoice -Entry $script:f85Entry
        [IO.File]::ReadAllText((Join-Path $script:f85Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        @($script:f85ChoiceCalls).Count | Should -Be 2
        (Get-F85Text $script:f85Rows) | Should -Match 'Changed file:'
        (Get-F85Text $script:f85Rows) | Should -Match '\(ReShade settings file\)'
        @($script:f85Prompts).Count | Should -Be 0
    }
}

Describe 'FIX85 one wording for what an undo puts back' {
    It 'words one game and many games from the same table' -ForEach @(
        @{ Owner = 'None'; One = 'The ReShade files TeknoParrot Manager added are removed.' }
        @{ Owner = 'Other'; One = 'Its own ReShade files are put back exactly as they were.' }
        @{ Owner = 'TeknoParrotManager'; One = 'Its ReShade files are put back exactly as they were.' }
        @{ Owner = ''; One = 'Its ReShade files are put back exactly as they were.' }
    ) {
        # Mutation: word the groups twice again and change one of them -> the one-game sentence no longer comes from Get-TpmReShadeUndoGroupText.
        Mock Write-Log {}
        $entry = [pscustomobject]@{ GameName = 'Game'; OwnerBefore = $Owner; LookBefore = 'None'; LookAfter = 'FastCrt'; Receipt = [pscustomobject]@{ NativeShader = $null } }
        @(Get-TpmReShadeUndoPlainLines -Entry $entry)[1] | Should -BeExactly $One
    }

    It 'groups Undo all by what comes back, one line per group, in a fixed order' {
        # Mutation: one line per game, or count only the owner named TeknoParrotManager as an earlier look -> the grouped lines or their counts differ.
        $entries = @('None', 'None', 'Other', 'TeknoParrotManager', 'TeknoParrotManager', 'TeknoParrotManager') | ForEach-Object { [pscustomobject]@{ OwnerBefore = $_; Receipt = [pscustomobject]@{ NativeShader = $null } } }
        @(Get-TpmReShadeUndoAllLines -Entries $entries) | Should -Be @('2 games go back to no ReShade.', '1 game gets its own ReShade back.', '3 games go back to the look they had before.')
    }
}

Describe 'FIX85 the Undo list stays short at <Width> columns' -ForEach @(@{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }) {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f85Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f85Rows.Add([string]$Object) }
        # Every text line the product prints starts with a marker row, so the tests count lines, not wrapped rows.
        Mock Write-TpmText { [void]$script:f85Rows.Add('<<TEXT>>'); & $script:f85RealText @PesterBoundParameters }
        $script:f85Width = $Width
        Mock Get-ConsoleContentWidth { $script:f85Width }
        Mock Test-TpmInteractiveInput { $false }
        $script:f85ChoiceAt = New-Object 'System.Collections.Generic.List[int]'
        Mock Read-TpmChoice { [void]$script:f85ChoiceAt.Add($script:f85Rows.Count); return 'B' }
        $script:f85State = New-F85Root 'width-state'
        $script:f85Games = New-F85Root 'width-games'
        for ($i = 1; $i -le 10; $i++) {
            $id = 'W{0:D2}' -f $i
            [void](New-F85Change -StateRoot $script:f85State -GameDir (Join-Path $script:f85Games $id) -GameId $id -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' } -OwnerBefore 'Other' -LookBefore 'Other' -Operation 'Adopt')
        }
    }

    It 'prints no run of 6 or more text lines on the page, and every line fits the console' {
        # Mutation: show 8 games per page again, or drop the blank line before the More line -> a run of 6 or more text lines.
        Show-TpmReShadeUndoMenu -StateRoot $script:f85State
        $rows = @($script:f85Rows | Select-Object -First $script:f85ChoiceAt[0] | ForEach-Object { ([string]$_).TrimEnd() })
        @($rows | Where-Object { $_ -match '^\s+\d+\) ' }).Count | Should -Be 4
        (Get-F85TextRun -Rows $rows) | Should -BeLessOrEqual 5
        @($rows | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
    }

    It 'would count the old 8-row page as one long run (the counter can see the problem)' {
        # Mutation: make the counter blind to rows -> the old page is not seen as longer than 5 lines and this guard fails.
        $entries = @(Get-TpmReShadeUndoEntries -StateRoot $script:f85State)
        $script:f85Rows.Clear()
        Write-TpmReShadeUndoList -Visible @($entries | Select-Object -First 8) -Total $entries.Count -PageCount 2
        (Get-F85TextRun -Rows @($script:f85Rows | ForEach-Object { ([string]$_).TrimEnd() })) | Should -BeGreaterThan 5
    }
}
