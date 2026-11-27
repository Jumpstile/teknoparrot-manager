#Requires -Module Pester

# SetIniValue: the recipe engine changes ONE line of a game's text settings file, with a backup, a receipt and undo.
# Every test is about what a player sees or could lose: the one line changes and nothing else, a file that does not
# match is left untouched, and undo puts the original bytes back (and refuses when the player edited the file since).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for SetIniValue tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    # One game folder with a program file and a settings file holding the given bytes.
    function New-SetIniCase {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$FileBytes, [string]$Pattern = '^\s*Mode\s*=\s*(?<v>\S*)\s*$', [string]$Value = '0', [AllowNull()][object]$BeforeValue = $null)
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'
        $payload = Join-Path $root 'p'
        $recovery = Join-Path $root 'r'
        $protected = Join-Path $root 'x'
        foreach ($directory in @((Join-Path $game 'cfg'), $payload, $recovery, $protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        [IO.File]::WriteAllBytes((Join-Path $game 'game.exe'), [Text.Encoding]::ASCII.GetBytes('synthetic program; never run'))
        $settings = Join-Path $game 'cfg\game.ini'
        if ($FileBytes.Length) { [IO.File]::WriteAllBytes($settings, $FileBytes) }
        $operation = [ordered]@{ Type = 'SetIniValue'; Target = 'cfg/game.ini'; LinePattern = $Pattern; Value = $Value }
        if ($null -ne $BeforeValue) { $operation['BeforeValue'] = $BeforeValue }
        $entry = [pscustomobject]@{
            Id = 'setini.test'; ProfileId = 'SetIniTest'; Executable = 'game.exe'; ExecutableSha256 = ''
            SourceUrl = ''; SourceRevision = ''; ExclusiveGroup = ''; Operations = @([pscustomobject]$operation)
        }
        $content = [pscustomobject]@{ Schema = 3; Entries = @($entry) } | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent = $content; CatalogSha256 = (Get-TpmPatchTextSha256 $content); PatchId = $entry.Id; ProfileId = 'SetIniTest'
            GameRoot = $game; PayloadRoot = $payload; RecoveryRoot = $recovery; ProtectedRoots = @($protected)
        }
        return [pscustomobject]@{ Inputs = $inputs; Settings = $settings; Recovery = $recovery }
    }

    function Get-SetIniText { param([string]$Text, [string]$Eol) return [Text.Encoding]::UTF8.GetBytes($Text.Replace("`n", $Eol)) }
}

Describe 'SetIniValue changes one line and nothing else' {
    It 'changes only the matching line and keeps <Label> line endings' -TestCases @(
        @{ Label = 'Windows (CRLF)'; Eol = "`r`n" }
        @{ Label = 'Unix (LF)'; Eol = "`n" }
    ) {
        $original = Get-SetIniText "[Engine]`nVolume = 5`nMode = 1`nName=a b`n" $Eol
        $case = New-SetIniCase ('one' + $Eol.Length) $original
        $inputs = $case.Inputs
        (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -BeExactly 'Applied'
        $expected = [Text.Encoding]::UTF8.GetString((Get-SetIniText "[Engine]`nVolume = 5`nMode = 0`nName=a b`n" $Eol))
        [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($case.Settings)) | Should -BeExactly $expected
    }

    It 'keeps a UTF-8 byte order mark and a file that does not end with a new line' {
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        $body = [Text.Encoding]::UTF8.GetBytes("Mode=2`r`nZ=1")
        $case = New-SetIniCase 'bom' ([byte[]]($bom + $body))
        $inputs = $case.Inputs
        [void](Invoke-TpmCatalogPatch @inputs -Confirm:$false)
        $after = [IO.File]::ReadAllBytes($case.Settings)
        $after[0..2] | Should -Be $bom
        [Text.Encoding]::UTF8.GetString($after, 3, $after.Length - 3) | Should -BeExactly "Mode=0`r`nZ=1"
    }

    It 'saves a backup of the whole original file and a receipt before it changes anything' {
        $original = Get-SetIniText "Mode = 7`nKeep=me`n" "`r`n"
        $case = New-SetIniCase 'backup' $original
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $receipt = [IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json')) | ConvertFrom-Json
        $receipt.State | Should -BeExactly 'Applied'
        [IO.File]::ReadAllBytes($receipt.Operations[0].Backup) | Should -Be $original
    }

    It 'says already done and writes no receipt when the line already holds the value' {
        $case = New-SetIniCase 'already' (Get-SetIniText "Mode = 0`n" "`n")
        $inputs = $case.Inputs
        $result = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $result.Status | Should -BeExactly 'AlreadyApplied'
        @(Get-ChildItem -LiteralPath $case.Recovery -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe 'SetIniValue leaves the file alone when it does not match' {
    It 'refuses: <Label>' -TestCases @(
        @{ Label = 'no line matches'; Text = "Volume=1`n"; Before = $null; Missing = $false }
        @{ Label = 'two lines match'; Text = "Mode=1`nMode=2`n"; Before = $null; Missing = $false }
        @{ Label = 'the line holds a value the recipe does not expect'; Text = "Mode=9`n"; Before = '1'; Missing = $false }
        @{ Label = 'the settings file is missing'; Text = ''; Before = $null; Missing = $true }
    ) {
        $bytes = if ($Missing) { ,[byte[]]@() } else { Get-SetIniText $Text "`r`n" }
        $case = New-SetIniCase ('refuse' + $Label.Length) $bytes -BeforeValue $Before
        $inputs = $case.Inputs
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        if (-not $Missing) { [IO.File]::ReadAllBytes($case.Settings) | Should -Be $bytes }
        @(Get-ChildItem -LiteralPath $case.Recovery -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'refuses a text file saved as UTF-16 instead of damaging it' {
        $bytes = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes("Mode=1`r`n")
        $case = New-SetIniCase 'utf16' ([byte[]]$bytes)
        $inputs = $case.Inputs
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllBytes($case.Settings) | Should -Be ([byte[]]$bytes)
    }
}

Describe 'SetIniValue undo' {
    It 'puts the original file back byte for byte' {
        $original = Get-SetIniText "A=1`nMode = 4`nB=2`n" "`r`n"
        $case = New-SetIniCase 'undo' $original
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        [IO.File]::ReadAllBytes($case.Settings) | Should -Be $original
    }

    It 'refuses to undo when the player changed the file after the edit, and keeps their file' {
        $case = New-SetIniCase 'undo-edited' (Get-SetIniText "Mode = 4`nB=2`n" "`r`n")
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $playerEdit = [Text.Encoding]::UTF8.GetBytes("Mode = 0`r`nB=3`r`n")
        [IO.File]::WriteAllBytes($case.Settings, $playerEdit)
        { Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllBytes($case.Settings) | Should -Be $playerEdit
    }
}

Describe 'SetIniValue recipes in the bundled catalog' {
    BeforeAll {
        $script:catalogContent = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchRecipes.json'))
        $script:catalogEntries = @(($script:catalogContent | ConvertFrom-Json).Entries | Where-Object { @($_.Operations | Where-Object { $_.Type -ceq 'SetIniValue' }).Count })
        # A settings file in the shape the guide shows for each game, with values the recipe must change.
        $script:sampleText = @{
            'lady-luck-io-board-com-port-off'                   = "; first`r`n    { `"IOBoardComPort`", 3 },`r`n"
            'lost-land-adventure-shader-reload-off'             = "; first`r`nAutoReloadChangedShaders = True`r`n"
            'sin-fullscreen-on'                                 = "; first`r`nset vid_fullscreen `"0`"`r`n"
            'america-army-arcade-display-and-gore-settings'     = "[Engine]`r`nWindowedViewportX=800`r`nWindowedViewportY=600`r`nFullscreenViewportX=1920`r`nFullscreenViewportY=1080`r`nMenuViewportX=1024`r`nMenuViewportY=768`r`nGoreLevel=0`r`nOther=keep`r`n"
        }
        function New-CatalogCase {
            param($Entry, [string]$Text)
            $root = Join-Path $TestDrive ('cat-' + $Entry.Id + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            $game = Join-Path $root 'g'
            foreach ($directory in @($game, (Join-Path $root 'p'), (Join-Path $root 'r'), (Join-Path $root 'x'))) { [void][IO.Directory]::CreateDirectory($directory) }
            foreach ($path in @($Entry.Executable, $Entry.Operations[0].Target)) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Join-Path $game $path))) }
            [IO.File]::WriteAllText((Join-Path $game $Entry.Executable), 'synthetic program; never run')
            [IO.File]::WriteAllText((Join-Path $game $Entry.Operations[0].Target), $Text)
            return @{
                CatalogContent = $script:catalogContent; CatalogSha256 = (Get-TpmPatchTextSha256 $script:catalogContent); PatchId = $Entry.Id; ProfileId = $Entry.ProfileId
                GameRoot = $game; PayloadRoot = (Join-Path $root 'p'); RecoveryRoot = (Join-Path $root 'r'); ProtectedRoots = @((Join-Path $root 'x'))
            }
        }
    }

    It 'offers exactly the four games the owner approved, each ready for a matching settings file' {
        @($script:catalogEntries.ProfileId | Sort-Object) | Should -Be @('AAA', 'LadyLuck', 'LostLand', 'SiN')
        foreach ($entry in $script:catalogEntries) {
            $inputs = New-CatalogCase $entry $script:sampleText[[string]$entry.Id]
            $plan = Get-TpmPatchPlan @inputs
            $plan.Status | Should -BeExactly 'Ready' -Because ($entry.Id + ': ' + $plan.Reason)
        }
    }

    It 'America''s Army Arcade sets all seven lines in one step and undo puts the file back' {
        $entry = @($script:catalogEntries | Where-Object { $_.ProfileId -ceq 'AAA' })[0]
        $inputs = New-CatalogCase $entry $script:sampleText[[string]$entry.Id]
        $settings = Join-Path $inputs.GameRoot $entry.Operations[0].Target
        $original = [IO.File]::ReadAllBytes($settings)
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        [IO.File]::ReadAllText($settings) | Should -BeExactly "[Engine]`r`nWindowedViewportX=640`r`nWindowedViewportY=480`r`nFullscreenViewportX=640`r`nFullscreenViewportY=480`r`nMenuViewportX=640`r`nMenuViewportY=480`r`nGoreLevel=1`r`nOther=keep`r`n"
        @(Get-ChildItem -LiteralPath $inputs.RecoveryRoot -Directory).Count | Should -Be 1
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        [IO.File]::ReadAllBytes($settings) | Should -Be $original
    }

    It 'America''s Army Arcade changes nothing when one of the seven lines is missing' {
        $entry = @($script:catalogEntries | Where-Object { $_.ProfileId -ceq 'AAA' })[0]
        $text = $script:sampleText[[string]$entry.Id].Replace("GoreLevel=0`r`n", '')
        $inputs = New-CatalogCase $entry $text
        $settings = Join-Path $inputs.GameRoot $entry.Operations[0].Target
        $original = [IO.File]::ReadAllBytes($settings)
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllBytes($settings) | Should -Be $original
        @(Get-ChildItem -LiteralPath $inputs.RecoveryRoot -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}
