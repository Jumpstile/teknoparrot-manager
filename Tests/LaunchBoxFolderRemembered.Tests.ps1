#Requires -Module Pester

# TPM-R94BA: the LaunchBox folder is remembered, so the user is not asked for it every time.
# Only the function definitions of the production script are loaded. Folders are made up under TestDrive.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LaunchBox folder tests could not parse the production script.' }
    $wanted = @('Test-TpmLooksLikeLaunchBox', 'Get-TpmSavedLaunchBoxFolder', 'Save-TpmLaunchBoxFolder', 'Read-TpmLaunchBoxFolder')
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in $wanted }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $file = Join-Path $TestDrive 'tpm-lbfolder-functions.ps1'
    [System.IO.File]::WriteAllText($file, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $file

    function Save-Config { $true }
    function Read-HostSafe { param([string]$Prompt, [string]$Default = $null) }

    function New-FakeLaunchBox {
        param([string]$Name)
        $dir = Join-Path $TestDrive $Name
        [void](New-Item -ItemType Directory -Path $dir -Force)
        Set-Content -LiteralPath (Join-Path $dir 'LaunchBox.exe') -Value 'x'
        return $dir
    }
}

Describe 'LaunchBox folder is remembered' {
    BeforeEach {
        $script:lbRoot = $null
        $script:SavedCount = 0
        Mock Save-Config { $script:SavedCount++; $true }
    }

    It 'uses the saved folder when the user just presses Enter' {
        $script:lbRoot = New-FakeLaunchBox 'LbSaved'
        Mock Read-HostSafe { '' }
        (Read-TpmLaunchBoxFolder) | Should -BeExactly $script:lbRoot
        Should -Invoke Read-HostSafe -Times 1 -Exactly -ParameterFilter { $Prompt -like '*Press Enter to use it*' -and $Prompt -like "*$($script:lbRoot)*" }
    }

    It 'replaces the saved folder when the user types a different LaunchBox folder' {
        $script:lbRoot = New-FakeLaunchBox 'LbOld'
        $new = New-FakeLaunchBox 'LbNew'
        Mock Read-HostSafe { $new }
        (Read-TpmLaunchBoxFolder) | Should -BeExactly $new
        $script:lbRoot | Should -BeExactly $new
        $script:SavedCount | Should -Be 1
    }

    It 'saves a valid folder typed when nothing was saved' {
        $new = New-FakeLaunchBox 'LbFirst'
        Mock Read-HostSafe { $new }
        (Read-TpmLaunchBoxFolder) | Should -BeExactly $new
        $script:lbRoot | Should -BeExactly $new
    }

    It 'ignores a saved folder that is gone and shows the normal prompt' {
        $script:lbRoot = Join-Path $TestDrive 'LbGone'
        Mock Read-HostSafe { '' }
        (Read-TpmLaunchBoxFolder) | Should -BeExactly ''
        Should -Invoke Read-HostSafe -Times 1 -Exactly -ParameterFilter { $Prompt -like '*LaunchBox install folder (Enter to go back)*' }
    }

    It 'B goes back and keeps the saved folder' {
        $script:lbRoot = New-FakeLaunchBox 'LbKeep'
        $keep = $script:lbRoot
        Mock Read-HostSafe { 'B' }
        (Read-TpmLaunchBoxFolder) | Should -BeExactly ''
        $script:lbRoot | Should -BeExactly $keep
        $script:SavedCount | Should -Be 0
    }

    It 'does not save a typed folder that is not LaunchBox' {
        $script:lbRoot = New-FakeLaunchBox 'LbStay'
        $keep = $script:lbRoot
        $junk = Join-Path $TestDrive 'NotLaunchBox'
        [void](New-Item -ItemType Directory -Path $junk -Force)
        Mock Read-HostSafe { $junk }
        [void](Read-TpmLaunchBoxFolder)
        $script:lbRoot | Should -BeExactly $keep
        $script:SavedCount | Should -Be 0
    }
}
