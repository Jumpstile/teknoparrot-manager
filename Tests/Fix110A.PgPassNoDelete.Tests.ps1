#Requires -Module Pester

# FIX110A (B-1): start-up never deletes files from the shared temp folder by name pattern.
#   Older TeknoParrot Manager builds left temporary PostgreSQL credential files (tpm-pgpass-*.conf) in the shared temp
#   folder. A name, an access list and a process id do not prove that TeknoParrot Manager made a file, and a delete by path
#   cannot tell the file that was inspected from one put there afterwards. So the start-up check only REPORTS how many files
#   have the old name shape. It never opens, reads or deletes them.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. Each It names the product change that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:F110Ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($script:F110Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix110a-pgpass-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile

    function New-F110PgPassFile {
        param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Name, [string]$Text = 'synthetic placeholder text')
        [void][System.IO.Directory]::CreateDirectory($Directory)
        $path = Join-Path $Directory $Name
        [System.IO.File]::WriteAllText($path, $Text)
        return $path
    }
}

Describe 'FIX110A B-1: old-looking temporary credential files are reported, never deleted' {
    BeforeEach { Mock Write-Log {} }

    It 'counts the exact old name shapes and leaves every file in place, even one that looks stale' {
        # Mutation: delete a candidate (File.Delete / Remove-Item) in Get-PostgresLeftoverPgPassFiles -> a counted file is gone.
        $folder = Join-Path $TestDrive ('f110-pgpass-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $hex = [guid]::NewGuid().ToString('N')
        $deadProcess = New-F110PgPassFile -Directory $folder -Name ('tpm-pgpass-2147483644-' + $hex + '.conf')
        $oldFormat = New-F110PgPassFile -Directory $folder -Name ('tpm-pgpass-' + [guid]::NewGuid().ToString('N') + '.conf')
        [System.IO.File]::SetLastWriteTimeUtc($oldFormat, [datetime]::UtcNow.AddDays(-30))
        $summary = Get-PostgresLeftoverPgPassFiles -Directory $folder
        $summary.Found | Should -Be 2
        Test-Path -LiteralPath $deadProcess | Should -BeTrue
        Test-Path -LiteralPath $oldFormat | Should -BeTrue
    }

    It 'keeps a foreign file that replaced a qualifying candidate, with its bytes untouched' {
        # Mutation: look at the name and then delete by path -> a foreign file that was put in place of a candidate is deleted.
        $folder = Join-Path $TestDrive ('f110-pgpass-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $name = 'tpm-pgpass-2147483640-' + [guid]::NewGuid().ToString('N') + '.conf'
        $path = New-F110PgPassFile -Directory $folder -Name $name -Text 'first'
        $first = Get-PostgresLeftoverPgPassFiles -Directory $folder
        [System.IO.File]::WriteAllText($path, 'a foreign file that is not ours')
        $second = Get-PostgresLeftoverPgPassFiles -Directory $folder
        $first.Found | Should -Be 1
        $second.Found | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -BeExactly 'a foreign file that is not ours'
    }

    It 'does not count files that only look similar' {
        # Mutation: count by the loose pattern tpm-pgpass-*.conf instead of the exact name shape -> a similar name is reported as ours.
        $folder = Join-Path $TestDrive ('f110-pgpass-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $hex = [guid]::NewGuid().ToString('N')
        [void](New-F110PgPassFile -Directory $folder -Name ('tpm-pgpass-' + $hex.Substring(0, 31) + '.conf'))
        [void](New-F110PgPassFile -Directory $folder -Name ('tpm-pgpass-x-' + $hex + '.conf'))
        [void](New-F110PgPassFile -Directory $folder -Name ('other-' + $hex + '.conf'))
        (Get-PostgresLeftoverPgPassFiles -Directory $folder).Found | Should -Be 0
    }

    It 'does not throw for a folder that cannot be listed' {
        # Mutation: let the listing failure escape -> start-up would stop.
        $summary = Get-PostgresLeftoverPgPassFiles -Directory (Join-Path $TestDrive ('missing-' + [guid]::NewGuid().ToString('N')))
        $summary.Found | Should -Be 0
    }

    It 'has no deleting command in the check, and no start-up caller deletes by pattern' {
        # Mutation: put File.Delete / Remove-Item / the old Remove-PostgresStalePgPassFiles back into the check or the start-up path.
        $check = @($script:F110Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PostgresLeftoverPgPassFiles' }, $true))
        $check.Count | Should -Be 1
        $deleting = @($check[0].FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -match '^(Remove-Item|Remove-TpmTreeOwnedFile|Clear-Content|Set-Content)$') -or
            ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Extent.Text -match '^(Delete|WriteAllText|WriteAllBytes|ReadAllText|ReadAllBytes|Open|OpenRead)$')
        }, $true))
        $deleting.Count | Should -Be 0
        $old = @($script:F110Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Remove-PostgresStalePgPassFiles' }, $true))
        $old.Count | Should -Be 0
        @($script:F110Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-PostgresStalePgPassFiles' }, $true)).Count | Should -Be 0
    }
}
