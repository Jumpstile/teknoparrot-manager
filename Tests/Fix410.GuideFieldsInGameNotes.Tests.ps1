#Requires -Module Pester

# The Game Notes file shows the guide's setup steps, graphics card notes and extra files for registered games
# and registered variants, not only the free-text notes.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix410 bootstrap could not parse the manager.' }
    $functionsPath = Join-Path $TestDrive 'fix410-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionsPath
    . $functionsPath
    function Write-Log { param([Parameter(ValueFromRemainingArguments)]$Message) }
}

Describe 'Game Notes shows the guide fields for registered games' {
    BeforeEach {
        Mock Get-TpmRegisteredProfileCodes {
            $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($code in @('rom1', 'rom1v', 'plain', 'gpu1', 'base2v')) { [void]$set.Add($code) }
            return ,$set
        }
        Mock Get-TpmGameNeedsLine { '' }
        Mock Get-EggmanGameData {
            @(
                [pscustomobject]@{
                    profile_name = 'rom1'; game_name = 'Rom Game'; setup_exe = 'rom1.zip'; setup_exe2 = 'rom1/disc.chd'; test_exe = ''
                    notes = ''; general_issues = 'Select rom1.zip. Required CHD: disc.chd.'
                    amd_status = 'OK'; amd_issues = ''; nvidia_status = 'OK'; nvidia_issues = ''; intel_status = 'OK'; intel_issues = ''
                    variants = @([pscustomobject]@{ profile_name = 'rom1v'; game_name = 'Rom Game (rev B)'; setup_exe = 'rom1v.zip'; notes = '' })
                }
                [pscustomobject]@{
                    profile_name = 'base2'; game_name = 'Base Two'; setup_exe = 'base2.zip'; notes = ''; general_issues = 'Select the exact set in Game Revision.'
                    variants = @([pscustomobject]@{ profile_name = 'base2v'; game_name = 'Base Two (rev B)'; setup_exe = 'base2v.zip'; notes = '' })
                }
                [pscustomobject]@{ profile_name = 'plain'; game_name = 'Plain Game'; setup_exe = 'game.exe'; notes = ''; general_issues = '' }
                [pscustomobject]@{
                    profile_name = 'gpu1'; game_name = 'Gpu Game'; setup_exe = 'gpu.exe'; notes = 'Run the setup once.'; general_issues = ''
                    amd_status = 'WITH_FIX'; amd_issues = 'Select AMD Fix in settings.'; nvidia_status = 'OK'; nvidia_issues = ''; intel_status = 'NO'; intel_issues = ''
                }
                [pscustomobject]@{ profile_name = 'notregistered'; game_name = 'Other'; setup_exe = 'o.zip'; general_issues = 'Select o.zip.' }
            )
        }
    }

    It 'lists registered games that have setup steps or graphics notes and skips the rest' {
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        @($notes | ForEach-Object { $_.Code } | Sort-Object) | Should -Be @('base2v', 'gpu1', 'rom1')
        $rom = $notes | Where-Object { $_.Code -eq 'rom1' }
        $rom.GeneralIssues | Should -Match 'Required CHD'
        $rom.SecondFile | Should -Be 'rom1/disc.chd'
        $rom.SetupExe | Should -BeNullOrEmpty
    }

    It 'lists the base game steps once: under the base game if it is registered, else under the version' {
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        @($notes | Where-Object { $_.Code -eq 'rom1v' }).Count | Should -Be 0
        $variant = $notes | Where-Object { $_.Code -eq 'base2v' }
        $variant.BaseGame | Should -Be 'Base Two'
        $variant.GeneralIssues | Should -Match 'exact set'
    }

    It 'writes the steps, graphics notes and extra file into the report, with the Run line only where there are source notes' {
        $text = New-TpmGameNotesReportText -SetupNotes @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        $text | Should -Match 'Setup steps and known issues:'
        $text | Should -Match 'Second file: rom1/disc.chd'
        $text | Should -Match 'This is a version of: Base Two'
        $text | Should -Match 'Setup steps and known issues \(base game\):'
        $text | Should -Match 'AMD \(works with a fix\): Select AMD Fix in settings.'
        $text | Should -Match 'Intel \(does not work\)\.'
        $text | Should -Match 'Run: gpu.exe'
        $text | Should -Not -Match 'Run: rom1'
    }
}
