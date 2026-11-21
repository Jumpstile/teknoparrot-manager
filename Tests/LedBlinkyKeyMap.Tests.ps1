#Requires -Module Pester
# Arcade key map read from LEDBlinky (controller work, issues #201 and #303).
# What a user sees or loses: when LEDBlinky is installed, TeknoParrot Manager can learn which key each arcade button sends without
# asking. It only reads. It never changes LEDBlinky's files, and a missing or broken file simply means the player is asked instead.
# What this CANNOT prove: that the buttons on a real cabinet really send these keys today. Only pressing them can show that.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LEDBlinky key map bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'ledblinky-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-TpmLedBlinkyKeyMap' }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function New-MapFolder {
        param([string]$Xml)
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        if ($Xml) { Set-Content -LiteralPath (Join-Path $folder 'LEDBlinkyInputMap.xml') -Value $Xml -Encoding utf8 }
        return $folder
    }
    $script:goodXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<dat>
  <ledController type="1" id="1" name="LEDWiz">
    <port number="1" label="P1B1" type="B" inputCodes="KEYCODE_X"/>
    <port number="2" label="P1B1" type="R" inputCodes="KEYCODE_X"/>
    <port number="3" label="P1START" type="B" inputCodes="KEYCODE_1|JOYCODE_1_BUTTON9"/>
    <port number="4" label="" type="" inputCodes=""/>
  </ledController>
  <ledController type="1" id="2" name="LEDWiz">
    <port number="1" label="P2B1" type="B" inputCodes="KEYCODE_A"/>
  </ledController>
</dat>
'@
}

Describe 'Get-TpmLedBlinkyKeyMap' {
    It 'reads each control once, with every key it can send, and skips empty ports' {
        $folder = New-MapFolder -Xml $script:goodXml
        $map = Get-TpmLedBlinkyKeyMap -Root @($folder)
        $map.Found | Should -BeTrue
        $map.Reason | Should -BeExactly 'Read'
        @($map.Controls | ForEach-Object Control) | Should -Be @('P1B1', 'P1START', 'P2B1')
        @(($map.Controls | Where-Object Control -eq 'P1B1').InputCodes) | Should -Be @('KEYCODE_X')
        @(($map.Controls | Where-Object Control -eq 'P1START').InputCodes) | Should -Be @('KEYCODE_1', 'JOYCODE_1_BUTTON9')
        $map.MapSHA256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'does not change the file it reads' {
        $folder = New-MapFolder -Xml $script:goodXml
        $path = Join-Path $folder 'LEDBlinkyInputMap.xml'
        $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        [void](Get-TpmLedBlinkyKeyMap -Root @($folder))
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -BeExactly $before
    }

    It 'reports not installed when there is no map' {
        # The product also looks in the default LEDBlinky folder; hide that real folder so a PC with LEDBlinky installed gives the same answer.
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\LEDBlinky\LEDBlinkyInputMap.xml' }
        $map = Get-TpmLedBlinkyKeyMap -Root @((New-MapFolder))
        $map.Found | Should -BeFalse
        $map.Controls.Count | Should -Be 0
    }

    It 'reports an unreadable map instead of failing' {
        $map = Get-TpmLedBlinkyKeyMap -Root @((New-MapFolder -Xml '<dat><ledController><port label="P1B1"'))
        $map.Found | Should -BeFalse
        $map.Reason | Should -BeExactly 'MapUnreadable'
    }

    It 'refuses a map that carries a document type definition' {
        $evil = '<?xml version="1.0"?><!DOCTYPE dat [<!ENTITY x "boom">]><dat><ledController><port label="P1B1" inputCodes="&x;"/></ledController></dat>'
        $map = Get-TpmLedBlinkyKeyMap -Root @((New-MapFolder -Xml $evil))
        $map.Found | Should -BeFalse
        $map.Reason | Should -BeExactly 'MapUnreadable'
    }

    It 'reports an empty map when no port has a control' {
        $map = Get-TpmLedBlinkyKeyMap -Root @((New-MapFolder -Xml '<dat><ledController><port number="1" label="" inputCodes=""/></ledController></dat>'))
        $map.Found | Should -BeFalse
        $map.Reason | Should -BeExactly 'MapEmpty'
    }
}
