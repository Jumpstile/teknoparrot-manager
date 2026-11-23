#Requires -Module Pester

# LaunchBox integration has its own item on the main menu, so a user whose games are already registered can reach the
# LaunchBox choices without running Register only first. The item opens the same choices that appear after AutoSync and
# Register only, and the guides name the same numbers the menu shows.
BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $script:GuideCases = @('README.md', 'QUICKSTART.md', 'docs\USER-GUIDE.md', 'docs\wiki-updates\Home.md') | ForEach-Object { @{ Name = $_; Path = (Join-Path $root $_) } }
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root 'TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
    foreach ($name in @('Get-MainMenuSections', 'Get-MainMenuItems', 'Write-TpmLaunchBoxOffer', 'Invoke-TpmLaunchBoxStep')) {
        $found = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true))
        if ($found.Count -ne 1) { throw "Expected exactly one $name function." }
        . ([scriptblock]::Create($found[0].Extent.Text))
    }
    $script:Lines = New-Object System.Collections.Generic.List[string]
    function Write-TpmText { param([AllowEmptyString()][string]$Text, [string]$Color, [switch]$BlankBefore, [int]$HangingIndent) $script:Lines.Add($Text) }
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) }
    function Write-Log { param([string]$msg) }
    function Read-TpmChoice { param($Prompt, $Choices, $Default) return 'B' }
    function Invoke-TpmLaunchBoxMediaStep { param($lbRoot, $userProfilesDir, [switch]$Unattended, [switch]$DryRun, $TpRoot, $DatIndex) }
}

Describe 'LaunchBox integration main-menu item' {
    It 'sits right after Register only, keeps Exit last, and numbers stay in one run' {
        $items = @(Get-MainMenuItems)
        $register = @($items | Where-Object Mode -eq 'RegisterOnly')[0]
        $launchBox = @($items | Where-Object Mode -eq 'LaunchBoxSetup')
        $launchBox.Count | Should -Be 1
        $launchBox[0].Label | Should -Be 'LaunchBox integration'
        $launchBox[0].Number | Should -Be ($register.Number + 1)
        ($items | Sort-Object Number | Select-Object -Last 1).Mode | Should -Be 'Exit'
        (@($items | ForEach-Object { $_.Number }) -join ',') | Should -Be ((1..$items.Count) -join ',')
    }

    It 'opens the LaunchBox choices straight from the menu' {
        $source = [System.IO.File]::ReadAllText((Join-Path $script:Root 'TeknoParrot-Manager.ps1'))
        $source | Should -Match '"3"\s*\{\s*\$mode\s*=\s*"LaunchBoxSetup"'
        $branch = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match "\`$mode\s+-eq\s+'LaunchBoxSetup'" }, $true))
        $branch.Count | Should -Be 1
        $commands = @($branch[0].Clauses[0].Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $commands | Should -Contain 'Invoke-TpmLaunchBoxStep'
    }

    It 'shows every LaunchBox choice and a way back, without saying registration just finished' {
        $script:Lines.Clear()
        Write-TpmLaunchBoxOffer -Direct
        foreach ($key in @('[P]', '[A]', '[G]', '[V]', '[S]', '[L]', '[C]', '[F]', '[B]')) {
            @($script:Lines | Where-Object { $_.StartsWith($key + ' ') }).Count | Should -Be 1 -Because $key
        }
        ($script:Lines -join "`n") | Should -Not -Match 'registration is finished'
        ($script:Lines -join "`n") | Should -Match '\[B\] Back to the main menu'
    }

    It 'asks for a choice when opened directly, and keeps the registration wording after registration' {
        $dryRunActive = $false; $Unattended = $false
        $script:Lines.Clear()
        Invoke-TpmLaunchBoxStep -Direct
        ($script:Lines -join "`n") | Should -Not -Match 'registration is finished'
        ($script:Lines -join "`n") | Should -Match '\[P\] Preview first'
        $script:Lines.Clear()
        Invoke-TpmLaunchBoxStep
        ($script:Lines -join "`n") | Should -Match 'registration is finished'
    }
}

Describe 'Guides name the same menu numbers as the menu' {
    It '<Name> lists every menu row it shows under the number the menu gives it' -TestCases $script:GuideCases {
        param($Name, $Path)
        $items = @(Get-MainMenuItems)
        $rows = @([System.IO.File]::ReadAllLines($Path) | ForEach-Object {
            $m = [regex]::Match($_, '^\|\s*(\d+)\s*\|\s*\**([^|*]+?)\**\s*\|')
            if ($m.Success) { [pscustomobject]@{ Number = [int]$m.Groups[1].Value; Label = $m.Groups[2].Value.Trim() } }
        })
        @($rows | Where-Object Label -eq 'LaunchBox integration').Count | Should -BeGreaterThan 0
        foreach ($row in $rows) {
            $item = @($items | Where-Object { $_.Label -ieq $row.Label })
            if ($item.Count -eq 1) { $row.Number | Should -Be $item[0].Number -Because ('{0} row "{1}"' -f $Name, $row.Label) }
        }
        @($rows | Where-Object Label -ieq 'Exit' | ForEach-Object { $_.Number }) | Should -Contain @($items | Where-Object Mode -eq 'Exit')[0].Number
    }
}
