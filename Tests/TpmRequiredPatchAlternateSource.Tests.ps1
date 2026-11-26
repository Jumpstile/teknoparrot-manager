#Requires -Module Pester

# A required patch whose file is also inside the game's own ZIP accepts that ZIP too, with the same exact size and SHA-256 checks.
# Synthetic ZIPs in TestDrive only; the engine is dot-sourced like the other TpmRequiredPatch tests.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for alternate-source tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup','Test-TpmPathLengthAllowed')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    # Fixed framework assembly names are required by Windows PowerShell 5.1.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # The folder question: the test answers it with the folder chosen in BeforeEach.
    function Read-PathWithBrowse { param($Prompt, $Mode, $InitialDirectory) return $script:PickedFolder }

    $script:GoodBytes = [Text.Encoding]::ASCII.GetBytes('good apm bytes 0123456789')
    $script:BadBytes = [Text.Encoding]::ASCII.GetBytes('evil apm bytes 0123456789')
    $script:GoodSha256 = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($script:GoodBytes)).Replace('-', '')

    function New-AlternateZip {
        param([string]$Folder, [string]$Name, [string]$Member, [byte[]]$Bytes)
        $zip = [IO.Compression.ZipFile]::Open((Join-Path $Folder $Name), [IO.Compression.ZipArchiveMode]::Create)
        try {
            $item = $zip.CreateEntry($Member)
            $stream = $item.Open()
            try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
        } finally { $zip.Dispose() }
    }
    function New-AlternateEntry {
        param([switch]$NoAlternate)
        $operation = [pscustomobject]@{ Type='CreateFile'; Target='apm.dll'; BeforeState='Absent'; AfterSha256=$script:GoodSha256; Payload='payload/apm.dll'; PayloadSha256=$script:GoodSha256 }
        $entry = [pscustomobject]@{
            Id='alt.apm'; ProfileId='AltGame'; SourceRole='UserSelected'
            SourceSet='Alt Game (1.00.00) - APM3 Component.zip'; SourceEntry='apm.dll'
            SourceSize=[int64]$script:GoodBytes.Length; SourceSha1=('2' * 40); SourceSha256=$script:GoodSha256; Operations=@($operation)
        }
        if (-not $NoAlternate) {
            $entry | Add-Member -NotePropertyName AlternateSources -NotePropertyValue @([pscustomobject]@{ SourceSet='Alt Game (1.00.00)(2020)(JPN)[TP].zip'; SourceEntry='game/apm.dll' })
        }
        return $entry
    }
}

Describe 'A required patch that the game''s own ZIP can supply' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('src-' + [guid]::NewGuid().ToString('N'))
        $temp = Join-Path $TestDrive ('tmp-' + [guid]::NewGuid().ToString('N'))
        foreach ($directory in @($script:Folder, $temp)) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $TestDrive; Temp = $temp }
        $script:PickedFolder = $script:Folder
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'is satisfied by the game ZIP that holds the exact file' {
        New-AlternateZip $script:Folder 'Alt Game (1.00.00)(2020)(JPN)[TP].zip' 'game/apm.dll' $script:GoodBytes
        $entry = New-AlternateEntry
        $root = Resolve-TpmRequiredPatchSourceRoot -Entry $entry
        $root | Should -BeExactly $script:Folder
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $root
        $stage.Sha256 | Should -BeExactly $script:GoodSha256
        $stage.SourceEntry | Should -BeExactly 'game/apm.dll'
        (Split-Path -Leaf $stage.SourceArchive) | Should -BeExactly 'Alt Game (1.00.00)(2020)(JPN)[TP].zip'
    }

    It 'refuses the game ZIP when the file inside has other bytes' {
        New-AlternateZip $script:Folder 'Alt Game (1.00.00)(2020)(JPN)[TP].zip' 'game/apm.dll' $script:BadBytes
        $entry = New-AlternateEntry
        { New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:Folder } | Should -Throw '*does not match the payload and target SHA-256 pins*'
    }

    It 'still works with the old separate ZIP name' {
        New-AlternateZip $script:Folder 'Alt Game (1.00.00) - APM3 Component.zip' 'apm.dll' $script:GoodBytes
        $entry = New-AlternateEntry
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot (Resolve-TpmRequiredPatchSourceRoot -Entry $entry)
        $stage.Sha256 | Should -BeExactly $script:GoodSha256
        $stage.SourceEntry | Should -BeExactly 'apm.dll'
    }

    It 'names both files, and that nothing is downloaded, when neither ZIP is there' {
        $entry = New-AlternateEntry
        $failure = $null
        try { [void](Resolve-TpmRequiredPatchSourceRoot -Entry $entry) } catch { $failure = $_.Exception.Message }
        $failure | Should -Not -BeNullOrEmpty
        $plain = Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure
        $plain.Contains('"Alt Game (1.00.00) - APM3 Component.zip" or "Alt Game (1.00.00)(2020)(JPN)[TP].zip"') | Should -BeTrue
        $plain | Should -BeLike '*does not download it*'
        $plain | Should -Not -BeLike '*separate download that TeknoParrot Manager does not provide*'
    }

    It 'says a lone patch ZIP is a separate download when no alternate exists' {
        $entry = New-AlternateEntry -NoAlternate
        $failure = $null
        try { [void](Resolve-TpmRequiredPatchSourceRoot -Entry $entry) } catch { $failure = $_.Exception.Message }
        $plain = Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure
        $plain | Should -BeLike '*"Alt Game (1.00.00) - APM3 Component.zip"*'
        $plain | Should -BeLike '*separate download that TeknoParrot Manager does not provide*'
    }
}

Describe 'The bundled APM3 recipes' {
    BeforeAll {
        $catalog = Read-TpmRequiredPatchCatalog -ProgramRoot (Join-Path $PSScriptRoot '..')
        $script:Apm3 = @($catalog.Entries | Where-Object { $_.SourceSet -like '*- APM3 Component.zip' })
        $script:Strive = @($catalog.Entries | Where-Object { $_.SourceSet -like '*- APM3 File.zip' })
    }
    It 'also accept the game''s own ZIP, named like the game build, holding the same file' {
        $script:Apm3.Count | Should -Be 25
        foreach ($entry in $script:Apm3) {
            $alternate = @($entry.AlternateSources)
            $alternate.Count | Should -Be 1
            $alternate[0].SourceSet | Should -BeExactly ($entry.BuildName + '.zip')
            $expected = if ($entry.BuildName -like 'Goonya Fighter*') { 'game/' + $entry.SourceEntry } else { $entry.SourceEntry }
            $alternate[0].SourceEntry | Should -BeExactly $expected
        }
    }
    It 'leave the Guilty Gear APM3 File patches without an alternate' {
        $script:Strive.Count | Should -Be 2
        foreach ($entry in $script:Strive) { $entry.PSObject.Properties['AlternateSources'] | Should -BeNullOrEmpty }
    }
}
