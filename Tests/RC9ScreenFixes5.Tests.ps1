#Requires -Module Pester

# RC9 screen fixes, batch 5.
#   13  The graphics card scan reads only the profile fields that can matter, and still finds every GPU and FFB field.
#   15  The keep/change question for the controller layout has a Back choice that saves nothing.
#   17  Force feedback ends with what was set and the next step, with the technical detail under Details.
# Only the function definitions are loaded. Nothing real is read or written.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'test.log'
    Mock Write-Log {}
    Mock Write-Host {}
    Mock Write-TpmCompactExtractionProgress {}
}

Describe 'Graphics card scan keeps finding every GPU and FFB field (fix 13)' {
    BeforeAll {
        $profiles = Join-Path $TestDrive 'GpuScan\GameProfiles'
        [void][IO.Directory]::CreateDirectory($profiles)
        function New-Field([string]$Category, [string]$Name, [string]$Type, [string[]]$Options = @()) {
            $opts = if ($Options.Count -gt 0) { '<FieldOptions>' + (($Options | ForEach-Object { "<string>$_</string>" }) -join '') + '</FieldOptions>' } else { '' }
            "<FieldInformation><CategoryName>$Category</CategoryName><FieldName>$Name</FieldName><FieldType>$Type</FieldType><FieldValue>0</FieldValue>$opts</FieldInformation>"
        }
        $fields = @(
            (New-Field 'General' 'Use AMD Fix' 'Bool'),
            (New-Field 'General' 'RADEON Workaround' 'Bool'),
            (New-Field 'General' 'Plain Option' 'Bool'),
            (New-Field 'General' 'AMD Level' 'Numeric'),
            (New-Field 'Video' 'Graphics Vendor' 'Dropdown' @('Auto', '  NVIDIA ')),
            (New-Field 'Video' 'Driver Mode' 'Dropdown' @('new amd driver', 'Old')),
            (New-Field 'Video' 'Quality' 'Dropdown' @('Low', 'High')),
            (New-Field 'FFB Blaster' 'Enable' 'Bool'),
            (New-Field 'Controls' 'blaster ffb' 'Bool')
        )
        Set-Content -LiteralPath (Join-Path $profiles 'Alpha.xml') -Value ('<GameProfile><ConfigValues>' + ($fields -join '') + '</ConfigValues></GameProfile>')
        Set-Content -LiteralPath (Join-Path $profiles 'Beta.xml') -Value '<GameProfile />'
        $script:GpuScanRoot = Split-Path -Parent $profiles
    }

    It 'finds the GPU fields, and only them, in a profile' {
        # Mutation: narrow the scan too far (or not at all for the wrong field type) -> a GPU field is missed or a plain field is added.
        $gpu = Get-GpuFixFieldNames -TpRoot $script:GpuScanRoot
        @($gpu.BoolFields) | Should -Contain 'Use AMD Fix'
        @($gpu.BoolFields) | Should -Contain 'RADEON Workaround'
        @($gpu.BoolFields) | Should -Not -Contain 'Plain Option'
        @($gpu.BoolFields) | Should -Not -Contain 'AMD Level'
        @($gpu.DropdownFields) | Should -Contain 'Graphics Vendor'
        @($gpu.DropdownFields) | Should -Contain 'Driver Mode'
        @($gpu.DropdownFields) | Should -Not -Contain 'Quality'
    }

    It 'finds the same GPU fields plus the FFB fields in the combined scan' {
        $both = Get-GpuAndFfbFieldNames -TpRoot $script:GpuScanRoot
        @($both.Gpu.BoolFields) | Should -Contain 'Use AMD Fix'
        @($both.Gpu.DropdownFields) | Should -Contain 'Graphics Vendor'
        @($both.Gpu.DropdownFields) | Should -Not -Contain 'Quality'
        @($both.Ffb) | Should -Contain 'FFB Blaster'
        @($both.Ffb) | Should -Contain 'blaster ffb'
        @($both.Ffb) | Should -Not -Contain 'Enable'
    }
}

Describe 'Controller layout keep/change question has a Back choice (fix 15)' {
    BeforeEach {
        $script:KcAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:KcPrompts = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText {}
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ DeviceObservations = @() } }
        Mock Save-TpmBaseline {}
        Mock Read-TpmChoice {
            [void]$script:KcPrompts.Add([string]$Prompt)
            if ($script:KcAnswers.Count -eq 0) { throw 'UNEXPECTED PROMPT' }
            return $script:KcAnswers.Dequeue()
        }
    }

    It 'goes back to the layout list without saving anything' {
        # Mutation: leave Back out, or save on Back -> the third prompt is never reached, or a layout is saved the user walked away from.
        foreach ($answer in @('1', 'B', 'B')) { $script:KcAnswers.Enqueue($answer) }
        $result = Invoke-TpmBaselineChooseScreen -StateDir (Join-Path $TestDrive 'state')
        $result | Should -BeNullOrEmpty
        Should -Invoke Read-TpmChoice -Times 3 -Exactly
        $script:KcPrompts[1] | Should -Match 'B to go back'
        Should -Invoke Save-TpmBaseline -Times 0 -Exactly
    }

    It 'still saves the layout when the user keeps it' {
        foreach ($answer in @('1', 'K')) { $script:KcAnswers.Enqueue($answer) }
        $result = Invoke-TpmBaselineChooseScreen -StateDir (Join-Path $TestDrive 'state')
        $result | Should -Not -BeNullOrEmpty
        Should -Invoke Save-TpmBaseline -Times 1 -Exactly
    }
}

Describe 'Force feedback ending says what was set and the next step (fix 17)' {
    It 'names what was turned on and keeps the game names under Details' {
        # Mutation: go back to a bare "Done." or print the game names in the short view -> no counts, or technical detail on the main screen.
        $native = [pscustomobject]@{ Outcome = 'SUCCEEDED'; Mutation = [pscustomobject]@{ CompletedItems = @('GameA', 'GameB') }; Backup = [pscustomobject]@{ RootPath = 'C:\Safety\copy' } }
        $plugin = [pscustomobject]@{ Deployed = 3; NoOp = $false; SourceRevision = 'abc123'; EvidencePath = 'C:\Reports\ffb.json' }
        $view = Get-TpmFfbSetupEndingView -NativeResult $native -Plugin $plugin -PluginChosen $true
        $view.Title | Should -Be 'Force feedback setup is finished.'
        $view.Done | Should -Contain 'FFB Blaster is on for 2 games.'
        $view.Done | Should -Contain 'The free FFB plugin was added for 3 games.'
        $view.Next | Should -Match '^Start a game'
        ($view.Done -join ' ') | Should -Not -Match 'GameA'
        $detail = ($view.DetailBlocks | ForEach-Object { $_.Heading; $_.Lines }) -join ' '
        $detail | Should -Match 'GameA and GameB'
        $detail | Should -Match 'C:\\Safety\\copy'
        $detail | Should -Match 'abc123'
    }

    It 'says plainly when nothing needed a change and the plugin was skipped' {
        $native = [pscustomobject]@{ Outcome = 'NO_OP'; Mutation = $null }
        $view = Get-TpmFfbSetupEndingView -NativeResult $native -Plugin $null -PluginChosen $false
        $view.Done | Should -Contain 'FFB Blaster: no game needed a change.'
        $view.Done | Should -Contain 'The free FFB plugin was skipped.'
        $view.Next | Should -Match 'Run Force feedback again'
        @($view.DetailBlocks).Count | Should -Be 0
    }
}
