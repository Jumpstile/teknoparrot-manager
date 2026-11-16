param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$FragmentPath = (Join-Path $RepositoryRoot 'tools/required-patches/fragments/native-main-component-restorations-20261015.json')
)

BeforeAll {
    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) { throw 'RepositoryRoot is unavailable.' }
    if (-not (Test-Path -LiteralPath $FragmentPath -PathType Leaf)) { throw 'The Main-component fragment is unavailable.' }
$script:mainFixtureGlobalNames=@('TpmRequiredPatchCatalogSha256','TpmOwnedLayout','gamesInstallFolder','requiredPatchInputQueue','requiredPatchHostMessages','requiredPatchBrowsePrompts','requiredPatchFixture')
$script:mainHarnessGlobalNames=@('mainFragmentText','mainFragmentHash','mainDelta','expectedRows','requiredPatchFixtureSetup')
$script:mainOriginalGlobalValues=@{}
foreach($name in @($script:mainFixtureGlobalNames+$script:mainHarnessGlobalNames)){
    $variable=Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
    if($null -eq $variable){$script:mainOriginalGlobalValues[$name]=[pscustomobject]@{Exists=$false;Value=$null}}
    else{$script:mainOriginalGlobalValues[$name]=[pscustomobject]@{Exists=$true;Value=$variable.Value}}
}
function Restore-NativeMainVariables {
    param([Parameter(Mandatory)][string[]]$Names)
    foreach($name in $Names){
        $saved=$script:mainOriginalGlobalValues[$name]
        if($saved.Exists){Set-Variable -Name $name -Scope Script -Value $saved.Value -Force}
        else{Remove-Variable -Name $name -Scope Script -Force -ErrorAction SilentlyContinue}
    }
}


    . (Join-Path $RepositoryRoot 'scripts\TpmRequiredPatchEngine.ps1')

    $script:mainFragmentText=[IO.File]::ReadAllText($FragmentPath,[Text.Encoding]::UTF8)
    $script:mainFragmentHash=(Get-FileHash -LiteralPath $FragmentPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $script:mainDelta=$script:mainFragmentText|ConvertFrom-Json -ErrorAction Stop
    $script:expectedRows=@'
[
  {
    "Id": "hummer-main-component-data-global-nnstdshader-nnstdshader-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/nnstdshader/nnstdshader.frag",
    "SourceSize": 76546,
    "SourceSha1": "CAA795B3A7B3D0C8151B775A00E115B240752836",
    "SourceSha256": "5005FA3730D012BF7F189587440CE9A0AEC8D7636CD368293F1F89690DE81026",
    "Target": "data-global/nnstdshader/nnstdshader.frag"
  },
  {
    "Id": "hummer-main-component-data-global-nnstdshader-nnstdshader-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/nnstdshader/nnstdshader.vert",
    "SourceSize": 68868,
    "SourceSha1": "41FE2ABACE4F64087190662670F473FD7750B998",
    "SourceSha256": "67C559C4DF7BC440DD8A0B7C7EF1C27E1FC120CB77A320321B787B6779C5EB34",
    "Target": "data-global/nnstdshader/nnstdshader.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2.frag",
    "SourceSize": 1097,
    "SourceSha1": "D5978F2E8AF50F7D5E1264F43575E951B89841A1",
    "SourceSha256": "B6FA51C6E0A8178788F437B656FC13E99ABBDA6BC40A248D6A9EE49825C860AC",
    "Target": "data-global/shader/gauss2.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2.vert",
    "SourceSize": 1235,
    "SourceSha1": "C19BEE0483EE6962CE8A5238DAA0A5F399EE277C",
    "SourceSha256": "1445CD238A4B88FCAFF29577C023DDF1C500E6BA2C93FF6127589B4B60448F8D",
    "Target": "data-global/shader/gauss2.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-a-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a.frag",
    "SourceSize": 1121,
    "SourceSha1": "E8F79812530110620E6DEBDFAA9441F4296389C6",
    "SourceSha256": "AAF803083A9021999F562DDA974CAD866EEE854FDD9102E6216F1AE6B1E9710D",
    "Target": "data-global/shader/gauss2_a.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-a-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a.vert",
    "SourceSize": 1151,
    "SourceSha1": "6D90A4845526AC8B73F75799AB933DD093B900B0",
    "SourceSha256": "3C3C08D76B22B91F2F47EFC717E016661339F79C1EEBD7FA7877C1D0573051EE",
    "Target": "data-global/shader/gauss2_a.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-a-to-c-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a_to_c.frag",
    "SourceSize": 1159,
    "SourceSha1": "49D77896E2EE04216FC3D7A5BF409EC7253AFE05",
    "SourceSha256": "5A77D4151F36F211AFEB2F5D4B2ADA8AD2376DC4DFBCDBDB9B82229DA2BCE9B6",
    "Target": "data-global/shader/gauss2_a_to_c.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss2-a-to-c-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a_to_c.vert",
    "SourceSize": 1156,
    "SourceSha1": "A418842B64B6E95ECF3682A8F4568A5CE84E77F1",
    "SourceSha256": "1DD4937A13FDBCF0E7EE188899189CB8062DB6A174773558E7C90D18CBCEBD24",
    "Target": "data-global/shader/gauss2_a_to_c.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss-x-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_x.frag",
    "SourceSize": 4326,
    "SourceSha1": "7EA808C1DB5133B1A831FCE29DE0E8525AB15D0F",
    "SourceSha256": "B3108DC28ED124032BF0445FF56A5DBC0992E814B2608E624C53ECE78D49D4BB",
    "Target": "data-global/shader/gauss_x.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss-x-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_x.vert",
    "SourceSize": 2765,
    "SourceSha1": "9E8DFB8A43494C6534BFCD840E795C1E5417F5BF",
    "SourceSha256": "E41DCE579CC7FFB9455541D4328403445A304E597011E17FB45A46709DDF30FF",
    "Target": "data-global/shader/gauss_x.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss-y-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_y.frag",
    "SourceSize": 4316,
    "SourceSha1": "0193D2821AEEEDDAE4BDAFEA8B73021F49804A6B",
    "SourceSha256": "0A5789C6E8834A36DDAEBB7595BA50B96C8CEECDDAB0BD488A592867B51C24AF",
    "Target": "data-global/shader/gauss_y.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-gauss-y-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_y.vert",
    "SourceSize": 2748,
    "SourceSha1": "42C0517078ACD90835B9ADFD2951BDD7D5B90820",
    "SourceSha256": "D5EF31EB08CEF024DC485C2D1D835C257C0F824379041BE1938EEA7884BC73B3",
    "Target": "data-global/shader/gauss_y.vert"
  },
  {
    "Id": "hummer-main-component-data-global-shader-hdr-frag",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/hdr.frag",
    "SourceSize": 2312,
    "SourceSha1": "29EC3DF4497F17E369591A17A5BF2E5936613A2B",
    "SourceSha256": "79F7C4C5A624D6596EF2BD2012A8F7EC1421F4FBA107A855CD3FB4A6C3CBEBE9",
    "Target": "data-global/shader/hdr.frag"
  },
  {
    "Id": "hummer-main-component-data-global-shader-hdr-vert",
    "ProfileId": "Hummer",
    "BuildName": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP]",
    "Executable": "a.elf",
    "ExecutableSha256": "D8552148793AB3DAC7E24DE802D9B408FEC0C87CA44FBC435B3F4160D9456412",
    "SourceSet": "Hummer (1.0)(2009-06-21)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/hdr.vert",
    "SourceSize": 668,
    "SourceSha1": "F7AB41A70D16D3746067DF6F2C38EFEDCBF95E9D",
    "SourceSha256": "767D9E2EE29A7642DE3904FD5400A52DDAC13299F8721BCEFB6E602F0DB37E3E",
    "Target": "data-global/shader/hdr.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-nnstdshader-nnstdshader-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/nnstdshader/nnstdshader.frag",
    "SourceSize": 76546,
    "SourceSha1": "CAA795B3A7B3D0C8151B775A00E115B240752836",
    "SourceSha256": "5005FA3730D012BF7F189587440CE9A0AEC8D7636CD368293F1F89690DE81026",
    "Target": "data-global/nnstdshader/nnstdshader.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-nnstdshader-nnstdshader-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/nnstdshader/nnstdshader.vert",
    "SourceSize": 68868,
    "SourceSha1": "41FE2ABACE4F64087190662670F473FD7750B998",
    "SourceSha256": "67C559C4DF7BC440DD8A0B7C7EF1C27E1FC120CB77A320321B787B6779C5EB34",
    "Target": "data-global/nnstdshader/nnstdshader.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2.frag",
    "SourceSize": 1097,
    "SourceSha1": "D5978F2E8AF50F7D5E1264F43575E951B89841A1",
    "SourceSha256": "B6FA51C6E0A8178788F437B656FC13E99ABBDA6BC40A248D6A9EE49825C860AC",
    "Target": "data-global/shader/gauss2.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2.vert",
    "SourceSize": 1235,
    "SourceSha1": "C19BEE0483EE6962CE8A5238DAA0A5F399EE277C",
    "SourceSha256": "1445CD238A4B88FCAFF29577C023DDF1C500E6BA2C93FF6127589B4B60448F8D",
    "Target": "data-global/shader/gauss2.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-a-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a.frag",
    "SourceSize": 1121,
    "SourceSha1": "E8F79812530110620E6DEBDFAA9441F4296389C6",
    "SourceSha256": "AAF803083A9021999F562DDA974CAD866EEE854FDD9102E6216F1AE6B1E9710D",
    "Target": "data-global/shader/gauss2_a.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-a-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a.vert",
    "SourceSize": 1151,
    "SourceSha1": "6D90A4845526AC8B73F75799AB933DD093B900B0",
    "SourceSha256": "3C3C08D76B22B91F2F47EFC717E016661339F79C1EEBD7FA7877C1D0573051EE",
    "Target": "data-global/shader/gauss2_a.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-a-to-c-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a_to_c.frag",
    "SourceSize": 1159,
    "SourceSha1": "49D77896E2EE04216FC3D7A5BF409EC7253AFE05",
    "SourceSha256": "5A77D4151F36F211AFEB2F5D4B2ADA8AD2376DC4DFBCDBDB9B82229DA2BCE9B6",
    "Target": "data-global/shader/gauss2_a_to_c.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss2-a-to-c-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss2_a_to_c.vert",
    "SourceSize": 1156,
    "SourceSha1": "A418842B64B6E95ECF3682A8F4568A5CE84E77F1",
    "SourceSha256": "1DD4937A13FDBCF0E7EE188899189CB8062DB6A174773558E7C90D18CBCEBD24",
    "Target": "data-global/shader/gauss2_a_to_c.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss-x-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_x.frag",
    "SourceSize": 4326,
    "SourceSha1": "7EA808C1DB5133B1A831FCE29DE0E8525AB15D0F",
    "SourceSha256": "B3108DC28ED124032BF0445FF56A5DBC0992E814B2608E624C53ECE78D49D4BB",
    "Target": "data-global/shader/gauss_x.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss-x-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_x.vert",
    "SourceSize": 2765,
    "SourceSha1": "9E8DFB8A43494C6534BFCD840E795C1E5417F5BF",
    "SourceSha256": "E41DCE579CC7FFB9455541D4328403445A304E597011E17FB45A46709DDF30FF",
    "Target": "data-global/shader/gauss_x.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss-y-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_y.frag",
    "SourceSize": 4316,
    "SourceSha1": "0193D2821AEEEDDAE4BDAFEA8B73021F49804A6B",
    "SourceSha256": "0A5789C6E8834A36DDAEBB7595BA50B96C8CEECDDAB0BD488A592867B51C24AF",
    "Target": "data-global/shader/gauss_y.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-gauss-y-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/gauss_y.vert",
    "SourceSize": 2748,
    "SourceSha1": "42C0517078ACD90835B9ADFD2951BDD7D5B90820",
    "SourceSha256": "D5EF31EB08CEF024DC485C2D1D835C257C0F824379041BE1938EEA7884BC73B3",
    "Target": "data-global/shader/gauss_y.vert"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-hdr-frag",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/hdr.frag",
    "SourceSize": 2312,
    "SourceSha1": "29EC3DF4497F17E369591A17A5BF2E5936613A2B",
    "SourceSha256": "79F7C4C5A624D6596EF2BD2012A8F7EC1421F4FBA107A855CD3FB4A6C3CBEBE9",
    "Target": "data-global/shader/hdr.frag"
  },
  {
    "Id": "hummerextreme-main-component-data-global-shader-hdr-vert",
    "ProfileId": "hummerextreme",
    "BuildName": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]",
    "Executable": "hummer_Master.elf",
    "ExecutableSha256": "7DC6575D94334267020AF90E5D383D2BBE67D5D8DD09DA630F2F3D8B305141D4",
    "SourceSet": "Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP].zip",
    "SourceEntry": "data-global/shader/hdr.vert",
    "SourceSize": 668,
    "SourceSha1": "F7AB41A70D16D3746067DF6F2C38EFEDCBF95E9D",
    "SourceSha256": "767D9E2EE29A7642DE3904FD5400A52DDAC13299F8721BCEFB6E602F0DB37E3E",
    "Target": "data-global/shader/hdr.vert"
  },
  {
    "Id": "primevil-main-component-disk0-data-nnstdshader-nnstdshader-frag",
    "ProfileId": "Primevil",
    "BuildName": "Primeval Hunt (1.0)(2008)[Sega Lindbergh Red][TP]",
    "Executable": "disk0/prog/main.exe",
    "ExecutableSha256": "20500ABE11892EA47BB111A667BA0F617CBFF21BD45702D8347B5F4AEEDB7224",
    "SourceSet": "Primeval Hunt (1.0)(2008)[Sega Lindbergh Red][TP].zip",
    "SourceEntry": "disk0/data/nnstdshader/nnstdshader.frag",
    "SourceSize": 53935,
    "SourceSha1": "7939A11608ABC1A0E6F8FC1876D81E727868EC76",
    "SourceSha256": "2CB5473563E0D74CFED694B712CD9D4A367303DA0A56F187F9979517F2DE3C80",
    "Target": "disk0/data/nnstdshader/nnstdshader.frag"
  },
  {
    "Id": "primevil-main-component-disk0-data-nnstdshader-nnstdshader-vert",
    "ProfileId": "Primevil",
    "BuildName": "Primeval Hunt (1.0)(2008)[Sega Lindbergh Red][TP]",
    "Executable": "disk0/prog/main.exe",
    "ExecutableSha256": "20500ABE11892EA47BB111A667BA0F617CBFF21BD45702D8347B5F4AEEDB7224",
    "SourceSet": "Primeval Hunt (1.0)(2008)[Sega Lindbergh Red][TP].zip",
    "SourceEntry": "disk0/data/nnstdshader/nnstdshader.vert",
    "SourceSize": 65063,
    "SourceSha1": "B4B867C48268B22E782AB5EDB463E1FA84F149E7",
    "SourceSha256": "118E2C8D2D1555CDE663CC39421FCE525BB635EB8DE16DCE9CCAB2A5C910AEF8",
    "Target": "disk0/data/nnstdshader/nnstdshader.vert"
  }
]
'@ | ConvertFrom-Json -ErrorAction Stop

    $managerPath=Join-Path $RepositoryRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($managerPath,[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw 'Unable to parse manager helper source for isolated Main-component transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $functionAst){throw ('Missing required transaction helper: '+$name)}
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    # The extracted fixture setup mocks Write-Log; the full product script is not loaded here, so the command must exist.
    function Write-Log { param([string]$msg) }

    $suitePath=Join-Path $RepositoryRoot 'Tests\TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if(@($suiteErrors).Count){throw 'Unable to parse existing RequiredPatch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing RequiredPatch fixture container was not found.'}
    $fixtureBeforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $fixtureBeforeEach){throw 'The existing RequiredPatch fixture setup was not found.'}
    $script:requiredPatchFixtureSetup=$fixtureBeforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function Get-NativeMainBytesHash {
        param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][string]$Algorithm)
        $hasher=[Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        try { return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToUpperInvariant() }
        finally { $hasher.Dispose() }
    }

    function New-NativeMainComponentCase {
        param([Parameter(Mandatory)]$Expected,[switch]$CreateTargetParent)
        $fixture=$script:requiredPatchFixture
        $entry=@($script:mainDelta.Entries|Where-Object {$_.Id -ceq $Expected.Id})[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        if(-not $entry){throw ('Fragment entry is missing: '+$Expected.Id)}

        $caseRoot=Join-Path $fixture.Root ('c-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $gameRoot=Join-Path $caseRoot 'game'
        $payloadRoot=Join-Path $caseRoot 'payload'
        $recoveryRoot=Join-Path $caseRoot 'recovery'
        $protectedRoot=Join-Path $caseRoot 'protected'
        $sourceRoot=Join-Path $caseRoot 'main-source'
        $ownedRoot=Join-Path $caseRoot 'o'
        $tempRoot=Join-Path $ownedRoot 't'
        $backupRoot=Join-Path $ownedRoot 'b'
        foreach($directory in @($gameRoot,$payloadRoot,$recoveryRoot,$protectedRoot,$sourceRoot,$tempRoot,$backupRoot)){
            [void][IO.Directory]::CreateDirectory($directory)
        }
        $script:TpmOwnedLayout=[pscustomobject]@{Root=$ownedRoot;Temp=$tempRoot;Backups=$backupRoot}

        $entry.Executable='synthetic.exe'
        $entry.SourceSet='s.zip'
        $entry.SourceUrl=''
        $entry.SourceRevision=''
        $entry.SourceRole='Main'
        $entry.ExclusiveGroup=''
        $entry.Prerequisites=@()
        $payloadBytes=[Text.Encoding]::UTF8.GetBytes('Synthetic Main component bytes; never execute: '+$Expected.Id)
        $exeBytes=[Text.Encoding]::UTF8.GetBytes('Synthetic executable bytes; never execute: '+$Expected.Id)
        $entry.SourceSize=[int]$payloadBytes.Length
        $entry.SourceSha1=Get-NativeMainBytesHash -Bytes $payloadBytes -Algorithm 'SHA1'
        $entry.SourceSha256=Get-NativeMainBytesHash -Bytes $payloadBytes -Algorithm 'SHA256'
        $entry.ExecutableSha256=Get-NativeMainBytesHash -Bytes $exeBytes -Algorithm 'SHA256'
        $entry.Operations[0].AfterSha256=$entry.SourceSha256
        $entry.Operations[0].Payload='payload/'+$entry.SourceEntry
        $entry.Operations[0].PayloadSha256=$entry.SourceSha256

        $executable=Join-Path $gameRoot $entry.Executable
        [IO.File]::WriteAllBytes($executable,$exeBytes)
        $archivePath=Join-Path $sourceRoot $entry.SourceSet
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
        try {
            $member=$archive.CreateEntry([string]$entry.SourceEntry)
            $stream=$member.Open()
            try {$stream.Write($payloadBytes,0,$payloadBytes.Length)} finally {$stream.Dispose()}
        } finally {$archive.Dispose()}

        $stage=New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
        $payloadPath=Join-Path $payloadRoot ([string]$entry.Operations[0].Payload).Replace('/','\')
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payloadPath))
        [IO.File]::Copy($stage.Payload,$payloadPath,$true)
        $target=Join-Path $gameRoot ([string]$entry.Operations[0].Target).Replace('/','\')
        $targetParent=[IO.Path]::GetDirectoryName($target)
        if($CreateTargetParent){[void][IO.Directory]::CreateDirectory($targetParent)}

        $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
        $inputs=@{
            CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content)
            PatchId=[string]$entry.Id;ProfileId=[string]$entry.ProfileId;GameRoot=$gameRoot
            PayloadRoot=$payloadRoot;RecoveryRoot=$recoveryRoot;ProtectedRoots=@($protectedRoot)
        }
        return [pscustomobject]@{Entry=$entry;Inputs=$inputs;GameRoot=$gameRoot;PayloadRoot=$payloadRoot;RecoveryRoot=$recoveryRoot;ProtectedRoot=$protectedRoot;Executable=$executable;Target=$target;TargetParent=$targetParent;SourceRoot=$sourceRoot;SourceArchive=$archivePath;Stage=$stage;PayloadPath=$payloadPath;PayloadBytes=$payloadBytes;PayloadSha256=$entry.SourceSha256}
    }
function New-NativeMainLifecycleCase {
    param([Parameter(Mandatory)]$Expected,[switch]$CreateTargetParent)
    $fixture=$script:requiredPatchFixture
    $entry=@($script:mainDelta.Entries|Where-Object {$_.Id -ceq $Expected.Id})[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if(-not $entry){throw ('Fragment entry is missing: '+$Expected.Id)}

    $entry.Executable='synthetic.exe'
    $entry.ExecutableSha256=$fixture.ExecutableSha256
    $entry.SourceUrl=''
    $entry.SourceRevision=''
    $entry.SourceRole='Main'
    $entry.SourceSet=('synthetic-main-'+$Expected.Id+'.zip')
    $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
    $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash.ToUpperInvariant()
    $entry.SourceSha256=$fixture.CreatedSha256
    $entry.ExclusiveGroup=''
    $entry.Prerequisites=@()
    $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
    $entry.Operations[0].Payload='payload/'+$entry.SourceEntry
    $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256

    $payloadPath=Join-Path $fixture.PayloadRoot ([string]$entry.Operations[0].Payload).Replace('/','\')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payloadPath))
    [IO.File]::Copy($fixture.CreatedPayload,$payloadPath,$true)
    $target=Join-Path $fixture.GameRoot ([string]$entry.Operations[0].Target).Replace('/','\')
    $targetParent=[IO.Path]::GetDirectoryName($target)
    if($CreateTargetParent){[void][IO.Directory]::CreateDirectory($targetParent)}
    $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
    $inputs=@{
        CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content)
        PatchId=[string]$entry.Id;ProfileId=[string]$entry.ProfileId;GameRoot=$fixture.GameRoot
        PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot;ProtectedRoots=@($fixture.ProtectedRoot)
    }
    return [pscustomobject]@{Entry=$entry;Inputs=$inputs;Target=$target;TargetParent=$targetParent}
}
}


Describe 'Main component absent-only restorations' {
    BeforeEach { & $script:requiredPatchFixtureSetup }
    AfterEach { Restore-NativeMainVariables -Names $script:mainFixtureGlobalNames }
    AfterAll {
        Restore-NativeMainVariables -Names @($script:mainFixtureGlobalNames+$script:mainHarnessGlobalNames)
        Remove-Variable -Name mainOriginalGlobalValues,mainFixtureGlobalNames,mainHarnessGlobalNames -Scope Script -Force -ErrorAction SilentlyContinue
    }
    It 'binds the complete fragment to all 30 independent frozen Main rows' {
        $script:mainDelta.Schema | Should -Be 3
        @($script:mainDelta.Entries).Count | Should -Be 30
        @($script:expectedRows).Count | Should -Be 30
        @($script:mainDelta.Entries.Id | Sort-Object -Unique).Count | Should -Be 30
        foreach($expected in $script:expectedRows){
            $matches=@($script:mainDelta.Entries|Where-Object {$_.Id -ceq $expected.Id})
            $matches.Count | Should -Be 1
            $entry=$matches[0]
            foreach($field in @('ProfileId','BuildName','Executable','ExecutableSha256','SourceSet','SourceEntry','SourceSize','SourceSha1','SourceSha256')){
                [string]$entry.$field | Should -BeExactly ([string]$expected.$field) -Because $expected.Id
            }
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceUrl | Should -BeExactly ''
            $entry.SourceRevision | Should -BeExactly ''
            $entry.ExclusiveGroup | Should -BeExactly ''
            @($entry.Prerequisites).Count | Should -Be 0
            $entry.SourceSha1.Length | Should -Be 40
            $entry.SourceSha1 | Should -Match '^[A-Fa-f0-9]{40}$'
            $entry.SourceSha256 | Should -Match '^[A-Fa-f0-9]{64}$'
            @($entry.Operations).Count | Should -Be 1
            $operation=$entry.Operations[0]
            $operation.Type | Should -BeExactly 'CreateFile'
            $operation.Target | Should -BeExactly $expected.Target
            $operation.BeforeState | Should -BeExactly 'Absent'
            $operation.AfterSha256 | Should -BeExactly $entry.SourceSha256
            $operation.Payload | Should -BeExactly ('payload/'+$entry.SourceEntry)
            $operation.PayloadSha256 | Should -BeExactly $entry.SourceSha256
            $operation.AfterSha256 | Should -BeExactly $operation.PayloadSha256
        }
        @($script:mainDelta.Entries|Where-Object {$_.ProfileId -ceq 'CrossRaid' -or $_.ProfileId -ceq 'ShiningForceCrossRaid'}).Count | Should -Be 0
    }

    It 'imports the exact 30-entry fragment through the production planner before the executable identity guard' {
        $entry=$script:mainDelta.Entries[0]
        $fixture=$script:requiredPatchFixture
        $game=Join-Path $fixture.Root 'main-fragment-import-game'
        [void][IO.Directory]::CreateDirectory($game)
        [IO.File]::WriteAllText((Join-Path $game $entry.Executable),'synthetic executable mismatch; never execute')
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Join-Path $game $entry.Operations[0].Target.Replace('/','\'))))
        $inputs=@{
            CatalogContent=$script:mainFragmentText;CatalogSha256=$script:mainFragmentHash
            PatchId=[string]$entry.Id;ProfileId=[string]$entry.ProfileId;GameRoot=$game
            PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot;ProtectedRoots=@($fixture.ProtectedRoot)
        }
        $plan=Get-TpmPatchPlan @inputs
        $plan.Status | Should -Be 'Unavailable'
        $plan.Reason | Should -BeExactly 'Executable revision mismatch.'
    }

    It -ForEach @(0..29 | ForEach-Object {@{Index=$_}}) 'lifecycle row <Index>: apply, no-op, undo, and foreign-byte refusal' {
        $expected=$script:expectedRows[$Index]
        $case=New-NativeMainLifecycleCase -Expected $expected -CreateTargetParent
        $inputs=$case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
        $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -Be 'Applied'
        (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -Be $case.Entry.SourceSha256
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($script:requiredPatchFixture.CreatedPayload)))
        (Get-TpmPatchPlan @inputs).Status | Should -Be 'AlreadyApplied'
        (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
        Test-Path -LiteralPath $case.Target | Should -BeFalse
        $foreign=[Text.Encoding]::UTF8.GetBytes('unknown existing bytes; never execute')
        [IO.File]::WriteAllBytes($case.Target,$foreign)
        $unknown=Get-TpmPatchPlan @inputs
        $unknown.Status | Should -Be 'Unavailable'
        $unknown.Reason | Should -Match 'Grouped target conflict'
        $failure=$null
        try {$null=Invoke-TpmCatalogPatch @inputs -Confirm:$false} catch {$failure=$_.Exception.Message}
        $failure | Should -Match 'Grouped target conflict'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($foreign))
    }
    It -ForEach @(0..29 | ForEach-Object {@{Index=$_}}) 'stages synthetic Main ZIP member for source row <Index>' {
        $expected=$script:expectedRows[$Index]
        $case=New-NativeMainComponentCase -Expected $expected
        $case.Stage.SourceArchive | Should -BeExactly $case.SourceArchive
        $case.Stage.SourceEntry | Should -BeExactly $expected.SourceEntry
        $case.Stage.Size | Should -Be $case.PayloadBytes.Length
        $case.Stage.Sha256 | Should -BeExactly $case.PayloadSha256
        (Test-PathInside $case.Stage.Root $script:TpmOwnedLayout.Temp) | Should -BeTrue
        (Test-PathInside $case.Stage.Payload $case.Stage.Root) | Should -BeTrue
        (Get-Item -LiteralPath $case.Stage.Payload).Length | Should -Be $case.PayloadBytes.Length
        (Get-FileHash -LiteralPath $case.Stage.Payload -Algorithm SHA256).Hash | Should -BeExactly $case.PayloadSha256
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Stage.Payload)) | Should -Be ([Convert]::ToBase64String($case.PayloadBytes))
    }

    It -ForEach @(0..29 | ForEach-Object {@{Index=$_}}) 'refuses wrong executable without target or recovery mutation for row <Index>' {
        $expected=$script:expectedRows[$Index]
        $case=New-NativeMainComponentCase -Expected $expected -CreateTargetParent
        $inputs=$case.Inputs
        $payloadHash=(Get-FileHash -LiteralPath (Join-Path $inputs.PayloadRoot $case.Entry.Operations[0].Payload.Replace('/','\')) -Algorithm SHA256).Hash
        $wrongExe=[Text.Encoding]::UTF8.GetBytes('wrong executable revision; never execute')
        [IO.File]::WriteAllBytes($case.Executable,$wrongExe)
        $plan=Get-TpmPatchPlan @inputs
        $plan.Status | Should -Be 'Unavailable'
        $plan.Reason | Should -BeExactly 'Executable revision mismatch.'
        $failure=$null
        try {$null=Invoke-TpmCatalogPatch @inputs -Confirm:$false} catch {$failure=$_.Exception.Message}
        $failure | Should -BeExactly 'Executable revision mismatch.'
        Test-Path -LiteralPath $case.Target | Should -BeFalse
        @(Get-ChildItem -LiteralPath $case.RecoveryRoot -Force).Count | Should -Be 0
        (Get-FileHash -LiteralPath (Join-Path $inputs.PayloadRoot $case.Entry.Operations[0].Payload.Replace('/','\')) -Algorithm SHA256).Hash | Should -BeExactly $payloadHash
    }

    It -ForEach @(0..29 | ForEach-Object {@{Index=$_}}) 'refuses absent target parent without creating it for row <Index>' {
        $expected=$script:expectedRows[$Index]
        $case=New-NativeMainComponentCase -Expected $expected
        $inputs=$case.Inputs
        Test-Path -LiteralPath $case.TargetParent | Should -BeFalse
        $plan=Get-TpmPatchPlan @inputs
        $plan.Status | Should -Be 'Unavailable'
        $plan.Reason | Should -BeExactly 'Grouped targets require existing safe parents.'
        $failure=$null
        try {$null=Invoke-TpmCatalogPatch @inputs -Confirm:$false} catch {$failure=$_.Exception.Message}
        $failure | Should -BeExactly 'Grouped targets require existing safe parents.'
        Test-Path -LiteralPath $case.TargetParent | Should -BeFalse
        Test-Path -LiteralPath $case.Target | Should -BeFalse
        @(Get-ChildItem -LiteralPath $case.RecoveryRoot -Force).Count | Should -Be 0
    }

    It -ForEach @(0..29 | ForEach-Object {@{Index=$_}}) 'refuses receipt undo after same-byte replacement changes object identity for row <Index>' {
        $expected=$script:expectedRows[$Index]
        $case=New-NativeMainComponentCase -Expected $expected -CreateTargetParent
        $inputs=$case.Inputs
        $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -Be 'Applied'
        $receiptPath=Join-Path $applied.RecoveryDirectory 'receipt.json'
        $receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
        $receipt.Schema | Should -Be 3
        @($receipt.Operations).Count | Should -Be 1
        $boundIdentity=[string]$receipt.Operations[0].AfterFileIdentity
        $boundIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
        $held=Join-Path $case.TargetParent ([IO.Path]::GetFileName($case.Target)+'.held')
        [IO.File]::Move($case.Target,$held)
        $sameBytes=[byte[]]$case.PayloadBytes
        [IO.File]::WriteAllBytes($case.Target,$sameBytes)
        $opened=Open-TpmPatchCreationFile $case.Target
        try {$newIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle)} finally {$opened.Dispose()}
        $newIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
        $newIdentity | Should -Not -BeExactly $boundIdentity
        $failure=$null
        try {$null=Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false} catch {$failure=$_.Exception.Message}
        $failure | Should -Match 'Grouped target object identity changed'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($sameBytes))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($held)) | Should -Be ([Convert]::ToBase64String($sameBytes))
        $afterFailure=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
        $afterFailure.State | Should -BeExactly 'Applied'
        $afterFailure.Operations[0].AfterFileIdentity | Should -BeExactly $boundIdentity
    }

    It 'returns an independent unverified result for an invalid snapshot ID without creating directories' {
        $caseRoot=Join-Path $TestDrive 'ns1'
        $backups=Join-Path $caseRoot 'backups'
        $targetDirectory=Join-Path $backups 'transaction'
        [void][IO.Directory]::CreateDirectory($targetDirectory)
        $target=Join-Path $targetDirectory 'receipt.json'
        [IO.File]::WriteAllText($target,'invalid ID target')
        $store=Join-Path $backups 'ReceiptHistory'
        $outerResult=[pscustomobject]@{
            Status='VERIFIED'
            PublicationState='VERIFIED'
            Reason='outer result sentinel'
        }
        $result=$outerResult

        $created=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId 'bad/id' -Kind Checkpoint -TargetPaths @($target) -PayloadRetention StateOnly

        $created.Status | Should -BeExactly 'FAILED'
        $created.PublicationState | Should -BeExactly 'UNVERIFIED'
        $created.Reason | Should -BeExactly 'Receipt history checkpoint identity or target count is invalid.'
        [object]::ReferenceEquals($created,$outerResult) | Should -BeFalse
        $result.Status | Should -BeExactly 'VERIFIED'
        $result.PublicationState | Should -BeExactly 'VERIFIED'
        $result.Reason | Should -BeExactly 'outer result sentinel'
        Test-Path -LiteralPath $store | Should -BeFalse
    }

    It 'creates and reuses a matching checkpoint with unchanged manifest bytes' {
        $caseRoot=Join-Path $TestDrive 'ns2'
        $backups=Join-Path $caseRoot 'backups'
        $targetDirectory=Join-Path $backups 'transaction'
        [void][IO.Directory]::CreateDirectory($targetDirectory)
        $target=Join-Path $targetDirectory 'receipt.json'
        [IO.File]::WriteAllText($target,'checkpoint receipt bytes')
        $store=Join-Path $backups 'ReceiptHistory'
        $snapshotId='s'
        $snapshot=Join-Path (Join-Path $store 'Snapshots') $snapshotId
        $manifestPath=Join-Path $snapshot 'manifest.json'
        ([IO.Path]::GetFullPath($snapshot).Length -le 247) | Should -BeTrue
        ([IO.Path]::GetFullPath($manifestPath).Length -le 247) | Should -BeTrue

        $created=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId $snapshotId -Kind Checkpoint -TargetPaths @($target) -PayloadRetention StateOnly
        $created.Status | Should -BeExactly 'VERIFIED'
        $created.PublicationState | Should -BeExactly 'VERIFIED'
        $verified=Test-TpmResetSnapshot -SnapshotPath $snapshot
        $verified.Verified | Should -BeTrue
        $verified.Manifest.SnapshotId | Should -BeExactly $snapshotId
        $before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath))

        Mock Open-TpmPatchCreationFile { throw 'unexpected checkpoint rewrite' }
        $again=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId $snapshotId -Kind Checkpoint -TargetPaths @($target) -PayloadRetention StateOnly

        $again.Status | Should -BeExactly 'VERIFIED'
        $again.PublicationState | Should -BeExactly 'VERIFIED'
        $again.Reason | Should -BeExactly 'The matching receipt history checkpoint already exists.'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath)) | Should -BeExactly $before
    }

    It 'returns the readback failure and retains an unverified manifest' {
        $caseRoot=Join-Path $TestDrive 'ns3'
        $backups=Join-Path $caseRoot 'backups'
        $targetDirectory=Join-Path $backups 'transaction'
        [void][IO.Directory]::CreateDirectory($targetDirectory)
        $target=Join-Path $targetDirectory 'receipt.json'
        [IO.File]::WriteAllText($target,'readback failure target')
        $store=Join-Path $backups 'ReceiptHistory'
        $snapshotId='r'
        $snapshot=Join-Path (Join-Path $store 'Snapshots') $snapshotId
        $manifestPath=Join-Path $snapshot 'manifest.json'
        ([IO.Path]::GetFullPath($snapshot).Length -le 247) | Should -BeTrue
        ([IO.Path]::GetFullPath($manifestPath).Length -le 247) | Should -BeTrue

        Mock Test-TpmResetSnapshot {
            [pscustomobject]@{
                Verified=$false
                Manifest=[pscustomobject]@{SnapshotId='wrong'}
                Reason='controlled readback failure'
            }
        }

        $created=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId $snapshotId -Kind Checkpoint -TargetPaths @($target) -PayloadRetention StateOnly

        $created.Status | Should -BeExactly 'FAILED'
        $created.PublicationState | Should -BeExactly 'UNVERIFIED'
        $created.Reason | Should -BeExactly 'Receipt history checkpoint readback failed: controlled readback failure'
        Test-Path -LiteralPath $snapshot -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        ([IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json).SnapshotId | Should -BeExactly $snapshotId
    }

    It 'preserves an existing verified snapshot when a request mismatches its target' {
        $caseRoot=Join-Path $TestDrive 'ns4'
        $backups=Join-Path $caseRoot 'backups'
        $firstDirectory=Join-Path $backups 'first'
        $secondDirectory=Join-Path $backups 'second'
        [void][IO.Directory]::CreateDirectory($firstDirectory)
        [void][IO.Directory]::CreateDirectory($secondDirectory)
        $firstTarget=Join-Path $firstDirectory 'receipt.json'
        $secondTarget=Join-Path $secondDirectory 'receipt.json'
        [IO.File]::WriteAllText($firstTarget,'first receipt')
        [IO.File]::WriteAllText($secondTarget,'different receipt')
        $store=Join-Path $backups 'ReceiptHistory'
        $snapshotId='m'
        $snapshot=Join-Path (Join-Path $store 'Snapshots') $snapshotId
        $manifestPath=Join-Path $snapshot 'manifest.json'
        ([IO.Path]::GetFullPath($snapshot).Length -le 247) | Should -BeTrue
        ([IO.Path]::GetFullPath($manifestPath).Length -le 247) | Should -BeTrue

        $first=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId $snapshotId -Kind Checkpoint -TargetPaths @($firstTarget) -PayloadRetention StateOnly
        $first.Status | Should -BeExactly 'VERIFIED'
        $first.PublicationState | Should -BeExactly 'VERIFIED'
        $before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath))

        $mismatch=New-TpmResetSnapshot -BackupsRoot $backups -StoreRoot $store -SnapshotId $snapshotId -Kind Checkpoint -TargetPaths @($secondTarget) -PayloadRetention StateOnly

        $mismatch.Status | Should -BeExactly 'FAILED'
        $mismatch.PublicationState | Should -BeExactly 'UNVERIFIED'
        $mismatch.Reason | Should -BeExactly 'Receipt history checkpoint already exists with different or invalid state; it was not overwritten.'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath)) | Should -BeExactly $before
        $stillVerified=Test-TpmResetSnapshot -SnapshotPath $snapshot
        $stillVerified.Verified | Should -BeTrue
        $stillVerified.Manifest.Paths[0].TargetPath | Should -BeExactly $firstTarget
    }

    It 'rejects a non-verified checkpoint result and surfaces its reason and arguments to the caller' {
        $caseRoot=Join-Path $TestDrive 'ns5'
        $backups=Join-Path $caseRoot 'backups'
        $directory=Join-Path $backups 'transaction'
        [void][IO.Directory]::CreateDirectory($directory)
        $catalogHash='A'*64
        $transactionId='c'
        $snapshotId=$transactionId+'_RolledBack'
        $store=Join-Path $backups 'ReceiptHistory'
        $snapshot=Join-Path (Join-Path $store 'Snapshots') $snapshotId
        $manifestPath=Join-Path $snapshot 'manifest.json'
        ([IO.Path]::GetFullPath($snapshot).Length -le 247) | Should -BeTrue
        ([IO.Path]::GetFullPath($manifestPath).Length -le 247) | Should -BeTrue
        $targetPath=Join-Path $directory 'receipt.json'
        $terminalReceipt=[ordered]@{
            State='RolledBack'
            TransactionId=$transactionId
            CatalogSha256=$catalogHash
        }
        [IO.File]::WriteAllText($targetPath,($terminalReceipt|ConvertTo-Json -Depth 4))
        $plan=[pscustomobject]@{RecoveryRoot=$backups}
        $receipt=[pscustomobject]$terminalReceipt
        $capturedArgs=[Collections.Generic.List[object]]::new()
        Mock Assert-TpmMultiPatchReceipt {}
        Mock New-TpmResetSnapshot {
            param(
                [string]$BackupsRoot,
                [string]$StoreRoot,
                [string]$SnapshotId,
                [string]$Kind,
                [string[]]$TargetPaths,
                [string]$PayloadRetention
            )
            [void]$capturedArgs.Add([pscustomobject]@{
                BackupsRoot=$BackupsRoot
                StoreRoot=$StoreRoot
                SnapshotId=$SnapshotId
                Kind=$Kind
                TargetPaths=@($TargetPaths)
                PayloadRetention=$PayloadRetention
            })
            [pscustomobject]@{
                Status='FAILED'
                PublicationState='UNVERIFIED'
                Reason='controlled checkpoint failure'
            }
        }

        $failure=$null
        try {
            New-TpmMultiPatchTerminalCheckpoint -Plan $plan -Receipt $receipt -Directory $directory
        } catch {$failure=$_.Exception.Message}
        $failure | Should -BeExactly 'Grouped terminal receipt checkpoint failed: controlled checkpoint failure'
        $capturedArgs.Count | Should -Be 1
        $capturedArgs[0].BackupsRoot | Should -BeExactly $backups
        $capturedArgs[0].StoreRoot | Should -BeExactly $store
        $capturedArgs[0].SnapshotId | Should -BeExactly $snapshotId
        $capturedArgs[0].Kind | Should -BeExactly 'Checkpoint'
        @($capturedArgs[0].TargetPaths).Count | Should -Be 1
        $capturedArgs[0].TargetPaths[0] | Should -BeExactly $targetPath
        $capturedArgs[0].PayloadRetention | Should -BeExactly 'StateOnly'
    }

}
