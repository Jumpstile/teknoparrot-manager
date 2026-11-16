#Requires -Module Pester
# FIX68: change the ReShade look any time, and undo it for one game or for all games. Every ReShade change TeknoParrot Manager makes to a
# game (install, switch the look, adopt/replace a ReShade it did not install, remove, and TeknoParrot's own CRT look turned off in the same
# run) writes ONE checked undo receipt for that game before the first write. ReShade > Undo ReShade changes puts a game back byte for byte,
# one game (typed YES) or all games (typed ALL), and leaves a game alone that changed after the receipt. These tests drive the real product
# functions with synthetic game folders in $TestDrive; nothing touches TeknoParrot, LaunchBox, the registry, services or the network.
# Each It names the product change that makes it fail.
# What this CANNOT prove: the menu 5 body itself (it only calls Show-TpmReShadeUndoMenu), how a real console paints the rows, and a real
# ReShade install with downloaded effects (the deployment tests use the Original look, which has no effects, and a mocked effect stage).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f68Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX68 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix68-functions.ps1'
    ($script:f68Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    # The caller's own global Unattended (if any) is put back after each test instead of being removed.
    $savedUnattended = Get-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
    $script:f68SavedUnattended = [pscustomobject]@{ Exists = ($null -ne $savedUnattended); Value = $(if ($null -ne $savedUnattended) { $savedUnattended.Value } else { $null }) }
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix68.log'
    $script:logWarnShown = $false
    $script:F68Utf8 = New-Object System.Text.UTF8Encoding $false

    function New-F68Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # Writes the text as UTF-8 bytes (no BOM); $null deletes the file.
    function Set-F68File {
        param([string]$Path, $Text)
        if ($null -eq $Text) {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            return
        }
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllBytes($Path, $script:F68Utf8.GetBytes([string]$Text))
    }
    function Get-F68Bytes {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<absent>' }
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    # One finished change of a game: Before (file name -> text, $null = absent) is written, the receipt is made, After is written, the
    # receipt is finished. -NoSetup keeps the files as they are (a change that follows an earlier one).
    function New-F68Change {
        param(
            [string]$StateRoot, [string]$GameDir, [string]$GameId, [hashtable]$Before = @{}, [hashtable]$After = @{},
            [string]$Operation = 'Install', [string]$LookBefore = 'None', [string]$LookAfter = 'FastCrt', [string]$OwnerBefore = 'None', [switch]$NoSetup
        )
        if (-not $NoSetup) { foreach ($name in @($Before.Keys)) { Set-F68File -Path (Join-Path $GameDir $name) -Text $Before[$name] } }
        $paths = @(@(@($Before.Keys) + @($After.Keys)) | Sort-Object -Unique | ForEach-Object { Join-Path $GameDir $_ })
        $request = New-TpmReShadeUndoRequest -GameId $GameId -GameName ('Game ' + $GameId) -Operation $Operation -LookBefore $LookBefore -LookAfter $LookAfter -OwnerBefore $OwnerBefore -StateRoot $StateRoot
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths $paths -Roots @($GameDir)
        if (-not $undo.Succeeded) { throw ('fixture: the receipt was not made: ' + $undo.Reason) }
        foreach ($name in @($After.Keys)) { Set-F68File -Path (Join-Path $GameDir $name) -Text $After[$name] }
        if ((Complete-TpmReShadeUndoReceipt -Undo $undo) -cne 'Ready') { throw 'fixture: the receipt was not finished' }
        # Receipt folders and rows are ordered by their time; keep two changes apart.
        Start-Sleep -Milliseconds 25
        return $undo
    }
    function Get-F68Entry {
        param([string]$StateRoot, [string]$GameId)
        return @(Get-TpmReShadeUndoEntries -StateRoot $StateRoot | Where-Object { $_.GameId -eq $GameId })[0]
    }
    function Get-F68Text {
        param($Rows)
        return ((@($Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ')
    }
    function Get-F68RowIndex {
        param([string[]]$Rows, [string]$Pattern)
        for ($i = 0; $i -lt @($Rows).Count; $i++) { if ([string]$Rows[$i] -match $Pattern) { return $i } }
        return -1
    }
    # The most logical lines in a row with no blank row between them (same counting as the FIX72 and FIX73 tests): a row that only
    # continues the sentence above it belongs to that line. It can only count too few lines, never too many.
    function Get-F68LongestRun {
        param([string[]]$Rows, [int]$Limit, [int]$Slack = 9)
        $longest = 0
        $run = 0
        $previous = ''
        foreach ($row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($row)) { $run = 0; $previous = ''; continue }
            $firstWord = ($row.Trim() -split '\s+')[0]
            $continues = ($previous.Length -gt 0 -and ($previous.Length + 1 + $firstWord.Length) -gt ($Limit - $Slack))
            if (-not $continues) { $run++; if ($run -gt $longest) { $longest = $run } }
            $previous = [string]$row
        }
        return $longest
    }
    # A user profile with TeknoParrot's own CRT setting (Lottes), saved with a BOM and CRLF like TeknoParrotUI does.
    function New-F68CrtProfileBytes {
        $lines = @(
            '<?xml version="1.0" encoding="utf-8"?>', '<GameProfile>', '  <GameName>Fixture CRT</GameName>', '  <ConfigValues>',
            '    <FieldInformation>', '      <CategoryName>Video</CategoryName>', '      <FieldName>CRT Shader</FieldName>',
            '      <FieldValue>Lottes</FieldValue>', '      <FieldOptions><string>None</string><string>Lottes</string></FieldOptions>',
            '    </FieldInformation>', '  </ConfigValues>', '</GameProfile>'
        )
        return [byte[]](@(0xEF, 0xBB, 0xBF) + @($script:F68Utf8.GetBytes((($lines -join "`r`n") + "`r`n"))))
    }
}

Describe 'FIX68 undo receipts and the undo itself, with synthetic game folders' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        Mock Get-ExeArchitecture { 'x64' }
        $script:f68State = New-F68Root 'state'
        $script:f68Games = New-F68Root 'games'
    }

    It 'makes the receipt before the change: an exact copy of every file that exists, checked, and nothing for a file that does not exist yet' {
        # Mutation: copy only the DLL, skip the copy check, or keep the receipt in the menu while it is unfinished -> a payload, a hash or the entry count is wrong.
        $game = Join-Path $script:f68Games 'Receipt'
        Set-F68File -Path (Join-Path $game 'dxgi.dll') -Text 'users own dll'
        Set-F68File -Path (Join-Path $game 'ReShade.ini') -Text "[GENERAL]`r`nPresetPath=.\mine.ini`r`n"
        $paths = @((Join-Path $game 'dxgi.dll'), (Join-Path $game 'ReShade.ini'), (Join-Path $game 'Shaders\TPM\new.fx'))
        $request = New-TpmReShadeUndoRequest -GameId 'Receipt' -GameName 'Receipt Game' -Operation 'Adopt' -LookBefore 'Other' -LookAfter 'FastCrt' -OwnerBefore 'Other' -StateRoot $script:f68State
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths $paths -Roots @($game)
        $undo.Succeeded | Should -BeTrue
        $undo.Receipt.State | Should -BeExactly 'Prepared'
        $undo.Receipt.HoldsOriginal | Should -BeTrue
        @($undo.Receipt.Files).Count | Should -Be 3
        foreach ($file in @($undo.Receipt.Files)) {
            if ([IO.Path]::GetFileName([string]$file.Path) -eq 'new.fx') {
                $file.BeforeExists | Should -BeFalse
                [string]$file.Payload | Should -BeNullOrEmpty
                continue
            }
            $copy = Join-Path $undo.Folder ([string]$file.Payload)
            (Get-F68Bytes $copy) | Should -BeExactly (Get-F68Bytes ([string]$file.Path))
            [string]$file.BeforeSha256 | Should -BeExactly ((Get-FileHash -LiteralPath ([string]$file.Path) -Algorithm SHA256).Hash)
        }
        (Read-TpmReShadeUndoReceipt -Folder $undo.Folder -VerifyPayload).Valid | Should -BeTrue
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State).Count | Should -Be 0 -Because 'an unfinished receipt is not offered for undo'
    }

    It 'adopt saves the ReShade files TeknoParrot Manager did not install, and undo puts them back byte for byte' {
        # Mutation: make the receipt after Invoke-TpmTransactionalPromote, or leave the receipt out of Install-TpmReShadeProfileDeployment -> the user's dxgi.dll is lost.
        $root = Join-Path $script:f68Games 'Adopt'
        [void][IO.Directory]::CreateDirectory($root)
        $gameExe = Join-Path $root 'game.exe'; [IO.File]::WriteAllText($gameExe, 'MZ-test-game')
        $sourceDll = Join-Path $script:f68Games 'ReShade64.dll'; [IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $hook = Join-Path $root 'dxgi.dll'; [IO.File]::WriteAllBytes($hook, [byte[]](0x4D, 0x5A, 0x00, 0xFF, 0x10, 0x20, 0x7F))
        $ini = Join-Path $root 'ReShade.ini'; Set-F68File -Path $ini -Text "[GENERAL]`r`nPresetPath=.\my-own-look.ini`r`n"
        $ownership = Join-Path $script:f68State 'Deployments\adopt.json'
        $hookBefore = Get-F68Bytes $hook; $iniBefore = Get-F68Bytes $ini
        $request = Get-TpmReShadeSetupUndoRequest -GameId 'Adopt' -GameName 'Adopt Game' -Status 'UnknownUserOwnedConflict' -Manifest $null -ProfileId 'Original'
        $request.StateRoot = $script:f68State
        $result = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $gameExe -Doc ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>') -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath $ownership -CanonicalPreset -AllowUserOwnedOverwrite -UndoReceipt $request
        $result.Succeeded | Should -BeTrue -Because ($result | ConvertTo-Json -Depth 3)
        (Get-F68Bytes $hook) | Should -Not -BeExactly $hookBefore
        (Complete-TpmReShadeUndoReceipt -Undo $result.UndoReceipt) | Should -BeExactly 'Ready'
        $entry = Get-F68Entry -StateRoot $script:f68State -GameId 'Adopt'
        $entry.OwnerBefore | Should -BeExactly 'Other'
        $entry.Receipt.Operation | Should -BeExactly 'Adopt'
        (Get-TpmReShadeUndoRowText -Entry $entry) | Should -Match '^Adopt Game - its own ReShade -> Original, \d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
        $undone = Invoke-TpmReShadeUndo -Entry $entry
        $undone.Status | Should -BeExactly 'Undone'
        (Get-F68Bytes $hook) | Should -BeExactly $hookBefore
        (Get-F68Bytes $ini) | Should -BeExactly $iniBefore
        Test-Path -LiteralPath $ownership | Should -BeFalse -Because 'TeknoParrot Manager did not own this game before'
        Test-Path -LiteralPath $entry.Folder | Should -BeFalse -Because 'a finished undo cleans up its own receipt'
    }

    It 'switching the look and then undoing puts the files of the previous look back' {
        # Mutation: leave the ownership record or ReShade.ini out of the receipt paths -> the record or the preset still says Original after the undo.
        $root = Join-Path $script:f68Games 'Switch'
        $stage = Join-Path $script:f68Games 'effect-stage'
        [void][IO.Directory]::CreateDirectory($root); [void][IO.Directory]::CreateDirectory($stage)
        $gameExe = Join-Path $root 'game.exe'; [IO.File]::WriteAllText($gameExe, 'MZ-test-game')
        $sourceDll = Join-Path $script:f68Games 'ReShade64.dll'; [IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $effect = Join-Path $stage 'Levels.fx'; $header = Join-Path $stage 'ReShade.fxh'; $uiHeader = Join-Path $stage 'ReShadeUI.fxh'
        [IO.File]::WriteAllText($effect, 'effect-bytes'); [IO.File]::WriteAllText($header, 'reshade-header'); [IO.File]::WriteAllText($uiHeader, 'ui-header')
        $script:f68Stage = $stage
        $script:f68EffectFiles = @(
            [pscustomobject]@{ RelativePath = 'Shaders/SweetFX/Levels.fx'; SourceRelativePath = 'Shaders/SweetFX/Levels.fx'; Path = $effect; SHA256 = (Get-FileHash -LiteralPath $effect -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShade.fxh'; SourceRelativePath = 'Shaders/ReShade.fxh'; Path = $header; SHA256 = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShadeUI.fxh'; SourceRelativePath = 'TPM-authored/ReShadeUI.fxh'; Path = $uiHeader; SHA256 = (Get-FileHash -LiteralPath $uiHeader -Algorithm SHA256).Hash }
        )
        Mock Install-TpmReShadeApprovedEffect { [pscustomobject]@{ Succeeded = $true; State = 'PREPARED'; StagingRoot = $script:f68Stage; Files = $script:f68EffectFiles } }
        $ownership = Join-Path $script:f68State 'Deployments\switch.json'
        $doc = [xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>'
        $first = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Levels) -GamePath $gameExe -Doc $doc -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath $ownership -CanonicalPreset
        $first.Succeeded | Should -BeTrue -Because ($first | ConvertTo-Json -Depth 3)
        $ini = Join-Path $root 'ReShade.ini'; $hook = Join-Path $root 'dxgi.dll'; $levels = Join-Path $root 'Shaders\SweetFX\Levels.fx'
        $levelsState = @{ Ini = (Get-F68Bytes $ini); Hook = (Get-F68Bytes $hook); Own = (Get-F68Bytes $ownership); Fx = (Get-F68Bytes $levels) }
        $request = Get-TpmReShadeSetupUndoRequest -GameId 'Switch' -GameName 'Switch Game' -Status 'TPMOwnedChangedProfile' -Manifest (Read-TpmReShadeOwnershipManifest -Path $ownership) -ProfileId 'Original'
        $request.StateRoot = $script:f68State
        $request.Operation | Should -BeExactly 'Switch'
        $second = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $gameExe -Doc $doc -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath $ownership -CanonicalPreset -UndoReceipt $request
        $second.Succeeded | Should -BeTrue -Because ($second | ConvertTo-Json -Depth 3)
        (Complete-TpmReShadeUndoReceipt -Undo $second.UndoReceipt) | Should -BeExactly 'Ready'
        (Get-F68Bytes $ini) | Should -Not -BeExactly $levelsState.Ini
        $entry = Get-F68Entry -StateRoot $script:f68State -GameId 'Switch'
        (Get-TpmReShadeUndoRowText -Entry $entry) | Should -Match ('^Switch Game - ' + [regex]::Escape((Get-TpmReShadeLookName -LookId 'Levels')) + ' -> Original, ')
        (Invoke-TpmReShadeUndo -Entry $entry).Status | Should -BeExactly 'Undone'
        (Get-F68Bytes $ini) | Should -BeExactly $levelsState.Ini
        (Get-F68Bytes $hook) | Should -BeExactly $levelsState.Hook
        (Get-F68Bytes $ownership) | Should -BeExactly $levelsState.Own
        (Get-F68Bytes $levels) | Should -BeExactly $levelsState.Fx
        (Read-TpmReShadeOwnershipManifest -Path $ownership).EffectId | Should -BeExactly 'ReShadeProfile.Levels'
    }

    It 'a switch still succeeds when a leftover file of the previous look was deleted, and the record stops listing it' {
        $root = Join-Path $script:f68Games 'SwitchGone'
        $stage = Join-Path $script:f68Games 'effect-stage-gone'
        [void][IO.Directory]::CreateDirectory($root); [void][IO.Directory]::CreateDirectory($stage)
        $gameExe = Join-Path $root 'game.exe'; [IO.File]::WriteAllText($gameExe, 'MZ-test-game')
        $sourceDll = Join-Path $script:f68Games 'ReShade64.dll'; [IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $effect = Join-Path $stage 'Levels.fx'; $header = Join-Path $stage 'ReShade.fxh'; $uiHeader = Join-Path $stage 'ReShadeUI.fxh'
        [IO.File]::WriteAllText($effect, 'effect-bytes'); [IO.File]::WriteAllText($header, 'reshade-header'); [IO.File]::WriteAllText($uiHeader, 'ui-header')
        $script:f68Stage = $stage
        $script:f68EffectFiles = @(
            [pscustomobject]@{ RelativePath = 'Shaders/SweetFX/Levels.fx'; SourceRelativePath = 'Shaders/SweetFX/Levels.fx'; Path = $effect; SHA256 = (Get-FileHash -LiteralPath $effect -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShade.fxh'; SourceRelativePath = 'Shaders/ReShade.fxh'; Path = $header; SHA256 = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShadeUI.fxh'; SourceRelativePath = 'TPM-authored/ReShadeUI.fxh'; Path = $uiHeader; SHA256 = (Get-FileHash -LiteralPath $uiHeader -Algorithm SHA256).Hash }
        )
        Mock Install-TpmReShadeApprovedEffect { [pscustomobject]@{ Succeeded = $true; State = 'PREPARED'; StagingRoot = $script:f68Stage; Files = $script:f68EffectFiles } }
        $ownership = Join-Path $script:f68State 'Deployments\switchgone.json'
        $doc = [xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>'
        $first = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Levels) -GamePath $gameExe -Doc $doc -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath $ownership -CanonicalPreset
        $first.Succeeded | Should -BeTrue -Because ($first | ConvertTo-Json -Depth 3)
        Remove-Item -LiteralPath (Join-Path $root 'Shaders\SweetFX\Levels.fx') -Force
        $second = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $gameExe -Doc $doc -SourceDll $sourceDll -SourceVersion '6.0.0' -CacheRoot (Join-Path $root 'cache') -OwnershipPath $ownership -CanonicalPreset
        $second.Succeeded | Should -BeTrue -Because ($second | ConvertTo-Json -Depth 3)
        (Test-TpmReShadeDeploymentVerified -DeploymentResult $second) | Should -BeTrue
        @((Read-TpmReShadeOwnershipManifest -Path $ownership).Files | ForEach-Object { [IO.Path]::GetFileName([string]$_.DestinationPath) }) | Should -Not -Contain 'Levels.fx'
    }

    It 'undoes one game and leaves every other game and its receipt alone' {
        # Mutation: let Invoke-TpmReShadeUndo work on every receipt, or remove the whole UndoReceipts folder after an undo -> game B changes or loses its receipt.
        $gameA = Join-Path $script:f68Games 'A'; $gameB = Join-Path $script:f68Games 'B'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $gameA -GameId 'A' -Before @{ 'dxgi.dll' = $null; 'ReShade.ini' = 'a-own' } -After @{ 'dxgi.dll' = 'tpm-dll'; 'ReShade.ini' = 'a-tpm' })
        [void](New-F68Change -StateRoot $script:f68State -GameDir $gameB -GameId 'B' -Before @{ 'dxgi.dll' = $null; 'ReShade.ini' = 'b-own' } -After @{ 'dxgi.dll' = 'tpm-dll'; 'ReShade.ini' = 'b-tpm' })
        $entryB = Get-F68Entry -StateRoot $script:f68State -GameId 'B'
        (Invoke-TpmReShadeUndo -Entry (Get-F68Entry -StateRoot $script:f68State -GameId 'A')).Status | Should -BeExactly 'Undone'
        Test-Path -LiteralPath (Join-Path $gameA 'dxgi.dll') | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $gameA 'ReShade.ini')) | Should -BeExactly 'a-own'
        [IO.File]::ReadAllText((Join-Path $gameB 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        [IO.File]::ReadAllText((Join-Path $gameB 'ReShade.ini')) | Should -BeExactly 'b-tpm'
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State | ForEach-Object { $_.GameId }) | Should -Be @('B')
        Test-Path -LiteralPath $entryB.Folder | Should -BeTrue
    }

    It 'does not overwrite a game that changed after the receipt, and keeps the receipt' {
        # Mutation: skip Get-TpmReShadeUndoCheck (or treat any difference as "as left") -> the user's later edit is overwritten.
        $game = Join-Path $script:f68Games 'Edited'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Edited' -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' })
        Set-F68File -Path (Join-Path $game 'ReShade.ini') -Text 'my later edit'
        $entry = Get-F68Entry -StateRoot $script:f68State -GameId 'Edited'
        $result = Invoke-TpmReShadeUndo -Entry $entry
        $result.Status | Should -BeExactly 'ChangedSince'
        $result.Code | Should -BeExactly 'UNDO_CHANGED_SINCE'
        @($result.Changed) | Should -Be @((Join-Path $game 'ReShade.ini'))
        [IO.File]::ReadAllText((Join-Path $game 'ReShade.ini')) | Should -BeExactly 'my later edit'
        Test-Path -LiteralPath $entry.Folder | Should -BeTrue
    }

    It 'rolls the game back to how it was when the undo fails half way, and keeps the receipt' {
        # Mutation: restore the files one by one without the transaction (no rollback) -> a.ini stays restored while b.ini is lost or still new.
        $game = Join-Path $script:f68Games 'Half'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Half' -Before @{ 'a.ini' = 'a-own'; 'b.ini' = 'b-own' } -After @{ 'a.ini' = 'a-tpm'; 'b.ini' = 'b-tpm' })
        $entry = Get-F68Entry -StateRoot $script:f68State -GameId 'Half'
        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like '*0001.payload') { throw 'simulated failure while the second file is put back' }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }
        $result = Invoke-TpmReShadeUndo -Entry $entry
        $result.Status | Should -BeExactly 'RolledBack'
        $result.Code | Should -BeExactly 'UNDO_ROLLED_BACK'
        [IO.File]::ReadAllText((Join-Path $game 'a.ini')) | Should -BeExactly 'a-tpm'
        [IO.File]::ReadAllText((Join-Path $game 'b.ini')) | Should -BeExactly 'b-tpm'
        Test-Path -LiteralPath $entry.Folder | Should -BeTrue
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State).Count | Should -Be 1
    }

    It 'changes nothing in a game when its receipt cannot be made' {
        # Mutation: ignore the failed receipt in Install-TpmReShadeProfileDeployment and promote anyway -> the promote runs and the user's dxgi.dll is replaced.
        $root = Join-Path $script:f68Games 'NoReceipt'
        [void][IO.Directory]::CreateDirectory($root)
        $gameExe = Join-Path $root 'game.exe'; [IO.File]::WriteAllText($gameExe, 'MZ-test-game')
        $sourceDll = Join-Path $script:f68Games 'ReShade64.dll'; [IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $hook = Join-Path $root 'dxgi.dll'; Set-F68File -Path $hook -Text 'users own dll'
        $hookBefore = Get-F68Bytes $hook
        Mock New-TpmReShadeUndoReceipt { [pscustomobject]@{ Succeeded = $false; Folder = ''; Receipt = $null; Reason = 'fixture: the disk is full' } }
        Mock Invoke-TpmTransactionalPromote { throw 'must not write' }
        $request = New-TpmReShadeUndoRequest -GameId 'NoReceipt' -Operation 'Adopt' -LookBefore 'Other' -LookAfter 'Original' -OwnerBefore 'Other' -StateRoot $script:f68State
        $result = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $gameExe -Doc ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>') -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath (Join-Path $script:f68State 'Deployments\n.json') -CanonicalPreset -AllowUserOwnedOverwrite -UndoReceipt $request
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'UNDO_RECEIPT_FAILED'
        Should -Invoke Invoke-TpmTransactionalPromote -Times 0
        (Get-F68Bytes $hook) | Should -BeExactly $hookBefore
        Test-Path -LiteralPath (Join-Path $root 'ReShade.ini') | Should -BeFalse
        (Get-TpmPlainReason -Code 'UNDO_RECEIPT_FAILED').Text | Should -BeExactly 'A copy for undo could not be saved, so nothing was changed.'
    }

    It 'leaves nothing behind when a receipt cannot be checked' {
        # Mutation: keep the half-made receipt folder on failure -> an unfinished folder stays under UndoReceipts.
        $game = Join-Path $script:f68Games 'Folder'
        [void][IO.Directory]::CreateDirectory((Join-Path $game 'ReShade.ini'))
        $request = New-TpmReShadeUndoRequest -GameId 'Folder' -Operation 'Install' -StateRoot $script:f68State
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $game 'ReShade.ini')) -Roots @($game)
        $undo.Succeeded | Should -BeFalse
        $undo.Reason | Should -Match 'folder is where a file'
        @(Get-ChildItem -LiteralPath (Get-TpmReShadeUndoGameFolder -GameId 'Folder' -StateRoot $script:f68State) -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'puts TeknoParrot''s own CRT setting back byte for byte' {
        # Mutation: leave the game profile out of the receipt (ExtraPaths) -> the profile keeps None after the undo.
        $game = Join-Path $script:f68Games 'Crt'
        $profilePath = Join-Path $script:f68Games 'UserProfiles\Crt.xml'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($profilePath))
        [IO.File]::WriteAllBytes($profilePath, (New-F68CrtProfileBytes))
        $profileBefore = Get-F68Bytes $profilePath
        Set-F68File -Path (Join-Path $game 'ReShade.ini') -Text 'own'
        $request = New-TpmReShadeUndoRequest -GameId 'Crt' -GameName 'Crt Game' -Operation 'Install' -LookAfter 'FastCrt' -ExtraPaths @($profilePath) -StateRoot $script:f68State
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths @((Join-Path $game 'ReShade.ini')) -Roots @($game)
        $undo.Succeeded | Should -BeTrue
        Set-F68File -Path (Join-Path $game 'ReShade.ini') -Text 'tpm'
        $write = Set-TpmReShadeNativeCrtOff -ProfilePath $profilePath -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $write.Outcome | Should -BeExactly 'TurnedOff'
        (Get-F68Bytes $profilePath) | Should -Not -BeExactly $profileBefore
        (Complete-TpmReShadeUndoReceipt -Undo $undo -NativeShader ([pscustomobject]@{ Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None' })) | Should -BeExactly 'Ready'
        $entry = Get-F68Entry -StateRoot $script:f68State -GameId 'Crt'
        $entry.Receipt.NativeShader.Before | Should -BeExactly 'Lottes'
        $entry.Receipt.NativeShader.After | Should -BeExactly 'None'
        @(Get-TpmReShadeUndoPlainLines -Entry $entry) | Should -Contain "TeknoParrot's own CRT look is turned back on."
        (Invoke-TpmReShadeUndo -Entry $entry).Status | Should -BeExactly 'Undone'
        (Get-F68Bytes $profilePath) | Should -BeExactly $profileBefore
        [IO.File]::ReadAllText((Join-Path $game 'ReShade.ini')) | Should -BeExactly 'own'
    }

    It 'keeps only the newest 5 receipts of a game whose first change was a plain install' {
        # Mutation: never remove older receipts (or remove the newest instead of the oldest) -> 7 receipts stay, or the newest change cannot be undone.
        $game = Join-Path $script:f68Games 'Plain'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Plain' -Before @{ 'ReShade.ini' = $null } -After @{ 'ReShade.ini' = 'look1' } -LookAfter 'Look1')
        for ($i = 2; $i -le 7; $i++) {
            [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Plain' -Before @{ 'ReShade.ini' = ('look{0}' -f ($i - 1)) } -After @{ 'ReShade.ini' = ('look{0}' -f $i) } -Operation 'Switch' -LookBefore ('Look{0}' -f ($i - 1)) -LookAfter ('Look{0}' -f $i) -OwnerBefore 'TeknoParrotManager' -NoSetup)
        }
        $receipts = @(Get-TpmReShadeUndoReceipts -GameFolder (Get-TpmReShadeUndoGameFolder -GameId 'Plain' -StateRoot $script:f68State) | Where-Object { $_.Valid })
        $receipts.Count | Should -Be 5
        @($receipts | ForEach-Object { [string]$_.Receipt.LookAfter }) | Should -Be @('Look7', 'Look6', 'Look5', 'Look4', 'Look3')
        (Invoke-TpmReShadeUndo -Entry (Get-F68Entry -StateRoot $script:f68State -GameId 'Plain')).Status | Should -BeExactly 'Undone'
        [IO.File]::ReadAllText((Join-Path $game 'ReShade.ini')) | Should -BeExactly 'look6'
    }

    It 'never removes the receipt that holds the ReShade TeknoParrot Manager did not install, so all undos still bring it back' {
        # Mutation: prune past 5 even when an older receipt has HoldsOriginal -> the adopt receipt is gone and the last undo cannot reach 'own'.
        $game = Join-Path $script:f68Games 'Many'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Many' -Before @{ 'ReShade.ini' = 'own'; 'dxgi.dll' = 'own-dll' } -After @{ 'ReShade.ini' = 'look1'; 'dxgi.dll' = 'tpm-dll' } -Operation 'Adopt' -LookBefore 'Other' -LookAfter 'Look1' -OwnerBefore 'Other')
        for ($i = 2; $i -le 7; $i++) {
            [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'Many' -Before @{ 'ReShade.ini' = ('look{0}' -f ($i - 1)) } -After @{ 'ReShade.ini' = ('look{0}' -f $i) } -Operation 'Switch' -LookBefore ('Look{0}' -f ($i - 1)) -LookAfter ('Look{0}' -f $i) -OwnerBefore 'TeknoParrotManager' -NoSetup)
        }
        $receipts = @(Get-TpmReShadeUndoReceipts -GameFolder (Get-TpmReShadeUndoGameFolder -GameId 'Many' -StateRoot $script:f68State) | Where-Object { $_.Valid })
        $receipts.Count | Should -Be 7
        $receipts[$receipts.Count - 1].Receipt.HoldsOriginal | Should -BeTrue
        for ($round = 0; $round -lt 7; $round++) {
            (Invoke-TpmReShadeUndo -Entry (Get-F68Entry -StateRoot $script:f68State -GameId 'Many')).Status | Should -BeExactly 'Undone'
        }
        [IO.File]::ReadAllText((Join-Path $game 'ReShade.ini')) | Should -BeExactly 'own'
        [IO.File]::ReadAllText((Join-Path $game 'dxgi.dll')) | Should -BeExactly 'own-dll'
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State).Count | Should -Be 0
    }

    It 'names install, switch, update and adopt from the ownership check' {
        # Mutation: call every TeknoParrot Manager change "Install", or treat a ReShade it did not install as its own -> the receipt names the wrong look before and the wrong owner.
        $levels = [pscustomobject]@{ EffectId = 'ReShadeProfile.Levels' }
        $install = Get-TpmReShadeSetupUndoRequest -GameId 'g' -Status 'NoReShadePresent' -Manifest $null -ProfileId 'FastCrt'
        @($install.Operation, $install.OwnerBefore, $install.LookBefore) | Should -Be @('Install', 'None', 'None')
        $switched = Get-TpmReShadeSetupUndoRequest -GameId 'g' -Status 'TPMOwnedChangedProfile' -Manifest $levels -ProfileId 'FastCrt'
        @($switched.Operation, $switched.OwnerBefore, $switched.LookBefore) | Should -Be @('Switch', 'TeknoParrotManager', 'Levels')
        $update = Get-TpmReShadeSetupUndoRequest -GameId 'g' -Status 'TPMOwnedStaleOutdated' -Manifest $levels -ProfileId 'Levels'
        $update.Operation | Should -BeExactly 'Update'
        $adopt = Get-TpmReShadeSetupUndoRequest -GameId 'g' -Status 'BundledPreinstalledProtected' -Manifest $levels -ProfileId 'FastCrt'
        @($adopt.Operation, $adopt.OwnerBefore, $adopt.LookBefore) | Should -Be @('Adopt', 'Other', 'Other')
    }
}

Describe 'FIX68 ReShade removal makes a receipt too' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f68Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f68Rows.Add([string]$Object) }
        Mock Get-ConsoleContentWidth { 100 }
        $script:f68Root = New-F68Root 'removal'
        $script:f68Profiles = Join-Path $script:f68Root 'UserProfiles'
        $script:f68RemovalState = Join-Path $script:f68Root 'state'
        [void][IO.Directory]::CreateDirectory($script:f68Profiles)
        $gameExe = Join-Path $script:f68Root 'game.exe'; [IO.File]::WriteAllText($gameExe, 'game')
        $script:f68Hook = Join-Path $script:f68Root 'dxgi.dll'; [IO.File]::WriteAllText($script:f68Hook, 'owned')
        [IO.File]::WriteAllText((Join-Path $script:f68Profiles 'Flow.xml'), '<GameProfile><GameName>Flow Game</GameName><GamePath>' + $gameExe + '</GamePath><EmulatorType>Default</EmulatorType></GameProfile>')
        $hash = (Get-FileHash -LiteralPath $script:f68Hook -Algorithm SHA256).Hash
        $script:f68Ownership = Get-TpmReShadeProfileOwnershipPath -GameId Flow -StateRoot $script:f68RemovalState
        Save-TpmReShadeOwnershipManifest -Manifest ([pscustomobject]@{ SchemaVersion = 1; EffectId = 'ReShadeProfile.CleanSharp'; PinnedRevision = 'TPM-PROFILE'; Files = @([pscustomobject]@{ RelativeSource = 'dxgi.dll'; DestinationPath = $script:f68Hook; ExpectedSHA256 = $hash; ActualSHA256 = $hash; TPMManaged = $true; Kind = 'ReShadeDll' }) }) -Path $script:f68Ownership
    }

    It 'removes, says Next: undo, and undo puts the removed file and the ownership record back' {
        # Mutation: leave the receipt out of Remove-TpmReShadeOwnedDeployment -> no entry to undo and the removed files cannot come back.
        $hookBefore = Get-F68Bytes $script:f68Hook
        $ownershipBefore = Get-F68Bytes $script:f68Ownership
        $script:f68Prompt = 0
        Mock Read-HostSafe { if ($script:f68Prompt++ -eq 0) { 'A' } else { 'REMOVE' } }
        $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $script:f68Profiles -StateRoot $script:f68RemovalState -BackupRoot (Join-Path $script:f68Profiles 'FullBackup')
        $summary.Removed | Should -Be 1
        $summary.ReceiptFailed | Should -Be 0
        Test-Path -LiteralPath $script:f68Hook | Should -BeFalse
        (Get-F68Text $script:f68Rows) | Should -Match ([regex]::Escape('Next: You can undo this in ReShade > Undo ReShade changes.'))
        $entry = Get-F68Entry -StateRoot $script:f68RemovalState -GameId 'Flow'
        $entry.GameName | Should -BeExactly 'Flow Game'
        $entry.LookAfter | Should -BeExactly 'None'
        (Invoke-TpmReShadeUndo -Entry $entry).Status | Should -BeExactly 'Undone'
        (Get-F68Bytes $script:f68Hook) | Should -BeExactly $hookBefore
        (Get-F68Bytes $script:f68Ownership) | Should -BeExactly $ownershipBefore
    }

    It 'removes nothing when the receipt of the removal cannot be made, and says so' {
        # Mutation: make the receipt after the first Remove-Item, or ignore its failure -> dxgi.dll is gone without a copy for undo.
        Mock New-TpmReShadeUndoReceipt { [pscustomobject]@{ Succeeded = $false; Folder = ''; Receipt = $null; Reason = 'fixture: the disk is full' } }
        $script:f68Prompt = 0
        Mock Read-HostSafe { if ($script:f68Prompt++ -eq 0) { 'A' } else { 'REMOVE' } }
        $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $script:f68Profiles -StateRoot $script:f68RemovalState -BackupRoot (Join-Path $script:f68Profiles 'FullBackup')
        $summary.ReceiptFailed | Should -Be 1
        $summary.Removed | Should -Be 0
        $summary.Succeeded | Should -BeFalse
        @($summary.Results)[0].Status | Should -BeExactly 'ReceiptFailed'
        Test-Path -LiteralPath $script:f68Hook | Should -BeTrue
        Test-Path -LiteralPath $script:f68Ownership | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:f68Profiles 'FullBackup') | Should -BeFalse -Because 'nothing was copied or removed'
        $text = Get-F68Text $script:f68Rows
        $text | Should -Match ([regex]::Escape('1 game not changed, because a copy for undo could not be saved.'))
        $text | Should -Not -Match 'Next: You can undo'
    }

    It 'says so, and does not call the run a success, when the files are removed but the undo copy cannot be finished' {
        # Mutation: ignore the 'Missing' answer of Complete-TpmReShadeUndoReceipt in Remove-TpmReShadeOwnedDeployment -> the game cannot be undone and nothing tells the user.
        Mock Complete-TpmReShadeUndoReceipt { 'Missing' }
        $script:f68Prompt = 0
        Mock Read-HostSafe { if ($script:f68Prompt++ -eq 0) { 'A' } else { 'REMOVE' } }
        $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $script:f68Profiles -StateRoot $script:f68RemovalState -BackupRoot (Join-Path $script:f68Profiles 'FullBackup')
        $summary.Removed | Should -Be 1
        $summary.UndoMissing | Should -Be 1
        $summary.Succeeded | Should -BeFalse
        $text = Get-F68Text $script:f68Rows
        $text | Should -Match ([regex]::Escape('the copy that lets you undo it could not be finished'))
        $text | Should -Not -Match 'Next: You can undo'
    }
}

Describe 'FIX68 the Undo menu' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f68Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f68Rows.Add([string]$Object) }
        $script:f68Width = 100
        Mock Get-ConsoleContentWidth { $script:f68Width }
        Mock Test-TpmInteractiveInput { $false }
        $script:f68Choices = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f68ChoiceCalls = New-Object 'System.Collections.Generic.List[object]'
        Mock Read-TpmChoice {
            [void]$script:f68ChoiceCalls.Add([pscustomobject]@{ Prompt = [string]$Prompt; Choices = @($Choices); At = $script:f68Rows.Count })
            if ($script:f68Choices.Count -gt 0) { return $script:f68Choices.Dequeue() }
            return 'B'
        }
        $script:f68Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f68Prompts = New-Object 'System.Collections.Generic.List[string]'
        Mock Read-HostSafe {
            [void]$script:f68Prompts.Add([string]$Prompt)
            if ($script:f68Answers.Count -gt 0) { return $script:f68Answers.Dequeue() }
            return ''
        }
        $script:f68State = New-F68Root 'menu-state'
        $script:f68Games = New-F68Root 'menu-games'
    }

    It 'lists at most 4 games per page in plain words, newest first, with More: M' {
        # Mutation: print every game at once, or the receipt folder and codes in the rows -> more than 4 numbered rows, or a path or code in the list.
        for ($i = 1; $i -le 10; $i++) {
            $id = 'G{0:D2}' -f $i
            [void](New-F68Change -StateRoot $script:f68State -GameDir (Join-Path $script:f68Games $id) -GameId $id -Before @{ 'dxgi.dll' = $null } -After @{ 'dxgi.dll' = 'tpm' })
        }
        $script:f68Choices.Enqueue('M'); $script:f68Choices.Enqueue('B')
        Show-TpmReShadeUndoMenu -StateRoot $script:f68State
        $firstPage = @($script:f68Rows | Select-Object -First $script:f68ChoiceCalls[0].At)
        $numbered = @($firstPage | Where-Object { $_ -match '^\s+\d+\) ' })
        $numbered.Count | Should -Be 4
        $numbered[0] | Should -Match '^  1\) Game G10 - no ReShade -> Fast CRT, \d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
        $numbered[3] | Should -Match '^  4\) Game G07 - '
        (Get-F68Text $firstPage) | Should -Match ([regex]::Escape('More: M (6 more games)'))
        (Get-F68Text $firstPage) | Should -Match ([regex]::Escape('[A] Undo all (10 games)'))
        @($firstPage | Where-Object { $_ -cmatch '\\|UNDO_|[Rr]eceipt|SHA-?256|\bTPM\b|payload' }).Count | Should -Be 0
        @($script:f68ChoiceCalls[0].Choices) | Should -Contain '4'
        @($script:f68ChoiceCalls[0].Choices) | Should -Not -Contain '5'
        @($script:f68ChoiceCalls[0].Choices) | Should -Contain 'M'
        $secondPage = @($script:f68Rows | Select-Object -Skip $script:f68ChoiceCalls[0].At -First ($script:f68ChoiceCalls[1].At - $script:f68ChoiceCalls[0].At))
        @($secondPage | Where-Object { $_ -match '^\s+\d+\) ' }).Count | Should -Be 4
        @($secondPage | Where-Object { $_ -match '^\s+\d+\) ' })[1] | Should -Match '^  2\) Game G05 - '
    }

    It 'shows the technical facts only under D, one block per game' {
        # Mutation: print the Details blocks in the default list -> "Saved copy:" appears before D is pressed.
        [void](New-F68Change -StateRoot $script:f68State -GameDir (Join-Path $script:f68Games 'D1') -GameId 'D1' -Before @{ 'dxgi.dll' = $null } -After @{ 'dxgi.dll' = 'tpm' })
        $script:f68Choices.Enqueue('D'); $script:f68Choices.Enqueue('B')
        Show-TpmReShadeUndoMenu -StateRoot $script:f68State
        $beforeD = @($script:f68Rows | Select-Object -First $script:f68ChoiceCalls[0].At)
        $afterD = @($script:f68Rows | Select-Object -Skip $script:f68ChoiceCalls[0].At)
        (Get-F68Text $beforeD) | Should -Not -Match 'Saved copy:'
        $details = Get-F68Text $afterD
        $details | Should -Match 'Game D1 Change: ReShade was installed'
        $details | Should -Match 'Look before: +no ReShade'
        $details | Should -Match 'Look now: +Fast CRT'
        $details | Should -Match 'Files the change added: +1'
        $details | Should -Match 'Saved copy: '
    }

    It 'undoes one game only after a typed YES; any other answer changes nothing' {
        # Mutation: accept Enter or "yes please" as YES, or skip the question -> the game is undone after the first answer.
        $gameA = Join-Path $script:f68Games 'UA'; $gameB = Join-Path $script:f68Games 'UB'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $gameA -GameId 'UA' -Before @{ 'dxgi.dll' = $null } -After @{ 'dxgi.dll' = 'tpm' })
        [void](New-F68Change -StateRoot $script:f68State -GameDir $gameB -GameId 'UB' -Before @{ 'dxgi.dll' = $null } -After @{ 'dxgi.dll' = 'tpm' })
        # Row 1 is UB (the newest), row 2 is UA: UA is picked twice, the first answer cancels and the second is YES.
        $script:f68Choices.Enqueue('2'); $script:f68Choices.Enqueue('2'); $script:f68Choices.Enqueue('B')
        $script:f68Answers.Enqueue('yes please'); $script:f68Answers.Enqueue('YES')
        Show-TpmReShadeUndoMenu -StateRoot $script:f68State
        Test-Path -LiteralPath (Join-Path $gameA 'dxgi.dll') | Should -BeFalse -Because 'YES was typed the second time'
        Test-Path -LiteralPath (Join-Path $gameB 'dxgi.dll') | Should -BeTrue
        $text = Get-F68Text $script:f68Rows
        $text | Should -Match ([regex]::Escape('Game UA goes back from Fast CRT to no ReShade.'))
        $text | Should -Match ([regex]::Escape('The ReShade files TeknoParrot Manager added are removed.'))
        $text | Should -Match ([regex]::Escape('Canceled. Nothing was changed.'))
        $text | Should -Match ([regex]::Escape('ReShade changes were undone for 1 game.'))
        $text | Should -Match ([regex]::Escape('Next: Start the game to check its look.'))
        @($script:f68Prompts | Where-Object { $_ -match 'Type YES to undo it' }).Count | Should -Be 2
    }

    It 'says plainly which kind of file changed, leaves the game as it is, and does not ask YES when nothing else can be put back' {
        # Mutation: ask for YES (or undo) when the files changed since the receipt, or leave the kind of file out -> a YES prompt appears, the edit is lost or the text is missing.
        $game = Join-Path $script:f68Games 'CS'
        [void](New-F68Change -StateRoot $script:f68State -GameDir $game -GameId 'CS' -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' })
        Set-F68File -Path (Join-Path $game 'ReShade.ini') -Text 'edited later'
        Invoke-TpmReShadeUndoGameChoice -Entry (Get-F68Entry -StateRoot $script:f68State -GameId 'CS')
        [IO.File]::ReadAllText((Join-Path $game 'ReShade.ini')) | Should -BeExactly 'edited later'
        (Get-F68Text $script:f68Rows) | Should -Match ([regex]::Escape('Game CS changed after TeknoParrot Manager changed it. These files are different now: - The ReShade settings file To keep those later changes, nothing is undone.'))
        @($script:f68Prompts).Count | Should -Be 0
        @($script:f68ChoiceCalls[0].Choices) | Should -Be @('D', 'C')
    }

    It 'undoes all games after a typed ALL, and nothing on any other answer' {
        # Mutation: start Undo all without the ALL check, or undo only the visible page -> the first answer already changes files, or a game stays changed.
        $games = @()
        for ($i = 1; $i -le 9; $i++) {
            $id = 'All{0}' -f $i
            $dir = Join-Path $script:f68Games $id
            $games += $dir
            [void](New-F68Change -StateRoot $script:f68State -GameDir $dir -GameId $id -Before @{ 'ReShade.ini' = ('own' + $i) } -After @{ 'ReShade.ini' = 'tpm' })
        }
        $entries = @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State)
        $script:f68Answers.Enqueue('no')
        Invoke-TpmReShadeUndoAllChoice -Entries $entries
        foreach ($dir in $games) { [IO.File]::ReadAllText((Join-Path $dir 'ReShade.ini')) | Should -BeExactly 'tpm' }
        $script:f68Answers.Enqueue('ALL')
        Invoke-TpmReShadeUndoAllChoice -Entries $entries
        for ($i = 1; $i -le 9; $i++) { [IO.File]::ReadAllText((Join-Path $games[$i - 1] 'ReShade.ini')) | Should -BeExactly ('own' + $i) }
        @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State).Count | Should -Be 0
        $text = Get-F68Text $script:f68Rows
        $text | Should -Match ([regex]::Escape('This undoes the last ReShade change of 9 games.'))
        $text | Should -Match ([regex]::Escape('- 9 games go back to no ReShade.'))
        $text | Should -Match ([regex]::Escape('ReShade changes were undone for 9 games.'))
    }

    It 'groups the games of Undo all by result: undone ones and changed ones each on one line' {
        # Mutation: write one line per game in the result -> the grouped "2 games changed after ..." line is missing.
        $ids = @('R1', 'R2', 'R3')
        foreach ($id in $ids) { [void](New-F68Change -StateRoot $script:f68State -GameDir (Join-Path $script:f68Games $id) -GameId $id -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' }) }
        Set-F68File -Path (Join-Path $script:f68Games 'R2\ReShade.ini') -Text 'edit'
        Set-F68File -Path (Join-Path $script:f68Games 'R3\ReShade.ini') -Text 'edit'
        $script:f68Answers.Enqueue('ALL')
        Invoke-TpmReShadeUndoAllChoice -Entries @(Get-TpmReShadeUndoEntries -StateRoot $script:f68State)
        $text = Get-F68Text $script:f68Rows
        $text | Should -Match ([regex]::Escape('ReShade changes were undone for 1 game.'))
        $text | Should -Match ([regex]::Escape('Not changed: 2 games changed after TeknoParrot Manager changed them. They were left as they are.'))
        @($script:f68Rows | Where-Object { $_ -match 'Game R2|Game R3' }).Count | Should -Be 0 -Because 'game names are only under Details'
    }
}

Describe 'FIX68 the Undo screens reflow at <Width> columns' -ForEach @(@{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }) {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f68Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f68Rows.Add([string]$Object) }
        $script:f68Width = $Width
        Mock Get-ConsoleContentWidth { $script:f68Width }
        Mock Test-TpmInteractiveInput { $false }
        $script:f68Choices = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f68ChoiceAt = New-Object 'System.Collections.Generic.List[int]'
        Mock Read-TpmChoice { [void]$script:f68ChoiceAt.Add($script:f68Rows.Count); if ($script:f68Choices.Count -gt 0) { return $script:f68Choices.Dequeue() }; return 'B' }
        $script:f68PromptAt = New-Object 'System.Collections.Generic.List[int]'
        Mock Read-HostSafe { [void]$script:f68PromptAt.Add($script:f68Rows.Count); return 'YES' }
        $script:f68State = New-F68Root 'width-state'
        $script:f68Games = New-F68Root 'width-games'
    }

    It 'keeps the list, the question and the result inside the console, the result a short run' {
        # Mutation: print a row with Write-Host and fixed text instead of Write-TpmText -> a row reaches the console width; or drop the blank lines -> the result runs on.
        for ($i = 1; $i -le 3; $i++) {
            $id = 'W{0}' -f $i
            [void](New-F68Change -StateRoot $script:f68State -GameDir (Join-Path $script:f68Games $id) -GameId $id -Before @{ 'ReShade.ini' = 'own' } -After @{ 'ReShade.ini' = 'tpm' } -OwnerBefore 'Other' -LookBefore 'Other' -Operation 'Adopt')
        }
        $script:f68Choices.Enqueue('1'); $script:f68Choices.Enqueue('B')
        Show-TpmReShadeUndoMenu -StateRoot $script:f68State
        $rows = @($script:f68Rows | ForEach-Object { ([string]$_).TrimEnd() })
        @($rows | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $question = @($rows[$script:f68ChoiceAt[0]..($script:f68PromptAt[0] - 1)])
        (Get-F68LongestRun -Rows $question -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $resultAt = Get-F68RowIndex -Rows $rows -Pattern 'ReShade changes were undone'
        $resultAt | Should -BeGreaterThan $script:f68PromptAt[0]
        $listAgain = $rows.Count
        for ($i = $resultAt + 1; $i -lt $rows.Count; $i++) { if ($rows[$i] -match '^\s*Undo ReShade changes$') { $listAgain = $i; break } }
        $result = @($rows[$resultAt..($listAgain - 1)])
        (Get-F68LongestRun -Rows $result -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        (Get-F68Text $rows) | Should -Match ([regex]::Escape('Its own ReShade files are put back exactly as they were.'))
        (Get-F68Text $rows) | Should -Not -Match '\b1 games\b'
    }
}

Describe 'FIX68 the result screens point to the undo menu' {
    BeforeEach {
        Mock Write-Log {}
        $script:f68Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f68Rows.Add([string]$Object) }
        Mock Get-ConsoleContentWidth { 100 }
        Mock Read-HostSafe { '' }
        Mock Test-TpmInteractiveInput { $false }
    }

    It 'says Next: undo on the ReShade result screen only when the change has a receipt' -ForEach @(
        @{ Case = 'ready'; Ready = @('GameA'); Missing = @(); Next = $true; NotReady = $false }
        @{ Case = 'no receipt'; Ready = @(); Missing = @(); Next = $false; NotReady = $false }
        @{ Case = 'not finished'; Ready = @(); Missing = @('GameB'); Next = $false; NotReady = $true }
    ) {
        # Mutation: always print the Next line, or never -> the line is missing for a ready receipt or promised for a game without one.
        $result = [pscustomobject]@{ Deployed = 1; Protected = 0; Unsafe = 0; MissingPath = 0; MissingDevice = 0; Unsupported = 0; KeptPrevious = 0; ErrorCount = 0; UnverifiedItems = @(); SelectedProfileName = 'Fast CRT'; ProtectedRecords = @(); UnsafeDetails = @(); SummaryDetails = @(); DetailNotes = @(); UndoReceiptItems = $Ready; UndoReceiptMissingItems = $Missing }
        $null = Show-TpmReShadeSetupResult -Result $result
        $text = Get-F68Text $script:f68Rows
        if ($Next) { $text | Should -Match ([regex]::Escape('Next: You can undo this in ReShade > Undo ReShade changes.')) -Because $Case } else { $text | Should -Not -Match 'Next: You can undo' -Because $Case }
        if ($NotReady) { $text | Should -Match ([regex]::Escape('Undo copy not finished for 1 game. The log has the reason.')) -Because $Case } else { $text | Should -Not -Match 'Undo copy not finished' -Because $Case }
    }

    It 'points the CRT result to the undo menu only when every turned-off game has a receipt' {
        # Mutation: always point to the undo menu -> a game whose receipt was not finished could not be put back there.
        Mock Test-TpmReShadeNativeCrtChoiceAllowed { $false }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($game in @('C1', 'C2')) { [void]$records.Add([pscustomobject]@{ Game = $game; Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None'; Succeeded = $true; Outcome = 'TurnedOff'; RolledBack = $false; NeedsRestore = $false; Reason = ''; TempRemoved = @(); TempKept = @() }) }
        $ready = New-Object 'System.Collections.Generic.List[string]'
        $ready.Add('C1'); $ready.Add('C2')
        $state = [pscustomobject]@{ Requested = $true; Items = @{ C1 = $null; C2 = $null }; NotOffered = @(); BackupTried = $true; BackupOk = $true; BackupPath = 'x'; BackupReason = ''; Records = $records; UndoReady = $ready }
        Write-TpmReShadeNativeCrtOutcome -State $state
        (Get-F68Text $script:f68Rows) | Should -Match ([regex]::Escape('Next: You can undo this in ReShade > Undo ReShade changes.'))
        $script:f68Rows.Clear()
        [void]$ready.Remove('C2')
        Write-TpmReShadeNativeCrtOutcome -State $state
        (Get-F68Text $script:f68Rows) | Should -Match ([regex]::Escape('Next: To undo it, use Restore backup.'))
    }
}

Describe 'FIX68 the setup flow (menu 5) with fixture games' {
    BeforeEach {
        $script:f68Root = New-F68Root 'flow'
        $script:f68Profiles = Join-Path $script:f68Root 'UserProfiles'
        [void][IO.Directory]::CreateDirectory($script:f68Profiles)
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:f68Root 'Assets'); State = (Join-Path $script:f68Root 'State') }
        $script:f68Names = @('GameA', 'GameB')
        foreach ($name in $script:f68Names) {
            $dir = Join-Path $script:f68Root ('Games\' + $name)
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::WriteAllText((Join-Path $script:f68Profiles ($name + '.xml')), ('<GameProfile><GameName>Fixture {0}</GameName><GamePath>{1}</GamePath></GameProfile>' -f $name, (Join-Path $dir ($name + '.exe'))))
        }
        $script:f68SourceDll = Join-Path $script:f68Root 'ReShade64.dll'
        [IO.File]::WriteAllBytes($script:f68SourceDll, [byte[]](0x4d, 0x5a))
        $script:f68Profile = Get-TpmReShadeProfile -ProfileId 'FastCrt'
        $script:f68ReceiptFails = @()
        $script:f68Status = 'NoReShadePresent'
        $script:f68Rows = New-Object 'System.Collections.Generic.List[string]'
        $script:f68Prompts = New-Object 'System.Collections.Generic.List[string]'
        $script:f68Requests = New-Object 'System.Collections.Generic.List[object]'
        Mock Write-Host { [void]$script:f68Rows.Add([string]$Object) }
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
        Mock Select-RegisteredGamesInteractive { @($script:f68Names | ForEach-Object { Get-Item -LiteralPath (Join-Path $script:f68Profiles ($_ + '.xml')) }) }
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = $script:f68Profile; PreviewSession = $null } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Test-TpmInteractiveInput { $false }
        Mock Read-HostSafe { [void]$script:f68Prompts.Add([string]$Prompt); return '' }
        Mock Read-TpmChoice { [void]$script:f68Prompts.Add([string]$Prompt); return 'Y' }
        Mock Read-TpmYesNo { [void]$script:f68Prompts.Add([string]$Prompt); return 'N' }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Get-TpmReShadeApplyPreflight {
            param($SelectedGames)
            $records = @($SelectedGames | ForEach-Object { [pscustomobject]@{ Game = $_.BaseName; Status = 'Ready'; Detail = '' } })
            [pscustomobject]@{ Total = $records.Count; Ready = $records.Count; Protected = 0; MissingPath = 0; Unsafe = 0; Failed = 0; Records = $records }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:f68Root ($GameId + '.ownership.json') }
        Mock Get-ReShadeTargetInfo { param($ExeDir) [pscustomobject]@{ TargetDir = $ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = $script:f68Status; Detail = 'fixture' } }
        Mock Test-TpmGameMutationPath { param($GamePath) [pscustomobject]@{ Valid = $true; ReasonCode = $null; Reason = 'valid'; ResolvedPath = $GamePath; GameDirectory = [IO.Path]::GetDirectoryName($GamePath) } }
        Mock New-TpmReShadePresetContent { '; fixture preset' }
        Mock Get-TpmReShadeProfileTechniqueDisplay { 'fixture' }
        # The deployment is a stand-in that does what the real one does around the receipt: receipt first, then the write.
        Mock Install-TpmReShadeProfileDeployment {
            param($GamePath, $OwnershipPath, $UndoReceipt)
            [void]$script:f68Requests.Add($UndoReceipt)
            if ($script:f68ReceiptFails -contains [IO.Path]::GetFileNameWithoutExtension($GamePath)) { return [pscustomobject]@{ Succeeded = $false; State = 'RECEIPT_FAILED'; Reason = 'UNDO_RECEIPT_FAILED'; Error = 'fixture' } }
            $dir = [IO.Path]::GetDirectoryName($GamePath)
            $hook = Join-Path $dir 'dxgi.dll'
            $undo = New-TpmReShadeUndoReceipt -Request $UndoReceipt -Paths @($hook, $OwnershipPath) -Roots @($dir, [IO.Path]::GetDirectoryName($OwnershipPath))
            [IO.File]::WriteAllText($hook, 'tpm-reshade')
            [IO.File]::WriteAllText($OwnershipPath, '{}')
            [pscustomobject]@{ Succeeded = $true; State = 'INSTALLED'; TargetDir = $dir; DllName = 'dxgi.dll'; PresetApplied = $false; PresetSource = $null; ApiDetected = $true; UndoReceipt = $undo }
        }
        Mock Test-TpmReShadeDeploymentVerified { $true }
        Mock Add-TpmReShadeProfileHistory {}
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
        Remove-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
        if ($script:f68SavedUnattended.Exists) { Set-Variable -Name Unattended -Scope Global -Value $script:f68SavedUnattended.Value }
    }

    It 'makes a finished receipt for every changed game in an unattended run and asks nothing new' {
        # Mutation: drop -UndoReceipt from the deployment call, skip Complete-TpmReShadeUndoReceipt, or ask for a confirmation -> no ready receipt, no entry, or an undo prompt.
        Set-Variable -Name Unattended -Scope Global -Value ([switch]$true)
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f68Profiles -SourceDll $script:f68SourceDll
        $result.Deployed | Should -Be 2
        @($result.UndoReceiptItems) | Should -Be @('GameA', 'GameB')
        @($result.UndoReceiptMissingItems).Count | Should -Be 0
        @($script:f68Requests | ForEach-Object { $_.Operation }) | Should -Be @('Install', 'Install')
        @($script:f68Requests | ForEach-Object { $_.GameName }) | Should -Be @('Fixture GameA', 'Fixture GameB')
        @(Get-TpmReShadeUndoEntries | ForEach-Object { $_.GameId } | Sort-Object) | Should -Be @('GameA', 'GameB')
        @($script:f68Prompts | Where-Object { $_ -cmatch 'YES|ALL|[Uu]ndo' }).Count | Should -Be 0
        @($result.SummaryDetails) | Should -Contain 'Saved for undo: 2 games'
    }

    It 'does not change a game whose receipt cannot be made, and says so in plain words' {
        # Mutation: treat UNDO_RECEIPT_FAILED like any other failure (raw "profile deployment rejected" text) or count the game as changed.
        $script:f68ReceiptFails = @('GameB')
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f68Profiles -SourceDll $script:f68SourceDll
        @($result.ChangedItems) | Should -Be @('GameA')
        @($result.FailedItems) | Should -Be @('GameB')
        $result.Errors | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:f68Root 'Games\GameB\dxgi.dll') | Should -BeFalse
        (Get-F68Text $script:f68Rows) | Should -Match ([regex]::Escape('FAILED Fixture GameB: not changed, because a copy for undo could not be saved.'))
        (Get-F68Text $script:f68Rows) | Should -Not -Match 'profile deployment rejected'
    }

    It 'counts a switch made game by game as a changed look' {
        # Mutation: count changed looks only from the bulk conflict list again -> a single game switched from Levels to Fast CRT counts 0.
        $script:f68Names = @('GameA')
        $script:f68Status = 'TPMOwnedChangedProfile'
        Save-TpmReShadeOwnershipManifest -Manifest ([pscustomobject]@{ SchemaVersion = 1; EffectId = 'ReShadeProfile.Levels'; PinnedRevision = 'TPM-PROFILE'; Files = @([pscustomobject]@{ RelativeSource = 'dxgi.dll'; DestinationPath = (Join-Path $script:f68Root 'Games\GameA\dxgi.dll'); ExpectedSHA256 = ('0' * 64); ActualSHA256 = ('0' * 64); TPMManaged = $true; Kind = 'ReShadeDll' }) }) -Path (Join-Path $script:f68Root 'GameA.ownership.json')
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f68Profiles -SourceDll $script:f68SourceDll
        $result.ChangedProfile | Should -Be 1
        $script:f68Requests[0].Operation | Should -BeExactly 'Switch'
        $script:f68Requests[0].LookBefore | Should -BeExactly 'Levels'
        @($result.SummaryDetails) | Should -Contain ('Changed TeknoParrot Manager profile: 1 game -> {0}' -f $script:f68Profile.FriendlyName)
    }
}
