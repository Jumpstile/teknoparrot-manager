#Requires -Module Pester
# Controller detection for the Device Survey (issue #410, contract docs/architecture/CONTROLLER_EVIDENCE_CONTRACT.md).
# What a user sees or loses: a clear Xbox pad becomes the default answer, nothing else is ever pre-answered, and a failed or empty
# detection leaves the survey exactly as it was. These tests drive the real functions; Windows device lists are replaced by small fixtures.
# What this CANNOT prove: real arcade hardware names. Only a real Xbox-style pad can be shown to give the High default on a real PC.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Controller evidence bootstrap could not parse the production script.' }
    $wanted = @('Get-TpmControllerEvidence', 'Invoke-DeviceSurvey')
    $functionFile = Join-Path $TestDrive 'controller-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in $wanted }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    $script:schemaPath = Join-Path $PSScriptRoot '..\schemas\TpmControllerEvidence.v1.schema.json'
    function Write-Log { param($msg) }
    function Read-TpmChoice { param($Prompt, $Choices) '1' }
    function Read-TpmYesNo { param($Prompt, $Default = '') 'N' }
    function New-FakeEvidence {
        param([object[]]$Observations = @(), [string]$Status = 'Observed')
        [pscustomobject]@{ EvidenceStatus = $Status; DeviceObservations = @($Observations) }
    }
}

Describe 'Get-TpmControllerEvidence' {
    It 'returns a result that matches the contract schema and carries no identifiers' {
        $result = Get-TpmControllerEvidence
        # The schema check needs PowerShell 7 (Windows PowerShell 5.1 has no Test-Json); every other check below runs in both.
        $testJson = Get-Command Test-Json -ErrorAction SilentlyContinue
        if ($testJson -and $testJson.Parameters.ContainsKey('SchemaFile')) {
            Test-Json -Json ($result | ConvertTo-Json -Depth 6) -SchemaFile $script:schemaPath | Should -BeTrue
        }
        $result.ReadOnly | Should -BeTrue
        $result.SensitiveIdentifiersIncluded | Should -BeFalse
        ($result | ConvertTo-Json -Depth 6) | Should -Not -Match '(?i)serial|VID_|PID_|HID\\\\|MAC'
    }

    It 'never throws and reports SourceUnavailable when Windows device lists fail' {
        Mock Get-CimInstance { throw 'forced failure' }
        $result = Get-TpmControllerEvidence
        $result.ContractVersion | Should -Be 'TpmControllerEvidence/v1'
        @($result.DeviceObservations | Where-Object Basis -ne 'XInputSlotActive').Count | Should -Be 0
    }

    It 'gives name-only evidence Low confidence and never High' {
        Mock Get-CimInstance {
            @([pscustomobject]@{ Name = 'Sinden Lightgun'; DeviceID = 'HID\A' },
              [pscustomobject]@{ Name = 'Generic trackball'; DeviceID = 'HID\B' },
              [pscustomobject]@{ Name = 'HID-compliant game controller'; DeviceID = 'HID\C' })
        }
        $result = Get-TpmControllerEvidence
        $gun = @($result.DeviceObservations | Where-Object DeviceClass -eq 'LightGun')
        $gun.Count | Should -Be 1
        $gun[0].Confidence | Should -Be 'Low'
        $gun[0].Basis | Should -Be 'NameHint'
        @($result.DeviceObservations | Where-Object DeviceClass -eq 'PointerOrTrackball')[0].Confidence | Should -Be 'Low'
        @($result.DeviceObservations | Where-Object DeviceClass -eq 'OtherGamePad')[0].Confidence | Should -Be 'Medium'
        @($result.DeviceObservations | Where-Object { $_.Confidence -eq 'High' -and $_.Basis -ne 'XInputSlotActive' }).Count | Should -Be 0
    }

    It 'recognizes a device from a maker that only builds arcade keyboard encoders, at Medium at most, without keeping the maker code' {
        Mock Get-CimInstance {
            @([pscustomobject]@{ Name = 'HID Keyboard Device'; DeviceID = 'HID\VID_D209&PID_0301&MI_00\7&1' },
              [pscustomobject]@{ Name = 'HID-compliant mouse'; DeviceID = 'HID\VID_D209&PID_0301&MI_01\7&2' },
              [pscustomobject]@{ Name = 'HID-compliant mouse'; DeviceID = 'HID\VID_046D&PID_C52B&MI_01\7&3' })
        }
        $result = Get-TpmControllerEvidence
        $board = @($result.DeviceObservations | Where-Object Basis -eq 'KnownVendor')
        $board.Count | Should -Be 1
        $board[0].DeviceClass | Should -Be 'ArcadeEncoder'
        $board[0].Confidence | Should -Be 'Medium'
        $board[0].Count | Should -Be 1
        Test-Json -Json ($result | ConvertTo-Json -Depth 6) -SchemaFile $script:schemaPath | Should -BeTrue
        ($result | ConvertTo-Json -Depth 6) | Should -Not -Match '(?i)D209|0301|C52B'
    }

    It 'gives the same EvidenceId for the same controllers at a different time' {
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'Wheel base'; DeviceID = 'HID\W' }) }
        $first = Get-TpmControllerEvidence
        Start-Sleep -Milliseconds 20
        $second = Get-TpmControllerEvidence
        $second.ObservationTimeUtc | Should -Not -Be $first.ObservationTimeUtc
        $second.EvidenceId | Should -Be $first.EvidenceId
    }
}

Describe 'Invoke-DeviceSurvey with detection' {
    BeforeEach {
        $script:asked = New-Object System.Collections.Generic.List[object]
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Read-TpmChoice { '1' }
        Mock Read-TpmYesNo { [void]$script:asked.Add([pscustomobject]@{ Prompt = $Prompt; Default = $Default }); 'N' }
    }

    It 'uses a connected Xbox pad as the default answer and leaves every other question unanswered' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'XboxStylePad'; Confidence = 'High'; Basis = 'XInputSlotActive'; Count = 1 }) }
        Invoke-DeviceSurvey
        $xbox = @($script:asked | Where-Object Prompt -match 'Xbox')[0]
        $xbox.Default | Should -Be 'Y'
        @($script:asked | Where-Object { $_.Prompt -notmatch 'Xbox' -and $_.Default -ne '' }).Count | Should -Be 0
    }

    It 'only says "may be connected" for a Low or Medium match and never pre-answers it' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'LightGun'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 }) }
        Invoke-DeviceSurvey
        $gun = @($script:asked | Where-Object Prompt -match 'Lightgun')[0]
        $gun.Default | Should -Be ''
        $gun.Prompt | Should -Match 'may be connected'
    }

    It 'asks exactly as before when detection found nothing or failed' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Status 'SourceUnavailable' }
        Invoke-DeviceSurvey
        $script:asked.Count | Should -Be 7
        @($script:asked | Where-Object { $_.Default -ne '' -or $_.Prompt -match 'connected' }).Count | Should -Be 0
    }

    It 'lets the user answer N even when a pad was detected' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'XboxStylePad'; Confidence = 'High'; Basis = 'XInputSlotActive'; Count = 1 }) }
        { Invoke-DeviceSurvey } | Should -Not -Throw
        Should -Invoke Read-TpmYesNo -Times 8 -Exactly
    }

    It 'asks one question and skips the other six when the user accepts the detected pad' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'XboxStylePad'; Confidence = 'High'; Basis = 'XInputSlotActive'; Count = 1 }) }
        Mock Read-TpmYesNo { [void]$script:asked.Add([pscustomobject]@{ Prompt = $Prompt; Default = $Default }); 'Y' }
        Invoke-DeviceSurvey
        $script:asked.Count | Should -Be 1
    }

    It 'never offers the shortcut for Low-confidence name hints' {
        Mock Get-TpmControllerEvidence { New-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'Wheel'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 }) }
        Invoke-DeviceSurvey
        $script:asked.Count | Should -Be 7
    }
}
