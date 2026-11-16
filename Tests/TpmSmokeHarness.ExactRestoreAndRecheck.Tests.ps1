#Requires -Module Pester

# Maintainer smoke harness. (1) After a normal run the saved settings file must be back byte for
# byte (a file with a BOM, or one that is not UTF-8, must not come back changed). (2) The
# blanked UserProfiles copy is read back from disk and is deleted if a saved password is still
# in it, even when the blanking step said it worked.
BeforeAll {
    $harnessPath = Join-Path $PSScriptRoot '..\scripts\Invoke-TPM-RealInstanceSmoke.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the smoke harness.' }
    $wanted = @(
        'Copy-IfExists', 'Copy-TPMXmlWithoutPass', 'Write-TPMBytesAtomic', 'Write-TPMTextAtomic', 'Get-TPMConfigJsonWithRootText',
        'Get-TPMTemporaryUnattendedConfigText', 'Get-TPMConfigJsonSnapshot', 'Set-TPMConfigJsonRoot', 'New-TPMTemporaryUnattendedConfig',
        'Restore-TPMConfigJsonSnapshot', 'Test-TPMConfigRestored', 'Get-TPMConfigRestoreRecordPath', 'Get-TPMBytesSha256',
        'Write-TPMConfigRestoreRecord', 'Remove-TPMConfigRestoreRecord', 'Restore-TPMInterruptedConfigOverride',
        'Invoke-TPMUnattendedRootBinding', 'Get-TPMEffectiveRootFromUnattendedLog', 'Test-TPMUnattendedRootMatch'
    )
    $found = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    if ($found.Count -ne $wanted.Count) { throw ('Expected {0} harness functions, found {1}.' -f $wanted.Count, $found.Count) }
    $functionFile = Join-Path $TestDrive 'harness-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (($found | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
}

Describe 'The settings file comes back byte for byte after a normal smoke run' {
    It 'restores a <Label> settings file exactly' -TestCases @(
        @{ Label = 'UTF-8 with BOM and Windows line endings'; Bytes = ([byte[]]@(0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes("{`r`n  `"TeknoParrotRoot`": `"C:\\Saved`",`r`n  `"Theme`": `"dark`"`r`n}`r`n")) }
        @{ Label = 'single-byte (non UTF-8) text'; Bytes = [Text.Encoding]::GetEncoding(28591).GetBytes("{`"TeknoParrotRoot`": `"C:\\Saved`", `"Note`": `"caf$([char]0xE9)`"}") }
        @{ Label = 'UTF-8 without BOM and no final line ending'; Bytes = [Text.Encoding]::UTF8.GetBytes('{"TeknoParrotRoot": "C:\\Saved", "Theme": "dark"}') }
    ) {
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($folder)
        $path = Join-Path $folder 'TeknoParrot-Manager.config.json'
        [IO.File]::WriteAllBytes($path, $Bytes)
        $log = Join-Path $folder 'unattended.log'

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $path -TeknoParrotRoot 'X:\Requested' -LogPath $log -InvokeUnattended {
            [IO.File]::WriteAllText($log, "Configuration:`r`n  TeknoParrot root     : X:\Requested`r`n", (New-Object Text.UTF8Encoding $false))
        }

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly ([Convert]::ToBase64String($Bytes))
        $binding.VerificationSucceeded | Should -BeTrue
        @($binding.Checks | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }).Passed | Should -BeTrue
        Test-Path -LiteralPath (Get-TPMConfigRestoreRecordPath -ConfigPath $path) | Should -BeFalse
    }
}

Describe 'The blanked UserProfiles copy is read back' {
    It 'deletes the copy when a saved password is still in it, even though the blanking step reported success' {
        Mock Write-Host {}
        Mock Copy-TPMXmlWithoutPass { [System.IO.File]::Copy($Source, $Destination, $true); 1 }
        $profiles = Join-Path $TestDrive 'profiles'
        [void][IO.Directory]::CreateDirectory($profiles)
        [IO.File]::WriteAllText((Join-Path $profiles 'G.xml'), '<GameProfile><FieldInformation><FieldName>Pass</FieldName><FieldValue>secret-value</FieldValue></FieldInformation></GameProfile>')
        $script:backupDir = Join-Path $TestDrive 'backups'
        [void][IO.Directory]::CreateDirectory($script:backupDir)

        (Copy-IfExists $profiles 'UserProfiles') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:backupDir 'UserProfiles') | Should -BeFalse
    }
}
