#Requires -Module Pester
# Finding 12: two profiles sharing one game folder -> duplicate ADD destinations in dgVoodoo2 batch.
BeforeAll {
    $sourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $definitions = @{}
    foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
        $definitions[$node.Name] += $node
    }
    $external = @('Write-Log','Write-TpmCompactExtractionProgress','Write-Host','Suspend-TpmProgressLine','Resume-TpmProgressLine')
    $selected = @{}
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue('Invoke-DgVoodoo2Setup')
    $pending.Enqueue('Invoke-TpmDgVoodoo2FileTransaction')
    while ($pending.Count) {
        $name = $pending.Dequeue()
        if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
        if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
        $node = $definitions[$name][0]; $selected[$name] = $node
        foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'f12-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}
    function Write-Log { param([string]$Message) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments=$true)]$Arguments) }
}
Describe 'F12 shared game folder' {
    It 'deploys once and succeeds when two profiles share one game folder' {
        $fx = Join-Path $TestDrive 'fx'
        $profiles = Join-Path $fx 'UserProfiles'; $source = Join-Path $fx 'Source'; $game = Join-Path $fx 'Game'
        foreach ($d in $profiles,$source,$game) { [void][System.IO.Directory]::CreateDirectory($d) }
        [System.IO.File]::WriteAllText((Join-Path $source 'D3D8.dll'), 'source D3D8 fixture')
        $exe = Join-Path $game 'game.exe'
        [System.IO.File]::WriteAllText($exe, 'inert fixture: d3d8.dll')
        foreach ($code in 'ProfA','ProfB') {
            [System.IO.File]::WriteAllText((Join-Path $profiles "$code.xml"), ('<GameProfile><GamePath>' + [System.Security.SecurityElement]::Escape($exe) + '</GamePath></GameProfile>'))
        }
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $fx 'Assets') }
        [void][System.IO.Directory]::CreateDirectory($script:TpmOwnedLayout.Assets)
        $oldTemp = $env:TEMP; $env:TEMP = $fx
        Mock Write-Host {}
        Mock Read-Host { 'A' }
        try { $result = Invoke-DgVoodoo2Setup -UserProfilesDir $profiles -SourceDir $source } finally { $env:TEMP = $oldTemp }
        [Console]::Error.WriteLine(('RESULT Succeeded={0} Outcome={1} Reason={2} Errors={3} Deployed={4}' -f $result.Succeeded,$result.TransactionResult.Outcome,$result.TransactionResult.ReasonCode,$result.Errors,$result.Deployed))
        [Console]::Error.WriteLine('DLL present: ' + (Test-Path (Join-Path $game 'D3D8.dll')))
        [Console]::Error.WriteLine('TECH: ' + ($result.TransactionResult.TechnicalDetails | ConvertTo-Json -Depth 3 -Compress))
        $result.Succeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $game 'D3D8.dll') | Should -BeTrue
    }
}
