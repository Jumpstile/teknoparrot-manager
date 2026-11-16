#Requires -Module Pester
# FIX74: the ReShade profile gallery window (menu 5) was transiently drawn wrongly while the user switched profiles. The fix is repaint-only:
# double-buffering, one layout pass and one repaint per refresh with the new bitmap built before it is swapped in, and coalescing of rapid
# profile changes. The settled layout (texts, sizes, buttons, colors) is unchanged and is NOT pinned again here.
# The behavior tests below run the product's own refresh scriptblocks (extracted from the production file with the parser) against fake form
# and picture objects; nothing touches a real window, TeknoParrot, LaunchBox, the registry, services or the network. The one test that needs a
# real WinForms control skips cleanly when the session is not Windows, interactive and STA.
# What this CANNOT prove: that the corruption is gone on screen. That needs a person looking at the real window on a real desktop.

$fix74CanUseForms = $false
try {
    if ([Environment]::OSVersion.Platform -eq 'Win32NT' -and [Environment]::UserInteractive -and [Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $fix74CanUseForms = $true
    }
} catch { $fix74CanUseForms = $false }

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:fix74Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX74 bootstrap could not parse the production script.' }
    $functionAsts = @($script:fix74Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $galleryAst = @($functionAsts | Where-Object { $_.Name -eq 'Show-TpmReShadeProfileGalleryWindow' })[0]
    $helperAst = @($functionAsts | Where-Object { $_.Name -eq 'Set-TpmReShadeControlDoubleBuffered' })[0]
    if (-not $galleryAst) { throw 'FIX74 bootstrap could not find Show-TpmReShadeProfileGalleryWindow.' }
    if (-not $helperAst) { throw 'FIX74 bootstrap could not find Set-TpmReShadeControlDoubleBuffered.' }
    $script:fix74GalleryText = $galleryAst.Extent.Text
    $script:fix74HelperText = $helperAst.Extent.Text
    $assignments = @($galleryAst.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
    $script:fix74RefreshOnceText = @($assignments | Where-Object { $_.Left.Extent.Text -eq '$refreshOnce' })[0].Extent.Text
    $script:fix74RefreshText = @($assignments | Where-Object { $_.Left.Extent.Text -eq '$refresh' })[0].Extent.Text
    if ([string]::IsNullOrWhiteSpace($script:fix74RefreshOnceText) -or [string]::IsNullOrWhiteSpace($script:fix74RefreshText)) { throw 'FIX74 bootstrap could not find the refresh scriptblocks.' }

    $helperFile = Join-Path $TestDrive 'fix74-helper.ps1'
    Set-Content -LiteralPath $helperFile -Value $script:fix74HelperText -Encoding utf8
    . $helperFile

    # Stand-ins for the product helpers the refresh scriptblocks call. They are global because a closure runs in its own module scope and only
    # sees global functions; they are removed again (and any pre-existing global of the same name is put back) in AfterAll.
    $script:fix74SavedFunctions = @{}
    foreach ($name in @('Set-TpmReShadeDescriptionLabel', 'Get-TpmReShadeDescriptionText', 'Get-TpmReShadePreviewProcessedBitmap', 'New-TpmReShadePreviewBitmapFromCache')) {
        $existing = Get-Item -LiteralPath ('Function:\' + $name) -ErrorAction SilentlyContinue
        $script:fix74SavedFunctions[$name] = if ($null -ne $existing) { $existing.ScriptBlock } else { $null }
    }
    $script:fix74SavedVariables = @{}
    foreach ($name in @('Fix74Log', 'Fix74OnProcess', 'Fix74FailRender', 'Fix74State')) {
        $existing = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
        $script:fix74SavedVariables[$name] = [pscustomobject]@{ Exists = ($null -ne $existing); Value = $(if ($null -ne $existing) { $existing.Value } else { $null }) }
    }
    $global:Fix74Log = New-Object 'System.Collections.Generic.List[string]'
    $global:Fix74OnProcess = $null
    $global:Fix74FailRender = $false
    function global:Set-TpmReShadeDescriptionLabel { param($Label, $Text, $State) $global:Fix74Log.Add('Label:' + $Text) }
    function global:Get-TpmReShadeDescriptionText { param($ProfileDefinition) return ('desc-' + $ProfileDefinition.ProfileId) }
    function global:Get-TpmReShadePreviewProcessedBitmap {
        param($Cache, $ProfileDefinition)
        $global:Fix74Log.Add('Process:' + $ProfileDefinition.ProfileId)
        if ($global:Fix74OnProcess) { & $global:Fix74OnProcess $ProfileDefinition.ProfileId }
        return $null
    }
    function global:New-TpmReShadePreviewBitmapFromCache {
        param($Cache, $ProfileDefinition, $Mode)
        if ($global:Fix74FailRender) { throw 'forced render failure' }
        $global:Fix74Log.Add('Build:' + $ProfileDefinition.ProfileId + '/' + $Mode)
        $bitmap = [pscustomobject]@{ Name = ($ProfileDefinition.ProfileId + '/' + $Mode) }
        Add-Member -InputObject $bitmap -MemberType ScriptMethod -Name Dispose -Value { $global:Fix74Log.Add('Dispose:' + $this.Name) }
        return $bitmap
    }

    function New-Fix74Bitmap {
        param([string]$Name)
        $bitmap = [pscustomobject]@{ Name = $Name }
        Add-Member -InputObject $bitmap -MemberType ScriptMethod -Name Dispose -Value { $global:Fix74Log.Add('Dispose:' + $this.Name) }
        return $bitmap
    }

    # Builds the product's real $refreshOnce / $refresh scriptblocks around fake form and picture objects that log every layout and paint call.
    function New-Fix74Harness {
        param([string]$ViewMode = 'Split', [string]$InitialImageName = 'old-image')
        $global:Fix74Log.Clear()
        $global:Fix74OnProcess = $null
        $global:Fix74FailRender = $false
        $form = [pscustomobject]@{}
        Add-Member -InputObject $form -MemberType ScriptMethod -Name SuspendLayout -Value { $global:Fix74Log.Add('Suspend') }
        Add-Member -InputObject $form -MemberType ScriptMethod -Name ResumeLayout -Value { param($performLayout) $global:Fix74Log.Add('Resume:' + $performLayout) }
        Add-Member -InputObject $form -MemberType ScriptMethod -Name PerformLayout -Value { $global:Fix74Log.Add('Perform') }
        $picture = [pscustomobject]@{ ImageValue = (New-Fix74Bitmap -Name $InitialImageName) }
        Add-Member -InputObject $picture -MemberType ScriptProperty -Name Image -Value { $this.ImageValue } -SecondValue {
            $newValue = $args[0]
            $global:Fix74Log.Add('Image=' + $(if ($null -eq $newValue) { '<null>' } else { $newValue.Name }))
            $this.ImageValue = $newValue
        }
        Add-Member -InputObject $picture -MemberType ScriptMethod -Name Invalidate -Value { $global:Fix74Log.Add('Invalidate') }
        Add-Member -InputObject $picture -MemberType ScriptMethod -Name Update -Value { $global:Fix74Log.Add('Update') }
        $descriptionLabel = [pscustomobject]@{}
        $state = [hashtable]::Synchronized(@{
            SelectedProfileId = 'A'
            Profiles = @([pscustomobject]@{ ProfileId = 'A' }, [pscustomobject]@{ ProfileId = 'B' }, [pscustomobject]@{ ProfileId = 'C' })
            ViewMode = $ViewMode
            SliderPosition = 50
            Initialized = $true
            PreviewEnabled = $true
            Closed = $false
            PreviewCache = $null
            Profile = $null
            RefreshRunning = $false
            RefreshPendingProfileId = $null
        })
        $scriptFile = Join-Path $TestDrive ('fix74-refresh-' + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $scriptFile -Value ($script:fix74RefreshOnceText + "`r`n" + $script:fix74RefreshText) -Encoding utf8
        . $scriptFile
        $state['Refresh'] = $refresh
        $global:Fix74State = $state
        return [pscustomobject]@{ State = $state; Form = $form; Picture = $picture; Refresh = $refresh }
    }
}

AfterAll {
    # Put back exactly what the caller had: a stand-in is removed, a pre-existing global function or variable is restored.
    foreach ($name in @('Set-TpmReShadeDescriptionLabel', 'Get-TpmReShadeDescriptionText', 'Get-TpmReShadePreviewProcessedBitmap', 'New-TpmReShadePreviewBitmapFromCache')) {
        Remove-Item -LiteralPath ('Function:\' + $name) -ErrorAction SilentlyContinue
        if ($null -ne $script:fix74SavedFunctions[$name]) { Set-Item -Path ('Function:\global:' + $name) -Value $script:fix74SavedFunctions[$name] }
    }
    foreach ($name in @('Fix74Log', 'Fix74OnProcess', 'Fix74FailRender', 'Fix74State')) {
        Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
        if ($script:fix74SavedVariables[$name].Exists) { Set-Variable -Name $name -Scope Global -Value $script:fix74SavedVariables[$name].Value }
    }
}

Describe 'FIX74 ReShade preview window repaint (double buffering)' {
    It 'double-buffers the form, the picture, the picture panel and the button row: <Target>' -ForEach @(
        @{ Target = 'form'; Pattern = 'Set-TpmReShadeControlDoubleBuffered -Control \$form\b' }
        @{ Target = 'picture'; Pattern = 'Set-TpmReShadeControlDoubleBuffered -Control \$picture\b' }
        @{ Target = 'pictureHost'; Pattern = 'Set-TpmReShadeControlDoubleBuffered -Control \$pictureHost\b' }
        @{ Target = 'toolbar'; Pattern = 'Set-TpmReShadeControlDoubleBuffered -Control \$toolbar\b' }
    ) {
        # Mutation: deleting the Set-TpmReShadeControlDoubleBuffered call for this control makes this test fail.
        $script:fix74GalleryText | Should -Match $Pattern
    }
    It 'turns double buffering on by reflection and never compiles a helper type' {
        # Mutation: replacing the reflection with Add-Type -TypeDefinition (or a variable -ReferencedAssemblies), or reading another property name, fails this.
        $script:fix74HelperText | Should -Match "GetProperty\('DoubleBuffered'"
        $script:fix74HelperText | Should -Match 'SetValue\(\$Control, \$true'
        $script:fix74HelperText | Should -Not -Match 'Add-Type|ReferencedAssemblies'
    }
    It 'sets DoubleBuffered on a real WinForms control and reports $false for something that is not a control' -Skip:(-not $fix74CanUseForms) {
        # Mutation: a helper that returns $true without setting the property, or that lets the reflection error escape, fails this.
        $flags = [Reflection.BindingFlags]'Instance,NonPublic'
        $property = [Windows.Forms.Control].GetProperty('DoubleBuffered', $flags)
        $fresh = New-Object Windows.Forms.Panel
        $property.GetValue($fresh, $null) | Should -BeFalse
        $panel = New-Object Windows.Forms.Panel
        $result = Set-TpmReShadeControlDoubleBuffered -Control $panel
        $result | Should -BeTrue
        $property.GetValue($panel, $null) | Should -BeTrue
        $flow = New-Object Windows.Forms.FlowLayoutPanel
        [void](Set-TpmReShadeControlDoubleBuffered -Control $flow)
        $property.GetValue($flow, $null) | Should -BeTrue
        $notAControl = Set-TpmReShadeControlDoubleBuffered -Control ([pscustomobject]@{ Name = 'not a control' })
        $notAControl | Should -BeFalse
        $panel.Dispose(); $fresh.Dispose(); $flow.Dispose()
    }
}

Describe 'FIX74 ReShade preview window repaint (one layout pass, bitmap swap, one repaint)' {
    It 'wraps the refresh in SuspendLayout/ResumeLayout, then one PerformLayout, then Invalidate and Update (source order)' {
        # Mutation: removing SuspendLayout, ResumeLayout, PerformLayout, Invalidate or Update, or reordering them, fails this. Moving SuspendLayout before the description label (label painted at its new height while the picture panel is not yet moved) also fails it.
        $text = $script:fix74RefreshOnceText
        $suspend = $text.IndexOf('$form.SuspendLayout()')
        $label = $text.IndexOf('Set-TpmReShadeDescriptionLabel')
        $swap = $text.IndexOf('$picture.Image = $image')
        $resume = $text.IndexOf('$form.ResumeLayout($false)')
        $perform = $text.IndexOf('$form.PerformLayout()')
        $invalidate = $text.IndexOf('$picture.Invalidate()')
        $update = $text.IndexOf('$picture.Update()')
        $suspend | Should -BeGreaterThan -1
        $suspend | Should -BeGreaterThan $label
        $swap | Should -BeGreaterThan $suspend
        $resume | Should -BeGreaterThan $swap
        $perform | Should -BeGreaterThan $resume
        $invalidate | Should -BeGreaterThan $perform
        $update | Should -BeGreaterThan $invalidate
        ([regex]::Matches($text, 'PerformLayout\(\)')).Count | Should -Be 1
        ([regex]::Matches($text, '\$picture\.Update\(\)')).Count | Should -Be 1
    }
    It 'resumes layout in a finally block so a failed render cannot leave the window frozen' {
        # Mutation: moving ResumeLayout out of finally (only on the success path) fails this.
        $script:fix74RefreshOnceText | Should -Match '(?s)finally\s*\{\s*if \(\$layoutSuspended\)\s*\{[^}]*ResumeLayout\(\$false\)'
    }
    It 'builds the new bitmap before it is assigned and disposes the old one only after the assignment' {
        # Mutation: disposing or clearing the old image before New-TpmReShadePreviewBitmapFromCache returns fails this.
        $text = $script:fix74RefreshOnceText
        $build = $text.IndexOf('New-TpmReShadePreviewBitmapFromCache')
        $oldRead = $text.IndexOf('$oldImage = $picture.Image', $build)
        $assign = $text.IndexOf('$picture.Image = $image')
        $dispose = $text.IndexOf('$oldImage.Dispose()', $assign)
        $build | Should -BeGreaterThan -1
        $oldRead | Should -BeGreaterThan $build
        $assign | Should -BeGreaterThan $oldRead
        $dispose | Should -BeGreaterThan $assign
    }
    It 'keeps the description label update ahead of the heavy render' {
        # Mutation: moving Set-TpmReShadeDescriptionLabel after Get-TpmReShadePreviewProcessedBitmap fails this.
        $text = $script:fix74RefreshOnceText
        $text.IndexOf('Set-TpmReShadeDescriptionLabel') | Should -BeGreaterThan -1
        $text.IndexOf('Set-TpmReShadeDescriptionLabel') | Should -BeLessThan $text.IndexOf('Get-TpmReShadePreviewProcessedBitmap')
    }
    It 'runs one switch as label, suspend, render, swap, dispose old, resume, perform, invalidate, update' {
        # Mutation: any of the layout/paint steps missing, doubled or out of order in the real refresh scriptblock changes this exact sequence.
        $harness = New-Fix74Harness
        $result = & $harness.Refresh
        $result | Should -BeTrue
        $global:Fix74Log -join '|' | Should -Be 'Label:desc-A|Suspend|Process:A|Build:A/Split|Image=A/Split|Dispose:old-image|Resume:False|Perform|Invalidate|Update'
        $harness.Picture.Image.Name | Should -Be 'A/Split'
    }
    It 'in Slider mode clears the picture image, disposes the old one and still repaints once' {
        # Mutation: dropping the Invalidate/Update after the Slider branch, or disposing before the image is cleared, fails this.
        $harness = New-Fix74Harness -ViewMode 'Slider'
        $result = & $harness.Refresh
        $result | Should -BeTrue
        $global:Fix74Log -join '|' | Should -Be 'Label:desc-A|Suspend|Process:A|Image=<null>|Dispose:old-image|Resume:False|Perform|Invalidate|Update'
        $harness.Picture.Image | Should -BeNullOrEmpty
    }
    It 'does not touch layout or the picture when the window is closed' {
        # Mutation: calling SuspendLayout before the Initialized/Closed guard fails this.
        $harness = New-Fix74Harness
        $harness.State['Closed'] = $true
        $result = & $harness.Refresh
        $result | Should -BeFalse
        $global:Fix74Log.Count | Should -Be 0
        $harness.Picture.Image.Name | Should -Be 'old-image'
    }
    It 'resumes layout, keeps the old picture undisposed and clears the coalescing flags when the render fails' {
        # Mutation: resuming layout only on success, disposing the old image before the new one is built, or clearing the flags outside finally fails this.
        $harness = New-Fix74Harness
        $global:Fix74FailRender = $true
        { & $harness.Refresh } | Should -Throw '*forced render failure*'
        $global:Fix74Log -contains 'Resume:False' | Should -BeTrue
        $global:Fix74Log -contains 'Dispose:old-image' | Should -BeFalse
        $global:Fix74Log -contains 'Perform' | Should -BeFalse
        $harness.Picture.Image.Name | Should -Be 'old-image'
        $harness.State['RefreshRunning'] | Should -BeFalse
        $harness.State['RefreshPendingProfileId'] | Should -BeNullOrEmpty
        $global:Fix74FailRender = $false
        $global:Fix74Log.Clear()
        (& $harness.Refresh) | Should -BeTrue
        $harness.Picture.Image.Name | Should -Be 'A/Split'
    }
}

Describe 'FIX74 ReShade preview window repaint (rapid profile changes are coalesced)' {
    It 'applies only the latest profile when requests arrive during a running refresh' {
        # Mutation: removing the RefreshRunning re-entrancy guard (nested requests render at once) or keeping the FIRST pending profile instead of the latest fails this.
        $harness = New-Fix74Harness
        $global:Fix74OnProcess = {
            param($id)
            if ($id -eq 'A') {
                $global:Fix74State['SelectedProfileId'] = 'B'
                $global:Fix74Nested1 = [bool](& $global:Fix74State['Refresh'])
                $global:Fix74State['SelectedProfileId'] = 'C'
                $global:Fix74Nested2 = [bool](& $global:Fix74State['Refresh'])
            }
        }
        $result = & $harness.Refresh
        $result | Should -BeTrue
        $global:Fix74Nested1 | Should -BeTrue
        $global:Fix74Nested2 | Should -BeTrue
        @($global:Fix74Log | Where-Object { $_ -like 'Process:*' }) -join ',' | Should -Be 'Process:A,Process:C'
        @($global:Fix74Log | Where-Object { $_ -like 'Build:*' }) -join ',' | Should -Be 'Build:A/Split,Build:C/Split'
        $harness.State['SelectedProfileId'] | Should -Be 'C'
        $harness.Picture.Image.Name | Should -Be 'C/Split'
        @($global:Fix74Log | Where-Object { $_ -eq 'Update' }).Count | Should -Be 2
        Remove-Variable -Name Fix74Nested1, Fix74Nested2 -Scope Global -ErrorAction SilentlyContinue
    }
    It 'clears the running and pending flags when the follow-up refresh fails, so the next request renders normally' {
        # Mutation: clearing RefreshRunning/RefreshPendingProfileId outside finally leaves the window unable to refresh again and fails this.
        $harness = New-Fix74Harness
        $global:Fix74OnProcess = {
            param($id)
            if ($id -eq 'A') {
                $global:Fix74State['SelectedProfileId'] = 'B'
                [void](& $global:Fix74State['Refresh'])
            }
            if ($id -eq 'B') { throw 'forced follow-up failure' }
        }
        { & $harness.Refresh } | Should -Throw '*forced follow-up failure*'
        $harness.State['RefreshRunning'] | Should -BeFalse
        $harness.State['RefreshPendingProfileId'] | Should -BeNullOrEmpty
        $global:Fix74OnProcess = $null
        $global:Fix74Log.Clear()
        $harness.State['SelectedProfileId'] = 'C'
        (& $harness.Refresh) | Should -BeTrue
        $harness.Picture.Image.Name | Should -Be 'C/Split'
    }
    It 'does nothing extra when no request arrives during the refresh' {
        # Mutation: re-running the render loop unconditionally (ignoring RefreshPendingProfileId) doubles the work and fails this.
        $harness = New-Fix74Harness
        $result = & $harness.Refresh
        $result | Should -BeTrue
        @($global:Fix74Log | Where-Object { $_ -like 'Build:*' }).Count | Should -Be 1
        $harness.State['RefreshRunning'] | Should -BeFalse
    }
}
