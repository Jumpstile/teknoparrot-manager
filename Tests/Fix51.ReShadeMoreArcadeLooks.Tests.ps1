#Requires -Module Pester
# FIX51 / issue 383 "more arcade-valuable ReShade looks": five new CRT looks from the pinned RSRetroArch port (CRT-Geom, CRT-Aperture,
# CRT-Easymode, CRT-Hyllian, CRT-ZFast), their pins, allowlist, technique and uniform names, license evidence, conflicts, the 17-entry
# profile list in its contract order, the per-effect preset sections, the preview approximation and the chooser cost text.
# Product functions are loaded exactly like Tests\Fix46.ReShadeSelectionRedraw.Tests.ps1 (AST-extracted function definitions of
# TeknoParrot-Manager.ps1, dot-sourced, plus Tests\TpmExtractedScriptState.ps1). No network, no registry, no services, no game folder.
# Every It carries a one-line comment naming the product mutation that must make it fail.
# Optional input: the saved candidate shader folder (environment variable TPM_SHADER_CANDIDATES_DIR only; no default path). The
# Its that read the saved .fx bytes are skipped when it is absent; every other It runs without it (the declared uniform names are
# embedded below as literals copied from the saved files).
# NOTHING WAS RUN when this file was written (no Pester, no product script). It was only parse-checked.
# What this CANNOT prove: how a shader looks in a real game, or that ReShade compiles the files (the preview is an approximation).

# Discovery-time values (Pester 5 evaluates -Skip while discovering); BeforeAll repeats the same resolution for the run phase.
$fix51CandidateDir = $env:TPM_SHADER_CANDIDATES_DIR
if ([string]::IsNullOrWhiteSpace($fix51CandidateDir)) { $fix51CandidateDir = Join-Path $PSScriptRoot 'no-candidate-folder-set' }
$fix51CandidatesPresent = $true
foreach ($fix51CandidateName in @('CRTGeom.fx', 'CRTAperture.fx', 'CRTEasymode.fx', 'CRTHyllian.fx', 'zfast_crt.fx')) {
    if (-not (Test-Path -LiteralPath (Join-Path $fix51CandidateDir ('Matsilagi_RSRetroArch__Shaders__' + $fix51CandidateName)) -PathType Leaf)) { $fix51CandidatesPresent = $false }
}
if (-not (Test-Path -LiteralPath (Join-Path $fix51CandidateDir 'crosire_reshade-shaders__Shaders__ReShade.fxh') -PathType Leaf)) { $fix51CandidatesPresent = $false }
$fix51CanDraw = $false
try { Add-Type -AssemblyName System.Drawing; $fix51Probe = New-Object Drawing.Bitmap(2, 2); $fix51Probe.Dispose(); $fix51CanDraw = $true } catch { $fix51CanDraw = $false }

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX51 bootstrap could not parse the production script.' }
    $script:Fix51Ast = $ast
    $functionFile = Join-Path $TestDrive 'fix51-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'fix51.log'
    $script:logWarnShown = $false

    # ---- optional saved candidate folder (same resolution as the discovery block above)
    $script:Fix51CandidateDir = $env:TPM_SHADER_CANDIDATES_DIR
    if ([string]::IsNullOrWhiteSpace($script:Fix51CandidateDir)) { $script:Fix51CandidateDir = Join-Path $PSScriptRoot 'no-candidate-folder-set' }

    # ---- literal copy of INDEX-RAW-BYTES.txt (coordinator download): the five new effects and the ReShade.fxh row their include uses
    $script:Fix51Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'
    $script:Fix51Index = @(
        @{ Repository = 'Matsilagi/RSRetroArch'; Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'; Path = 'Shaders/CRTGeom.fx'; Bytes = 12140; Sha = '4144AE6B796EAEC065A54E1DC39DE0781DE3E28D22FBAE70C3096642ACFBA5F4' }
        @{ Repository = 'Matsilagi/RSRetroArch'; Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'; Path = 'Shaders/CRTAperture.fx'; Bytes = 6700; Sha = '098B720CA54176CC438DD8E5B14C0370D951AEB6C568F4FD16FB2B9082E67C83' }
        @{ Repository = 'Matsilagi/RSRetroArch'; Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'; Path = 'Shaders/CRTEasymode.fx'; Bytes = 9104; Sha = 'FB17CAD974DDB4E896350FB0DB2F7718B56E1C1A4DA34416F071D702EC359D4F' }
        @{ Repository = 'Matsilagi/RSRetroArch'; Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'; Path = 'Shaders/CRTHyllian.fx'; Bytes = 10041; Sha = '2AF21CBBB181D6145ED9E3B18AAC6CE4AE26627659ABCAF167908708DAEF3E9F' }
        @{ Repository = 'Matsilagi/RSRetroArch'; Commit = '73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d'; Path = 'Shaders/zfast_crt.fx'; Bytes = 4212; Sha = 'AEDCB3AEB5DE5DF871245D5EC7BA1F9E7603AF87460179FFB6671F7BDBABCBCB' }
        @{ Repository = 'crosire/reshade-shaders'; Commit = 'fd0022170615ce0d8162d219bff07232fa6dd84f'; Path = 'Shaders/ReShade.fxh'; Bytes = 4250; Sha = '6DABFBBAF968C3871905D2EA17F96572FF7B1CEC01310B5D0E5252B66B30174F' }
    )
    $script:Fix51GplNoticeSha = '186D4B813CCA7C779938DB8FB041D9FE9C132F403045F88C251AF1656358D169'
    $script:Fix51GplNoticeBytes = 15521

    # ---- contract table of the five new effects / profiles. Uniforms = every uniform declared in the saved .fx file (copied from it).
    $script:Fix51Effects = @(
        @{
            EffectId = 'RSRetroArch.CRTGeom'; ProfileId = 'CurvedArcadeMonitor'; Friendly = 'Curved Arcade Monitor'; Technical = 'CRT-Geom'; Cost = 'MEDIUM'; CostWord = 'medium'; Fallback = 'LightweightCrt'
            File = 'CRTGeom.fx'; Path = 'Shaders/CRTGeom.fx'; Technique = 'GeomCRT'; License = 'GPL-2.0-or-later'; GplCopy = $true; Kind = 'Geom'; Glow = 0.0; LevelsGain = 1.0; Saturation = 1.0
            Uniforms = ('texture_sizeX texture_sizeY video_sizeX video_sizeY CRTgamma monitorgamma d CURVATURE R cornersize cornersmooth x_tilt y_tilt overscan_x overscan_y DOTMASK SHARPER scanline_weight lum interlace_toggle OVERSAMPLE INTERLACED framecount' -split ' ')
            Preset = ('texture_sizeX=640 texture_sizeY=480 video_sizeX=640 video_sizeY=480 CURVATURE=1 cornersize=0.05 DOTMASK=0.3 scanline_weight=0.3 interlace_toggle=5 OVERSAMPLE=1' -split ' ')
        }
        @{
            EffectId = 'RSRetroArch.CRTAperture'; ProfileId = 'SharpApertureGrille'; Friendly = 'Sharp Aperture Grille'; Technical = 'CRT-Aperture'; Cost = 'MEDIUM'; CostWord = 'medium'; Fallback = 'LightweightCrt'
            File = 'CRTAperture.fx'; Path = 'Shaders/CRTAperture.fx'; Technique = 'ApertureCRT'; License = 'GPL (version not stated)'; GplCopy = $true; Kind = 'Aperture'; Glow = 0.30; LevelsGain = 1.0; Saturation = 1.0
            Uniforms = ('resX resY video_sizeX video_sizeY SHARPNESS_IMAGE SHARPNESS_EDGES GLOW_WIDTH GLOW_HEIGHT GLOW_HALATION GLOW_DIFFUSION MASK_COLORS MASK_STRENGTH MASK_SIZE SCANLINE_SIZE_MIN SCANLINE_SIZE_MAX GAMMA_INPUT GAMMA_OUTPUT BRIGHTNESS' -split ' ')
            Preset = ('resX=640 resY=480 video_sizeX=640 video_sizeY=480 SHARPNESS_IMAGE=1 SHARPNESS_EDGES=3 MASK_COLORS=3 MASK_STRENGTH=0.4 MASK_SIZE=1 GLOW_HALATION=0.1 BRIGHTNESS=1.5' -split ' ')
        }
        @{
            EffectId = 'RSRetroArch.CRTEasymode'; ProfileId = 'EasymodeCrt'; Friendly = 'Balanced Flat CRT'; Technical = 'CRT-Easymode'; Cost = 'MEDIUM'; CostWord = 'medium'; Fallback = 'LightweightCrt'
            File = 'CRTEasymode.fx'; Path = 'Shaders/CRTEasymode.fx'; Technique = 'EasymodeCRT'; License = 'GPL (version not stated)'; GplCopy = $true; Kind = 'Easymode'; Glow = 0.0; LevelsGain = 1.08; Saturation = 1.0
            Uniforms = ('texture_sizeX texture_sizeY video_sizeX video_sizeY SHARPNESS_H SHARPNESS_V MASK_STRENGTH MASK_DOT_WIDTH MASK_DOT_HEIGHT MASK_STAGGER MASK_SIZE SCANLINE_STRENGTH SCANLINE_BEAM_WIDTH_MIN SCANLINE_BEAM_WIDTH_MAX SCANLINE_BRIGHT_MIN SCANLINE_BRIGHT_MAX SCANLINE_CUTOFF GAMMA_INPUT GAMMA_OUTPUT BRIGHT_BOOST DILATION ENABLE_LANCZOS' -split ' ')
            Preset = ('texture_sizeX=640 texture_sizeY=480 video_sizeX=640 video_sizeY=480 SHARPNESS_H=0.5 SHARPNESS_V=1 MASK_STRENGTH=0.3 SCANLINE_STRENGTH=1 SCANLINE_CUTOFF=1000 BRIGHT_BOOST=1.2' -split ' ')
        }
        @{
            EffectId = 'RSRetroArch.CRTHyllian'; ProfileId = 'HyllianCrt'; Friendly = 'Sharp Phosphor CRT'; Technical = 'CRT-Hyllian'; Cost = 'MEDIUM'; CostWord = 'medium'; Fallback = 'LightweightCrt'
            File = 'CRTHyllian.fx'; Path = 'Shaders/CRTHyllian.fx'; Technique = 'CRTHyllian'; License = 'MIT'; GplCopy = $false; Kind = 'Hyllian'; Glow = 0.0; LevelsGain = 1.06; Saturation = 1.15
            Uniforms = ('CRT_MULRES_X CRT_MULRES_Y texture_sizeX texture_sizeY video_sizeX video_sizeY PHOSPHOR VSCANLINES InputGamma OutputGamma SHARPNESS COLOR_BOOST RED_BOOST GREEN_BOOST BLUE_BOOST SCANLINES_STRENGTH BEAM_MIN_WIDTH BEAM_MAX_WIDTH CRT_ANTI_RINGING B C' -split ' ')
            Preset = ('CRT_MULRES_X=1 CRT_MULRES_Y=1 texture_sizeX=640 texture_sizeY=480 video_sizeX=640 video_sizeY=480 PHOSPHOR=1 SCANLINES_STRENGTH=0.4 COLOR_BOOST=1.5 BEAM_MIN_WIDTH=0.86 BEAM_MAX_WIDTH=1 CRT_ANTI_RINGING=0.8' -split ' ')
        }
        @{
            EffectId = 'RSRetroArch.CRTZFast'; ProfileId = 'FastCrt'; Friendly = 'Fast CRT'; Technical = 'CRT-ZFast'; Cost = 'LOW'; CostWord = 'light'; Fallback = 'Original'
            File = 'zfast_crt.fx'; Path = 'Shaders/zfast_crt.fx'; Technique = 'CRTZFast'; License = 'GPL-2.0-or-later'; GplCopy = $true; Kind = 'ZFast'; Glow = 0.0; LevelsGain = 1.0; Saturation = 1.0
            Uniforms = ('FINEMASK BLACK_OUT_BORDER BLURSCALEX LOWLUMSCAN HILUMSCAN BRIGHTBOOST MASK_DARK MASK_FADE video_sizeX video_sizeY' -split ' ')
            Preset = ('video_sizeX=640 video_sizeY=480 FINEMASK=1 BLACK_OUT_BORDER=0 BLURSCALEX=0.3 LOWLUMSCAN=6 HILUMSCAN=8 BRIGHTBOOST=1.25 MASK_DARK=0.25 MASK_FADE=0.8' -split ' ')
        }
    )
    $script:Fix51OldCrtIds = @('FXShaders.CRT_Lottes', 'Akgunter.CRTRoyale', 'RSRetroArch.CRTPi')
    $script:Fix51ProfileOrder = @('Original', 'CurvedArcadeMonitor', 'ClassicCrt', 'SharpApertureGrille', 'EasymodeCrt', 'HyllianCrt', 'CrtGlow', 'DetailedCrt', 'FastCrt', 'LightweightCrt', 'ScanlineGlow', 'BrightScanlines', 'ArcadeGlow', 'Crisp3d', 'Crisp3dGlow', 'ContrastCurves', 'Levels')

    # ---- one real catalog / profile list; most Its read these (the catalog is expensive to rebuild: it builds every evidence record)
    $script:Fix51Catalog = @(Get-TpmReShadeEffectCatalog)
    $script:Fix51Profiles = @(Get-TpmReShadeProfiles)

    function Get-Fix51IndexRow {
        param([string]$Repository, [string]$Path)
        return @($script:Fix51Index | Where-Object { $_.Repository -eq $Repository -and $_.Path -eq $Path })[0]
    }
    function Get-Fix51Row {
        param([string]$EffectId)
        return @($script:Fix51Catalog | Where-Object { $_.EffectId -eq $EffectId })[0]
    }
    function Get-Fix51Profile {
        param([string]$ProfileId)
        return @($script:Fix51Profiles | Where-Object { $_.ProfileId -eq $ProfileId })[0]
    }
    function Get-Fix51CandidatePath {
        param($IndexRow)
        return (Join-Path $script:Fix51CandidateDir ((([string]$IndexRow.Repository) -replace '/', '_') + '__' + (([string]$IndexRow.Path) -replace '/', '__')))
    }
    function Get-Fix51BytesHash {
        param([byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '') } finally { $sha.Dispose() }
    }
    # Preset text split into flat lines and "[Section]" key=value lines (blank lines dropped inside sections).
    function Get-Fix51PresetParts {
        param([string]$Content)
        $flat = New-Object System.Collections.Generic.List[string]
        $headers = New-Object System.Collections.Generic.List[string]
        $sections = @{}
        $current = $null
        foreach ($line in @($Content -split "`r?`n")) {
            if ($line -match '^\[(?<name>[^\]]*)\]$') {
                $current = [string]$Matches['name']
                [void]$headers.Add($current)
                $sections[$current] = New-Object System.Collections.Generic.List[string]
                continue
            }
            if ($null -eq $current) { [void]$flat.Add($line) } elseif (-not [string]::IsNullOrWhiteSpace($line)) { [void]$sections[$current].Add($line) }
        }
        return [pscustomobject]@{ Flat = @($flat.ToArray()); Headers = @($headers.ToArray()); Sections = $sections }
    }

    # ---- preview helpers (small deterministic synthetic bitmap; every channel stays well above black)
    $script:Fix51Width = 96
    $script:Fix51Height = 64
    # The same threshold the existing content test (Assert-TpmApproximationChangesContent in TeknoParrot-Manager.Tests.ps1) uses for NO_CONTENT_CHANGE.
    $script:Fix51MinChangedPixels = 1000
    function New-Fix51Bitmap {
        $bitmap = New-Object Drawing.Bitmap($script:Fix51Width, $script:Fix51Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        for ($y = 0; $y -lt $script:Fix51Height; $y++) {
            for ($x = 0; $x -lt $script:Fix51Width; $x++) {
                $r = 64 + [int][Math]::Floor($x * 160 / ($script:Fix51Width - 1))
                $g = 64 + [int][Math]::Floor($y * 160 / ($script:Fix51Height - 1))
                $b = 96 + (($x * 7 + $y * 5) % 128)
                $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(255, $r, $g, $b))
            }
        }
        return $bitmap
    }
    function Get-Fix51Bgra {
        param([Parameter(Mandatory)][Drawing.Bitmap]$Bitmap)
        $rectangle = New-Object Drawing.Rectangle -ArgumentList @(0, 0, $Bitmap.Width, $Bitmap.Height)
        $data = $Bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = [int]$data.Stride
            $absoluteStride = [Math]::Abs($stride)
            $length = $absoluteStride * $Bitmap.Height
            $raw = New-Object byte[] $length
            $start = if ($stride -lt 0) { [IntPtr]::Add($data.Scan0, (($Bitmap.Height - 1) * $stride)) } else { $data.Scan0 }
            [Runtime.InteropServices.Marshal]::Copy($start, $raw, 0, $length)
        } finally { $Bitmap.UnlockBits($data) }
        $compact = New-Object byte[] ($Bitmap.Width * $Bitmap.Height * 4)
        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            $rowOffset = if ($stride -ge 0) { $y * $absoluteStride } else { ($Bitmap.Height - 1 - $y) * $absoluteStride }
            [Array]::Copy($raw, $rowOffset, $compact, $y * $Bitmap.Width * 4, $Bitmap.Width * 4)
        }
        return , $compact
    }
    function Get-Fix51Render {
        param($ProfileDefinition)
        $bitmap = New-Fix51Bitmap
        try {
            if ($null -ne $ProfileDefinition) { Invoke-TpmReShadePreviewProfilePixels -Bitmap $bitmap -ProfileDefinition $ProfileDefinition }
            $lastX = $script:Fix51Width - 1
            $lastY = $script:Fix51Height - 1
            $bytes = Get-Fix51Bgra -Bitmap $bitmap
            return [pscustomobject]@{
                Bytes = $bytes
                Hash = (Get-Fix51BytesHash -Bytes $bytes)
                Corners = @($bitmap.GetPixel(0, 0), $bitmap.GetPixel($lastX, 0), $bitmap.GetPixel(0, $lastY), $bitmap.GetPixel($lastX, $lastY))
                Center = $bitmap.GetPixel([int]($script:Fix51Width / 2), [int]($script:Fix51Height / 2))
            }
        } finally { $bitmap.Dispose() }
    }
    function Get-Fix51DiffCount {
        param([byte[]]$Left, [byte[]]$Right)
        $count = 0
        for ($i = 0; $i -lt $Left.Length; $i += 4) {
            if ($Left[$i] -ne $Right[$i] -or $Left[$i + 1] -ne $Right[$i + 1] -or $Left[$i + 2] -ne $Right[$i + 2] -or $Left[$i + 3] -ne $Right[$i + 3]) { $count++ }
        }
        return $count
    }
    function Test-Fix51Black {
        param([Drawing.Color]$Color)
        return ($Color.R -eq 0 -and $Color.G -eq 0 -and $Color.B -eq 0)
    }
}

Describe 'FIX51 pins match the coordinator download (INDEX-RAW-BYTES.txt)' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'pins repository, commit, source and destination path, SHA-256 and byte length of each new effect to the downloaded bytes' {
        # Mutation: change one hex digit of a SHA256 entry, one ByteLengths entry, the PinnedCommit or a RelativeFiles/DestinationFiles path of any new catalog row.
        foreach ($e in $script:Fix51Effects) {
            $pin = Get-Fix51IndexRow -Repository 'Matsilagi/RSRetroArch' -Path $e.Path
            $row = Get-Fix51Row -EffectId $e.EffectId
            $row | Should -Not -BeNullOrEmpty -Because $e.EffectId
            $row.Repository | Should -BeExactly $pin.Repository -Because $e.EffectId
            $row.PinnedCommit | Should -BeExactly $pin.Commit -Because $e.EffectId
            @($row.RelativeFiles).Count | Should -Be 1 -Because $e.EffectId
            @($row.RelativeFiles)[0] | Should -BeExactly $pin.Path -Because $e.EffectId
            @($row.DestinationFiles).Count | Should -Be 1 -Because $e.EffectId
            @($row.DestinationFiles)[0] | Should -BeExactly $pin.Path -Because $e.EffectId
            @($row.SHA256).Count | Should -Be 1 -Because $e.EffectId
            ([string]@($row.SHA256)[0]).ToUpperInvariant() | Should -BeExactly ([string]$pin.Sha).ToUpperInvariant() -Because $e.EffectId
            @($row.ByteLengths).Count | Should -Be 1 -Because $e.EffectId
            [int64]@($row.ByteLengths)[0] | Should -Be ([int64]$pin.Bytes) -Because $e.EffectId
            @($row.RequiredIncludes) | Should -Contain 'ReShade.fxh' -Because $e.EffectId
        }
    }

    It 'deploys the pinned crosire ReShade.fxh include for each new effect exactly as the index row says' {
        # Mutation: change the revision, SHA-256, byte length or source path of the ReShade.fxh RuntimeInclude block in Get-TpmReShadeApprovedEffectFilesForEffect.
        $pin = Get-Fix51IndexRow -Repository 'crosire/reshade-shaders' -Path 'Shaders/ReShade.fxh'
        foreach ($e in $script:Fix51Effects) {
            $include = @(Get-TpmReShadeApprovedEffectFiles -EffectId $e.EffectId | Where-Object { $_.Role -eq 'RuntimeInclude' -and $_.RelativePath -eq 'Shaders/TPM/ReShade.fxh' })
            $include.Count | Should -Be 1 -Because $e.EffectId
            $include[0].Repository | Should -BeExactly $pin.Repository
            $include[0].PinnedRevision | Should -BeExactly $pin.Commit
            $include[0].SourceRelativePath | Should -BeExactly $pin.Path
            ([string]$include[0].SHA256).ToUpperInvariant() | Should -BeExactly ([string]$pin.Sha).ToUpperInvariant()
            [int64]$include[0].ByteLength | Should -Be ([int64]$pin.Bytes)
            $include[0].Url | Should -BeExactly ('https://raw.githubusercontent.com/' + $pin.Repository + '/' + $pin.Commit + '/' + $pin.Path)
        }
    }

    It 'lists the five new rows in the approved catalog, which now has 25 effects with unique ids' {
        # Mutation: delete one of the five new rows from Get-TpmReShadeEffectCatalog (or add a sixth unreviewed row).
        $script:Fix51Catalog.Count | Should -Be 25
        @($script:Fix51Catalog | ForEach-Object { $_.EffectId } | Sort-Object -Unique).Count | Should -Be 25
        foreach ($e in $script:Fix51Effects) { @($script:Fix51Catalog | Where-Object { $_.EffectId -eq $e.EffectId }).Count | Should -Be 1 -Because $e.EffectId }
    }
}

Describe 'FIX51 allowlist of the new effects' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'allows exactly raw.githubusercontent.com and the pinned Matsilagi/RSRetroArch path prefix for each new effect' {
        # Mutation: add a second host to AllowedHosts, drop the trailing slash, or point AllowedPathPrefix at another repository or commit.
        foreach ($e in $script:Fix51Effects) {
            $row = Get-Fix51Row -EffectId $e.EffectId
            @($row.AllowedHosts).Count | Should -Be 1 -Because $e.EffectId
            @($row.AllowedHosts)[0] | Should -BeExactly 'raw.githubusercontent.com' -Because $e.EffectId
            $row.AllowedPathPrefix | Should -BeExactly ('/Matsilagi/RSRetroArch/' + $script:Fix51Commit + '/') -Because $e.EffectId
        }
    }

    It 'builds every effect file URL on that host and prefix, ending with the file name, and no specification uses another host' {
        # Mutation: build the URL from another host or commit, or let a notice/include specification point at a non-raw.githubusercontent.com host.
        foreach ($e in $script:Fix51Effects) {
            $specs = @(Get-TpmReShadeApprovedEffectFiles -EffectId $e.EffectId)
            $assets = @($specs | Where-Object { $_.Role -eq 'EffectAsset' })
            $assets.Count | Should -Be 1 -Because $e.EffectId
            $assets[0].Url | Should -BeExactly ('https://raw.githubusercontent.com/Matsilagi/RSRetroArch/' + $script:Fix51Commit + '/Shaders/' + $e.File) -Because $e.EffectId
            $assets[0].Url.EndsWith('/' + $e.File) | Should -BeTrue -Because $e.EffectId
            foreach ($spec in @($specs | Where-Object { $null -ne $_.Url })) {
                $uri = [Uri]$spec.Url
                $uri.Scheme | Should -BeExactly 'https' -Because ($e.EffectId + ' ' + $spec.RelativePath)
                $uri.Host | Should -BeExactly 'raw.githubusercontent.com' -Because ($e.EffectId + ' ' + $spec.RelativePath)
                [string]$uri.Query | Should -BeNullOrEmpty
                [string]$uri.Fragment | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'FIX51 technique names and uniform names' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'uses the expected technique name in the catalog row and the profile TechniqueOrder' {
        # Mutation: rename a TechniqueName in the catalog or in the profile's -Techniques (a technique that does not exist in the .fx makes ReShade load nothing).
        foreach ($e in $script:Fix51Effects) {
            (Get-Fix51Row -EffectId $e.EffectId).TechniqueName | Should -BeExactly $e.Technique -Because $e.EffectId
            $profileDef = Get-Fix51Profile -ProfileId $e.ProfileId
            (@($profileDef.TechniqueOrder) -join ',') | Should -BeExactly $e.Technique -Because $e.ProfileId
        }
    }

    It 'sets preset section names equal to the .fx file and only keys that the embedded uniform list declares (runs without the candidate folder)' {
        # Mutation: misspell one key in a Parameters table of Get-TpmReShadeProfiles (for example cornersize -> cornersize2) or name the section after another file.
        foreach ($e in $script:Fix51Effects) {
            $profileDef = Get-Fix51Profile -ProfileId $e.ProfileId
            @($profileDef.Parameters.Keys).Count | Should -Be 1 -Because $e.ProfileId
            @($profileDef.Parameters.Keys)[0] | Should -BeExactly $e.File -Because $e.ProfileId
            $sectionName = @($profileDef.Parameters.Keys)[0]
            @($profileDef.RequiredEffects) | Should -Contain $sectionName -Because $e.ProfileId
            foreach ($key in @($profileDef.Parameters[$e.File].Keys)) {
                @($e.Uniforms) | Should -Contain $key -Because ($e.ProfileId + ' key ' + $key)
            }
            foreach ($pair in @($e.Preset)) {
                @($e.Uniforms) | Should -Contain ($pair.Split('=')[0]) -Because ($e.ProfileId + ' literal ' + $pair)
            }
        }
    }

    It 'matches the saved candidate .fx bytes: pinned SHA-256 and length, technique, ReShade.fxh include and every preset key declared as a uniform (needs the saved candidate folder; skipped when it is absent)' -Skip:(-not $fix51CandidatesPresent) {
        # Mutation: pin a hash or length that is not the saved file, rename the technique, or use a preset key the file does not declare as a uniform.
        foreach ($e in $script:Fix51Effects) {
            $pin = Get-Fix51IndexRow -Repository 'Matsilagi/RSRetroArch' -Path $e.Path
            $bytes = [IO.File]::ReadAllBytes((Get-Fix51CandidatePath -IndexRow $pin))
            $bytes.Length | Should -Be ([int]$pin.Bytes) -Because $e.File
            (Get-Fix51BytesHash -Bytes $bytes) | Should -BeExactly ([string]$pin.Sha).ToUpperInvariant() -Because $e.File
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            [regex]::IsMatch($text, '(?m)^[ \t]*technique[ \t]+' + [regex]::Escape($e.Technique) + '\b') | Should -BeTrue -Because ($e.File + ' declares technique ' + $e.Technique)
            $text.Contains('#include "ReShade.fxh"') | Should -BeTrue -Because $e.File
            $declared = @([regex]::Matches($text, '(?m)^[ \t]*uniform[ \t]+\w+[ \t]+([A-Za-z_]\w*)[ \t]*(?:<|=|;)') | ForEach-Object { $_.Groups[1].Value })
            ((@($declared) | Sort-Object -Unique) -join ',') | Should -BeExactly ((@($e.Uniforms) | Sort-Object -Unique) -join ',') -Because ($e.File + ' embedded uniform list equals the file')
            $profileDef = Get-Fix51Profile -ProfileId $e.ProfileId
            foreach ($key in @($profileDef.Parameters[$e.File].Keys)) {
                [regex]::IsMatch($text, '(?m)^[ \t]*uniform[ \t]+\w+[ \t]+' + [regex]::Escape($key) + '\b') | Should -BeTrue -Because ($e.File + ' declares uniform ' + $key)
            }
        }
        $fxh = Get-Fix51IndexRow -Repository 'crosire/reshade-shaders' -Path 'Shaders/ReShade.fxh'
        $fxhBytes = [IO.File]::ReadAllBytes((Get-Fix51CandidatePath -IndexRow $fxh))
        $fxhBytes.Length | Should -Be ([int]$fxh.Bytes)
        (Get-Fix51BytesHash -Bytes $fxhBytes) | Should -BeExactly ([string]$fxh.Sha).ToUpperInvariant()
    }
}

Describe 'FIX51 license evidence of the new effects' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'offers each new effect: reviewed record, no gaps, evidence digest equal to the row digest' {
        # Mutation: remove a $table['RSRetroArch.CRT...'] evidence record, edit its PinDigest, or leave a license field (License/Attribution/SourceObligations) empty.
        $table = Get-TpmReShadeLicenseEvidenceTable
        foreach ($e in $script:Fix51Effects) {
            $row = Get-Fix51Row -EffectId $e.EffectId
            $status = Get-TpmReShadeEffectObligationStatus -Effect $row
            $status.Offerable | Should -BeTrue -Because $e.EffectId
            $status.ReviewStatus | Should -BeExactly 'REVIEWED' -Because $e.EffectId
            @($status.Gaps).Count | Should -Be 0 -Because $e.EffectId
            @($status.OutstandingItems).Count | Should -Be 0 -Because $e.EffectId
            $row.ObligationReview.Status | Should -BeExactly 'REVIEWED' -Because $e.EffectId
            $table.ContainsKey($e.EffectId) | Should -BeTrue -Because $e.EffectId
            ([string]$table[$e.EffectId].PinDigest).ToUpperInvariant() | Should -BeExactly (Get-TpmReShadeEffectPinDigest -Effect $row).ToUpperInvariant() -Because $e.EffectId
        }
    }

    It 'records 25 effects and 25 evidence records, one per effect' {
        # Mutation: add a catalog row without an evidence record (or the reverse).
        $table = Get-TpmReShadeLicenseEvidenceTable
        @($table.Keys).Count | Should -Be 25
        $script:Fix51Catalog.Count | Should -Be 25
        foreach ($row in $script:Fix51Catalog) { $table.ContainsKey([string]$row.EffectId) | Should -BeTrue -Because $row.EffectId }
    }

    It 'makes the review record EVIDENCE_INCOMPLETE with EVIDENCE_STALE when a bound pin, license, prefix or technique field of a new row changes' {
        # Mutation: take SHA256[0], ByteLengths[0], FileLicenses[0], AllowedPathPrefix or TechniqueName out of Get-TpmReShadeEffectPinDigest.
        foreach ($e in $script:Fix51Effects) {
            $base = Get-Fix51Row -EffectId $e.EffectId
            $clone = { $c = $base | Select-Object *; foreach ($p in 'RelativeFiles', 'DestinationFiles', 'SHA256', 'ByteLengths', 'FileLicenses', 'RequiredIncludes', 'RequiredTextures', 'AllowedHosts') { $c.$p = @($base.$p) }; $c.NoticeFiles = @($base.NoticeFiles | ForEach-Object { $_ | Select-Object * }); $c }
            $unchanged = & $clone
            (Get-TpmReShadeObligationReviewRecord -EffectId $e.EffectId -Effect $unchanged).Status | Should -BeExactly 'REVIEWED' -Because ($e.EffectId + ' control')
            $mutations = @(
                @{ Name = 'file hash'; Edit = { param($c) $c.SHA256[0] = ('A' * 64) } }
                @{ Name = 'byte length'; Edit = { param($c) $c.ByteLengths[0] = [int64]$c.ByteLengths[0] + 1 } }
                @{ Name = 'per-file license basis'; Edit = { param($c) $c.FileLicenses[0] = 'GPL-3.0' } }
                @{ Name = 'allowed path prefix'; Edit = { param($c) $c.AllowedPathPrefix = '/someone/else/' + ('1' * 40) + '/' } }
                @{ Name = 'technique'; Edit = { param($c) $c.TechniqueName = 'Other' } }
            )
            foreach ($case in $mutations) {
                $c = & $clone
                & $case.Edit $c
                $record = Get-TpmReShadeObligationReviewRecord -EffectId $e.EffectId -Effect $c
                $record.Status | Should -BeExactly 'EVIDENCE_INCOMPLETE' -Because ($e.EffectId + ' ' + $case.Name)
                ($record.OutstandingItems -join ' ') | Should -Match 'EVIDENCE_STALE' -Because ($e.EffectId + ' ' + $case.Name)
            }
        }
    }

    It 'generates a NOTICE.txt specification for each new effect' {
        # Mutation: skip the generated NOTICE.txt block in Get-TpmReShadeApprovedEffectFilesForEffect, or put non-ASCII text into Get-TpmReShadeEffectNoticeBytes.
        foreach ($e in $script:Fix51Effects) {
            $notice = @(Get-TpmReShadeApprovedEffectFiles -EffectId $e.EffectId | Where-Object { $_.RelativePath -eq ('Shaders/TPM/Notices/' + $e.EffectId + '/NOTICE.txt') })
            $notice.Count | Should -Be 1 -Because $e.EffectId
            $notice[0].Role | Should -BeExactly 'LicenseNotice'
            $notice[0].InlineBytes | Should -Not -BeNullOrEmpty
            [int64]$notice[0].ByteLength | Should -Be ([int64]@($notice[0].InlineBytes).Count)
            [Text.Encoding]::ASCII.GetString([byte[]]$notice[0].InlineBytes) | Should -Match ([regex]::Escape($e.EffectId))
        }
    }

    It 'copies the GPL-2.0 text (the CRT-Pi notice pin) for the four GPL effects and no license copy for Hyllian (MIT, in-file notice)' {
        # Mutation: change the notice SHA-256 or byte length, drop the NoticeFiles entry of a GPL row, or give Hyllian a notice copy / another FileLicenses value.
        foreach ($e in $script:Fix51Effects) {
            $row = Get-Fix51Row -EffectId $e.EffectId
            @($row.FileLicenses).Count | Should -Be 1 -Because $e.EffectId
            @($row.FileLicenses)[0] | Should -BeExactly $e.License -Because $e.EffectId
            $specs = @(Get-TpmReShadeApprovedEffectFiles -EffectId $e.EffectId)
            $copies = @($specs | Where-Object { $_.RelativePath -like 'Shaders/TPM/Notices/*/GPL-2.0.txt' })
            if ($e.GplCopy) {
                @($row.NoticeFiles).Count | Should -Be 1 -Because $e.EffectId
                $copies.Count | Should -Be 1 -Because $e.EffectId
                $copies[0].RelativePath | Should -BeExactly ('Shaders/TPM/Notices/' + $e.EffectId + '/GPL-2.0.txt')
                $copies[0].Role | Should -BeExactly 'LicenseNotice'
                ([string]$copies[0].SHA256).ToUpperInvariant() | Should -BeExactly $script:Fix51GplNoticeSha
                [int64]$copies[0].ByteLength | Should -Be ([int64]$script:Fix51GplNoticeBytes)
                @($specs).Count | Should -Be 4 -Because ($e.EffectId + ' effect file, GPL text, NOTICE.txt, ReShade.fxh')
            } else {
                @($row.NoticeFiles).Count | Should -Be 0 -Because $e.EffectId
                $copies.Count | Should -Be 0 -Because $e.EffectId
                $row.License | Should -BeExactly 'MIT'
                @($specs).Count | Should -Be 3 -Because ($e.EffectId + ' effect file, NOTICE.txt, ReShade.fxh')
            }
        }
    }

    It 'matches the pinned CRT-Pi license copy exactly (same hash and length as the existing row)' {
        # Mutation: point a new row at a different license file than the one already verified for CRT-Pi.
        $pi = @((Get-Fix51Row -EffectId 'RSRetroArch.CRTPi').NoticeFiles)[0]
        ([string]$pi.SHA256).ToUpperInvariant() | Should -BeExactly $script:Fix51GplNoticeSha
        [int64]$pi.ByteLength | Should -Be ([int64]$script:Fix51GplNoticeBytes)
        foreach ($e in @($script:Fix51Effects | Where-Object { $_.GplCopy })) {
            $copy = @((Get-Fix51Row -EffectId $e.EffectId).NoticeFiles)[0]
            $copy.Repository | Should -BeExactly $pi.Repository
            $copy.PinnedCommit | Should -BeExactly $pi.PinnedCommit
            $copy.SourceRelativePath | Should -BeExactly $pi.SourceRelativePath
            ([string]$copy.SHA256).ToUpperInvariant() | Should -BeExactly ([string]$pi.SHA256).ToUpperInvariant()
            [int64]$copy.ByteLength | Should -Be ([int64]$pi.ByteLength)
        }
    }

    It 'records the evidence row count of each new effect equal to its specification count' {
        # Mutation: change PinnedRows in a new evidence record without changing the specifications (3 for Hyllian, 4 for the four GPL effects).
        $table = Get-TpmReShadeLicenseEvidenceTable
        foreach ($e in $script:Fix51Effects) {
            $specCount = @(Get-TpmReShadeApprovedEffectFiles -EffectId $e.EffectId).Count
            [int]$table[$e.EffectId].PinnedRows | Should -Be $specCount -Because $e.EffectId
            [int]$table[$e.EffectId].PinnedRowsVerified | Should -Be $specCount -Because $e.EffectId
        }
    }
}

Describe 'FIX51 CRT effects conflict with every other CRT and with sharpen and color alternatives' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'marks every pair of the eight CRT effects as conflicting in both directions in the catalog' {
        # Mutation: remove one of the new ids from $crtIds in Get-TpmReShadeEffectCatalog.
        $crtIds = @($script:Fix51OldCrtIds) + @($script:Fix51Effects | ForEach-Object { $_.EffectId })
        $crtIds.Count | Should -Be 8
        foreach ($a in $crtIds) {
            foreach ($b in $crtIds) {
                if ($a -eq $b) { continue }
                @((Get-Fix51Row -EffectId $a).ConflictsWith) | Should -Contain $b -Because ($a + ' conflicts with ' + $b)
            }
        }
    }

    It 'rejects a stack of two CRT effects in every pair, old and new, and accepts a single new CRT' {
        # Mutation: make Resolve-TpmReShadeEffectStack ignore ConflictsWith, or drop a new id from $crtIds.
        $crtIds = @($script:Fix51OldCrtIds) + @($script:Fix51Effects | ForEach-Object { $_.EffectId })
        for ($i = 0; $i -lt $crtIds.Count; $i++) {
            for ($j = $i + 1; $j -lt $crtIds.Count; $j++) {
                (Resolve-TpmReShadeEffectStack -EffectIds @($crtIds[$i], $crtIds[$j])).Valid | Should -BeFalse -Because ($crtIds[$i] + ' then ' + $crtIds[$j])
                (Resolve-TpmReShadeEffectStack -EffectIds @($crtIds[$j], $crtIds[$i])).Valid | Should -BeFalse -Because ($crtIds[$j] + ' then ' + $crtIds[$i])
            }
        }
        foreach ($id in $crtIds) { (Resolve-TpmReShadeEffectStack -EffectIds @($id)).Valid | Should -BeTrue -Because $id }
    }

    It 'rejects each new CRT together with a sharpen effect or a color-strength alternative, in both orders' {
        # Mutation: remove $sharpenIds or $colorAlternativeIds from the CRT conflict line in Get-TpmReShadeEffectCatalog.
        foreach ($e in $script:Fix51Effects) {
            foreach ($other in @('SweetFX.LumaSharpen', 'SweetFX.CAS', 'SweetFX.Vibrance')) {
                (Resolve-TpmReShadeEffectStack -EffectIds @($e.EffectId, $other)).Valid | Should -BeFalse -Because ($e.EffectId + ' then ' + $other)
                (Resolve-TpmReShadeEffectStack -EffectIds @($other, $e.EffectId)).Valid | Should -BeFalse -Because ($other + ' then ' + $e.EffectId)
            }
        }
    }

    It 'still allows a new CRT with glow, contrast and black/white effects (the conflict is not over-broad)' {
        # Mutation: add glow, contrast or levels ids to the CRT conflict list.
        foreach ($e in $script:Fix51Effects) {
            (Resolve-TpmReShadeEffectStack -EffectIds @($e.EffectId, 'FXShaders.ArcaneBloom')).Valid | Should -BeTrue -Because $e.EffectId
            (Resolve-TpmReShadeEffectStack -EffectIds @('SweetFX.Levels', $e.EffectId)).Valid | Should -BeTrue -Because $e.EffectId
        }
    }
}

Describe 'FIX51 profile list' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'lists exactly the 17 contract ids in the contract order, 16 profiles besides Original and never fewer than 10' {
        # Mutation: reorder, add, remove or rename a profile in Get-TpmReShadeProfiles.
        @($script:Fix51Profiles | ForEach-Object { $_.ProfileId }) | Should -Be $script:Fix51ProfileOrder
        $script:Fix51Profiles.Count | Should -Be 17
        $others = @($script:Fix51Profiles | Where-Object { $_.ProfileId -ne 'Original' })
        $others.Count | Should -BeGreaterOrEqual 10
        $others.Count | Should -Be 16
        @($script:Fix51Profiles | ForEach-Object { $_.FriendlyName } | Sort-Object -Unique).Count | Should -Be 17
    }

    It 'offers no retired profile id' {
        # Mutation: re-add a profile whose id is listed by Get-TpmReShadeRetiredProfiles (for example Vivid or CleanSharp).
        $ids = @($script:Fix51Profiles | ForEach-Object { $_.ProfileId })
        foreach ($retired in @(Get-TpmReShadeRetiredProfiles)) { $ids | Should -Not -Contain $retired.ProfileId -Because $retired.ProfileId }
    }

    It 'gives every non-Original profile a group, cost class, description, approved effects and pins whose counts match' {
        # Mutation: empty a Description, use a Group other than Crt/Main, a PerformanceClass other than LOW/MEDIUM/HIGH, or an effect id that is not in the catalog.
        foreach ($p in @($script:Fix51Profiles | Where-Object { $_.ProfileId -ne 'Original' })) {
            $p.Group | Should -BeIn @('Crt', 'Main') -Because $p.ProfileId
            $p.PerformanceClass | Should -BeIn @('LOW', 'MEDIUM', 'HIGH') -Because $p.ProfileId
            [string]$p.Description | Should -Not -BeNullOrEmpty -Because $p.ProfileId
            @($p.Effects).Count | Should -BeGreaterThan 0 -Because $p.ProfileId
            foreach ($id in @($p.Effects)) {
                $row = Get-Fix51Row -EffectId $id
                $row | Should -Not -BeNullOrEmpty -Because ($p.ProfileId + ' ' + $id)
                @($row.SHA256).Count | Should -BeGreaterThan 0 -Because $id
                foreach ($hash in @($row.SHA256)) { [string]$hash | Should -Match '^[0-9A-Fa-f]{64}$' -Because $id }
                @($row.ByteLengths).Count | Should -Be @($row.SHA256).Count -Because $id
                @($row.ByteLengths).Count | Should -Be @($row.RelativeFiles).Count -Because $id
            }
        }
        @(Get-Fix51Profile -ProfileId 'Original').Count | Should -Be 1
        @((Get-Fix51Profile -ProfileId 'Original').Effects).Count | Should -Be 0
    }

    It 'uses only arcade display, lighting, anti-aliasing and contrast effects: no sharpen-only, color-only, HDR-only, AO or depth-of-field profile' {
        # Mutation: put a SHARPNESS, COLOR, HDR, AO or depth-of-field effect into any profile's -Effects.
        foreach ($p in @($script:Fix51Profiles | Where-Object { $_.ProfileId -ne 'Original' })) {
            foreach ($id in @($p.Effects)) {
                (Get-Fix51Row -EffectId $id).Category | Should -BeIn @('ARCADE DISPLAY', 'LIGHTING', 'ANTI-ALIASING', 'CONTRAST') -Because ($p.ProfileId + ' ' + $id)
            }
            $p.RequiresHdr | Should -BeFalse -Because $p.ProfileId
        }
    }

    It 'uses exactly 12 of the 25 effects across the profiles' {
        # Mutation: leave a new effect unused by every profile, or use an extra approved effect.
        $used = @($script:Fix51Profiles | ForEach-Object { $_.Effects } | Sort-Object -Unique)
        $used | Should -Be @('Akgunter.CRTRoyale', 'FXShaders.ArcaneBloom', 'FXShaders.CRT_Lottes', 'RSRetroArch.CRTAperture', 'RSRetroArch.CRTEasymode', 'RSRetroArch.CRTGeom', 'RSRetroArch.CRTHyllian', 'RSRetroArch.CRTPi', 'RSRetroArch.CRTZFast', 'SweetFX.Curves', 'SweetFX.Levels', 'SweetFX.SMAA')
        $used.Count | Should -Be 12
    }

    It 'defines the five new profiles exactly as the contract table says' {
        # Mutation: change a friendly or technical name, group, cost class, fallback, effect, file or technique of a new profile.
        foreach ($e in $script:Fix51Effects) {
            $p = Get-Fix51Profile -ProfileId $e.ProfileId
            $p | Should -Not -BeNullOrEmpty -Because $e.ProfileId
            $p.FriendlyName | Should -BeExactly $e.Friendly -Because $e.ProfileId
            $p.TechnicalName | Should -BeExactly $e.Technical -Because $e.ProfileId
            $p.Group | Should -BeExactly 'Crt' -Because $e.ProfileId
            $p.PerformanceClass | Should -BeExactly $e.Cost -Because $e.ProfileId
            $p.FallbackProfileId | Should -BeExactly $e.Fallback -Because $e.ProfileId
            (@($p.Effects) -join ',') | Should -BeExactly $e.EffectId -Because $e.ProfileId
            (@($p.RequiredEffects) -join ',') | Should -BeExactly $e.File -Because $e.ProfileId
            (@($p.TechniqueOrder) -join ',') | Should -BeExactly $e.Technique -Because $e.ProfileId
            $p.DisplayLabel | Should -BeExactly ($e.Friendly + ' [' + $e.Technical + ']') -Because $e.ProfileId
        }
    }

    It 'gives each new profile a preview note that says the preview is an approximation, and no user-visible text says TPM' {
        # Mutation: empty a new profile's PreviewNote, drop the word approximation from it, or write TPM instead of TeknoParrot Manager.
        foreach ($e in $script:Fix51Effects) {
            $p = Get-Fix51Profile -ProfileId $e.ProfileId
            [string]$p.PreviewNote | Should -Not -BeNullOrEmpty -Because $e.ProfileId
            [string]$p.PreviewNote | Should -Match 'approximation' -Because $e.ProfileId
            [string]$p.PreviewNote | Should -Match 'TeknoParrot Manager' -Because $e.ProfileId
            foreach ($text in @([string]$p.PreviewNote, [string]$p.Description, [string]$p.FriendlyName)) { $text | Should -Not -Match '\bTPM\b' -Because $e.ProfileId }
        }
    }

    It 'does not offer MAMEPostProc, ColorMAME, scanlines-abs, FXAA, a LUT, CRT-Guest-Advanced or the unverified Sony CRT shader in any effect, file, technique or profile' {
        # Mutation: add a catalog row, file or profile for one of these (they have no verifiable pinned source or license basis, or do nothing).
        $pattern = '(?i)MAME|scanlines-abs|FXAA|\bLUT\b|LUT\.fx|lut\.png|Guest|Mega(?:tron)'
        # The approved (never offered) Lilium HDR rows legitimately carry the include file below (an HDR10 conversion helper, not a color-grading
        # LUT); exactly that file of exactly those rows is exempt, every other text of every row and every profile text is still checked.
        $liliumInclude = 'Shaders/lilium__include/colour_space/hdr10_to_linear_lut.fxh'
        foreach ($row in $script:Fix51Catalog) {
            foreach ($text in @(@($row.EffectId) + @($row.FriendlyName) + @($row.RelativeFiles) + @($row.DestinationFiles) + @($row.RequiredTextures) + @($row.TechniqueName))) {
                if (([string]$row.EffectId).StartsWith('Lilium.', [System.StringComparison]::Ordinal) -and [string]$text -ceq $liliumInclude) { continue }
                [string]$text | Should -Not -Match $pattern -Because ('catalog ' + $row.EffectId)
            }
        }
        foreach ($p in $script:Fix51Profiles) {
            foreach ($text in @(@($p.ProfileId) + @($p.FriendlyName) + @($p.TechnicalName) + @($p.Description) + @($p.RequiredEffects) + @($p.TechniqueOrder) + @($p.Effects))) {
                [string]$text | Should -Not -Match $pattern -Because ('profile ' + $p.ProfileId)
            }
        }
    }
}

Describe 'FIX51 generated presets' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'writes exactly one section named after the .fx file with the contract key=value set for each new profile, and valid numeric values' {
        # Mutation: change a value or key in a Parameters table, emit a second section, write the section before the flat lines, or name it after another file.
        foreach ($e in $script:Fix51Effects) {
            $p = Get-Fix51Profile -ProfileId $e.ProfileId
            $content = New-TpmReShadePresetContent -ProfileDefinition $p
            (Test-TpmReShadePresetContent -Content $content -ProfileDefinition $p) | Should -BeTrue -Because $e.ProfileId
            $content | Should -Match ('(?m)^Techniques=' + [regex]::Escape($e.Technique) + '\r?$') -Because $e.ProfileId
            $content | Should -Match ('(?m)^TechniqueSorting=' + [regex]::Escape($e.Technique) + '\r?$') -Because $e.ProfileId
            $parts = Get-Fix51PresetParts -Content $content
            @($parts.Headers).Count | Should -Be 1 -Because $e.ProfileId
            @($parts.Headers)[0] | Should -BeExactly $e.File -Because $e.ProfileId
            $lines = @($content -split "`r?`n")
            ([array]::IndexOf($lines, '[' + $e.File + ']')) | Should -BeGreaterThan ([array]::IndexOf(@($lines), ('TechniqueSorting=' + $e.Technique))) -Because ($e.ProfileId + ' section after the flat lines')
            $actual = @($parts.Sections[$e.File])
            (@($actual | Sort-Object) -join ' ') | Should -BeExactly ((@($e.Preset) | Sort-Object) -join ' ') -Because $e.ProfileId
            foreach ($line in $actual) { $line | Should -Match '^[A-Za-z_][A-Za-z0-9_]*=-?[0-9]+(?:\.[0-9]+)?$' -Because ($e.ProfileId + ' ' + $line) }
        }
    }

    It 'writes ASCII only, and the product validator rejects a foreign section, a non-numeric value and non-ASCII text' {
        # Mutation: weaken the section/value checks in Test-TpmReShadePresetContent, or write a non-ASCII character into a preset.
        foreach ($e in $script:Fix51Effects) {
            $p = Get-Fix51Profile -ProfileId $e.ProfileId
            $content = New-TpmReShadePresetContent -ProfileDefinition $p
            $content | Should -Not -Match '[^\x09\x0A\x0D\x20-\x7E]' -Because $e.ProfileId
            ([Text.Encoding]::ASCII.GetString([Text.Encoding]::ASCII.GetBytes($content))) | Should -BeExactly $content -Because $e.ProfileId
            (Test-TpmReShadePresetContent -Content ($content + "[CRTPi.fx]`r`nx=1`r`n") -ProfileDefinition $p) | Should -BeFalse -Because ($e.ProfileId + ' foreign section')
            $firstKey = @($e.Preset)[0].Split('=')[0]
            (Test-TpmReShadePresetContent -Content ($content -replace ('(?m)^' + [regex]::Escape($firstKey) + '=.*$'), ($firstKey + '=abc')) -ProfileDefinition $p) | Should -BeFalse -Because ($e.ProfileId + ' non-numeric value')
            (Test-TpmReShadePresetContent -Content ($content + '; caf' + [char]0x00E9 + "`r`n") -ProfileDefinition $p) | Should -BeFalse -Because ($e.ProfileId + ' non-ASCII')
        }
    }

    It 'keeps . decimals when the current culture uses a decimal comma (de-DE)' {
        # Mutation: store a Parameters value as a number instead of a string, or format with the current culture.
        $previous = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            $invariant = @{}
            foreach ($e in $script:Fix51Effects) { $invariant[$e.ProfileId] = New-TpmReShadePresetContent -ProfileDefinition (Get-Fix51Profile -ProfileId $e.ProfileId) }
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
            (1.5).ToString() | Should -BeExactly '1,5' -Because 'the culture switch must be in effect for this check to mean anything'
            foreach ($e in $script:Fix51Effects) {
                $content = New-TpmReShadePresetContent -ProfileDefinition (Get-Fix51Profile -ProfileId $e.ProfileId)
                $content | Should -BeExactly $invariant[$e.ProfileId] -Because $e.ProfileId
                $decimalPairs = @($e.Preset | Where-Object { $_ -match '=\d+\.\d+$' })
                $decimalPairs.Count | Should -BeGreaterThan 0 -Because $e.ProfileId
                foreach ($pair in $decimalPairs) { $content | Should -Match ('(?m)^' + [regex]::Escape($pair) + '\r?$') -Because ($e.ProfileId + ' ' + $pair) }
                $content | Should -Not -Match '(?m)^[A-Za-z_][A-Za-z0-9_]*=-?[0-9]+,[0-9]+\r?$' -Because $e.ProfileId
            }
        } finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }

    It 'writes no section for the profiles that existed before, and keeps their techniques valid' {
        # Mutation: give an older profile a non-empty Parameters table, or emit a section header for an empty table.
        $newIds = @($script:Fix51Effects | ForEach-Object { $_.ProfileId })
        foreach ($p in @($script:Fix51Profiles | Where-Object { $newIds -notcontains $_.ProfileId })) {
            @($p.Parameters.Keys).Count | Should -Be 0 -Because $p.ProfileId
            $content = New-TpmReShadePresetContent -ProfileDefinition $p
            $content | Should -Not -Match '(?m)^\[' -Because $p.ProfileId
            (Test-TpmReShadePresetContent -Content $content -ProfileDefinition $p) | Should -BeTrue -Because $p.ProfileId
        }
    }
}

Describe 'FIX51 preview approximation (needs System.Drawing; skipped when it cannot create a bitmap)' -Skip:(-not $fix51CanDraw) {
    BeforeAll {
        Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog }
        $script:Fix51Renders = @{}
        $script:Fix51Renders['Original'] = Get-Fix51Render -ProfileDefinition $null
        foreach ($p in @($script:Fix51Profiles | Where-Object { $_.ProfileId -ne 'Original' })) { $script:Fix51Renders[$p.ProfileId] = Get-Fix51Render -ProfileDefinition $p }
        $script:Fix51RenderTwice = @{}
        foreach ($e in $script:Fix51Effects) { $script:Fix51RenderTwice[$e.ProfileId] = Get-Fix51Render -ProfileDefinition (Get-Fix51Profile -ProfileId $e.ProfileId) }
    }

    It 'returns the contract CRT kind and companion settings for each new profile' {
        # Mutation: change a Crt kind, the Aperture Glow (0.30), the Easymode LevelsGain (1.08) or the Hyllian Saturation (1.15) / LevelsGain (1.06) in Get-TpmReShadePreviewApproximationSettings.
        foreach ($e in $script:Fix51Effects) {
            $s = Get-TpmReShadePreviewApproximationSettings -ProfileDefinition (Get-Fix51Profile -ProfileId $e.ProfileId)
            $s | Should -Not -BeNullOrEmpty -Because $e.ProfileId
            $s.Crt | Should -BeExactly $e.Kind -Because $e.ProfileId
            [double]$s.Glow | Should -Be ([double]$e.Glow) -Because $e.ProfileId
            [double]$s.LevelsGain | Should -Be ([double]$e.LevelsGain) -Because $e.ProfileId
            [double]$s.Saturation | Should -Be ([double]$e.Saturation) -Because $e.ProfileId
        }
    }

    It 'changes more pixels than the NO_CONTENT_CHANGE threshold for each new profile' {
        # Mutation: make a new profile's approximation a no-op (default branch, empty Crt kind or the early return).
        foreach ($e in $script:Fix51Effects) {
            (Get-Fix51DiffCount -Left $script:Fix51Renders['Original'].Bytes -Right $script:Fix51Renders[$e.ProfileId].Bytes) | Should -BeGreaterThan $script:Fix51MinChangedPixels -Because $e.ProfileId
        }
    }

    It 'renders each new profile differently from Original and from every other profile' {
        # Mutation: make two Crt kinds share one branch of Invoke-TpmReShadePreviewProfilePixels (for example Hyllian and Geom).
        foreach ($e in $script:Fix51Effects) {
            $script:Fix51Renders[$e.ProfileId].Hash | Should -Not -BeExactly $script:Fix51Renders['Original'].Hash -Because $e.ProfileId
            foreach ($other in @($script:Fix51Renders.Keys | Where-Object { $_ -ne $e.ProfileId -and $_ -ne 'Original' })) {
                $script:Fix51Renders[$e.ProfileId].Hash | Should -Not -BeExactly $script:Fix51Renders[$other].Hash -Because ($e.ProfileId + ' versus ' + $other)
            }
        }
    }

    It 'renders the same bytes twice for each new profile (no time or random input)' {
        # Mutation: add a random or time-dependent term to the renderer.
        foreach ($e in $script:Fix51Effects) {
            $script:Fix51RenderTwice[$e.ProfileId].Hash | Should -BeExactly $script:Fix51Renders[$e.ProfileId].Hash -Because $e.ProfileId
        }
    }

    It 'blacks the four corners of the curved monitor and keeps its center lit, while a flat CRT keeps its corners' {
        # Mutation: remove the corner test in the Geom branch of Invoke-TpmReShadePreviewProfilePixels, or let the other kinds black their corners.
        $curved = $script:Fix51Renders['CurvedArcadeMonitor']
        @($curved.Corners).Count | Should -Be 4
        foreach ($corner in @($curved.Corners)) { (Test-Fix51Black -Color $corner) | Should -BeTrue }
        (Test-Fix51Black -Color $curved.Center) | Should -BeFalse
        foreach ($id in @('SharpApertureGrille', 'EasymodeCrt', 'HyllianCrt', 'FastCrt', 'Original')) {
            @($script:Fix51Renders[$id].Corners | Where-Object { Test-Fix51Black -Color $_ }).Count | Should -Be 0 -Because $id
        }
    }
}

Describe 'FIX51 chooser text: rough cost of the new profiles' {
    BeforeAll { Mock Get-TpmReShadeEffectCatalog { $script:Fix51Catalog } }

    It 'shows light for Fast CRT and medium for the four medium profiles in the cost text, the menu description rows and the preview description' {
        # Mutation: change a new profile's -Cost, or the LOW/MEDIUM/HIGH mapping in Get-TpmReShadePerformanceBadge, or drop the ' Cost: ' suffix of the menu row.
        $lines = @(Get-TpmReShadeTerminalMenuLines -Selectable @($script:Fix51Profiles) -Selected $null)
        foreach ($e in $script:Fix51Effects) {
            $p = Get-Fix51Profile -ProfileId $e.ProfileId
            (Get-TpmReShadeProfileCostText -ProfileDefinition $p) | Should -BeExactly $e.CostWord -Because $e.ProfileId
            $titleIndex = -1
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Kind -eq 'Title' -and $lines[$i].ProfileId -eq $e.ProfileId) { $titleIndex = $i; break } }
            $titleIndex | Should -BeGreaterOrEqual 0 -Because ($e.ProfileId + ' is listed in the chooser')
            $lines[$titleIndex].Text | Should -Match ('^\s*\[' + ([array]::IndexOf($script:Fix51ProfileOrder, $e.ProfileId) + 1) + '\] ') -Because ($e.ProfileId + ' numbered in contract order')
            $lines[$titleIndex].Text | Should -BeExactly ('  [' + ([array]::IndexOf($script:Fix51ProfileOrder, $e.ProfileId) + 1) + ']   ' + $e.Friendly + ' [' + $e.Technical + ']') -Because $e.ProfileId
            $lines[$titleIndex + 1].Text | Should -BeExactly ('      ' + $p.Description + ' Cost: ' + $e.CostWord + '.') -Because $e.ProfileId
            $text = Get-TpmReShadeDescriptionText -ProfileDefinition $p
            $text | Should -Match ('(?m)^Performance cost: ' + $e.CostWord + ' \(rough estimate, not measured\)\.\r?$') -Because $e.ProfileId
            $text | Should -Not -Match '\bTPM\b' -Because $e.ProfileId
        }
        (Get-TpmReShadeProfileCostText -ProfileDefinition (Get-Fix51Profile -ProfileId 'Original')) | Should -BeExactly ''
    }
}
