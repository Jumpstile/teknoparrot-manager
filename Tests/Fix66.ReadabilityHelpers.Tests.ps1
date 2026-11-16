#Requires -Module Pester

# FIX66: shared readability helpers and the shorter start-up screen.
#
#  1. Write-TpmText     one wrapped-paragraph writer (hanging indent, blank lines, width cap).
#  2. Write-TpmOutcome  the shared short result screen with a Details key; it always logs the full text.
#  3. Get-TpmPlainReason / Get-TpmFriendlyProgressLabel  plain words for reason codes and progress labels.
#  4. The start-up screen: saved settings behind the D key, a three-line DAT question, quiet migration notices.
#
# The production script is parsed and only its function definitions are dot-sourced. Every file lives under
# TestDrive. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F66Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX66 tests could not parse the production script.' }
    $script:F66Source = $source
    $definitions = @($script:F66Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $script:F66FunctionText = @{}
    foreach ($definition in $definitions) {
        if (-not $script:F66FunctionText.ContainsKey($definition.Name)) { $script:F66FunctionText[$definition.Name] = $definition.Extent.Text }
    }
    $functionFile = Join-Path $TestDrive 'tpm-fix66-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    $script:F66Paragraph = 'Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda'
    $script:F66Six = @('Game one was set up', 'Game two was set up', 'Game three was set up', 'Game four was set up', 'Game five was set up', 'Game six was set up')
    $script:F66Blocks = @(
        @{ Heading = 'Game one'; Lines = @('Database: GameDB01', 'What happened: It was set up.', 'What it means: Nothing else is needed.') },
        @{ Heading = 'Game two'; Lines = @('Database: GameDB02', 'What happened: It was already set up.') }
    )

    function Install-F66Mocks {
        param([int]$Width = 80, [string[]]$Answers = @(), [bool]$Interactive = $true)
        $script:F66Screen = New-Object System.Collections.Generic.List[object]
        $script:F66Log = New-Object System.Collections.Generic.List[string]
        $script:F66Prompts = New-Object System.Collections.Generic.List[string]
        $script:F66Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:F66Width = $Width
        $script:F66Interactive = $Interactive
        foreach ($answer in $Answers) { [void]$script:F66Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:F66Screen.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = [string]$ForegroundColor }) }
        Mock Write-Log { [void]$script:F66Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:F66Width }
        Mock Test-TpmInteractiveInput { return [bool]$script:F66Interactive }
        Mock Read-HostSafe {
            [void]$script:F66Prompts.Add([string]$Prompt)
            if ($script:F66Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F66Answers.Dequeue()
        }
    }

    function Get-F66Lines { return @($script:F66Screen | ForEach-Object { $_.Text }) }
}

Describe 'FIX66 Write-TpmText' {
    It 'wraps with a hanging indent and never exceeds the width at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: wrap at the full width instead of width minus one, or drop the hanging indent -> a line reaches the
        # width, or a continuation line starts under the first line.
        Install-F66Mocks -Width $Width
        Write-TpmText -Text $script:F66Paragraph -Indent 2 -HangingIndent 4
        $lines = @(Get-F66Lines)
        $lines.Count | Should -BeGreaterThan 1
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $lines[0] | Should -Match '^  \S'
        foreach ($continuation in @($lines | Select-Object -Skip 1)) { $continuation | Should -Match '^      \S' }
        ((@($lines | ForEach-Object { $_.Trim() })) -join ' ') | Should -BeExactly $script:F66Paragraph
    }

    It 'caps the line width at 100 columns on a wide console' {
        # Mutation: ignore MaxWidth -> a line is as wide as the 200 column console.
        Install-F66Mocks -Width 200
        Write-TpmText -Text ($script:F66Paragraph + ' ' + $script:F66Paragraph + ' ' + $script:F66Paragraph)
        $lines = @(Get-F66Lines)
        $longest = ($lines | Measure-Object -Property Length -Maximum).Maximum
        $longest | Should -BeLessThan 100
        $longest | Should -BeGreaterThan 80
    }

    It 'uses the console width when MaxWidth is 0' {
        # Mutation: treat MaxWidth 0 as 100 -> the longest line stays under 100 on a 160 column console.
        Install-F66Mocks -Width 160
        Write-TpmText -Text ($script:F66Paragraph + ' ' + $script:F66Paragraph + ' ' + $script:F66Paragraph) -MaxWidth 0
        $longest = (@(Get-F66Lines) | Measure-Object -Property Length -Maximum).Maximum
        $longest | Should -BeGreaterThan 120
        $longest | Should -BeLessThan 160
    }

    It 'keeps the Reset and Restore writer on the console width, not the 100 column cap' {
        # Mutation: let Write-TpmResetRestoreText use the default MaxWidth -> its lines stop at 99 columns.
        Install-F66Mocks -Width 140
        Write-TpmResetRestoreText -Text ($script:F66Paragraph + ' ' + $script:F66Paragraph + ' ' + $script:F66Paragraph)
        $longest = (@(Get-F66Lines) | Measure-Object -Property Length -Maximum).Maximum
        $longest | Should -BeGreaterThan 100
        $longest | Should -BeLessThan 140
    }

    It 'cuts a word wider than the line only when BreakLongWords is set' {
        # Mutation: ignore BreakLongWords -> the long path overflows the 60 column line; or break it always -> the
        # default no longer matches the Reset and Restore text.
        $path = 'D:\' + ('Folder\' * 20) + 'file.txt'
        Install-F66Mocks -Width 60
        Write-TpmText -Text $path -Indent 2 -BreakLongWords
        $broken = @(Get-F66Lines)
        @($broken | Where-Object { $_.Length -ge 60 }).Count | Should -Be 0
        (($broken | ForEach-Object { $_.Trim() }) -join '') | Should -BeExactly $path
        Install-F66Mocks -Width 60
        Write-TpmText -Text $path -Indent 2
        @(Get-F66Lines).Count | Should -Be 1
        (@(Get-F66Lines))[0].Length | Should -BeGreaterThan 60
    }

    It 'keeps wrapped text under a Prefix' {
        # Mutation: indent a continuation line by the hanging indent only -> it starts under the label.
        Install-F66Mocks -Width 50
        Write-TpmText -Text 'one two three four five six seven eight nine ten eleven twelve' -Prefix 'Label      : ' -Indent 4
        $lines = @(Get-F66Lines)
        $lines.Count | Should -BeGreaterThan 1
        $lines[0] | Should -Match '^    Label      : one'
        foreach ($continuation in @($lines | Select-Object -Skip 1)) { $continuation | Should -Match '^ {17}\S' }
    }

    It 'writes the blank lines asked for and no others' {
        # Mutation: ignore BlankBefore / BlankAfter, or always write them.
        Install-F66Mocks
        Write-TpmText -Text 'plain' -BlankBefore -BlankAfter
        (@(Get-F66Lines) -join '|') | Should -BeExactly '|  plain|'
        Install-F66Mocks
        Write-TpmText -Text 'plain'
        (@(Get-F66Lines) -join '|') | Should -BeExactly '  plain'
        Install-F66Mocks
        Write-TpmText -Text ''
        @(Get-F66Lines).Count | Should -Be 0
    }

    It 'passes the color on to the console' {
        # Mutation: drop -ForegroundColor -> the color is empty.
        Install-F66Mocks
        Write-TpmText -Text 'careful' -Color Yellow
        $script:F66Screen[0].Color | Should -BeExactly 'Yellow'
    }
}

Describe 'FIX66 Show-TpmDetailBlocks' {
    It 'prints one block per item: heading, aligned labeled lines, a blank line between blocks' {
        # Mutation: print the blocks as one run-on paragraph, or skip the blank line between blocks.
        Install-F66Mocks -Width 80
        Show-TpmDetailBlocks -Blocks $script:F66Blocks
        $lines = @(Get-F66Lines)
        $first = [array]::IndexOf($lines, '  Game one')
        $second = [array]::IndexOf($lines, '  Game two')
        $first | Should -BeGreaterThan -1
        $second | Should -BeGreaterThan $first
        $lines[$first - 1] | Should -BeExactly ''
        $lines[$second - 1] | Should -BeExactly ''
        $lines[$first + 1] | Should -Match '^    Database:\s+GameDB01$'
        $valueColumns = @($lines[($first + 1)..($first + 3)] | ForEach-Object { if ($_ -match '^(    \S[^:]*:\s+)\S') { $Matches[1].Length } })
        $valueColumns.Count | Should -Be 3
        @($valueColumns | Select-Object -Unique).Count | Should -Be 1
        $heading = @($script:F66Screen | Where-Object { $_.Text -eq '  Game one' })[0]
        $heading.Color | Should -BeExactly 'Cyan'
    }

    It 'wraps a long value under its text at <Width> columns' -TestCases @(@{ Width = 40 }, @{ Width = 60 }) {
        param($Width)
        # Mutation: wrap a labeled line without the label indent -> a continuation line starts under the label.
        Install-F66Mocks -Width $Width
        Show-TpmDetailBlocks -Blocks @(@{ Heading = 'Game'; Lines = @('What it means: This is a long sentence that has to wrap across more than one line of the console.') })
        $lines = @(Get-F66Lines | Where-Object { $_ -ne '' -and $_ -ne '  Game' })
        $lines.Count | Should -BeGreaterThan 1
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $valueColumn = $lines[0].IndexOf('This')
        $valueColumn | Should -BeGreaterThan 4
        foreach ($continuation in @($lines | Select-Object -Skip 1)) { $continuation | Should -Match ('^ {' + $valueColumn + '}\S') }
    }

    It 'states a common note once, at the top' {
        # Mutation: repeat the note in every block.
        Install-F66Mocks
        Show-TpmDetailBlocks -Blocks $script:F66Blocks -Note 'Nothing was deleted.'
        $lines = @(Get-F66Lines)
        @($lines | Where-Object { $_ -like '*Nothing was deleted.*' }).Count | Should -Be 1
        [array]::IndexOf($lines, '  Nothing was deleted.') | Should -BeLessThan ([array]::IndexOf($lines, '  Game one'))
    }

    It 'accepts objects as well as hashtables' {
        # Mutation: read the block fields as hashtable keys only -> an object block prints nothing.
        Install-F66Mocks
        Show-TpmDetailBlocks -Blocks @([pscustomobject]@{ Heading = 'Object block'; Lines = @('Key: value') })
        @(Get-F66Lines) | Should -Contain '  Object block'
        @(Get-F66Lines) | Should -Contain '    Key: value'
    }
}

Describe 'FIX66 Write-TpmOutcome' {
    It 'prints at most 12 lines for a six item example and collapses the extra bullets' {
        # Mutation: print every bullet -> more than 12 lines and no "... and 3 more".
        Install-F66Mocks -Answers @('')
        $result = Write-TpmOutcome -Title 'Setup finished.' -Done $script:F66Six -NotChanged 'No game files were touched.' -Next 'Press Enter to go back.' -DetailBlocks $script:F66Blocks -PassThru
        $lines = @(Get-F66Lines)
        $lines.Count | Should -BeLessOrEqual 12
        $lines[0] | Should -BeExactly ''
        $lines | Should -Contain '  Setup finished.'
        $lines | Should -Contain '    - Game one was set up'
        $lines | Should -Contain '    - Game three was set up'
        $lines | Should -Contain '    ... and 3 more'
        @($lines | Where-Object { $_ -like '*Game four*' -or $_ -like '*Game six*' }).Count | Should -Be 0
        $lines | Should -Contain '  Not changed: No game files were touched.'
        $lines | Should -Contain '  Next: Press Enter to go back.'
        $result.DetailsAvailable | Should -BeTrue
        $result.DetailsShown | Should -BeFalse
        $script:F66Prompts.Count | Should -Be 1
        $script:F66Prompts[0] | Should -Match '^\s*\[D\] Details'
    }

    It 'writes the full detail text to the log even when D is not pressed' {
        # Mutation: log the details only when the user opens them -> the log lacks the detail and collapsed lines.
        Install-F66Mocks -Answers @('')
        [void](Write-TpmOutcome -Title 'Setup finished.' -Done $script:F66Six -DetailBlocks $script:F66Blocks)
        @($script:F66Screen | Where-Object { $_.Text -like '*GameDB01*' }).Count | Should -Be 0
        $script:F66Log | Should -Contain 'Result detail [Game one]: Database: GameDB01'
        $script:F66Log | Should -Contain 'Result detail [Game two]: What happened: It was already set up.'
        foreach ($item in $script:F66Six) { $script:F66Log | Should -Contain ('Result done: ' + $item) }
        $script:F66Log | Should -Contain 'Result [Ok]: Setup finished.'
    }

    It 'shows the details as labeled blocks when D is pressed, in either case' -TestCases @(
        @{ Key = 'D' }, @{ Key = 'd' }
    ) {
        param($Key)
        # Mutation: show the details for any answer, or never.
        Install-F66Mocks -Answers @($Key)
        $result = Write-TpmOutcome -Title 'Setup finished.' -Done @('One thing') -DetailBlocks $script:F66Blocks -PassThru
        $result.DetailsShown | Should -BeTrue
        $lines = @(Get-F66Lines)
        $lines | Should -Contain '  Game one'
        $lines | Should -Contain '  Game two'
        @($lines | Where-Object { $_ -match '^    Database:\s+GameDB02$' }).Count | Should -Be 1
    }

    It 'does not show the details for Enter or another key' -TestCases @(@{ Key = '' }, @{ Key = 'x' }) {
        param($Key)
        # Mutation: treat every answer as D.
        Install-F66Mocks -Answers @($Key)
        $result = Write-TpmOutcome -Title 'Done.' -Done @('One thing') -DetailBlocks $script:F66Blocks -PassThru
        $result.DetailsShown | Should -BeFalse
        @(Get-F66Lines) | Should -Not -Contain '  Game one'
    }

    It 'adds the collapsed bullets and attention items to the details' {
        # Mutation: drop the overflow blocks -> the fourth to sixth bullet and the sixth and seventh item are nowhere on screen.
        Install-F66Mocks -Answers @('d')
        $needs = @(1..7 | ForEach-Object { 'Game {0} needs a look' -f $_ })
        [void](Write-TpmOutcome -Title 'Finished with notes.' -Status Attention -Done $script:F66Six -Needs $needs)
        $text = (@(Get-F66Lines) -join "`n")
        $text | Should -Match 'Everything that was done'
        $text | Should -Match 'Game six was set up'
        $text | Should -Match 'Everything that needs your attention'
        $text | Should -Match 'Game 7 needs a look'
    }

    It 'prints attention items only when there are some, at most five' {
        # Mutation: print the "Needs" heading with no items, or all seven items.
        Install-F66Mocks -Interactive $false
        [void](Write-TpmOutcome -Title 'Done.' -Done @('One thing'))
        @(Get-F66Lines | Where-Object { $_ -like '*Needs your attention*' }).Count | Should -Be 0
        Install-F66Mocks -Interactive $false
        [void](Write-TpmOutcome -Title 'Done.' -Needs @(1..7 | ForEach-Object { 'Item {0}' -f $_ }))
        $lines = @(Get-F66Lines)
        $lines | Should -Contain '  Needs your attention:'
        $lines | Should -Contain '    - Item 5'
        $lines | Should -Contain '    ... and 2 more'
        @($lines | Where-Object { $_ -like '*Item 6*' }).Count | Should -Be 0
    }

    It 'colors the status line by status: <Status>' -TestCases @(
        @{ Status = 'Ok'; Color = 'Green' }, @{ Status = 'Attention'; Color = 'Yellow' }, @{ Status = 'Problem'; Color = 'Red' }
    ) {
        param($Status, $Color)
        # Mutation: always color the status line green.
        Install-F66Mocks -Interactive $false
        [void](Write-TpmOutcome -Title 'Status line.' -Status $Status)
        @($script:F66Screen | Where-Object { $_.Text -eq '  Status line.' })[0].Color | Should -BeExactly $Color
    }

    It 'asks nothing and only logs the details when nobody can answer' {
        # Mutation: read the Details answer without checking for redirected or unattended input -> the prompt count is 1
        # and an exhausted input stream would stop the run.
        Install-F66Mocks -Interactive $false
        $result = Write-TpmOutcome -Title 'Done.' -Done $script:F66Six -DetailBlocks $script:F66Blocks -Unattended -PassThru
        $script:F66Prompts.Count | Should -Be 0
        $result.DetailsAvailable | Should -BeTrue
        $result.DetailsShown | Should -BeFalse
        @(Get-F66Lines | Where-Object { $_ -match '\[D\]' }).Count | Should -Be 0
        $script:F66Log | Should -Contain 'Result detail [Game one]: Database: GameDB01'
    }

    It 'asks no Details question when there are no details' {
        # Mutation: always ask.
        Install-F66Mocks
        $result = Write-TpmOutcome -Title 'Done.' -Done @('One', 'Two') -PassThru
        $script:F66Prompts.Count | Should -Be 0
        $result.DetailsAvailable | Should -BeFalse
    }

    It 'fits the console at <Width> columns' -TestCases @(@{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }) {
        param($Width)
        # Mutation: write the status or Next line without wrapping.
        Install-F66Mocks -Width $Width -Answers @('d')
        [void](Write-TpmOutcome -Title 'TeknoParrot Manager set up the game settings and checked every file it changed.' -Done $script:F66Six -Next 'Choose another option from the menu when you are ready to carry on with your games.' -DetailBlocks $script:F66Blocks)
        @(Get-F66Lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
    }

    It 'treats unattended and redirected input as not interactive' {
        # Mutation: return $true for -Unattended.
        Test-TpmInteractiveInput -Unattended | Should -BeFalse
    }
}

Describe 'FIX66 Get-TpmPlainReason' {
    It 'gives <Code> one plain sentence and returns the code separately' -TestCases @(
        @{ Code = 'ALREADY_APPLIED' }, @{ Code = 'UNKNOWN_ARCHITECTURE' }, @{ Code = 'CHANGED_SINCE_PREVIEW' },
        @{ Code = 'FAILED_BEFORE_MUTATION' }, @{ Code = 'RESTORE_POINT_HAS_NO_GAMES' }, @{ Code = 'PATH_TOO_LONG' },
        @{ Code = 'CANNOT_READ_SETTINGS' }, @{ Code = 'REBUILD_BACKUP_MISSING' }, @{ Code = 'POSTGRES_PREFLIGHT_FAILED' },
        @{ Code = 'POSTGRES_DATABASE_ROLLBACK_VERIFIED' }
    ) {
        param($Code)
        # Mutation: remove the code from the table -> Known is false and the text is the generic sentence.
        $reason = Get-TpmPlainReason -Code $Code
        $reason.Known | Should -BeTrue
        $reason.Code | Should -BeExactly $Code
        $reason.Text | Should -Match '^[A-Z][^_]*\.$'
        $reason.Text | Should -Not -BeExactly 'This could not be completed. Details have the technical reason.'
        $reason.Text.Length | Should -BeLessThan 130
    }

    It 'gives the ten required codes ten different sentences' {
        # Mutation: map every code to one sentence.
        $codes = @('ALREADY_APPLIED', 'UNKNOWN_ARCHITECTURE', 'CHANGED_SINCE_PREVIEW', 'FAILED_BEFORE_MUTATION', 'RESTORE_POINT_HAS_NO_GAMES', 'PATH_TOO_LONG', 'CANNOT_READ_SETTINGS', 'REBUILD_BACKUP_MISSING', 'POSTGRES_PREFLIGHT_FAILED', 'POSTGRES_DATABASE_ROLLBACK_VERIFIED')
        @($codes | ForEach-Object { (Get-TpmPlainReason -Code $_).Text } | Select-Object -Unique).Count | Should -Be 10
    }

    It 'falls back to a safe generic sentence for an unknown, empty or missing code' -TestCases @(
        @{ Code = 'SOMETHING_NEW_AND_ODD'; Expected = 'SOMETHING_NEW_AND_ODD' },
        @{ Code = '  something_new  '; Expected = 'SOMETHING_NEW' },
        @{ Code = ''; Expected = '' },
        @{ Code = $null; Expected = '' }
    ) {
        param($Code, $Expected)
        # Mutation: throw, or return the raw code as the sentence.
        $reason = Get-TpmPlainReason -Code $Code
        $reason.Known | Should -BeFalse
        $reason.Text | Should -BeExactly 'This could not be completed. Details have the technical reason.'
        $reason.Code | Should -BeExactly $Expected
    }

    It 'accepts a known code in any case' {
        # Mutation: look the code up case-sensitively.
        (Get-TpmPlainReason -Code 'path_too_long').Known | Should -BeTrue
        (Get-TpmPlainReason -Code ' Path_Too_Long ').Code | Should -BeExactly 'PATH_TOO_LONG'
    }

    It 'covers every literal reason code of the Reset and Restore and Restore backup results' {
        # Mutation: add a new -ReasonCode literal to New-TpmResetRestoreResult or New-TpmRestoreBackupLegacyResult without a table entry.
        $commands = @($script:F66Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and @('New-TpmResetRestoreResult', 'New-TpmRestoreBackupLegacyResult') -contains $args[0].GetCommandName() }, $true))
        $codes = New-Object System.Collections.Generic.List[string]
        foreach ($command in $commands) {
            $elements = @($command.CommandElements)
            for ($index = 0; $index -lt ($elements.Count - 1); $index++) {
                if ($elements[$index] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$index].ParameterName -eq 'ReasonCode' -and $elements[$index + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    [void]$codes.Add([string]$elements[$index + 1].Value)
                }
            }
        }
        $unique = @($codes | Select-Object -Unique)
        $unique.Count | Should -BeGreaterThan 25
        $missing = @($unique | Where-Object { -not (Get-TpmPlainReason -Code $_).Known })
        ($missing -join ', ') | Should -BeExactly ''
    }
}

Describe 'FIX66 Get-TpmFriendlyProgressLabel' {
    It 'maps <Label> to <Plain>' -TestCases @(
        @{ Label = 'UserProfiles manifest root discovery'; Plain = 'Checking your settings' },
        @{ Label = 'UserProfiles manifest scan'; Plain = 'Checking your settings' },
        @{ Label = 'Restore point check'; Plain = 'Checking your backups' },
        @{ Label = 'Start-up restore point check'; Plain = 'Checking your backups' },
        @{ Label = 'Control readiness profile scan'; Plain = 'Checking your game controls' },
        @{ Label = 'AutoSync ZIP inventory'; Plain = 'Checking your game ZIP files' },
        @{ Label = 'UserProfiles backup completion inventory'; Plain = 'Checking your backup' },
        @{ Label = 'backup completion inventory'; Plain = 'Checking your backup' },
        @{ Label = 'Owned-state migration'; Plain = 'Updating TeknoParrot Manager files' },
        @{ Label = 'Reset and Restore comparison'; Plain = 'Comparing with your restore point' }
    ) {
        param($Label, $Plain)
        # Mutation: remove the label from the table -> the internal label is returned.
        Get-TpmFriendlyProgressLabel -Label $Label | Should -BeExactly $Plain
    }

    It 'passes an unknown or empty label through unchanged' -TestCases @(
        @{ Label = 'Game-Alpha' }, @{ Label = 'CPS3 file promotion' }, @{ Label = '' }
    ) {
        param($Label)
        # Mutation: return a generic label for everything that is not in the table.
        Get-TpmFriendlyProgressLabel -Label $Label | Should -BeExactly $Label
    }

    It 'shows no internal jargon in any plain label' {
        # Mutation: map a label to text that still reads as an internal step name.
        $labels = @('UserProfiles manifest scan', 'Restore point check', 'Control readiness profile scan', 'AutoSync ZIP inventory', 'Owned-state migration', 'FFB plugin profile matching', 'BepInEx staged-file discovery', 'File transaction preflight')
        foreach ($label in $labels) {
            $plain = Get-TpmFriendlyProgressLabel -Label $label
            $plain | Should -Not -BeExactly $label
            $plain | Should -Not -Match 'UserProfiles|manifest|inventory|Owned-state|transaction|preflight|discovery|profile-code|ZIP/directory'
        }
    }
}

Describe 'FIX66 progress label in the progress wrapper' {
    BeforeAll {
        # Recording stand-ins for the progress module; the real wrapper is the unit under test.
        function Import-TpmProgressModule {}
        function Test-TpmProgressActive { return [bool]$script:F66ProgressActive }
        function Test-TpmProgressGroupOwned { return $false }
        function Get-TpmProgressTitle { return $script:F66ProgressTitle }
        function Register-TpmProgressOutcome { param($State) }
        function Start-TpmProgressOperation {
            param($Title, $Stage, $Total, $Width, [switch]$Group, $Unit = 'Items')
            $script:F66ProgressActive = $true
            $script:F66ProgressTitle = $Title
            [void]$script:F66ProgressEvents.Add([pscustomobject]@{ Kind = 'Start'; Stage = $Stage; Title = $Title })
        }
        function Set-TpmProgressStage {
            param([string]$Stage, [long]$Current, [long]$Total, [switch]$StageOnly, $Unit = 'Items', [switch]$SameStage)
            [void]$script:F66ProgressEvents.Add([pscustomobject]@{ Kind = 'Stage'; Stage = $Stage; Title = '' })
        }
        function Complete-TpmProgressOperation {
            param($State = 'Final', $Message = '', [switch]$Superseded)
            $script:F66ProgressActive = $false
            [void]$script:F66ProgressEvents.Add([pscustomobject]@{ Kind = 'Complete'; Stage = ''; Title = '' })
        }
        function Format-TpmProgressLine { param($Title, $Stage, $Current, $Total, $ElapsedSeconds, $Width, $Unit = 'Items') return ('{0}/{1}' -f $Current, $Total) }
        . ([scriptblock]::Create($script:F66FunctionText['Write-TpmCompactExtractionProgress']))
    }
    BeforeEach {
        $script:F66ProgressEvents = New-Object System.Collections.Generic.List[object]
        $script:F66ProgressActive = $false
        $script:F66ProgressTitle = $null
        $script:TpmLastLoggedProgressLabel = $null
        Install-F66Mocks
    }

    It 'shows the plain label and logs the internal label once when the step starts' {
        # Mutation: pass the internal label on, or log it on every update.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Restore point check' -Current 1 -Total 4
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Restore point check' -Current 2 -Total 4
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Restore point check' -Current 3 -Total 4
        @($script:F66ProgressEvents | Where-Object { $_.Kind -eq 'Start' })[0].Stage | Should -BeExactly 'Checking your backups'
        @($script:F66ProgressEvents | Where-Object { $_.Stage -like '*Restore point*' }).Count | Should -Be 0
        @($script:F66Log | Where-Object { $_ -eq 'Progress step: Restore point check (shown as "Checking your backups")' }).Count | Should -Be 1
    }

    It 'logs again when the step changes, and not when it completes' {
        # Mutation: log the closing call too, or log only the first step of the session.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Restore point check' -Current 1 -Total 2
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Reset and Restore comparison' -Current 1 -Total 2
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Reset and Restore comparison' -Current 2 -Total 2 -Complete
        @($script:F66Log | Where-Object { $_ -like 'Progress step:*' }).Count | Should -Be 2
        @($script:F66Log | Where-Object { $_ -like '*Reset and Restore comparison (shown as "Comparing with your restore point")' }).Count | Should -Be 1
    }

    It 'leaves an unknown label and the log alone' {
        # Mutation: log or rename a label that is not in the table.
        Write-TpmCompactExtractionProgress -Phase Scanning -Label 'Game-Alpha' -Current 1 -Total 4
        @($script:F66ProgressEvents | Where-Object { $_.Kind -eq 'Start' })[0].Stage | Should -BeExactly 'Game-Alpha'
        @($script:F66Log | Where-Object { $_ -like 'Progress step:*' }).Count | Should -Be 0
    }
}

Describe 'FIX66 start-up saved settings' {
    BeforeAll {
        $offerAssign = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -eq '$tpmOfferSavedConfig'
        }, $true))
        if ($offerAssign.Count -ne 1) { throw 'Expected exactly one $tpmOfferSavedConfig assignment.' }
        $offerBlock = @($offerAssign[0].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true))[0]
        $offerText = $offerBlock.Extent.Text
        $script:F66OfferBody = $offerText.Substring(1, $offerText.Length - 2)
        $script:F66Paths = [ordered]@{
            Root = 'D:\TeknoParrotRootFolder\TeknoParrot'
            Zip = 'E:\Collections\TeknoParrot\ZipSources\Main'
            Games = 'F:\Arcade\ExtractedGames\TeknoParrotGames'
            Dat = 'D:\TeknoParrotRootFolder\Eggman\Eggman-TeknoParrot-DAT-2026.zip'
        }

        function Invoke-F66Offer {
            param([bool]$Unattended = $false)
            $configPath = $script:F66ConfigPath
            $isPostgresRecoveryResume = $false
            $postgresSuperPasswordEncrypted = $null
            $checkForUpdatesOnStartup = $true
            $unattendedModeSaved = $null
            $configAccepted = $false
            $tpRoot = $null
            $gamesInstallFolder = $null
            $pendingApplyMode = $null
            . ([scriptblock]::Create($script:F66OfferBody))
            return [pscustomobject]@{ Accepted = $configAccepted; Root = $tpRoot }
        }
    }
    BeforeEach {
        $script:F66ConfigPath = Join-Path $TestDrive ('saved-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        $settings = [pscustomobject]@{
            TeknoParrotRoot = $script:F66Paths.Root; ZipSourceFolder = $script:F66Paths.Zip
            GamesInstallFolder = $script:F66Paths.Games; EggmanDatZip = $script:F66Paths.Dat
        }
        [System.IO.File]::WriteAllText($script:F66ConfigPath, ($settings | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
    }


    It 'shows a short default view with no settings list and no Configuration block' {
        # Mutation: print the settings list (or the old "Configuration:" block) again -> a path is on screen and the
        # screen is longer than six lines.
        Install-F66Mocks -Answers @('Y')
        $result = Invoke-F66Offer
        $result.Accepted | Should -BeTrue
        $result.Root | Should -BeExactly $script:F66Paths.Root
        $text = (@(Get-F66Lines) -join "`n")
        $text | Should -Not -Match 'Configuration:|Saved configuration found:'
        foreach ($path in $script:F66Paths.Values) { $text | Should -Not -Match ([regex]::Escape($path)) }
        ($script:F66Screen.Count + $script:F66Prompts.Count) | Should -BeLessOrEqual 6
        @(Get-F66Lines) | Should -Contain 'TeknoParrot Manager found your saved settings.'
        @(Get-F66Lines) | Should -Contain 'Using your saved settings.'
        $script:F66Prompts[0] | Should -Match 'Use these settings\? \(Y/N, D = show them\)'
    }

    It 'keeps the full paths in the log' {
        # Mutation: stop logging the saved settings -> the log has no path.
        Install-F66Mocks -Answers @('Y')
        [void](Invoke-F66Offer)
        $script:F66Log | Should -Contain ('Startup settings -   TeknoParrot root : ' + $script:F66Paths.Root)
        $script:F66Log | Should -Contain ('Startup settings -   ZIP source folder : ' + $script:F66Paths.Zip)
        $script:F66Log | Should -Contain ('Startup settings -   Games install folder : ' + $script:F66Paths.Games)
        $script:F66Log | Should -Contain ('Startup settings -   Eggman dat ZIP : ' + $script:F66Paths.Dat)
    }

    It 'shows the full paths on D and then asks the same question again at <Width> columns' -TestCases @(@{ Width = 40 }, @{ Width = 80 }, @{ Width = 120 }) {
        param($Width)
        # Mutation: ignore D (it is then refused as an invalid answer), or show the paths without wrapping.
        Install-F66Mocks -Width $Width -Answers @('D', 'Y')
        $result = Invoke-F66Offer
        $result.Accepted | Should -BeTrue
        $script:F66Prompts.Count | Should -Be 2
        $lines = @(Get-F66Lines)
        $lines | Should -Contain '  Saved configuration found:'
        @($lines | Where-Object { $_ -like '*Please choose Y or N*' }).Count | Should -Be 0
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        $joined = ($lines -join '') -replace '\s', ''
        foreach ($path in $script:F66Paths.Values) { $joined | Should -Match ([regex]::Escape($path)) }
        @($lines | Where-Object { $_ -match 'TeknoParrot root\s+:' }).Count | Should -Be 1
    }

    It 'keeps the Y, N and other-answer behavior of the question' {
        # Mutation: accept Enter or another key as Y, or take N as Y.
        Install-F66Mocks -Answers @('N')
        $declined = Invoke-F66Offer
        $declined.Accepted | Should -BeFalse
        ($null -eq $declined.Root) | Should -BeTrue
        @(Get-F66Lines) | Should -Not -Contain 'Using your saved settings.'
        Install-F66Mocks -Answers @('', 'x', 'y')
        $accepted = Invoke-F66Offer
        $accepted.Accepted | Should -BeTrue
        @(Get-F66Lines | Where-Object { $_ -eq '  Please choose Y or N.' }).Count | Should -Be 2
        $script:F66Prompts.Count | Should -Be 3
    }

    It 'accepts the saved settings without a question in an unattended run' {
        # Mutation: ask in an unattended run, or print the settings list there.
        Install-F66Mocks
        $result = Invoke-F66Offer -Unattended $true
        $result.Accepted | Should -BeTrue
        $script:F66Prompts.Count | Should -Be 0
        @(Get-F66Lines) | Should -Contain '  [Unattended] Using saved settings.'
        (@(Get-F66Lines) -join "`n") | Should -Not -Match ([regex]::Escape($script:F66Paths.Root))
        $script:F66Log | Should -Contain 'Unattended: auto-accepted saved settings.'
    }
}

Describe 'FIX66 Show-TpmStartupSummary' {
    BeforeAll {
        $script:F66Rows = @(
            (New-TpmStartupRow -Label 'TeknoParrot root' -Value 'C:\TeknoParrot'),
            (New-TpmStartupRow -Label 'ZIP source folder' -Value 'D:\Zips'),
            (New-TpmStartupRow -Label 'Games install folder' -Value 'E:\Games'),
            (New-TpmStartupRow -Label 'RetroBat mode' -Value 'Yes (*.teknoparrot / *.parrot / *.game recognized)' -Color 'Cyan')
        )
    }

    It 'only logs the rows by default' {
        # Mutation: print in the default mode, or skip the log.
        Install-F66Mocks
        Show-TpmStartupSummary -Title 'Configuration:' -Rows $script:F66Rows
        $script:F66Screen.Count | Should -Be 0
        $script:F66Log | Should -Contain 'Startup settings -   TeknoParrot root : C:\TeknoParrot'
        $script:F66Log | Should -Contain 'Startup settings -   Games install folder : E:\Games'
    }

    It 'prints the old lines exactly in Plain mode, so the smoke harness still finds the root' {
        # Mutation: change the "Label : value" layout or the title -> the harness regexes no longer match.
        Install-F66Mocks
        Show-TpmStartupSummary -Title 'Configuration:' -Rows $script:F66Rows -Mode Plain -TitleColor Green
        $lines = @(Get-F66Lines)
        $lines[0] | Should -BeExactly 'Configuration:'
        $script:F66Screen[0].Color | Should -BeExactly 'Green'
        $lines[1] | Should -BeExactly '  TeknoParrot root     : C:\TeknoParrot'
        $lines[3] | Should -BeExactly '  Games install folder : E:\Games'
        $lines[4] | Should -BeExactly '  RetroBat mode        : Yes (*.teknoparrot / *.parrot / *.game recognized)'
        $console = ($lines -join "`r`n") + "`r`n`r`nLoading collection dat from ZIP..."
        $block = [regex]::Match($console, '(?ms)^Configuration:\s*$(.*?)(?:\r?\n\r?\n|\z)')
        $block.Success | Should -BeTrue
        [regex]::Match($block.Groups[1].Value, '(?m)^\s*TeknoParrot root\s*:\s*(.+?)\s*$').Groups[1].Value | Should -BeExactly 'C:\TeknoParrot'
    }

    It 'prints wrapped rows in Details mode without logging them again' {
        # Mutation: log in Details mode (the log then holds every row twice).
        Install-F66Mocks -Width 40
        Show-TpmStartupSummary -Title 'Saved configuration found:' -Rows $script:F66Rows -Mode Details
        $script:F66Log.Count | Should -Be 0
        @(Get-F66Lines | Where-Object { $_.Length -ge 40 }).Count | Should -Be 0
        (@(Get-F66Lines) -join '') | Should -Match ([regex]::Escape('C:\TeknoParrot'))
    }

    It 'uses no second Configuration block in an interactive run, and the old one only when unattended' {
        # Mutation: restore Write-Host "Configuration:" for every run -> a Write-Host command with that title exists
        # and the interactive branch prints the block.
        $summaryCalls = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Show-TpmStartupSummary' -and $args[0].Extent.Text -like "*-Title 'Configuration:'*"
        }, $true))
        $summaryCalls.Count | Should -Be 2
        $plain = @($summaryCalls | Where-Object { $_.Extent.Text -match '-Mode Plain' })
        $quiet = @($summaryCalls | Where-Object { $_.Extent.Text -notmatch '-Mode' })
        $plain.Count | Should -Be 1
        $quiet.Count | Should -Be 1
        $branch = $plain[0].Parent
        while ($null -ne $branch -and $branch -isnot [System.Management.Automation.Language.IfStatementAst]) { $branch = $branch.Parent }
        $branch.Clauses[0].Item1.Extent.Text | Should -BeExactly '$Unattended'
        $plain[0].Extent.StartOffset | Should -BeGreaterThan $branch.Clauses[0].Item2.Extent.StartOffset
        $plain[0].Extent.EndOffset | Should -BeLessThan $branch.Clauses[0].Item2.Extent.EndOffset
        $quiet[0].Extent.StartOffset | Should -BeGreaterThan $branch.ElseClause.Extent.StartOffset
        $titleWrites = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Write-Host' -and $args[0].Extent.Text -match "^Write-Host\s+['""]Configuration:['""]"
        }, $true))
        $titleWrites.Count | Should -Be 0
    }
}

Describe 'FIX66 start-up DAT question and notices' {
    It 'shows the DAT question as three short lines with a blank line before and after at <Width> columns' -TestCases @(
        @{ Width = 80 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: bring back the six-line paragraph -> more than three text lines.
        $datIf = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -like '*-not $eggmanDatZip -and -not $datFilePath*' -and
            @($args[0].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Read-TpmChoice' }, $true)).Count -gt 0
        }, $true)) | Select-Object -First 1
        $datIf | Should -Not -BeNullOrEmpty
        $statements = @($datIf.Clauses[0].Item2.Statements)
        $choiceIndex = -1
        for ($index = 0; $index -lt $statements.Count; $index++) {
            if ($statements[$index] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $statements[$index].Left.Extent.Text -eq '$datChoice') { $choiceIndex = $index; break }
        }
        $choiceIndex | Should -BeGreaterThan 0
        $beforeQuestion = $script:F66Source.Substring($statements[0].Extent.StartOffset, $statements[$choiceIndex - 1].Extent.EndOffset - $statements[0].Extent.StartOffset)
        Install-F66Mocks -Width $Width
        Mock Get-EggmanDatDataRoot { return 'C:\Eggman' }
        . ([scriptblock]::Create($beforeQuestion))
        $lines = @(Get-F66Lines)
        $lines.Count | Should -Be 5
        $lines[0] | Should -BeExactly ''
        $lines[4] | Should -BeExactly ''
        $lines[1] | Should -Match '^  Optional: download the DAT index'
        $lines[2] | Should -Match '^    D = download it \(default\)'
        $lines[2] | Should -Match 'B = browse'
        $lines[3] | Should -Match '^    N = skip'
        @($script:F66Log | Where-Object { $_ -like 'EggmanDat: start-up question shown.*no games*' }).Count | Should -Be 1
    }

    It 'keeps the DAT question lines inside a narrow console' {
        # Mutation: write the DAT lines without wrapping.
        $datIf = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -like '*-not $eggmanDatZip -and -not $datFilePath*' -and
            @($args[0].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Read-TpmChoice' }, $true)).Count -gt 0
        }, $true)) | Select-Object -First 1
        $statements = @($datIf.Clauses[0].Item2.Statements)
        $choiceIndex = -1
        for ($index = 0; $index -lt $statements.Count; $index++) {
            if ($statements[$index] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $statements[$index].Left.Extent.Text -eq '$datChoice') { $choiceIndex = $index; break }
        }
        $beforeQuestion = $script:F66Source.Substring($statements[0].Extent.StartOffset, $statements[$choiceIndex - 1].Extent.EndOffset - $statements[0].Extent.StartOffset)
        Install-F66Mocks -Width 40
        Mock Get-EggmanDatDataRoot { return 'C:\Eggman' }
        . ([scriptblock]::Create($beforeQuestion))
        @(Get-F66Lines | Where-Object { $_.Length -ge 40 }).Count | Should -Be 0
        @(Get-F66Lines | Where-Object { $_ -ne '' }).Count | Should -BeGreaterThan 3
    }

    It 'keeps the migration notices in the log and shows only a failure: <Outcome>' -TestCases @(
        @{ Outcome = 'SUCCEEDED'; Visible = $false; Logged = 'TeknoParrot Manager-owned state migration completed.' },
        @{ Outcome = 'NO_OP'; Visible = $false; Logged = $null },
        @{ Outcome = 'FAILED_BEFORE_MUTATION'; Visible = $true; Logged = 'Owned-state migration did not complete before any managed move; normal startup is continuing.' },
        @{ Outcome = 'ROLLED_BACK_VERIFIED'; Visible = $true; Logged = 'State migration was rolled back and no managed state was changed.' }
    ) {
        param($Outcome, $Visible, $Logged)
        # Mutation: print the success notice again, or hide a failure.
        $chain = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -eq "`$migration.Outcome -eq 'FAILED_BEFORE_MUTATION'"
        }, $true))
        $chain.Count | Should -Be 1
        Install-F66Mocks
        $migration = [pscustomobject]@{ Outcome = $Outcome }
        . ([scriptblock]::Create($chain[0].Extent.Text))
        if ($Visible) {
            $script:F66Screen.Count | Should -BeGreaterThan 0
            $script:F66Screen[0].Color | Should -BeExactly 'Yellow'
            (@(Get-F66Lines) -join ' ') | Should -Not -Match 'TPM|Owned-state|state migration'
        } else {
            $script:F66Screen.Count | Should -Be 0
        }
        # The failure line also carries the reason code after the fixed sentence, so match the start of the line.
        if ($Logged) { @($script:F66Log | Where-Object { ([string]$_).StartsWith($Logged) }).Count | Should -BeGreaterThan 0 } else { $script:F66Log.Count | Should -Be 0 }
    }

    It 'ends the failed-migration log line with the real reason and no trailing space: <Case>' -TestCases @(
        @{ Case = 'no backup'; Backup = $null; Expected = 'Reason: DESTINATION_OCCUPIED' },
        @{ Case = 'backup reason'; Backup = [pscustomobject]@{ FailureStage = 'Backup'; FailureCode = 'disk is full' }; Expected = 'Reason: BACKUP_FAILED disk is full' }
    ) {
        param($Case, $Backup, $Expected)
        # Mutation: join the reason code and the backup detail with a fixed space -> the line ends in a space when there is no backup.
        $chain = @($script:F66Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -eq "`$migration.Outcome -eq 'FAILED_BEFORE_MUTATION'"
        }, $true))
        Install-F66Mocks
        $migration = [pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; ReasonCode = $(if ($Backup) { 'BACKUP_FAILED' } else { 'DESTINATION_OCCUPIED' }); Backup = $Backup }
        . ([scriptblock]::Create($chain[0].Extent.Text))
        $line = @($script:F66Log | Where-Object { ([string]$_).StartsWith('Owned-state migration did not complete before any managed move; normal startup is continuing.') })[0]
        $line | Should -Not -BeNullOrEmpty
        $line.EndsWith($Expected) | Should -BeTrue
    }

    It 'moves a lone start-up log with a log line and nothing on screen' {
        # Mutation: bring back the Write-Host line "Moving TeknoParrot Manager's start-up log into its Logs folder."
        $root = Join-Path $TestDrive 'fix66-migration-startup-log'
        $scriptRoot = Join-Path $root 'program'
        $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $scriptRoot, $tpRoot -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $scriptRoot 'TeknoParrot-Manager.log'), 'startup-log')
        $layout = Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $tpRoot)
        Install-F66Mocks
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-TpmYesNo { throw 'Unexpected migration prompt' }
        $result = Invoke-TpmOwnedMigration -ScriptRoot $scriptRoot -Layout $layout
        $result.Outcome | Should -Be 'SUCCEEDED'
        (@(Get-F66Lines) -join ' ') | Should -Not -Match 'start-up log|Logs folder'
        @($script:F66Log | Where-Object { $_ -eq "Owned-state migration: moving TeknoParrot Manager's start-up log into its Logs folder." }).Count | Should -Be 1
    }
}
