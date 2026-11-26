#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/364
# Audit: <audit-folder>/ISSUES-AUDIT-RESULT.md (#364, PARTIAL).
# AST-extract only the target and its real helper dependency closure. Never load startup.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:issueAst = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $definitions = @{}
    foreach ($node in $script:issueAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
        $definitions[$node.Name] += $node
    }
    $external = @('Write-Log','Write-TpmCompactExtractionProgress','Write-Host','Suspend-TpmProgressLine','Resume-TpmProgressLine')
    $selected = @{}
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue('Invoke-DgVoodoo2Setup')
    $pending.Enqueue('Invoke-TpmDgVoodoo2FileTransaction')
    $pending.Enqueue('Get-TpmDgVoodoo2ResultView')
    while ($pending.Count) {
        $name = $pending.Dequeue()
        if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
        if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
        if (@($definitions[$name]).Count -ne 1) { throw "Ambiguous production helper: $name" }
        $node = $definitions[$name][0]; $selected[$name] = $node
        foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'issue-364-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "

" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}
    function Write-Log { param([string]$Message) [void]$script:messages.Add($Message) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments=$true)]$Arguments) }
    $script:messages = New-Object 'System.Collections.Generic.List[string]'
    function Get-Issue364Snapshot {
        param([string]$Root)
        return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            if ($_.PSIsContainer) { 'D:' + $_.FullName }
            else { 'F:' + $_.FullName + ':' + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName)) }
        }) -join '|')
    }
    function Add-Issue364Game {
        param([string]$Code, [switch]$ExistingDll, [switch]$NoApi)
        $game = Join-Path $script:fixture $Code
        [void][System.IO.Directory]::CreateDirectory($game)
        $exe = Join-Path $game 'game.exe'
        $bytes = if ($NoApi) { 'inert executable fixture with no legacy imports' } else { 'inert fixture: d3d8.dll' }
        [System.IO.File]::WriteAllText($exe, $bytes)
        if ($ExistingDll) { [System.IO.File]::WriteAllText((Join-Path $game 'D3D8.dll'), 'existing file must stay unchanged') }
        $xmlPath = Join-Path $script:profiles ($Code + '.xml')
        $escaped = [System.Security.SecurityElement]::Escape($exe)
        [System.IO.File]::WriteAllText($xmlPath, ('<GameProfile><GamePath>' + $escaped + '</GamePath></GameProfile>'))
        return $exe
    }
}
Describe 'RC8 issue #364: empty dgVoodoo2 plans preserve no-op and planning failures' -Tag 'RC8-Issue' {
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:fixture 'UserProfiles'
        $script:source = Join-Path $script:fixture 'Source'
        [void][System.IO.Directory]::CreateDirectory($script:profiles)
        [void][System.IO.Directory]::CreateDirectory($script:source)
        [System.IO.File]::WriteAllText((Join-Path $script:source 'D3D8.dll'), 'source D3D8 fixture')
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets=(Join-Path $script:fixture 'Assets') }
        [void][System.IO.Directory]::CreateDirectory($script:TpmOwnedLayout.Assets)
        $script:oldTemp = $env:TEMP
        $env:TEMP = $script:fixture
        $script:hostLines = New-Object 'System.Collections.Generic.List[string]'
        $script:messages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:hostLines.Add([string]($Object -join ' ')) }
        Mock Read-Host { 'A' }
    }
    AfterEach { $env:TEMP = $script:oldTemp }
    It 'Preserve safe no-op semantics at the wrapper/caller boundary; do not crash merely because every item is unchanged/not applicable. (zero operations)' {
        $before = Get-Issue364Snapshot $script:fixture
        $result = Invoke-TpmDgVoodoo2FileTransaction -Operations @()
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        $result.Backup.Attempted | Should -BeFalse
        Get-Issue364Snapshot $script:fixture | Should -BeExactly $before
    }
    It 'Preserve safe no-op semantics at the wrapper/caller boundary; do not crash merely because every item is unchanged/not applicable. (all unchanged caller)' {
        $exe = Add-Issue364Game -Code 'UNCHANGED' -ExistingDll
        $before = Get-Issue364Snapshot $script:fixture
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeTrue
        $result.NoOp | Should -BeTrue
        $result.TransactionResult.Outcome | Should -BeExactly 'NO_OP'
        $result.Deployed | Should -Be 0
        $result.Errors | Should -Be 0
        ($script:hostLines -join '|') | Should -Not -Match 'No dgVoodoo2 file changes were needed'
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        $view.Title | Should -Match 'No game needed a new dgVoodoo2 file'
        ($view.Done -join '|') | Should -Match '1 game checked\. 1 need dgVoodoo2\.'
        ($view.Done -join '|') | Should -Match 'You selected 1 game: 1 already set up \(nothing to change\)\.'
        $every = @($view.DetailBlocks | Where-Object { $_.Heading -eq 'Every game you selected' })[0]
        ($every.Lines -join '|') | Should -Match 'UNCHANGED: Already set up\. API: D3D8\.'
        Get-Issue364Snapshot $script:fixture | Should -BeExactly $before
    }
    It 'accounts for every selected game in a mixed run: one set up now, one already set up' {
        [void](Add-Issue364Game -Code 'ALREADY' -ExistingDll)
        [void](Add-Issue364Game -Code 'FRESH')
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeTrue
        $result.NoOp | Should -BeFalse
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        ($view.Done -join '|') | Should -Match '2 games checked\. 2 need dgVoodoo2\.'
        ($view.Done -join '|') | Should -Match 'You selected 2 games: 1 set up now, 1 already set up \(nothing to change\)\.'
        $every = @($view.DetailBlocks | Where-Object { $_.Heading -eq 'Every game you selected' })[0]
        ($every.Lines -join '|') | Should -Match 'FRESH: Set up now\. API: D3D8\.'
        ($every.Lines -join '|') | Should -Match 'ALREADY: Already set up\.'
    }
    It 'Preserve safe no-op semantics at the wrapper/caller boundary; do not crash merely because every item is unchanged/not applicable. (not applicable caller)' {
        $exe = Add-Issue364Game -Code 'MODERN' -NoApi
        Mock Read-Host { 'Q' }
        $before = Get-Issue364Snapshot $script:fixture
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeTrue
        $result.NoOp | Should -BeTrue
        $result.Reason | Should -BeExactly 'NOT_NEEDED'
        ($script:hostLines -join '|') | Should -Match 'No dgVoodoo2 setup is needed right now'
        Get-Issue364Snapshot $script:fixture | Should -BeExactly $before
    }
    It 'Distinguish genuine no-op from inspection/planning failures that happen to leave no operations. Do not hide real failures by returning success for every empty list. (all skipped after selection)' {
        $script:vanishingExe = Add-Issue364Game -Code 'VANISHED'
        Mock Read-Host { [System.IO.File]::Delete($script:vanishingExe); 'A' }
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeFalse
        $result.NoOp | Should -BeFalse
        $result.TransactionResult.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.TransactionResult.ReasonCode | Should -BeExactly 'PREFLIGHT_INCOMPLETE'
        $result.Skipped | Should -Be 1
        @($result.SkipDetails).Count | Should -BeGreaterThan 0
        $result.SkipDetails[0].ReasonCode | Should -BeExactly 'GAME_PATH_MISSING'
        Test-Path -LiteralPath (Join-Path (Split-Path $script:vanishingExe -Parent) 'D3D8.dll') | Should -BeFalse
        ($script:hostLines -join '|') | Should -Match 'did not complete|SKIP'
    }
    It 'Distinguish genuine no-op from inspection/planning failures that happen to leave no operations. Do not hide real failures by returning success for every empty list. (unreadable deployment target)' {
        $exe = Add-Issue364Game -Code 'BADTARGET'
        [void][System.IO.Directory]::CreateDirectory((Join-Path (Split-Path $exe -Parent) 'D3D8.dll'))
        $before = Get-Issue364Snapshot $script:fixture
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeFalse
        $result.NoOp | Should -BeFalse
        $result.TransactionResult.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.TransactionResult.ReasonCode | Should -BeExactly 'PREFLIGHT_FAILED'
        $result.Errors | Should -BeGreaterThan 0
        ($script:messages -join '|') | Should -Match 'destination is not a readable file'
        Get-Issue364Snapshot $script:fixture | Should -BeExactly $before
    }
    It 'Cover zero operations, all unchanged, all skipped, mixed applicable/skipped, invalid input, and true transaction failures under PS5.1 and PS7. (mixed applicable/skipped)' {
        $goodExe = Add-Issue364Game -Code 'GOOD'
        $script:vanishingExe = Add-Issue364Game -Code 'VANISHED'
        Mock Read-Host { [System.IO.File]::Delete($script:vanishingExe); 'A' }
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeFalse
        $result.NoOp | Should -BeFalse
        $result.TransactionResult.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.Skipped | Should -Be 1
        $result.Deployed | Should -Be 1
        $result.Reason | Should -BeExactly 'PREFLIGHT_INCOMPLETE'
        [System.IO.File]::ReadAllText((Join-Path (Split-Path $goodExe -Parent) 'D3D8.dll')) | Should -BeExactly 'source D3D8 fixture'
        @($result.SkipDetails).Count | Should -Be 1
    }
    It 'Cover zero operations, all unchanged, all skipped, mixed applicable/skipped, invalid input, and true transaction failures under PS5.1 and PS7. (invalid profile)' {
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'INVALID.xml'), '<GameProfile>')
        $before = Get-Issue364Snapshot $script:fixture
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeFalse
        $result.NoOp | Should -BeFalse
        $result.TransactionResult.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.Reason | Should -BeExactly 'DETECTION_FAILED'
        @($result.TransactionResult.Errors).Count | Should -BeGreaterThan 0
        Get-Issue364Snapshot $script:fixture | Should -BeExactly $before
    }
    It 'Cover zero operations, all unchanged, all skipped, mixed applicable/skipped, invalid input, and true transaction failures under PS5.1 and PS7. (real transaction staging failure)' {
        $exe = Add-Issue364Game -Code 'STAGEFAIL'
        Mock Copy-Item { throw 'Injected staging copy failure' } -ParameterFilter { $Destination -like '*payload*' }
        $result = Invoke-DgVoodoo2Setup -UserProfilesDir $script:profiles -SourceDir $script:source
        $result.Succeeded | Should -BeFalse
        $result.NoOp | Should -BeFalse
        $result.TransactionResult.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.TransactionResult.ProductState | Should -BeExactly 'UNCHANGED'
        $result.Errors | Should -BeGreaterThan 0
        ($result.TransactionResult.TechnicalDetails | Out-String) | Should -Match 'Injected staging copy failure'
        Test-Path -LiteralPath (Join-Path (Split-Path $exe -Parent) 'D3D8.dll') | Should -BeFalse
        ($script:hostLines -join '|') | Should -Match 'did not complete'
    }
}
