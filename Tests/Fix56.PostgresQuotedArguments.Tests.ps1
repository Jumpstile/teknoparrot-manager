# FIX56 (found by the real-data smoke test N18): creating a PostgreSQL database whose name has capital letters (GameDBPPL13,
# GameDB19) failed because Windows PowerShell 5.1 drops the double quotes inside a native-command argument, so
# ALTER DATABASE "GameDBPPL13" reached psql as ALTER DATABASE GameDBPPL13, which the server folds to lowercase.
# FIX129: the tools are started as real child processes with a time limit (Invoke-PostgresToolProcess), so the product builds the
# command line itself (ConvertTo-PostgresNativeArgument, the Windows command-line rules) instead of relying on the engine's
# native-argument passing (the old ConvertTo-PostgresLegacyNativeArgument and its engine-mode switch are gone). These tests keep the
# FIX56 expectations on the new helper; the real-program round trip is in Fix129.PostgresToolResults.Tests.ps1.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ProductPath = Join-Path $script:RepoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ProductPath, [ref]$tokens, [ref]$parseErrors)
    $fn = $script:Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'ConvertTo-PostgresNativeArgument' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $script:Sql = 'ALTER DATABASE "GameDBPPL13" SET standard_conforming_strings = on;'
    $script:Escaped = '"ALTER DATABASE \"GameDBPPL13\" SET standard_conforming_strings = on;"'
}

Describe 'FIX56 PostgreSQL tool arguments keep their double quotes' {
    It 'escapes inner double quotes whatever the engine or its argument-passing mode is' {
        # Mutation: return the value unchanged -> the quotes are lost and mixed-case database names fail.
        ConvertTo-PostgresNativeArgument -Value $script:Sql | Should -BeExactly $script:Escaped
        $PSNativeCommandArgumentPassing = 'Legacy'
        ConvertTo-PostgresNativeArgument -Value $script:Sql | Should -BeExactly $script:Escaped
        $PSNativeCommandArgumentPassing = 'Standard'
        ConvertTo-PostgresNativeArgument -Value $script:Sql | Should -BeExactly $script:Escaped -Because 'the product builds the command line itself, so the engine mode must not matter (no double escaping)'
    }
    It 'leaves plain values untouched, quotes values with spaces and doubles backslashes in front of a quote' {
        # Mutation: always quote or rewrite -> plain names and paths change; forget the doubled backslashes -> a path ending in a backslash swallows its closing quote.
        ConvertTo-PostgresNativeArgument -Value 'GameDBPPL13' | Should -BeExactly 'GameDBPPL13'
        ConvertTo-PostgresNativeArgument -Value 'C:\Program Files (x86)\PostgreSQL\8.3\bin' | Should -BeExactly '"C:\Program Files (x86)\PostgreSQL\8.3\bin"'
        ConvertTo-PostgresNativeArgument -Value 'C:\Game Files\' | Should -BeExactly '"C:\Game Files\\"'
        ConvertTo-PostgresNativeArgument -Value 'a\"b' | Should -BeExactly '"a\\\"b"'
        ConvertTo-PostgresNativeArgument -Value '' | Should -BeExactly '""'
    }
    It 'builds the tool command line from every argument through the helper and starts a real child process' {
        # Mutation: join the raw arguments, or go back to the call operator (no time limit, and the quotes are lost again).
        $runner = $script:Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-PostgresToolProcess' }, $true).Extent.Text
        $runner | Should -Match 'ConvertTo-PostgresNativeArgument -Value \(\[string\]\$_\)'
        $runner | Should -Match 'System\.Diagnostics\.ProcessStartInfo'
        $runner | Should -Not -Match '& \$FilePath'
    }
}
