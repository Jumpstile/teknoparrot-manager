#Requires -Module Pester

# A function exists only after the line that defines it has run. TeknoParrot-Manager.ps1 runs its main flow from top to bottom, and the
# main flow sits in one loop that also holds some function definitions. A tester registered games with AutoSync, chose the LaunchBox
# step, and the run stopped with "The term 'Invoke-TpmLaunchBoxMediaStep' is not recognized": the call ran before the line that defines it.
#   - The checker below walks the script in run order and lists every function that code can call (directly or through other
#     functions) before its definition has run. The real script must have none.
#   - The checker itself is proven on small scripts with the same layout as the bug.
#   - The LaunchBox step is run for real (only the prompts are scripted) with just the functions defined before the main loop starts,
#     so the LaunchBox picture step is reached the way a first AutoSync run reaches it.
# Everything is synthetic (TestDrive). Nothing reads a real install.
# What this CANNOT prove: calls built at run time (& $name, dot-sourced files) are not seen; a call that is conditional is still counted.

BeforeAll {
    if (-not ('TpmAstScan' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation.Language;
public static class TpmAstScan {
    public static FunctionDefinitionAst[] Functions(Ast root) {
        var list = new List<FunctionDefinitionAst>();
        foreach (var a in root.FindAll(n => n is FunctionDefinitionAst, true)) { list.Add((FunctionDefinitionAst)a); }
        return list.ToArray();
    }
    // Names of the commands that run when this node runs: the bodies of function definitions nested inside it do not.
    public static string[] LiveCommandNames(Ast root) {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var a in root.FindAll(n => n is CommandAst, true)) {
            string name = ((CommandAst)a).GetCommandName();
            if (name == null) { continue; }
            bool nested = false;
            for (Ast p = a.Parent; p != null && p != root.Parent; p = p.Parent) {
                if (p is FunctionDefinitionAst && p != root) { nested = true; break; }
            }
            if (!nested) { names.Add(name); }
        }
        var result = new string[names.Count];
        names.CopyTo(result);
        return result;
    }
}
'@
    }

    # The statements of the script in the order they run. A try or while block that holds function definitions is opened up, because
    # its definitions run one by one as the block runs.
    function Get-TpmRunOrder {
        param($Statements, $Items)
        foreach ($s in $Statements) {
            $body = $null
            if ($s -is [System.Management.Automation.Language.TryStatementAst]) { $body = $s.Body }
            elseif ($s -is [System.Management.Automation.Language.WhileStatementAst]) { $body = $s.Body }
            $holdsFunctions = $body -and (@($body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }).Count -gt 0)
            if (-not $holdsFunctions) { [void]$Items.Add($s); continue }
            if ($s -is [System.Management.Automation.Language.WhileStatementAst]) { [void]$Items.Add($s.Condition) }
            Get-TpmRunOrder -Statements $body.Statements -Items $Items
            if ($s -is [System.Management.Automation.Language.TryStatementAst]) {
                foreach ($c in @($s.CatchClauses)) { [void]$Items.Add($c.Body) }
                if ($s.Finally) { [void]$Items.Add($s.Finally) }
            }
        }
    }

    function Get-TpmCmdletNames {
        $names = New-Object System.Collections.Generic.HashSet[string]
        foreach ($c in Get-Command -CommandType Cmdlet) { [void]$names.Add($c.Name.ToLowerInvariant()) }
        , $names
    }

    # Every function whose definition is still to run when code that runs earlier calls it. A function with the name of a built-in
    # cmdlet is skipped: the cmdlet answers until the function exists, so nothing is "not recognized".
    function Get-TpmLateFunctionHits {
        param([Parameter(Mandatory)][System.Management.Automation.Language.ScriptBlockAst]$Ast)
        $defLine = @{}; $defName = @{}; $callees = @{}
        foreach ($f in [TpmAstScan]::Functions($Ast)) {
            $key = $f.Name.ToLowerInvariant()
            if ($defLine.ContainsKey($key)) { continue }
            $defLine[$key] = $f.Extent.StartLineNumber; $defName[$key] = $f.Name
            $callees[$key] = [TpmAstScan]::LiveCommandNames($f)
        }
        $items = New-Object System.Collections.Generic.List[object]
        Get-TpmRunOrder -Statements $Ast.EndBlock.Statements -Items $items
        $defined = New-Object System.Collections.Generic.HashSet[string]
        $visited = New-Object System.Collections.Generic.HashSet[string]
        $cmdletNames = Get-TpmCmdletNames
        $hits = New-Object System.Collections.Generic.List[object]
        foreach ($item in $items) {
            if ($item -is [System.Management.Automation.Language.FunctionDefinitionAst]) { [void]$defined.Add($item.Name.ToLowerInvariant()); continue }
            $from = @{}
            $queue = New-Object System.Collections.Generic.Queue[string]
            foreach ($name in [TpmAstScan]::LiveCommandNames($item)) {
                $key = $name.ToLowerInvariant()
                if (-not $from.ContainsKey($key)) { $from[$key] = ('script line {0}' -f $item.Extent.StartLineNumber); $queue.Enqueue($key) }
            }
            while ($queue.Count -gt 0) {
                $key = $queue.Dequeue()
                if (-not $defLine.ContainsKey($key) -or -not $visited.Add($key)) { continue }
                if ($cmdletNames.Contains($key)) { continue }
                if (-not $defined.Contains($key)) { [void]$hits.Add([pscustomobject]@{ Function = $defName[$key]; DefinedAtLine = $defLine[$key]; CalledFrom = $from[$key] }) }
                foreach ($callee in $callees[$key]) {
                    $c = $callee.ToLowerInvariant()
                    if (-not $from.ContainsKey($c)) { $from[$c] = ('{0} via {1}' -f $from[$key], $defName[$key]); $queue.Enqueue($c) }
                }
            }
        }
        $hits.ToArray()
    }
    function ConvertTo-TpmHitText { param($Hits) (@($Hits) | ForEach-Object { '{0} (defined at line {1}, reached from {2})' -f $_.Function, $_.DefinedAtLine, $_.CalledFrom }) -join '; ' }
    function Get-TpmSyntheticHits { param([string]$Text) @(Get-TpmLateFunctionHits -Ast ([System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null))) }

    $script:Src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Src, [ref]$null, [ref]$null)
}

Describe 'The checker finds a function that is called before its definition has run' {
    It 'reports a helper that a function reaches but that is defined later in the main loop (the layout of the tester crash)' {
        $text = @'
function Step { Media-Step }
$ready = 1
while ($true) {
    Step
    function Media-Step { 'media' }
    break
}
'@
        $hits = Get-TpmSyntheticHits -Text $text
        @($hits).Count | Should -Be 1
        @($hits)[0].Function | Should -Be 'Media-Step'
    }
    It 'reports a function defined after the script-level call that needs it' {
        $hits = Get-TpmSyntheticHits -Text "Do-Work`nfunction Do-Work { 'x' }"
        @($hits).Count | Should -Be 1
        @($hits)[0].Function | Should -Be 'Do-Work'
    }
    It 'reports nothing when every definition runs before the call' {
        $text = @'
function Media-Step { 'media' }
function Step { Media-Step }
while ($true) {
    Step
    function Later { 'x' }
    Later
    break
}
'@
        @(Get-TpmSyntheticHits -Text $text).Count | Should -Be 0
    }
    It 'accepts a function defined later when nothing calls it earlier' {
        @(Get-TpmSyntheticHits -Text "function A { 'a' }`nA`nfunction Late { 'l' }`nLate").Count | Should -Be 0
    }
    It 'ignores a function that shares its name with a built-in cmdlet' {
        @(Get-TpmSyntheticHits -Text "Write-Host 'hi'`nfunction Write-Host { 'x' }").Count | Should -Be 0
    }
}

Describe 'TeknoParrot-Manager.ps1 defines every function before code can call it' {
    It 'has no function that is called before its definition has run' {
        $hits = @(Get-TpmLateFunctionHits -Ast $script:Ast)
        (ConvertTo-TpmHitText -Hits $hits) | Should -BeNullOrEmpty
    }
    It 'defines the LaunchBox picture step before the main loop starts' {
        $mainTry = @($script:Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] -and @($_.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.WhileStatementAst] }).Count -gt 0 })
        $mainTry.Count | Should -Be 1
        $loopStart = @($mainTry[0].Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.WhileStatementAst] })[0].Extent.StartOffset
        foreach ($name in 'Invoke-TpmLaunchBoxStep', 'Invoke-TpmLaunchBoxMediaStep', 'Get-TpmLaunchBoxMediaPlan', 'Invoke-TpmLaunchBoxMediaImport', 'Invoke-TpmLaunchBoxMediaUndo') {
            $def = @([TpmAstScan]::Functions($script:Ast) | Where-Object { $_.Name -eq $name })
            $def.Count | Should -Be 1
            ($name + ' ' + [bool]($def[0].Extent.StartOffset -lt $loopStart)) | Should -Be ($name + ' True')
        }
    }
}

Describe 'The LaunchBox step reaches the picture step on a first run' {
    BeforeAll {
        $mainTry = @($script:Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] -and @($_.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.WhileStatementAst] }).Count -gt 0 })
        $loopStart = @($mainTry[0].Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.WhileStatementAst] })[0].Extent.StartOffset
        # Only what exists when the main loop starts its first pass, in file order. Names of built-in cmdlets are left alone.
        $cmdletNames = Get-TpmCmdletNames
        $texts = foreach ($f in [TpmAstScan]::Functions($script:Ast)) {
            if ($f.Extent.StartOffset -ge $loopStart) { continue }
            if ($cmdletNames.Contains($f.Name.ToLowerInvariant())) { continue }
            $f.Extent.Text
        }
        . ([scriptblock]::Create(($texts -join "`n")))

        $script:Log = New-Object System.Collections.Generic.List[string]
        $script:Shown = New-Object System.Collections.Generic.List[string]
        $script:Answers = New-Object System.Collections.Generic.Queue[string]
        function Write-Log { param([string]$msg) $script:Log.Add([string]$msg) }
        function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) }
        function Write-TpmText { param([string]$Text, $Color, [switch]$BlankBefore) $script:Shown.Add($Text) }
        function Write-TpmLaunchBoxOffer { param([switch]$Direct) }
        function Read-TpmChoice { param($Prompt, $Choices, $Default) $script:Shown.Add('ask: ' + $Prompt); if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() } return $Default }
        function Read-HostSafe { param($Prompt, $Default) $script:Shown.Add('ask: ' + $Prompt); if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() } return '' }
        function Read-TpmYesNo { param($Prompt, $Default, $DetailsAction) return 'N' }
        # The details and playlists screen has its own tests; here it only has to be a valid choice that leads on to the picture step.
        function Invoke-TpmLaunchBoxEnrichStep { param($UserProfilesDir, $LbRoot, $TpRoot, $DatIndex) }
        $script:TpmOwnedLayout = @{ Reports = $TestDrive; LogPath = (Join-Path $TestDrive 'log.txt') }
    }
    BeforeEach { $script:Log.Clear(); $script:Shown.Clear(); $script:Answers.Clear() }

    It 'offers the picture step after a LaunchBox choice instead of stopping with "not recognized"' {
        $dryRunActive = $false; $Unattended = $false
        $userProfilesDir = Join-Path $TestDrive 'UserProfiles'; $null = New-Item -ItemType Directory -Path $userProfilesDir -Force
        $lbRoot = Join-Path $TestDrive 'LaunchBox'; $null = New-Item -ItemType Directory -Path (Join-Path $lbRoot 'Data\Platforms') -Force
        $tpRoot = $TestDrive; $datIndex = @{}
        foreach ($a in 'G', 'S') { $script:Answers.Enqueue($a) }
        { Invoke-TpmLaunchBoxStep } | Should -Not -Throw
        ($script:Shown -join "`n") | Should -Match 'Optional: add logos or box art'
    }
    It 'runs the picture preview with a fake LaunchBox folder without a missing-command error' {
        $dryRunActive = $false; $Unattended = $false
        $userProfilesDir = Join-Path $TestDrive 'UserProfiles'; $null = New-Item -ItemType Directory -Path $userProfilesDir -Force
        $lbRoot = Join-Path $TestDrive 'LaunchBox'; $null = New-Item -ItemType Directory -Path (Join-Path $lbRoot 'Data\Platforms') -Force
        $pictures = Join-Path $TestDrive 'Pictures'; $null = New-Item -ItemType Directory -Path $pictures -Force
        $tpRoot = $TestDrive; $datIndex = @{}
        foreach ($a in 'G', 'I', $pictures, '1', '2') { $script:Answers.Enqueue($a) }
        { Invoke-TpmLaunchBoxStep } | Should -Not -Throw
        ($script:Shown -join "`n") | Should -Not -Match 'is not recognized'
        ($script:Log -join "`n") | Should -Not -Match 'is not recognized'
        ($script:Shown -join "`n") | Should -Match 'Nothing is downloaded'
    }
}
