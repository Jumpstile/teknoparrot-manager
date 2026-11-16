#Requires -Module Pester

# FIX73 (port of FIX67 plus its review findings): after choosing a ReShade CRT look, TeknoParrot Manager only preserved TeknoParrot's own CRT
# shader ("Video / CRT Shader") and warned, so the two effects stacked. Now the user can choose T to turn it off, only for the games ReShade is
# really installed on in this run, and only that one profile field. The question and the outcome use the short, spaced, plain screens
# (Write-TpmText, Show-TpmDetailBlocks, Write-TpmOutcome).
#
# The production script is parsed and only its function definitions are dot-sourced. Every file lives under TestDrive. No TeknoParrot,
# no real ReShade, no network. Each It names the product change that makes it fail.
# What this CANNOT prove: how a real console paints the rows, and the real TeknoParrot option list of the "CRT Shader" field (the repository
# holds no real TeknoParrot profile with that field, so the fixtures are synthetic).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F73Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX73 tests could not parse the production script.' }
    $definitions = @($script:F73Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionText = @($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F73FunctionFile = Join-Path $TestDrive 'tpm-fix73-functions.ps1'
    [System.IO.File]::WriteAllText($script:F73FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F73FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    # The real atomic writer and XML loader, kept so a mock can fail once (or change a file) and then fall back to the real one.
    $script:F73RealWrite = (Get-Command -Name Write-TpmAtomicTextFile -CommandType Function).ScriptBlock
    $script:F73RealConvert = (Get-Command -Name ConvertTo-TpmReShadeXmlDocument -CommandType Function).ScriptBlock
    # The caller's own global Unattended (if any) is put back after each test instead of being removed.
    $savedUnattended = Get-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
    $script:F73SavedUnattended = [pscustomobject]@{ Exists = ($null -ne $savedUnattended); Value = $(if ($null -ne $savedUnattended) { $savedUnattended.Value } else { $null }) }
    function Restore-F73Unattended {
        Remove-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
        if ($script:F73SavedUnattended.Exists) { Set-Variable -Name Unattended -Scope Global -Value $script:F73SavedUnattended.Value }
    }

    $script:F73Utf8 = New-Object System.Text.UTF8Encoding $false

    function New-F73ProfileText {
        param([string]$Name, [string]$Value = 'Lottes', [string]$Options = '<FieldOptions><string>None</string><string>Lottes</string><string>Aperture</string></FieldOptions>', [string]$Eol = "`r`n", [string]$GamePath = 'C:\Games\x.exe')
        $lines = @(
            '<?xml version="1.0" encoding="utf-8"?>',
            '<GameProfile>',
            ('  <GameName>Fixture {0}</GameName>' -f $Name),
            ('  <GamePath>{0}</GamePath>' -f $GamePath),
            '  <ConfigValues>',
            '    <FieldInformation>',
            '      <CategoryName>Video</CategoryName>',
            '      <FieldName>CRT Shader</FieldName>',
            '      <FieldType>Dropdown</FieldType>',
            ('      <FieldValue>{0}</FieldValue>' -f $Value),
            ('      {0}' -f $Options),
            '    </FieldInformation>',
            '    <FieldInformation>',
            '      <CategoryName>Video</CategoryName>',
            '      <FieldName>SSAA</FieldName>',
            '      <FieldValue>2</FieldValue>',
            '    </FieldInformation>',
            '    <FieldInformation><CategoryName>Input</CategoryName><FieldName>Input API</FieldName><FieldValue>Lottes</FieldValue></FieldInformation>',
            '  </ConfigValues>',
            '</GameProfile>'
        )
        return (($lines -join $Eol) + $Eol)
    }
    function Write-F73Profile {
        param([string]$Path, [string]$Text, [switch]$Bom)
        $bytes = $script:F73Utf8.GetBytes($Text)
        if ($Bom) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + @($bytes)) }
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }
    function Get-F73Base64 {
        param([string]$Path)
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    # The original bytes with ONLY the value text of the CRT Shader field replaced (independent of the product code).
    function Get-F73ExpectedBase64 {
        param([string]$Path, [string]$Old, [string]$New)
        $text = $script:F73Utf8.GetString([System.IO.File]::ReadAllBytes($Path))
        $rx = [regex]::new('(?s)(<FieldName>CRT Shader</FieldName>.*?<FieldValue>)' + [regex]::Escape($Old) + '(</FieldValue>)')
        $replaced = $rx.Replace($text, ('${1}' + $New + '${2}'), 1)
        if ($replaced -ceq $text) { throw 'fixture: the expected text did not change' }
        return [System.Convert]::ToBase64String($script:F73Utf8.GetBytes($replaced))
    }
    function Get-F73Warnings {
        param([string]$Text)
        $document = New-Object System.Xml.XmlDocument
        $document.LoadXml($Text)
        return (Get-TpmReShadeNativeShaderWarnings -Document $document)
    }
    function Get-F73Normalized {
        param([object[]]$Lines)
        return (((@($Lines) -join ' ') -replace '\s+', ' ').Trim())
    }
    function Get-F73LineIndex {
        param([object[]]$Lines, [string]$Pattern)
        for ($i = 0; $i -lt @($Lines).Count; $i++) { if ([string]@($Lines)[$i] -match $Pattern) { return $i } }
        return -1
    }
    # The most logical lines in a row with no blank row between them. A row that only continues the sentence above it (its first word did not
    # fit, so it was wrapped) belongs to that line. Slack covers the hanging indent. It can only count too few lines, never too many.
    function Get-F73LongestRun {
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

    # Break: '' = the real writer; 'Once' = the first write to ReadyA leaves garbage and fails (the rollback then works);
    # 'Always' = every write to ReadyA leaves garbage and fails (so the rollback fails too).
    function Invoke-F73Setup {
        param(
            [string[]]$Games = @('Prot', 'ReadyA', 'ReadyB'), [string]$ProfileId = 'FastCrt', [string[]]$NativeAnswers = @(), [string[]]$NoticeAnswers = @(),
            [string[]]$DetailAnswers = @(), [bool]$BackupVerified = $true, [string]$Break = '', [string[]]$NoOff = @(), [bool]$Interactive = $true,
            [int]$Width = 100, [string]$FailInstallFor = '', [switch]$ThroughSetup
        )
        $script:f73Root = Join-Path $TestDrive ('f73-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:f73Profiles = Join-Path $script:f73Root 'UserProfiles'
        [void](New-Item -ItemType Directory -Path $script:f73Profiles -Force)
        $script:f73Names = @($Games)
        $script:f73Rows = New-Object 'System.Collections.Generic.List[object]'
        $script:f73Prompts = New-Object 'System.Collections.Generic.List[string]'
        $script:f73Events = New-Object 'System.Collections.Generic.List[string]'
        $script:f73NativeAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $NativeAnswers) { $script:f73NativeAnswers.Enqueue($answer) }
        $script:f73NoticeAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $NoticeAnswers) { $script:f73NoticeAnswers.Enqueue($answer) }
        $script:f73DetailAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $DetailAnswers) { $script:f73DetailAnswers.Enqueue($answer) }
        $script:f73BackupVerified = $BackupVerified
        $script:f73BackupSnap = @{}
        $script:f73Break = $Break
        $script:f73BrokeOnce = $false
        $script:f73FailInstall = $FailInstallFor
        $script:f73Interactive = $Interactive
        $script:f73Width = $Width
        $script:f73Profile = Get-TpmReShadeProfile -ProfileId $ProfileId
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:f73Root 'Assets') }
        $noOffOptions = '<FieldOptions><string>Lottes</string><string>Aperture</string></FieldOptions>'
        $before = @{}
        foreach ($name in $script:f73Names) {
            $gameDir = Join-Path $script:f73Root ('Games\' + $name)
            [void](New-Item -ItemType Directory -Path $gameDir -Force)
            $profilePath = Join-Path $script:f73Profiles ($name + '.xml')
            $text = if ($NoOff -contains $name) { New-F73ProfileText -Name $name -GamePath (Join-Path $gameDir ($name + '.exe')) -Options $noOffOptions } else { New-F73ProfileText -Name $name -GamePath (Join-Path $gameDir ($name + '.exe')) }
            Write-F73Profile -Path $profilePath -Text $text -Bom
            $before[$name] = Get-F73Base64 $profilePath
        }
        $sourceDll = Join-Path $script:f73Root 'ReShade64.dll'
        [System.IO.File]::WriteAllBytes($sourceDll, [byte[]](0x4d, 0x5a))
        try {
            $result = if ($ThroughSetup) {
                Invoke-ReShadeSetup -UserProfilesDir $script:f73Profiles -SourceDll $sourceDll
            } else {
                Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f73Profiles -SourceDll $sourceDll
            }
        } finally {
            $script:TpmOwnedLayout = $null
        }
        $after = @{}
        foreach ($name in $script:f73Names) { $after[$name] = Get-F73Base64 (Join-Path $script:f73Profiles ($name + '.xml')) }
        return [pscustomobject]@{
            Result = $result; Before = $before; After = $after; Rows = @($script:f73Rows | ForEach-Object { [pscustomobject]@{ Text = ([string]$_.Text).TrimEnd(); Color = $_.Color } })
            Out = @($script:f73Rows | ForEach-Object { ([string]$_.Text).TrimEnd() }); Prompts = @($script:f73Prompts)
            Events = @($script:f73Events); BackupSnap = $script:f73BackupSnap; Profiles = $script:f73Profiles; Root = $script:f73Root
        }
    }
    # A plan for the direct screen tests: ReadyA with an off value, one game for each other case.
    function New-F73Plan {
        param([string]$Group = 'Crt')
        $withOff = Get-F73Warnings -Text (New-F73ProfileText -Name 'x')
        $noOff = Get-F73Warnings -Text (New-F73ProfileText -Name 'y' -Options '<FieldOptions><string>Lottes</string></FieldOptions>')
        $games = @(
            [pscustomobject]@{ BaseName = 'ReadyA'; FullName = 'C:\x\ReadyA.xml' }
            [pscustomobject]@{ BaseName = 'NoOffGame'; FullName = 'C:\x\NoOffGame.xml' }
            [pscustomobject]@{ BaseName = 'Prot'; FullName = 'C:\x\Prot.xml' }
        )
        $warnings = @(
            [pscustomobject]@{ Game = 'ReadyA'; Fields = @($withOff.Fields) }
            [pscustomobject]@{ Game = 'NoOffGame'; Fields = @($noOff.Fields) }
            [pscustomobject]@{ Game = 'Prot'; Fields = @($withOff.Fields) }
        )
        $preflight = [pscustomobject]@{ Records = @(
            [pscustomobject]@{ Game = 'ReadyA'; Status = 'Ready'; Detail = '' }
            [pscustomobject]@{ Game = 'NoOffGame'; Status = 'Ready'; Detail = '' }
            [pscustomobject]@{ Game = 'Prot'; Status = 'Protected'; Detail = 'A ReShade hook exists without verified ownership.' }
        ) }
        return (Get-TpmReShadeNativeCrtPlan -Warnings $warnings -SelectedGames $games -Preflight $preflight -ProfileDefinition ([pscustomobject]@{ Group = $Group }))
    }
}

AfterAll {
    Restore-F73Unattended
}

Describe 'FIX73 the off value comes from the profile itself' {
    It 'uses the profile own off option and never invents one' {
        # Mutation: hard-code 'None' (or any value) instead of reading the field's FieldOptions -> the Off, Disabled and no-option rows fail.
        $cases = @(
            @{ Options = '<FieldOptions><string>None</string><string>Lottes</string></FieldOptions>'; Value = 'Lottes'; Expected = 'None' }
            @{ Options = '<FieldOptions><string>Lottes</string><string>Off</string></FieldOptions>'; Value = 'Lottes'; Expected = 'Off' }
            @{ Options = '<FieldOptions><string>Disabled</string><string>Lottes</string></FieldOptions>'; Value = 'Lottes'; Expected = 'Disabled' }
            @{ Options = ''; Value = '1'; Expected = '0' }
            @{ Options = ''; Value = 'True'; Expected = 'False' }
        )
        foreach ($case in $cases) {
            $warnings = Get-F73Warnings -Text (New-F73ProfileText -Name 'Off' -Value $case.Value -Options $case.Options)
            $crt = @($warnings.Fields | Where-Object { $_.IsCrtShader })
            $crt.Count | Should -Be 1
            $crt[0].OffValue | Should -BeExactly $case.Expected
        }
    }

    It 'finds no off value when the profile offers none, and then the choice is not offered for that game' {
        # Mutation: fall back to a default 'None' when the option list has no off value -> OffValue is not null and the plan offers T.
        $warnings = Get-F73Warnings -Text (New-F73ProfileText -Name 'NoOff' -Options '<FieldOptions><string>Lottes</string><string>Aperture</string></FieldOptions>')
        $crt = @($warnings.Fields | Where-Object { $_.IsCrtShader })
        ($null -eq $crt[0].OffValue) | Should -BeTrue
        $games = @([pscustomobject]@{ BaseName = 'NoOff'; FullName = 'C:\x\NoOff.xml' })
        $preflight = [pscustomobject]@{ Records = @([pscustomobject]@{ Game = 'NoOff'; Status = 'Ready'; Detail = '' }) }
        $plan = Get-TpmReShadeNativeCrtPlan -Warnings @([pscustomobject]@{ Game = 'NoOff'; Fields = @($warnings.Fields) }) -SelectedGames $games -Preflight $preflight -ProfileDefinition ([pscustomobject]@{ Group = 'Crt' })
        $plan.EnabledCount | Should -Be 1
        $plan.Offer | Should -BeFalse
    }

    It 'treats only the field named CRT Shader as the native CRT shader' {
        # Mutation: match any detected field (for example SSAA) as the CRT shader -> the SSAA field gets IsCrtShader and could be turned off.
        $warnings = Get-F73Warnings -Text (New-F73ProfileText -Name 'Only')
        @($warnings.Fields).Count | Should -Be 2
        @($warnings.Fields | Where-Object { $_.IsCrtShader } | ForEach-Object { $_.Field }) | Should -Be @('Video / CRT Shader')
        @($warnings.Fields | Where-Object { -not $_.IsCrtShader } | ForEach-Object { $_.Field }) | Should -Be @('Video / SSAA')
    }
}

Describe 'FIX73 Set-TpmReShadeNativeCrtOff changes exactly one value' {
    BeforeEach {
        Mock Test-TpmNoReparsePath { $true }
        Mock Assert-TpmNoReparseWriteTarget {}
        Mock Write-Log {}
        $script:f73Path = Join-Path $TestDrive ('set-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.xml')
    }

    It 'keeps every other byte identical (BOM, CRLF, other fields with the same text) and verifies the result' {
        # Mutation: save the document with Save-Xml/XmlDocument.Save (re-indents, drops the BOM) or replace every 'Lottes' -> the bytes differ from the expected file.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Bytes') -Bom
        $expected = Get-F73ExpectedBase64 -Path $script:f73Path -Old 'Lottes' -New 'None'
        $original = Get-F73Base64 $script:f73Path
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeTrue
        $result.Changed | Should -BeTrue
        $result.Outcome | Should -BeExactly 'TurnedOff'
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $expected
        (Get-F73Base64 $script:f73Path) | Should -Not -BeExactly $original
        $text = $script:F73Utf8.GetString([System.IO.File]::ReadAllBytes($script:f73Path))
        $text | Should -Match '<FieldName>Input API</FieldName><FieldValue>Lottes</FieldValue>'
        $text | Should -Match '<FieldName>SSAA</FieldName>\s*<FieldValue>2</FieldValue>'
    }

    It 'writes nothing when the setting is already off' {
        # Mutation: write the profile even when the value already equals the off value -> Changed is true.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Off' -Value 'None') -Bom
        $original = Get-F73Base64 $script:f73Path
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeTrue
        $result.Changed | Should -BeFalse
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $original
    }

    It 'refuses a value that changed after it was checked' {
        # Mutation: drop the current-value comparison -> the profile is overwritten although the user changed it meanwhile.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Moved' -Value 'Aperture')
        $original = Get-F73Base64 $script:f73Path
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Match 'changed after it was checked'
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $original
    }

    It 'does not write when the profile changes after it was read the first time, and says so' {
        # Mutation: remove the second read of the profile bytes just before the write -> the changed profile is overwritten and Write-TpmAtomicTextFile is called.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Racing') -Bom
        $script:f73ConvertCalls = 0
        $script:f73MovedBytes = $script:F73Utf8.GetBytes((New-F73ProfileText -Name 'Racing' -Value 'Aperture'))
        Mock ConvertTo-TpmReShadeXmlDocument {
            $script:f73ConvertCalls++
            # The second document is built after the first read and before the write: change the file on disk right there.
            if ($script:f73ConvertCalls -eq 2) { [System.IO.File]::WriteAllBytes($script:f73Path, $script:f73MovedBytes) }
            & $script:F73RealConvert @PesterBoundParameters
        }
        Mock Write-TpmAtomicTextFile { throw 'the profile must not be written' }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        $result.Outcome | Should -BeExactly 'ChangedMeanwhile'
        $result.ChangedMeanwhile | Should -BeTrue
        $result.Reason | Should -Match 'changed while TeknoParrot Manager was working, so it was left as it was'
        (Get-F73Base64 $script:f73Path) | Should -BeExactly ([System.Convert]::ToBase64String($script:f73MovedBytes))
        Should -Invoke Write-TpmAtomicTextFile -Times 0 -Exactly
    }

    It 'rolls the profile back and verifies it when a write leaves wrong bytes' {
        # Mutation: remove the rollback (or report RolledBack without re-reading the bytes) -> the file keeps 'partial garbage' or RolledBack is false.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Roll') -Bom
        $original = Get-F73Base64 $script:f73Path
        $script:f73Calls = 0
        Mock Write-TpmAtomicTextFile {
            $script:f73Calls++
            if ($script:f73Calls -eq 1) {
                [System.IO.File]::WriteAllText($Path, 'partial garbage', (New-Object System.Text.UTF8Encoding $false))
                throw 'simulated failure after a partial write'
            }
            & $script:F73RealWrite @PesterBoundParameters
        }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        $result.RolledBack | Should -BeTrue
        $result.NeedsRestore | Should -BeFalse
        $result.Reason | Should -Match 'put back'
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $original
        $script:f73Calls | Should -Be 2
    }

    It 'removes the temporary file the failed write left behind after a verified rollback, and only that one' {
        # Mutation: skip the cleanup after the rollback (or delete every *.tmp beside the profile) -> the stray file stays, or the decoy of someone else is deleted.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Tmp') -Bom
        $original = Get-F73Base64 $script:f73Path
        $decoy = $script:f73Path + '.' + ('a' * 32) + '.tmp'
        [System.IO.File]::WriteAllText($decoy, 'not ours', $script:F73Utf8)
        $script:f73Stray = $script:f73Path + '.' + ('b' * 32) + '.tmp'
        $script:f73Calls = 0
        Mock Write-TpmAtomicTextFile {
            $script:f73Calls++
            if ($script:f73Calls -eq 1) {
                [System.IO.File]::WriteAllText($Path, 'partial garbage', (New-Object System.Text.UTF8Encoding $false))
                [System.IO.File]::WriteAllText($script:f73Stray, 'leftover of the failed write', (New-Object System.Text.UTF8Encoding $false))
                # Like the real writer, report the exact temporary file this call created and kept.
                $RetainedTempPaths.Add($script:f73Stray)
                throw 'simulated failure after the previous file was removed'
            }
            & $script:F73RealWrite @PesterBoundParameters
        }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.RolledBack | Should -BeTrue
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $original
        (Test-Path -LiteralPath $script:f73Stray) | Should -BeFalse
        (Test-Path -LiteralPath $decoy) | Should -BeTrue
        @($result.TempRemoved) | Should -Be @($script:f73Stray)
        @($result.TempKept).Count | Should -Be 0
    }

    It 'says plainly that nothing needed undoing when the write failed without touching the file' {
        # Mutation: claim a rollback (or success) when the file was never changed -> RolledBack is true or Succeeded is true.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Untouched')
        $original = Get-F73Base64 $script:f73Path
        Mock Write-TpmAtomicTextFile { throw 'simulated failure before any write' }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        $result.RolledBack | Should -BeFalse
        $result.NeedsRestore | Should -BeFalse
        $result.Outcome | Should -BeExactly 'LeftAsIs'
        $result.Reason | Should -Match 'left as it was'
        (Get-F73Base64 $script:f73Path) | Should -BeExactly $original
    }

    It 'asks for a restore when even the rollback fails, and keeps the temporary file it cannot judge' {
        # Mutation: report a verified rollback without reading the file back after it, or delete the temporary file of an unverified rollback -> NeedsRestore stays false or the file is gone.
        Write-F73Profile -Path $script:f73Path -Text (New-F73ProfileText -Name 'Stuck')
        $script:f73Stray = $script:f73Path + '.' + ('c' * 32) + '.tmp'
        Mock Write-TpmAtomicTextFile {
            [System.IO.File]::WriteAllText($Path, 'partial garbage', (New-Object System.Text.UTF8Encoding $false))
            [System.IO.File]::WriteAllText($script:f73Stray, 'maybe the only copy of the new content', (New-Object System.Text.UTF8Encoding $false))
            # Like the real writer, report the exact temporary file this call created and kept (this mock writes the same file on both calls).
            if (-not $RetainedTempPaths.Contains($script:f73Stray)) { $RetainedTempPaths.Add($script:f73Stray) }
            throw 'simulated failure'
        }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:f73Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        $result.RolledBack | Should -BeFalse
        $result.NeedsRestore | Should -BeTrue
        $result.Reason | Should -Match 'restore the safety backup'
        (Test-Path -LiteralPath $script:f73Stray) | Should -BeTrue
        @($result.TempKept) | Should -Be @($script:f73Stray)
    }
}

Describe 'FIX73 plan: which games can be offered the choice' {
    BeforeAll {
        $script:f73PlanGames = @(
            [pscustomobject]@{ BaseName = 'A'; FullName = 'C:\x\A.xml' }
            [pscustomobject]@{ BaseName = 'B'; FullName = 'C:\x\B.xml' }
            [pscustomobject]@{ BaseName = 'C'; FullName = 'C:\x\C.xml' }
        )
        $withOff = Get-F73Warnings -Text (New-F73ProfileText -Name 'x')
        $noOff = Get-F73Warnings -Text (New-F73ProfileText -Name 'y' -Options '<FieldOptions><string>Lottes</string></FieldOptions>')
        $script:f73PlanWarnings = @(
            [pscustomobject]@{ Game = 'A'; Fields = @($withOff.Fields) }
            [pscustomobject]@{ Game = 'B'; Fields = @($withOff.Fields) }
            [pscustomobject]@{ Game = 'C'; Fields = @($noOff.Fields) }
        )
        $script:f73PlanPreflight = [pscustomobject]@{ Records = @(
            [pscustomobject]@{ Game = 'A'; Status = 'Ready'; Detail = '' }
            [pscustomobject]@{ Game = 'B'; Status = 'Protected'; Detail = 'protected fixture' }
            [pscustomobject]@{ Game = 'C'; Status = 'Ready'; Detail = '' }
        ) }
    }

    It 'counts and offers only games ReShade will change, and only for a CRT profile' {
        # Mutation: count protected games or ignore the profile group -> EnabledCount is 3, B is eligible, or Offer is true for the Main profile.
        $plan = Get-TpmReShadeNativeCrtPlan -Warnings $script:f73PlanWarnings -SelectedGames $script:f73PlanGames -Preflight $script:f73PlanPreflight -ProfileDefinition ([pscustomobject]@{ Group = 'Crt' })
        $plan.EnabledCount | Should -Be 2
        @($plan.EligibleItems | ForEach-Object { $_.Game }) | Should -Be @('A')
        $plan.Offer | Should -BeTrue
        $main = Get-TpmReShadeNativeCrtPlan -Warnings $script:f73PlanWarnings -SelectedGames $script:f73PlanGames -Preflight $script:f73PlanPreflight -ProfileDefinition ([pscustomobject]@{ Group = 'Main' })
        $main.Offer | Should -BeFalse
    }

    It 'counts the games that can be turned off apart from the games that use the CRT shader' {
        # Mutation: report EnabledCount as the number T can change -> EligibleCount equals EnabledCount (2) and the game without an off value is not listed as not offered.
        $plan = Get-TpmReShadeNativeCrtPlan -Warnings $script:f73PlanWarnings -SelectedGames $script:f73PlanGames -Preflight $script:f73PlanPreflight -ProfileDefinition ([pscustomobject]@{ Group = 'Crt' })
        $plan.EnabledCount | Should -Be 2
        $plan.EligibleCount | Should -Be 1
        @($plan.NotOfferedItems | ForEach-Object { $_.Game }) | Should -Be @('C')
    }

    It 'includes a protected game only when the user chose Adopt' {
        # Mutation: ignore -Adopt -> B stays out of the eligible list for Adopt, or enters it without Adopt.
        $plan = Get-TpmReShadeNativeCrtPlan -Warnings $script:f73PlanWarnings -SelectedGames $script:f73PlanGames -Preflight $script:f73PlanPreflight -ProfileDefinition ([pscustomobject]@{ Group = 'Crt' }) -Adopt
        @($plan.EligibleItems | ForEach-Object { $_.Game }) | Should -Be @('A', 'B')
    }

    It 'offers nothing when the preflight rows do not line up with the selected games' {
        # Mutation: guess a status when the row count differs -> a game gets turned off without a matching preflight row.
        $short = [pscustomobject]@{ Records = @([pscustomobject]@{ Game = 'A'; Status = 'Ready'; Detail = '' }) }
        $plan = Get-TpmReShadeNativeCrtPlan -Warnings $script:f73PlanWarnings -SelectedGames $script:f73PlanGames -Preflight $short -ProfileDefinition ([pscustomobject]@{ Group = 'Crt' })
        $plan.Offer | Should -BeFalse
        $plan.EnabledCount | Should -Be 0
    }
}

Describe 'FIX73 the unattended switch' {
    AfterEach { Restore-F73Unattended }

    It 'allows the choice normally and refuses it when the script runs unattended' {
        # Mutation: ignore the Unattended switch -> the function says yes for an unattended run.
        Remove-Variable -Name Unattended -Scope Global -ErrorAction SilentlyContinue
        Test-TpmReShadeNativeCrtChoiceAllowed | Should -BeTrue
        Set-Variable -Name Unattended -Scope Global -Value ([switch]$true)
        Test-TpmReShadeNativeCrtChoiceAllowed | Should -BeFalse
    }
}

Describe 'FIX73 the setup flow with fixture games (Prot = protected, ReadyA and ReadyB = ReShade is applied)' {
    BeforeEach {
        # The mocks live here (not in a helper function) so every It sees them exactly as Pester scopes them. Their bodies read $script:f73* values
        # that Invoke-F73Setup sets for each run.
        Mock Write-Host { [void]$script:f73Rows.Add([pscustomobject]@{ Text = [string]$Object; Color = [string]$ForegroundColor }) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { $script:f73Width }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = $script:f73Width; Left = 0; Top = 0; Height = 40; BufferWidth = $script:f73Width; BufferHeight = 300 } }
        Mock Test-TpmNoReparsePath { $true }
        Mock Assert-TpmNoReparseWriteTarget {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Session = $null; Reason = 'fixture' } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'UnknownError'; Signer = '(none)'; Thumbprint = ('C3' * 20) } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Select-RegisteredGamesInteractive { @($script:f73Names | Sort-Object | ForEach-Object { Get-Item -LiteralPath (Join-Path $script:f73Profiles ($_ + '.xml')) }) }
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = $script:f73Profile; PreviewSession = $null } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Test-TpmInteractiveInput { $script:f73Interactive }
        Mock Read-HostSafe {
            [void]$script:f73Prompts.Add([string]$Prompt)
            if ($script:f73DetailAnswers.Count -gt 0) { return $script:f73DetailAnswers.Dequeue() }
            return ''
        }
        Mock Read-TpmChoice {
            [void]$script:f73Prompts.Add([string]$Prompt)
            if ($Prompt -match 'Choice, default K') {
                if ($script:f73NativeAnswers.Count -gt 0) { return $script:f73NativeAnswers.Dequeue() }
                return 'K'
            }
            if ($Prompt -match 'Press D for details, or Enter') {
                if ($script:f73NoticeAnswers.Count -gt 0) { return $script:f73NoticeAnswers.Dequeue() }
                return 'C'
            }
            return 'Y'
        }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Get-TpmReShadeApplyPreflight {
            param($SelectedGames)
            $records = @($SelectedGames | ForEach-Object { [pscustomobject]@{ Game = $_.BaseName; Status = $(if ($_.BaseName -like 'Prot*') { 'Protected' } else { 'Ready' }); Detail = '' } })
            [pscustomobject]@{
                Total = $records.Count
                Ready = @($records | Where-Object { $_.Status -eq 'Ready' }).Count
                Protected = @($records | Where-Object { $_.Status -eq 'Protected' }).Count
                MissingPath = 0; Unsafe = 0; Failed = 0; Records = $records
            }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:f73Root ($GameId + '.ownership.json') }
        Mock Get-ReShadeTargetInfo { param($ExeDir) [pscustomobject]@{ TargetDir = $ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification {
            param($HookPath)
            if ($HookPath -like '*\Prot\*') { [pscustomobject]@{ Status = 'UnknownUserOwnedConflict'; Detail = 'fixture protected' } }
            else { [pscustomobject]@{ Status = 'ManagedTrusted'; Detail = 'trusted fixture' } }
        }
        Mock Test-TpmGameMutationPath {
            param($GamePath)
            [pscustomobject]@{ Valid = $true; ReasonCode = $null; Reason = 'valid'; ResolvedPath = $GamePath; GameDirectory = [IO.Path]::GetDirectoryName($GamePath) }
        }
        Mock New-TpmReShadePresetContent { '; fixture preset' }
        Mock Get-TpmReShadeProfileTechniqueDisplay { 'fixture' }
        Mock Install-TpmReShadeProfileDeployment {
            param($GamePath)
            if ($script:f73FailInstall -and $GamePath -like ('*\' + $script:f73FailInstall + '\*')) {
                return [pscustomobject]@{ Succeeded = $false; State = 'FAILED'; Reason = 'FIXTURE_FAILURE'; Error = 'fixture failure' }
            }
            [pscustomobject]@{ Succeeded = $true; State = 'INSTALLED'; TargetDir = [IO.Path]::GetDirectoryName($GamePath); DllName = 'dxgi.dll'; PresetApplied = $false; PresetSource = $null; ApiDetected = $true }
        }
        Mock Test-TpmReShadeDeploymentVerified { $true }
        Mock Add-TpmReShadeProfileHistory {}
        Mock New-TpmVerifiedUserProfilesBackup {
            $snapshot = @{}
            foreach ($n in $script:f73Names) { $snapshot[$n] = Get-F73Base64 (Join-Path $script:f73Profiles ($n + '.xml')) }
            $script:f73BackupSnap = $snapshot
            [void]$script:f73Events.Add('backup')
            [pscustomobject]@{
                Verified = $script:f73BackupVerified
                Path = $(if ($script:f73BackupVerified) { Join-Path $script:f73Root 'FullBackup\ReShadeNativeCrt_fixture' } else { '' })
                Reason = $(if ($script:f73BackupVerified) { $null } else { 'fixture backup failure' })
            }
        }
        Mock Write-TpmAtomicTextFile {
            if ($Path -like '*ReadyA.xml' -and ($script:f73Break -eq 'Always' -or ($script:f73Break -eq 'Once' -and -not $script:f73BrokeOnce))) {
                $script:f73BrokeOnce = $true
                [System.IO.File]::WriteAllText($Path, 'partial garbage', (New-Object System.Text.UTF8Encoding $false))
                throw 'simulated failure after a partial write'
            }
            & $script:F73RealWrite @PesterBoundParameters
        }
    }
    AfterEach { Restore-F73Unattended }

    It 'keeps the CRT look byte for byte by default and shows a short notice without game names or profile keys' {
        # Mutation: make T the default, or write without the choice -> the Ready games change; or print the game names / field names in the default view -> the notice checks fail.
        $run = Invoke-F73Setup
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
        $run.Events | Should -Not -Contain 'backup'
        $run.Result.NativeCrtRequested | Should -BeFalse
        $firstNotice = Get-F73LineIndex -Lines $run.Out -Pattern 'own CRT look'
        $firstOption = Get-F73LineIndex -Lines $run.Out -Pattern '^\s*\[K\] '
        $firstNotice | Should -BeGreaterOrEqual 0
        $firstOption | Should -BeGreaterThan $firstNotice
        $noticeLines = @($run.Out[$firstNotice..($firstOption - 1)])
        (Get-F73Normalized $noticeLines) | Should -BeExactly "2 of these games already use TeknoParrot's own CRT look. Together with this ReShade look, it can look doubled."
        $shown = @($run.Out[0..($firstOption + 2)])
        @($shown | Where-Object { $_ -cmatch 'CRT Shader|Lottes|Video /|\b(ReadyA|ReadyB|Prot)\b' }).Count | Should -Be 0
        @($run.Out | Where-Object { $_ -match 'Native TeknoParrot display/shader settings detected|preserves those native settings|may stack another display effect' }).Count | Should -Be 0
        (Get-F73Normalized $run.Out) | Should -Match '\[K\] Keep TeknoParrot''s CRT look \(default\) \[T\] Turn it off for 2 games \[D\] Details'
    }

    It 'T turns off only that one field, only for the games ReShade is applied to, after a verified backup' {
        # Mutation: change the protected game too, take the backup after the first write, or change another field -> Prot differs, BackupSnap differs, or the expected bytes differ.
        $run = Invoke-F73Setup -NativeAnswers @('T')
        $run.After['Prot'] | Should -BeExactly $run.Before['Prot']
        foreach ($name in @('ReadyA', 'ReadyB')) {
            $run.After[$name] | Should -Not -BeExactly $run.Before[$name]
            # the expected bytes are rebuilt from the original text, replacing only the CRT Shader value
            $original = $script:F73Utf8.GetString([System.Convert]::FromBase64String($run.Before[$name]))
            $rx = [regex]::new('(?s)(<FieldName>CRT Shader</FieldName>.*?<FieldValue>)Lottes(</FieldValue>)')
            $expectedText = $rx.Replace($original, '${1}None${2}', 1)
            $run.After[$name] | Should -BeExactly ([System.Convert]::ToBase64String($script:F73Utf8.GetBytes($expectedText)))
        }
        @($run.Events | Where-Object { $_ -eq 'backup' }).Count | Should -Be 1
        $run.BackupSnap['ReadyA'] | Should -BeExactly $run.Before['ReadyA']
        $run.BackupSnap['ReadyB'] | Should -BeExactly $run.Before['ReadyB']
        @($run.Result.NativeCrtTurnedOff) | Should -Be @('ReadyA', 'ReadyB')
        @($run.Result.ChangedItems) | Should -Be @('ReadyA', 'ReadyB')
        $run.Result.NativeCrtBackupPath | Should -Match 'ReShadeNativeCrt_fixture'
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "TeknoParrot's own CRT look was turned off for 2 games\."
        $text | Should -Match 'Next: To undo it, use Restore backup\.'
        $text | Should -Match 'OK\. It will be turned off only in games that get ReShade now\.'
        $remaining = @($run.Result.NativeShaderWarnings | Where-Object { $_.Game -eq 'ReadyA' })
        $remaining.Count | Should -Be 1
        @($remaining[0].Fields | ForEach-Object { $_.Field }) | Should -Be @('Video / SSAA')
    }

    It 'uses the singular wording when one game is affected' {
        # Mutation: remove the plural handling in the notice, the T line or the outcome line -> '1 games', 'these games' or 'turned off for 1 games' appears.
        $run = Invoke-F73Setup -Games @('Prot', 'ReadyA') -NativeAnswers @('T')
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "1 of these games already uses TeknoParrot's own CRT look"
        $text | Should -Match '\[T\] Turn it off for 1 game \[D\]'
        $text | Should -Match "turned off for 1 game\."
        $text | Should -Not -Match '\b1 games\b'
        @($run.Result.NativeCrtTurnedOff) | Should -Be @('ReadyA')
    }

    It 'says "this game" and shows no game name or setting when only one game is selected' {
        # Mutation: print the game name or the 'Video / CRT Shader = Lottes' line in the default view of a single game -> the name/setting checks fail.
        $run = Invoke-F73Setup -Games @('ReadyA')
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "This game already uses TeknoParrot's own CRT look\."
        $text | Should -Match '\[T\] Turn it off for this game'
        @($run.Out | Where-Object { $_ -cmatch 'ReadyA|Lottes|CRT Shader|Video /|Turn off :|Turn off:' }).Count | Should -Be 0
    }

    It 'never changes anything in an unattended run and shows the short notice only' {
        # Mutation: remove the Unattended check -> the choice prompt appears and a scripted T would change the profiles.
        Set-Variable -Name Unattended -Scope Global -Value ([switch]$true)
        $run = Invoke-F73Setup -NativeAnswers @('T') -Interactive $false
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
        @($run.Prompts | Where-Object { $_ -match 'Choice, default K' }).Count | Should -Be 0
        $run.Events | Should -Not -Contain 'backup'
        $run.Result.NativeCrtRequested | Should -BeFalse
        (Get-F73Normalized $run.Out) | Should -Match "3 of these games use TeknoParrot's own screen settings, such as a CRT look\. TeknoParrot Manager keeps them as they are\. A ReShade look can add to them\."
        @($run.Out | Where-Object { $_ -match 'Press D at the next menu|Press D for details' }).Count | Should -Be 0
    }

    It 'shows no game name, setting or "Turn off" line in the default view of one unattended game, but logs them' {
        # Mutation: print the old per-game lines (game name, 'Video / CRT Shader = Lottes; Video / SSAA = 2', 'Turn off :') in the general notice -> the default-view checks fail.
        Set-Variable -Name Unattended -Scope Global -Value ([switch]$true)
        $run = Invoke-F73Setup -Games @('ReadyA') -Interactive $false
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "This game uses TeknoParrot's own screen settings, such as a CRT look\. TeknoParrot Manager keeps them as they are\."
        @($run.Out | Where-Object { $_ -cmatch 'ReadyA|Lottes|CRT Shader|SSAA|Video /|Turn off' }).Count | Should -Be 0
        Should -Invoke Write-Log -ParameterFilter { $msg -match 'native display settings kept in ReadyA: Video / CRT Shader=Lottes; Video / SSAA=2' } -Times 1 -Exactly
    }

    It 'offers a one-line D for details when one game is selected and no choice is offered, and shows the details then' {
        # Mutation: drop the D prompt or print the details without asking -> no prompt is recorded, or the details are in the default rows.
        $run = Invoke-F73Setup -Games @('ReadyA') -ProfileId 'ArcadeGlow' -NoticeAnswers @('D')
        @($run.Prompts | Where-Object { $_ -match 'Press D for details, or Enter to continue' }).Count | Should -Be 1
        $text = Get-F73Normalized $run.Out
        $text | Should -Match 'Settings: Video / CRT Shader = Lottes; Video / SSAA = 2'
        $text | Should -Match 'ReShade: will be installed or updated for this game'
        $run.After['ReadyA'] | Should -BeExactly $run.Before['ReadyA']
        $without = Invoke-F73Setup -Games @('ReadyA') -ProfileId 'ArcadeGlow'
        (Get-F73Normalized $without.Out) | Should -Not -Match 'Settings: Video'
    }

    It 'points to D at the next menu when several games are selected and no choice is offered' {
        # Mutation: drop the hint, or ask the D question before the menu that already has D -> no hint line, or a second D prompt is recorded.
        $run = Invoke-F73Setup -ProfileId 'ArcadeGlow'
        $text = Get-F73Normalized $run.Out
        $text | Should -Match 'Press D at the next menu for details\.'
        @($run.Prompts | Where-Object { $_ -match 'Press D for details, or Enter to continue' }).Count | Should -Be 0
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
    }

    It 'does not offer the choice for a profile that is not a CRT look' {
        # Mutation: offer T for every profile -> the K/T prompt appears for the Main profile.
        $run = Invoke-F73Setup -ProfileId 'ArcadeGlow' -NativeAnswers @('T')
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
        @($run.Prompts | Where-Object { $_ -match 'Choice, default K' }).Count | Should -Be 0
        $run.Events | Should -Not -Contain 'backup'
    }

    It 'offers T for the games that can be changed, says how many cannot, and names them in the outcome and the details' {
        # Mutation: size the T line or the outcome by the number of games that use the CRT shader (3) -> the T line says 2 games and the cannot-change sentences are missing.
        $run = Invoke-F73Setup -Games @('Prot', 'ReadyA', 'ReadyB') -NoOff @('ReadyB') -NativeAnswers @('D', 'T') -DetailAnswers @('D')
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "2 of these games already use TeknoParrot's own CRT look\."
        $text | Should -Match '1 of them cannot be turned off here\. Press D to see why\.'
        $text | Should -Match '\[T\] Turn it off for 1 game \[D\]'
        $text | Should -Match "TeknoParrot's own CRT look was turned off for 1 game\."
        $text | Should -Match 'Not changed: 1 game cannot be turned off here\. Its game profile has no off choice\.'
        $text | Should -Match 'Turn off: cannot be turned off here \(the game profile has no off value for it\)'
        $text | Should -Match 'What happened: The game profile has no off choice for the CRT look, so it was left on\.'
        @($run.Result.NativeCrtTurnedOff) | Should -Be @('ReadyA')
        $run.After['ReadyB'] | Should -BeExactly $run.Before['ReadyB']
    }

    It 'rolls one failed game back, reports it, still installs ReShade everywhere, and finishes the other game' {
        # Mutation: let the failed write escape into the ReShade loop, or skip the rollback -> ReadyA is listed as failed/garbage, or ReadyB stays unchanged.
        $run = Invoke-F73Setup -NativeAnswers @('T') -Break 'Once'
        $run.After['ReadyA'] | Should -BeExactly $run.Before['ReadyA']
        $run.After['ReadyB'] | Should -Not -BeExactly $run.Before['ReadyB']
        $run.After['Prot'] | Should -BeExactly $run.Before['Prot']
        @($run.Result.ChangedItems) | Should -Be @('ReadyA', 'ReadyB')
        @($run.Result.FailedItems).Count | Should -Be 0
        @($run.Result.UnverifiedItems).Count | Should -Be 0
        @($run.Result.NativeCrtTurnedOff) | Should -Be @('ReadyB')
        $notChanged = @($run.Result.NativeCrtNotChanged)
        $notChanged.Count | Should -Be 1
        $notChanged[0].Game | Should -BeExactly 'ReadyA'
        $notChanged[0].RolledBack | Should -BeTrue
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "TeknoParrot's own CRT look was turned off for 1 game\."
        $text | Should -Match 'Not changed: 1 game could not be changed\. Its game profile is as it was\.'
        $text | Should -Not -Match 'may be damaged'
    }

    It 'says the game profile may be damaged in red, adds the game to the unverified list, and the run is not a success when the rollback fails too' {
        # Mutation: report only 'could not be turned off' for NeedsRestore (or leave the game out of UnverifiedItems) -> no red damaged line, and the run ends SUCCEEDED.
        $run = Invoke-F73Setup -NativeAnswers @('T') -Break 'Always' -ThroughSetup
        $run.Result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $run.Result.Succeeded | Should -BeFalse
        @($run.Result.UnverifiedItems) | Should -Be @('ReadyA')
        @($run.Result.NativeCrtNeedsRestoreItems) | Should -Be @('ReadyA')
        $run.After['ReadyA'] | Should -BeExactly ([System.Convert]::ToBase64String($script:F73Utf8.GetBytes('partial garbage')))
        $row = @($run.Rows | Where-Object { $_.Text.Trim() -ceq 'The game profile of 1 game may be damaged. Use Restore backup now.' })
        $row.Count | Should -BeGreaterOrEqual 1
        $row[0].Color | Should -BeExactly 'Red'
        (Get-F73Normalized $run.Out) | Should -Match "- TeknoParrot's own CRT look was turned off for 1 game\."
        (Get-F73Normalized $run.Out) | Should -Match 'Next: Open Restore backup from the main menu and pick the newest saved copy\.'
        @($run.Out | Where-Object { $_ -match 'could not confirm the files' }).Count | Should -Be 0
        $run.Result.Summary | Should -Match 'game profile may be damaged'
        Should -Invoke Write-Log -ParameterFilter { $msg -match 'ReadyA: the game profile may be damaged.*ReShadeNativeCrt_fixture' } -Times 1 -Exactly
    }

    It 'names the safety backup folder under Details when a profile may be damaged' {
        # Mutation: leave the backup folder out of the details -> the path (compared without white space, because it wraps) is not found.
        $run = Invoke-F73Setup -NativeAnswers @('T') -Break 'Always' -DetailAnswers @('D')
        $flat = ((@($run.Out) -join '') -replace '\s', '')
        $flat | Should -Match ([regex]::Escape((('FullBackup\ReShadeNativeCrt_fixture') -replace '\s', '')))
        (Get-F73Normalized $run.Out) | Should -Match 'Result: may be damaged \(Video / CRT Shader: Lottes\)'
        (Get-F73Normalized $run.Out) | Should -Match 'What happened: The change could not be checked or put back\. The game profile may be damaged\.'
        (Get-F73Normalized $run.Out) | Should -Match 'Saved copy of your game profiles'
        (Get-F73Normalized $run.Out) | Should -Match 'What to do: use Restore backup and pick the saved copy named below'
    }

    It 'changes nothing when the safety backup cannot be verified, and ReShade is still installed' {
        # Mutation: write the profiles without a verified backup -> the Ready profiles change although the backup failed.
        $run = Invoke-F73Setup -NativeAnswers @('T') -BackupVerified $false -DetailAnswers @('D')
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
        @($run.Events | Where-Object { $_ -eq 'backup' }).Count | Should -Be 1
        @($run.Result.ChangedItems) | Should -Be @('ReadyA', 'ReadyB')
        @($run.Result.NativeCrtTurnedOff).Count | Should -Be 0
        @($run.Result.NativeCrtNotChanged).Count | Should -Be 2
        $run.Result.NativeCrtNotChanged[0].Reason | Should -Match 'safety backup could not be made'
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "TeknoParrot's own CRT look was not changed\."
        $text | Should -Match 'Not changed: 2 games could not be changed\. Their game profiles are as they were\.'
        $text | Should -Match 'What happened: A saved copy of your game profiles could not be made, so nothing was changed\.'
    }

    It 'says so when ReShade was not installed on a game the user wanted to change' {
        # Mutation: leave the games that did not get ReShade out of the outcome -> the sentence and the details block for ReadyB are missing.
        $run = Invoke-F73Setup -NativeAnswers @('T') -DetailAnswers @('D') -FailInstallFor 'ReadyB'
        $run.Result.Errors | Should -Be 1
        @($run.Result.ChangedItems) | Should -Be @('ReadyA')
        @($run.Result.NativeCrtTurnedOff) | Should -Be @('ReadyA')
        $run.After['ReadyB'] | Should -BeExactly $run.Before['ReadyB']
        $text = Get-F73Normalized $run.Out
        $text | Should -Match "TeknoParrot's own CRT look was turned off for 1 game\."
        $text | Should -Match 'Not changed: 1 game did not get ReShade, so its CRT look stays on\.'
        $text | Should -Match 'What happened: ReShade was not installed in this game, so its CRT look was left on\.'
        @($run.Out | Where-Object { $_.Trim() -ceq 'ReadyB' }).Count | Should -BeGreaterOrEqual 1
    }

    It 'lists every game with its settings under Details and keeps the default view free of them' {
        # Mutation: drop a game, the setting line, or the note about removing ReShade from the Details output -> a Details assertion fails.
        $run = Invoke-F73Setup -NativeAnswers @('D', 'K')
        $text = Get-F73Normalized $run.Out
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { @($run.Out | Where-Object { $_.Trim() -ceq $name }).Count | Should -Be 1 }
        $text | Should -Match 'Settings: Video / CRT Shader = Lottes; Video / SSAA = 2'
        $text | Should -Match 'ReShade: will be installed or updated for this game'
        $text | Should -Match 'Turn off: option T sets Video / CRT Shader to None'
        $text | Should -Match 'ReShade: stays unchanged \(it already has ReShade files that TeknoParrot Manager did not create\)'
        $text | Should -Match 'Turn off: not changed \(ReShade is not installed for this game\)'
        $text | Should -Match 'Undo: use Restore backup; removing ReShade later does not turn it back on'
        $text | Should -Match 'A ReShade CRT or shader look can add to them\.'
        @($run.Prompts | Where-Object { $_ -match 'Choice, default K' }).Count | Should -Be 2
        foreach ($name in @('Prot', 'ReadyA', 'ReadyB')) { $run.After[$name] | Should -BeExactly $run.Before[$name] }
    }
}

Describe 'FIX73 the screens reflow at <Width> columns' -ForEach @(@{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }) {
    BeforeEach {
        $script:f73Rows = New-Object 'System.Collections.Generic.List[object]'
        $script:f73Width = $Width
        $script:f73Prompts = New-Object 'System.Collections.Generic.List[string]'
        $script:f73PromptAt = -1
        Mock Write-Host { [void]$script:f73Rows.Add([pscustomobject]@{ Text = [string]$Object; Color = [string]$ForegroundColor }) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { $script:f73Width }
        Mock Test-TpmInteractiveInput { $true }
        Mock Read-HostSafe { if ($script:f73PromptAt -lt 0) { $script:f73PromptAt = $script:f73Rows.Count }; return 'D' }
        $script:f73ChoiceCalls = 0
        Mock Read-TpmChoice {
            $script:f73ChoiceCalls++
            if ($script:f73PromptAt -lt 0) { $script:f73PromptAt = $script:f73Rows.Count }
            if ($script:f73ChoiceCalls -eq 1) { return 'D' }
            return 'K'
        }
    }

    It 'keeps the question and its details inside the console and the default part to a short run' {
        # Mutation: print the notice or the details with Write-Host and fixed text (no wrapping) -> a row reaches the console width; or drop the blank lines -> the run is longer than 5 lines.
        $plan = New-F73Plan
        $answer = Read-TpmReShadeNativeCrtChoice -Plan $plan -SelectedCount 3
        $answer | Should -BeExactly 'K'
        $rows = @($script:f73Rows | ForEach-Object { ([string]$_.Text).TrimEnd() })
        @($rows | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $defaultRows = @($rows[0..($script:f73PromptAt - 1)])
        (Get-F73LongestRun -Rows $defaultRows -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $text = Get-F73Normalized $rows
        $text | Should -Match 'Settings: Video / CRT Shader = Lottes; Video / SSAA = 2'
    }

    It 'keeps the outcome and its details inside the console and the default part to a short run' {
        # Mutation: print the outcome with fixed text or list one line per game in the default view -> a row reaches the console width or the default run is longer than 5 lines.
        $records = [System.Collections.Generic.List[object]]::new()
        [void]$records.Add([pscustomobject]@{ Game = 'GameOne'; Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None'; Succeeded = $true; Outcome = 'TurnedOff'; RolledBack = $false; NeedsRestore = $false; Reason = ''; TempRemoved = @(); TempKept = @() })
        [void]$records.Add([pscustomobject]@{ Game = 'GameTwo'; Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None'; Succeeded = $false; Outcome = 'RolledBack'; RolledBack = $true; NeedsRestore = $false; Reason = 'The change could not be verified, so the setting was put back: the saved profile did not match what was written.'; TempRemoved = @('C:\UserProfiles\GameTwo.xml.0123456789abcdef0123456789abcdef.tmp'); TempKept = @() })
        [void]$records.Add([pscustomobject]@{ Game = 'GameThree'; Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None'; Succeeded = $false; Outcome = 'NeedsRestore'; RolledBack = $false; NeedsRestore = $true; Reason = 'The change could not be verified and could not be undone (access denied); restore the safety backup. the saved profile did not match what was written.'; TempRemoved = @(); TempKept = @('C:\UserProfiles\GameThree.xml.fedcba9876543210fedcba9876543210.tmp') })
        $state = [pscustomobject]@{
            Requested = $true; Items = @{ GameOne = $null; GameTwo = $null; GameThree = $null; GameFour = $null }; NotOffered = @('GameFive'); BackupTried = $true; BackupOk = $true
            BackupPath = 'C:\Users\Someone\AppData\Local\Temp\TeknoParrot\UserProfiles\FullBackup\ReShadeNativeCrt_2026-11-03_10-00-00_000_abcd1234'
            BackupReason = ''; Records = $records
        }
        Write-TpmReShadeNativeCrtOutcome -State $state
        $rows = @($script:f73Rows | ForEach-Object { ([string]$_.Text).TrimEnd() })
        @($rows | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $script:f73PromptAt | Should -BeGreaterThan 0
        $defaultRows = @($rows[0..($script:f73PromptAt - 1)])
        (Get-F73LongestRun -Rows $defaultRows -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $text = Get-F73Normalized $rows
        $text | Should -Match 'The game profile of 1 game may be damaged\. Use Restore backup now\.'
        $text | Should -Match 'Not changed: 1 game could not be changed\.'
        $text | Should -Match '1 game did not get ReShade, so its CRT look stays on\.'
        $text | Should -Match '1 game cannot be turned off here\.'
        $text | Should -Match 'Cleaned up: removed the leftover file'
        $text | Should -Match 'Leftover file: '
        @($defaultRows | Where-Object { $_ -cmatch 'GameOne|GameTwo|GameThree|GameFour|GameFive|FullBackup' }).Count | Should -Be 0
    }

    It 'says a game that got a different ReShade look kept its CRT look, not that it did not get ReShade' {
        # Mutation: list every game without a record as "did not get ReShade" -> a game installed with its own remembered look is reported as missing ReShade.
        $records = [System.Collections.Generic.List[object]]::new()
        [void]$records.Add([pscustomobject]@{ Game = 'GameOne'; Field = 'Video / CRT Shader'; OldValue = 'Lottes'; NewValue = 'None'; Succeeded = $true; Outcome = 'TurnedOff'; RolledBack = $false; NeedsRestore = $false; Reason = ''; TempRemoved = @(); TempKept = @() })
        $others = New-Object 'System.Collections.Generic.List[string]'
        [void]$others.Add('GameTwo')
        $state = [pscustomobject]@{ Requested = $true; Items = @{ GameOne = $null; GameTwo = $null }; NotOffered = @(); OtherLook = $others; BackupTried = $true; BackupOk = $true; BackupPath = 'C:\Backup'; BackupReason = ''; Records = $records }
        Write-TpmReShadeNativeCrtOutcome -State $state
        $text = Get-F73Normalized @($script:f73Rows | ForEach-Object { ([string]$_.Text).TrimEnd() })
        $text | Should -Match '1 game got a different ReShade look, so its CRT look stays on\.'
        $text | Should -Not -Match 'did not get ReShade'
    }

    It 'keeps the short notice inside the console when no choice is offered' {
        # Mutation: print the notice with fixed text -> a row reaches the console width; or ask the D question for several games -> a prompt is recorded before the rows end.
        $plan = New-F73Plan -Group 'Main'
        Write-TpmReShadeNativeGeneralNotice -Plan $plan -SelectedCount 3 -Interactive
        $rows = @($script:f73Rows | ForEach-Object { ([string]$_.Text).TrimEnd() })
        @($rows | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F73LongestRun -Rows $rows -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        (Get-F73Normalized $rows) | Should -BeExactly "3 of these games use TeknoParrot's own screen settings, such as a CRT look. TeknoParrot Manager keeps them as they are. A ReShade look can add to them. Press D at the next menu for details."
        $script:f73PromptAt | Should -Be -1
    }
}

Describe 'FIX73 plain words' {
    It 'keeps every sentence of the default view short' {
        # Mutation: put the old long sentence back into the notice, the choice or the outcome -> a sentence is longer than 16 words.
        $script:f73Rows = [System.Collections.Generic.List[object]]::new()
        $script:f73Width = 100
        Mock Write-Host { [void]$script:f73Rows.Add([pscustomobject]@{ Text = [string]$Object; Color = [string]$ForegroundColor }) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { $script:f73Width }
        Mock Read-TpmChoice { 'K' }
        $plan = New-F73Plan
        [void](Read-TpmReShadeNativeCrtChoice -Plan $plan -SelectedCount 3)
        Write-TpmReShadeNativeGeneralNotice -Plan $plan -SelectedCount 1
        # Each row is one paragraph here (width 100), so its sentences are split on their own.
        $sentences = New-Object System.Collections.Generic.List[string]
        foreach ($row in @($script:f73Rows)) {
            foreach ($sentence in @(([string]$row.Text).Trim() -split '(?<=[.!?])\s+')) { if ($sentence.Length -gt 0) { [void]$sentences.Add($sentence) } }
        }
        $sentences.Count | Should -BeGreaterThan 6
        @($sentences | Where-Object { ($_ -split '\s+').Count -gt 16 }).Count | Should -Be 0
        foreach ($text in @((Get-TpmReShadeNativeCrtDamagedText -Count 1), (Get-TpmReShadeNativeCrtDamagedText -Count 2), (Get-TpmReShadeNativeCrtOutcomeText -Outcome 'NeedsRestore'))) {
            @(($text -split '(?<=[.!?])\s+') | Where-Object { ($_ -split '\s+').Count -gt 16 }).Count | Should -Be 0
        }
    }

    It 'says "game profile" for one game and "game profiles" for several, with the right count' {
        # Mutation: use one wording for every count -> '1 games' or 'profile of 2 games' appears.
        Get-TpmReShadeNativeCrtDamagedText -Count 1 | Should -BeExactly 'The game profile of 1 game may be damaged. Use Restore backup now.'
        Get-TpmReShadeNativeCrtDamagedText -Count 3 | Should -BeExactly 'The game profiles of 3 games may be damaged. Use Restore backup now.'
    }

    It 'has no bare TPM in a visible string of the new functions or in the scan warning' {
        # Mutation: put "TPM" back into any visible string of these functions (the scan warning, a notice, the outcome, the details).
        $names = @(
            'Get-TpmReShadeNativeOffValue', 'Get-TpmReShadeNativeShaderWarnings', 'Get-TpmReShadeNativeCrtPlan', 'Get-TpmReShadeNativeDetailBlocks',
            'Show-TpmReShadeNativeDetails', 'Write-TpmReShadeNativeCrtNotice', 'Write-TpmReShadeNativeGeneralNotice', 'Read-TpmReShadeNativeCrtChoice',
            'Set-TpmReShadeNativeCrtOff', 'Invoke-TpmReShadeNativeCrtTurnOff', 'Get-TpmReShadeNativeCrtDamagedText', 'Get-TpmReShadeNativeCrtOutcomeText',
            'Write-TpmReShadeNativeCrtOutcome', 'New-TpmReShadeNativeCrtWriteResult', 'Get-TpmReShadeResultSummaryText', 'Show-TpmReShadeSetupResult'
        )
        $offenders = New-Object System.Collections.Generic.List[string]
        foreach ($name in $names) {
            $found = @($script:F73Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
            $found.Count | Should -Be 1 -Because $name
            $strings = $found[0].FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
            foreach ($stringNode in $strings) {
                $inLog = $false
                $parent = $stringNode.Parent
                while ($null -ne $parent) {
                    if ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent.GetCommandName() -in @('Write-Log', 'Write-Verbose')) { $inLog = $true; break }
                    $parent = $parent.Parent
                }
                if ($inLog) { continue }
                if ([string]$stringNode.Value -cmatch '\bTPM\b') { [void]$offenders.Add(('{0}: {1}' -f $name, $stringNode.Value)) }
            }
        }
        ($offenders -join "`n") | Should -BeExactly ''
        $warning = (Get-F73Warnings -Text (New-F73ProfileText -Name 'Warn')).Warning
        $warning | Should -Match 'TeknoParrot Manager preserves them'
        $warning | Should -Not -Match '\bTPM\b'
    }
}
