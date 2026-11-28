#Requires -Module Pester

# R94AT: screens must say "controller" or the chosen layout, not "Xbox pad" or "Xbox controls", for the general case.
# Only the real layout names are allowed, by exact string. Reads the production script as text; nothing is run.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($productionPath), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'R94AT test could not parse the production script.' }
    $script:Strings = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true) | ForEach-Object { [string]$_.Value })
    $script:Allowed = @('Xbox controller', 'Arcade stick that shows up as an Xbox controller', 'Arcade stick, 8 buttons, that shows up as an Xbox controller', 'TPM''s built-in layouts (Xbox, PlayStation, Nintendo, arcade stick) with any change you made. Buttons use the standard Xbox button codes. Coin on Back, Start on Start, and the six action buttons follow the common arcade-to-gamepad layout used by public emulator guides. The 8-button arcade stick adds Button 7 and Button 8 on the left and right stick clicks. No data was copied from another program.')
}

Describe 'R94AT screens do not make controls sound Xbox-only' {
    It 'no screen string says Xbox pad, Xbox controls, Xbox button, Xbox setting, Xbox mode or Xbox-style' {
        $bad = @($script:Strings | Where-Object { $_ -match 'Xbox[ -](pad|controls?|controller|button|setting|mode|style|trigger)' -and $script:Allowed -notcontains $_ })
        ($bad -join "`n") | Should -BeNullOrEmpty
    }
}
