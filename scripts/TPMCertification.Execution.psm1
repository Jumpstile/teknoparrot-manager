Set-StrictMode -Version Latest

function ConvertTo-TPMWin32ArgumentV1 {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    if($Value.Length-gt0-and$Value.IndexOfAny([char[]](' ',"`t",'"'))-lt0){return $Value}
    $builder=New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $index=0
    while($index-lt$Value.Length){
        $backslashes=0
        while($index-lt$Value.Length-and$Value[$index]-eq'\'){$backslashes++;$index++}
        if($index-eq$Value.Length){[void]$builder.Append('\'*($backslashes*2));break}
        if($Value[$index]-eq'"'){
            [void]$builder.Append('\'*($backslashes*2+1))
            [void]$builder.Append('"')
        }else{
            [void]$builder.Append('\'*$backslashes)
            [void]$builder.Append($Value[$index])
        }
        $index++
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-TPMSafeTechnicalTextV1 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){return ''}
    $withoutAnsi=[regex]::Replace($Text,"`e(?:\[[0-?]*[ -/]*[@-~]|\][^`a]*(?:`a|`e\\))",'')
    $builder=New-Object Text.StringBuilder
    foreach($character in $withoutAnsi.ToCharArray()){
        $code=[int][char]$character
        if($code-eq9-or$code-eq10-or$code-eq13-or$code-ge32){
            [void]$builder.Append($character)
        }else{
            [void]$builder.Append(('\x{0:X2}'-f$code))
        }
    }
    return $builder.ToString()
}

function Test-TPMTransientIOHResultV1 {
    # Windows can briefly hold the redirected-output file handle open after
    # Start-Process's own .HasExited/.ExitCode already report the child as
    # exited (confirmed by direct reproduction: reading a just-exited
    # child's redirected stdout log immediately afterward intermittently
    # threw "being used by another process"). That specific race is the
    # ONLY thing the retry loop in Invoke-TPMSafeFileRetryV1 is meant to
    # tolerate. The two Win32 errors that race produces are
    # ERROR_SHARING_VIOLATION (32) and ERROR_LOCK_VIOLATION (33), which the
    # CLR surfaces as an IOException whose HResult is the Win32 code packed
    # into an HRESULT: 0x80070000 | code, i.e. 0x80070020 / 0x80070021.
    # Exception.HResult is a plain Int32 property on every System.Exception
    # in both Windows PowerShell 5.1 (.NET Framework) and pwsh 7+ (.NET) --
    # using it (rather than a Win32Exception/NativeErrorCode wrapper that
    # only exists on one engine) keeps this classification identical under
    # both. Every other IOException subtype/HResult (DirectoryNotFound,
    # PathTooLong, disk-full, etc. all derive from IOException too) is
    # deliberately NOT in this list -- those are not transient and must
    # fail immediately, not be retried.
    param([Parameter(Mandatory=$true)][int]$HResult)
    $transientHResults=@(0x80070020,0x80070021)
    return ($transientHResults-contains$HResult)
}

function New-TPMSanitizationExhaustedExceptionV1 {
    # Deliberate, distinctly-tagged exception thrown when the bounded
    # transient-retry budget in Invoke-TPMSafeFileRetryV1 is exhausted
    # without success. Message carries operation identity and a safe
    # target identity (a file path, never raw file content) plus attempt
    # count/elapsed time/underlying exception identity for diagnosis; the
    # original exception is preserved as InnerException so its own
    # HResult/stack trace is never lost. System.IO.IOException is used as
    # the carrier type (constructible identically under both engines via
    # the (message, innerException) constructor) with the
    # SANITIZATION_RETRY_EXHAUSTED: tag making it unambiguous which family
    # of failure this is -- callers must never mistake it for an ordinary
    # transient IOException that is safe to retry again.
    param(
        [Parameter(Mandatory=$true)][string]$Operation,
        [Parameter(Mandatory=$true)][string]$TargetIdentity,
        [Parameter(Mandatory=$true)][int]$AttemptCount,
        [Parameter(Mandatory=$true)][double]$ElapsedMilliseconds,
        [Parameter(Mandatory=$true)][Exception]$InnerException
    )
    $message=(
        "SANITIZATION_RETRY_EXHAUSTED: operation={0} target={1} attempts={2} elapsedMs={3} innerType={4} innerHResult=0x{5}" -f
        $Operation,$TargetIdentity,$AttemptCount,[long]$ElapsedMilliseconds,$InnerException.GetType().FullName,$InnerException.HResult.ToString('X8')
    )
    return (New-Object IO.IOException($message,$InnerException))
}

function Invoke-TPMSafeFileRetryV1 {
    # Shared bounded-retry wrapper for the read and write halves of
    # Write-TPMSafeTechnicalFileV1. Bound: 20 attempts at 100ms apart
    # (~2 seconds worst case per direction) -- chosen because the handle-
    # release race this exists for is a sub-second OS delay (see
    # LESSONS_LEARNED.md); 2 seconds is generous headroom without letting a
    # genuinely stuck lock hang the certification pipeline indefinitely.
    # Only the exact transient HResults from Test-TPMTransientIOHResultV1
    # are retried -- every other exception (UnauthorizedAccessException,
    # a nontransient IOException such as disk-full or a bad path, or
    # anything else) is rethrown immediately with no retry. On exhaustion
    # this throws (never returns a value pretending success) so neither
    # the read nor the write path can silently look like it succeeded.
    param([Parameter(Mandatory=$true)][string]$Operation,[Parameter(Mandatory=$true)][string]$TargetIdentity,[Parameter(Mandatory=$true)][scriptblock]$Action)
    $stopwatch=[Diagnostics.Stopwatch]::StartNew()
    $attempt=0
    while($true){
        $attempt++
        try{
            return (& $Action)
        }catch [IO.IOException]{
            if(-not(Test-TPMTransientIOHResultV1 -HResult $_.Exception.HResult)){throw}
            if($attempt-ge20){
                throw (New-TPMSanitizationExhaustedExceptionV1 -Operation $Operation -TargetIdentity $TargetIdentity -AttemptCount $attempt -ElapsedMilliseconds $stopwatch.Elapsed.TotalMilliseconds -InnerException $_.Exception)
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Write-TPMSafeTechnicalFileV1 {
    # Sanitization of a just-exited child's captured stdout/stderr is a
    # safety invariant, not a best-effort convenience: nothing downstream
    # may assume a log file is safe to display/relay unless this function
    # actually ran to completion. A persistent (non-transient, or
    # transient-but-never-clearing) failure on either the read or the
    # write half must therefore throw rather than silently leaving the
    # caller believing sanitization happened. The underlying unsanitized
    # file is never deleted or overwritten on failure -- it remains on
    # disk as the preserved technical evidence for diagnosis, and this
    # function never prints its content to the operator console under any
    # circumstance, including this failure path.
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    $raw=Invoke-TPMSafeFileRetryV1 -Operation 'read-technical-log' -TargetIdentity $Path -Action { [IO.File]::ReadAllText($Path) }
    $safe=ConvertTo-TPMSafeTechnicalTextV1 -Text $raw
    [void](Invoke-TPMSafeFileRetryV1 -Operation 'write-technical-log' -TargetIdentity $Path -Action { [IO.File]::WriteAllText($Path,$safe,(New-Object Text.UTF8Encoding $false)) })
}

function Get-TPMPathComponentsV1 {
    # Splits an already-canonical, absolute path into its individual
    # segments (drive/UNC-root first, then each directory/file name).
    # Every containment/reparse check below compares these component
    # arrays element-by-element rather than doing a raw string prefix
    # comparison, which is what makes the containment check immune to
    # sibling-prefix confusion (e.g. "C:\Owned-Evil" must never be treated
    # as being "under" "C:\Owned").
    param([Parameter(Mandatory=$true)][string]$FullPath)
    $trimmed=$FullPath.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    return @($trimmed-split'[\\/]'|Where-Object{$_.Length-gt0})
}

function Test-TPMPathIsContainedV1 {
    # True only when $Target's path components are $Root's components
    # followed by zero or more additional components (component-boundary
    # containment) -- i.e. $Target equals $Root or is a proper descendant
    # of it. Deliberately NOT a $Target.StartsWith($Root) string check:
    # that class of check is the one a naive implementation gets wrong on
    # sibling directories that merely share a text prefix.
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Target)
    $rootParts=Get-TPMPathComponentsV1 -FullPath ([IO.Path]::GetFullPath($Root))
    $targetParts=Get-TPMPathComponentsV1 -FullPath ([IO.Path]::GetFullPath($Target))
    if($targetParts.Count-lt$rootParts.Count){return $false}
    for($i=0;$i-lt$rootParts.Count;$i++){
        if(-not$targetParts[$i].Equals($rootParts[$i],[StringComparison]::OrdinalIgnoreCase)){return $false}
    }
    return $true
}

function Assert-TPMNoReparseInChainV1 {
    # Validates every EXISTING path component from $Root through $Target
    # (inclusive of both ends) individually for the reparse-point
    # attribute -- not just $Target's own final attributes. Checking only
    # the leaf is insufficient: an attacker (or an unrelated junction
    # already present on the host) could redirect the effective location
    # via any intermediate ancestor even when the leaf name itself is an
    # ordinary directory. $Target must first be a component-boundary
    # descendant of $Root (see Test-TPMPathIsContainedV1); components
    # above $Root are not inspected, since $Root is the caller's declared
    # trusted anchor.
    #
    # -AllowMissingLeaf permits exactly the final component to not yet
    # exist (the one authorized creation flow: Assert-TPMOwnedDirectoryV1
    # -CreateIfMissing bringing its own owned directory into existence for
    # the first time). Every other missing/uninspectable component in the
    # chain -- including any missing intermediate ancestor -- is rejected;
    # only the single authorized leaf may be absent.
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Target,[switch]$AllowMissingLeaf)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $targetFull=[IO.Path]::GetFullPath($Target).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-TPMPathIsContainedV1 -Root $rootFull -Target $targetFull)){throw "PROCESS_PATH_OUTSIDE_OWNED_ROOT: $targetFull is not a component-boundary descendant of owned root $rootFull"}
    $rootParts=Get-TPMPathComponentsV1 -FullPath $rootFull
    $targetParts=Get-TPMPathComponentsV1 -FullPath $targetFull
    $current=$targetParts[0]+[IO.Path]::DirectorySeparatorChar
    for($i=1;$i-lt$targetParts.Count;$i++){
        $current=Join-Path $current $targetParts[$i]
        if($i-lt($rootParts.Count-1)){continue}
        $isLeaf=($i-eq($targetParts.Count-1))
        if(-not(Test-Path -LiteralPath $current)){
            if($isLeaf-and$AllowMissingLeaf){continue}
            throw "PROCESS_DIRECTORY_INVALID: path component does not exist and is not the authorized creation leaf: $current"
        }
        $componentItem=Get-Item -LiteralPath $current -Force
        if(($componentItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "PROCESS_DIRECTORY_INVALID: reparse point rejected in owned-path chain: $current"}
    }
}

function Assert-TPMOwnedDirectoryV1 {
    # ADR155-0309 round 3 correction: a prior round of this function called
    # Assert-TPMNoReparseInChainV1 with Root and Target both set to the
    # SAME path, which meant the chain walk below (see
    # Assert-TPMNoReparseInChainV1's own "only the last component is
    # inspected when Root and Target are identical" behavior) only ever
    # inspected the leaf directory's own attributes -- no ancestor above
    # the leaf, including the caller's real trust boundary, was ever
    # actually consulted. That defeated the entire point of ancestor-chain
    # reparse validation: a junction planted at an INTERMEDIATE level
    # (e.g. the harness's own "Reports" or "ProductionWork" folder) was
    # never checked at all, only the final path component was.
    #
    # -Root is now a distinct, mandatory, CALLER-SUPPLIED trusted anchor --
    # this function never infers or guesses one. -Root itself is validated
    # here (must exist, be stat-able, and not itself be a reparse point)
    # before anything else happens; -Path (the target) must equal -Root or
    # be a proper component-boundary descendant of it (Root == Target is a
    # deliberately supported, explicit case -- e.g. a caller's own
    # already-established top-level working directory -- not an
    # accidental collapse: it is exercised by a dedicated regression test
    # precisely so this remains a deliberate choice, not a silent default).
    # Every existing component from -Root through -Path inclusive is then
    # walked and reparse-checked by Assert-TPMNoReparseInChainV1.
    #
    # -CreateIfMissing creates -Path when it does not yet exist -- but only
    # the single immediate leaf: its parent must already be an EXISTING,
    # already-validated component of the Root-to-Path chain (i.e. -Path
    # must be at most one level below something that already exists).
    # Callers that need to bring a multi-level path into existence beneath
    # a trusted root (e.g. HarnessRoot\Reports\<stamp>) must do so one
    # authorized level at a time -- see New-TPMOwnedDirectoryChainV1 --
    # never by asking the filesystem to create several untracked
    # intermediate levels in one call, which is exactly the shortcut that
    # let an unvalidated intermediate directory come into existence under
    # the old root==target defect. New-Item is called WITHOUT -Force so
    # that if something else has raced in and created a (possibly
    # reparse-point) entry at this exact path between the pre-creation
    # check and now, creation fails closed instead of -Force's silent
    # "already exists, do nothing" behavior.
    #
    # After creation, the ENTIRE Root-to-Path chain is re-validated
    # (TOCTOU-narrowing point 1): creation itself is a window in which the
    # freshly-created path could in principle have been raced, so the
    # pre-creation validation is never trusted to still hold
    # post-creation. This narrows the TOCTOU race; it does not, and cannot,
    # eliminate it -- a substitution racing in strictly between this
    # revalidation and the caller's own subsequent use of the path remains
    # possible in principle. Callers that go on to create an owned file
    # beneath the validated path (New-TPMCreateNewFileV1) get a SECOND,
    # later revalidation immediately before that file is actually opened,
    # which narrows the window further but likewise does not eliminate it.
    # If a substitution IS observed at any validation point, this fails
    # closed (throws) rather than proceeding.
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[switch]$CreateIfMissing)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-Path -LiteralPath $rootFull -PathType Container)){throw "PROCESS_DIRECTORY_INVALID: trusted root does not exist: $rootFull"}
    $rootItem=Get-Item -LiteralPath $rootFull -Force
    if(($rootItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "PROCESS_DIRECTORY_INVALID: reparse point rejected at trusted root: $rootFull"}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not[IO.Path]::GetPathRoot($rootFull).Equals([IO.Path]::GetPathRoot($full),[StringComparison]::OrdinalIgnoreCase)){throw "PROCESS_PATH_OUTSIDE_OWNED_ROOT: $full is on a different drive/root than owned root $rootFull"}
    Assert-TPMNoReparseInChainV1 -Root $rootFull -Target $full -AllowMissingLeaf:$CreateIfMissing
    if(-not(Test-Path -LiteralPath $full -PathType Container)){
        if(-not$CreateIfMissing){throw "PROCESS_DIRECTORY_INVALID: directory does not exist: $full"}
        $parent=[IO.Path]::GetDirectoryName($full)
        if([string]::IsNullOrEmpty($parent)-or-not(Test-Path -LiteralPath $parent -PathType Container)){throw "PROCESS_DIRECTORY_INVALID: parent of directory to create does not exist or is not itself validated: $full"}
        [void](New-Item -ItemType Directory -Path $full -ErrorAction Stop)
        Assert-TPMNoReparseInChainV1 -Root $rootFull -Target $full
    }
    return $full
}

function New-TPMOwnedDirectoryChainV1 {
    # Brings a multi-level directory path into existence beneath a trusted
    # root by validating/creating exactly one authorized level at a time
    # through Assert-TPMOwnedDirectoryV1 -CreateIfMissing, instead of ever
    # asking the filesystem (New-Item's own intermediate-directory
    # creation) to bring multiple untracked levels into existence in a
    # single call -- see Assert-TPMOwnedDirectoryV1's own comment for why
    # that shortcut is exactly the defect this round corrects. Every
    # intermediate level created along the way is individually
    # reparse-checked, both before and after its own creation, by the
    # underlying Assert-TPMOwnedDirectoryV1 call for that level. Returns
    # the fully validated final path.
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $targetFull=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-TPMPathIsContainedV1 -Root $rootFull -Target $targetFull)){throw "PROCESS_PATH_OUTSIDE_OWNED_ROOT: $targetFull is not a component-boundary descendant of owned root $rootFull"}
    $rootParts=Get-TPMPathComponentsV1 -FullPath $rootFull
    $targetParts=Get-TPMPathComponentsV1 -FullPath $targetFull
    $current=Assert-TPMOwnedDirectoryV1 -Root $rootFull -Path $rootFull -CreateIfMissing
    for($i=$rootParts.Count;$i-lt$targetParts.Count;$i++){
        $next=Join-Path $current $targetParts[$i]
        $current=Assert-TPMOwnedDirectoryV1 -Root $current -Path $next -CreateIfMissing
    }
    return $current
}

function New-TPMCreateNewFileV1 {
    # -Root is the caller's real trusted anchor for -Parent (which may
    # equal -Root or be a validated descendant of it) -- NOT -Parent
    # collapsed onto itself. -Parent is revalidated against -Root here
    # (TOCTOU-narrowing point), and the eventual file path is revalidated
    # against -Root a SECOND time immediately before the underlying
    # FileStream is opened (point 2 of 2; see Assert-TPMOwnedDirectoryV1's
    # comment) -- as close to actual use as this code can get. Neither
    # revalidation eliminates the residual race; each narrows it.
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Parent,[Parameter(Mandatory=$true)][string]$Name)
    $rootFull=Assert-TPMOwnedDirectoryV1 -Root $Root -Path $Root
    $parentFull=Assert-TPMOwnedDirectoryV1 -Root $rootFull -Path $Parent
    $path=[IO.Path]::GetFullPath((Join-Path $parentFull $Name))
    if(-not(Test-TPMPathIsContainedV1 -Root $rootFull -Target $path)){throw 'PROCESS_PATH_OUTSIDE_OWNED_ROOT'}
    Assert-TPMNoReparseInChainV1 -Root $rootFull -Target $path -AllowMissingLeaf
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stream.Dispose()
    return $path
}

function Get-TPMCertificationSha256HexV1 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return (-join($sha.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')}))}finally{$sha.Dispose()}
}

function Invoke-TPMCertificationGitReadV1 {
    param([Parameter(Mandatory=$true)][string]$RepositoryPath,[Parameter(Mandatory=$true)][string[]]$Arguments)
    $repo=[IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $scoped=@('-c',("safe.directory={0}"-f$repo),'-C',$repo)
    $commandArguments=@($scoped)+@($Arguments)
    $output=@(& git @commandArguments 2>$null)
    $exitCode=$LASTEXITCODE
    return [pscustomobject]@{Output=$output;ExitCode=$exitCode}
}

function Get-TPMCertificationGitIdentitySnapshotV1 {
    param([Parameter(Mandatory=$true)][string]$RepositoryPath)
    $repo=[IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $branchResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--abbrev-ref','HEAD')
    $commitResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--verify','HEAD')
    $statusResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('status','--porcelain=v1','--untracked-files=all')
    $upstreamResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--abbrev-ref','--symbolic-full-name','@{upstream}')

    $branch=if($branchResult.ExitCode-eq0-and$branchResult.Output.Count-gt0){([string]$branchResult.Output[0]).Trim()}else{$null}
    $commit=if($commitResult.ExitCode-eq0-and$commitResult.Output.Count-gt0){([string]$commitResult.Output[0]).Trim()}else{$null}
    $statusLines=@()
    if($statusResult.ExitCode-eq0){$statusLines=@($statusResult.Output|ForEach-Object{[string]$_})}
    $upstreamRef=if($upstreamResult.ExitCode-eq0-and$upstreamResult.Output.Count-gt0){([string]$upstreamResult.Output[0]).Trim()}else{$null}
    $upstreamCommit=$null
    if(-not[string]::IsNullOrWhiteSpace($upstreamRef)){
        $upstreamCommitResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--verify',($upstreamRef+'^{commit}'))
        if($upstreamCommitResult.ExitCode-eq0-and$upstreamCommitResult.Output.Count-gt0){$upstreamCommit=([string]$upstreamCommitResult.Output[0]).Trim()}
    }

    $refResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('for-each-ref','--format=%(refname)%09%(objectname)','refs')
    $refEntries=New-Object Collections.Generic.List[string]
    $refLines=@($refResult.Output|ForEach-Object{([string]$_).Trim()}|Where-Object{$_-ne''}|Sort-Object)
    if($refResult.ExitCode-eq0){foreach($line in $refLines){[void]$refEntries.Add($line)}}
    $headPathResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--git-path','HEAD')
    if($headPathResult.ExitCode-eq0-and$headPathResult.Output.Count-gt0){
        $headPath=([string]$headPathResult.Output[0]).Trim()
        if(-not[IO.Path]::IsPathRooted($headPath)){$headPath=Join-Path $repo $headPath}
        if(Test-Path -LiteralPath $headPath -PathType Leaf){
            $headBytes=[IO.File]::ReadAllBytes($headPath)
            [void]$refEntries.Add(('HEAD|{0}|{1}'-f(Get-TPMCertificationSha256HexV1 -Bytes $headBytes),$headBytes.Length))
        }
    }
    $refSnapshotHash=$null
    if($refResult.ExitCode-eq0-and$headPathResult.ExitCode-eq0-and$headPathResult.Output.Count-gt0){
        try{
            $refSnapshotText=(($refEntries.ToArray()|Sort-Object)-join"`n")
            $refSnapshotHash=Get-TPMCertificationSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes($refSnapshotText))
        }catch{$refSnapshotHash=$null}
    }

    $logsResult=Invoke-TPMCertificationGitReadV1 -RepositoryPath $repo -Arguments @('rev-parse','--git-path','logs')
    $reflogSnapshotHash=$null
    if($logsResult.ExitCode-eq0-and$logsResult.Output.Count-gt0){
        $logsRoot=([string]$logsResult.Output[0]).Trim()
        if(-not[IO.Path]::IsPathRooted($logsRoot)){$logsRoot=Join-Path $repo $logsRoot}
        $reflogEntries=New-Object Collections.Generic.List[string]
        if(Test-Path -LiteralPath $logsRoot -PathType Container){
            try{
            $logsBase=[IO.Path]::GetFullPath($logsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
            foreach($file in @(Get-ChildItem -LiteralPath $logsRoot -File -Recurse -Force -ErrorAction Stop|Sort-Object FullName)){
                $relative=$file.FullName.Substring($logsBase.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace('\','/')
                $bytes=[IO.File]::ReadAllBytes($file.FullName)
                [void]$reflogEntries.Add(('{0}|{1}|{2}'-f$relative,(Get-TPMCertificationSha256HexV1 -Bytes $bytes),$bytes.Length))
            }
            $reflogSnapshotText=(($reflogEntries.ToArray()|Sort-Object)-join"`n")
                $reflogSnapshotHash=Get-TPMCertificationSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes($reflogSnapshotText))
            }catch{$reflogSnapshotHash=$null}
        }
    }

    return [ordered]@{
        Branch=$branch
        Commit=$commit
        RemoteRef=$upstreamRef
        RemoteCommit=$upstreamCommit
        Clean=($statusResult.ExitCode-eq0-and$statusLines.Count-eq0)
        RefSnapshotSha256=$refSnapshotHash
        ReflogSnapshotSha256=$reflogSnapshotHash
    }
}

function New-TPMCertificationGitIdentityV1 {
    param(
        [Parameter(Mandatory=$true)]$Start,
        [Parameter(Mandatory=$true)]$End,
        [AllowNull()][string]$ExpectedBranch,
        [AllowNull()][string]$ExpectedCommit
    )
    $reasons=New-Object Collections.Generic.List[string]
    $refMutation=$false
    if($null-eq$Start-or$null-eq$End){[void]$reasons.Add('CERTIFICATION_IDENTITY_CAPTURE_FAILED')}
    else{
        if(-not$Start.Clean){[void]$reasons.Add('CERTIFICATION_WORKTREE_DIRTY_AT_START')}
        if(-not$End.Clean){[void]$reasons.Add('CERTIFICATION_WORKTREE_DIRTY_AT_END')}
        if([string]::IsNullOrWhiteSpace([string]$Start.Branch)-or[string]$Start.Branch-ceq'HEAD'-or[string]$Start.Branch-ne[string]$End.Branch){[void]$reasons.Add('CERTIFICATION_BRANCH_CHANGED');$refMutation=$true}
        if([string]::IsNullOrWhiteSpace([string]$Start.Commit)-or[string]$Start.Commit-ne[string]$End.Commit){[void]$reasons.Add('CERTIFICATION_COMMIT_CHANGED');$refMutation=$true}
        if([string]$Start.RemoteRef-ne[string]$End.RemoteRef-or[string]$Start.RemoteCommit-ne[string]$End.RemoteCommit){[void]$reasons.Add('CERTIFICATION_REMOTE_REF_CHANGED');$refMutation=$true}
        if([string]::IsNullOrWhiteSpace([string]$Start.RemoteRef)-or[string]::IsNullOrWhiteSpace([string]$Start.RemoteCommit)){[void]$reasons.Add('CERTIFICATION_REMOTE_SHA_UNAVAILABLE')}
        elseif([string]$Start.Commit-ne[string]$Start.RemoteCommit-or[string]$End.Commit-ne[string]$End.RemoteCommit){[void]$reasons.Add('CERTIFICATION_REMOTE_SHA_MISMATCH')}
        if([string]::IsNullOrWhiteSpace([string]$Start.RefSnapshotSha256)-or[string]::IsNullOrWhiteSpace([string]$End.RefSnapshotSha256)){[void]$reasons.Add('CERTIFICATION_REF_SNAPSHOT_UNAVAILABLE')}
        if([string]::IsNullOrWhiteSpace([string]$Start.ReflogSnapshotSha256)-or[string]::IsNullOrWhiteSpace([string]$End.ReflogSnapshotSha256)){[void]$reasons.Add('CERTIFICATION_REFLOG_SNAPSHOT_UNAVAILABLE')}
        if([string]$Start.RefSnapshotSha256-ne[string]$End.RefSnapshotSha256){[void]$reasons.Add('CERTIFICATION_REF_MUTATED');$refMutation=$true}
        if([string]$Start.ReflogSnapshotSha256-ne[string]$End.ReflogSnapshotSha256){[void]$reasons.Add('CERTIFICATION_REFLOG_MUTATED');$refMutation=$true}
        if(-not[string]::IsNullOrWhiteSpace($ExpectedBranch)-and[string]$Start.Branch-ne$ExpectedBranch){[void]$reasons.Add('CERTIFICATION_EXPECTED_BRANCH_MISMATCH')}
        if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)-and[string]$Start.Commit-ne$ExpectedCommit){[void]$reasons.Add('CERTIFICATION_EXPECTED_COMMIT_MISMATCH')}
        if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)-and[string]$Start.RemoteCommit-ne$ExpectedCommit){[void]$reasons.Add('CERTIFICATION_EXPECTED_REMOTE_SHA_MISMATCH')}
    }
    return [ordered]@{
        ExpectedBranch=$(if([string]::IsNullOrWhiteSpace($ExpectedBranch)){$null}else{$ExpectedBranch})
        ExpectedCommit=$(if([string]::IsNullOrWhiteSpace($ExpectedCommit)){$null}else{$ExpectedCommit})
        Start=$Start
        End=$End
        RefMutationDetected=$refMutation
        RefMutationReason=$(if($reasons.Count-eq0){$null}else{$reasons.ToArray()-join'; '})
        IdentityValid=($reasons.Count-eq0)
    }
}

function Get-TPMCertificationRepositoryLockNameV1 {
    param([Parameter(Mandatory=$true)][string]$RepositoryPath)
    $repo=[IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).ToUpperInvariant()
    $hash=Get-TPMCertificationSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes($repo))
    return "Local\TeknoParrotManager-Certification-$hash"
}

function Enter-TPMCertificationRepositoryLockV1 {
    param([Parameter(Mandatory=$true)][string]$RepositoryPath)
    $name=Get-TPMCertificationRepositoryLockNameV1 -RepositoryPath $RepositoryPath
    $mutex=New-Object System.Threading.Mutex($false,$name)
    $acquired=$false
    try{
        try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
        if(-not$acquired){throw "CERTIFICATION_ALREADY_RUNNING: another certification process holds the repository lock for $([IO.Path]::GetFullPath($RepositoryPath))"}
        return [pscustomobject]@{RepositoryPath=[IO.Path]::GetFullPath($RepositoryPath);Name=$name;Mutex=$mutex;Acquired=$true}
    }catch{
        if(-not$acquired){$mutex.Dispose()}
        throw
    }
}

function Exit-TPMCertificationRepositoryLockV1 {
    param([AllowNull()]$Lock)
    if($null-eq$Lock){return}
    try{if([bool]$Lock.Acquired){$Lock.Mutex.ReleaseMutex()}}finally{$Lock.Mutex.Dispose()}
}

function Invoke-TPMIsolatedProcessV1 {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$WorkingDirectoryRoot,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$LogDirectoryRoot,
        [Parameter(Mandatory=$true)][string]$LogDirectory,
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Identity,
        [int]$TimeoutSeconds=3600,
        [string]$OperatorStatusPath,
        [switch]$RelayOperatorStatus,
        [hashtable]$Environment
    )
    # WorkingDirectoryRoot/LogDirectoryRoot are the caller's own real,
    # independently-justified trust anchors -- this function never invents
    # one (e.g. by taking Split-Path on its own WorkingDirectory/
    # LogDirectory parameters). See ARCHITECTURE.md for what each
    # production caller supplies and why.
    $workingRoot=Assert-TPMOwnedDirectoryV1 -Root $WorkingDirectoryRoot -Path $WorkingDirectory -CreateIfMissing
    $logRoot=Assert-TPMOwnedDirectoryV1 -Root $LogDirectoryRoot -Path $LogDirectory -CreateIfMissing
    $nonce=[guid]::NewGuid().ToString('N')
    $prefix=$nonce+'-'+$Identity
    $stdinPath=New-TPMCreateNewFileV1 -Root $LogDirectoryRoot -Parent $logRoot -Name ($prefix+'-stdin.empty')
    $stdoutPath=New-TPMCreateNewFileV1 -Root $LogDirectoryRoot -Parent $logRoot -Name ($prefix+'-stdout.log')
    $stderrPath=New-TPMCreateNewFileV1 -Root $LogDirectoryRoot -Parent $logRoot -Name ($prefix+'-stderr.log')
    $metadataPath=Join-Path $logRoot ($prefix+'-process.json')
    $quoted=@($ArgumentList|ForEach-Object{ConvertTo-TPMWin32ArgumentV1 -Value $_})
    $started=[DateTime]::UtcNow
    $process=$null
    $timedOut=$false
    $terminationConfirmed=$false
    $exitCode=$null
    $processId=$null
    $statusOffset=0L
    $lastHeartbeat=[DateTime]::UtcNow
    try{
        $savedEnvironment=@{}
        if($Environment){
            foreach($key in $Environment.Keys){
                $savedEnvironment[$key]=[Environment]::GetEnvironmentVariable([string]$key,'Process')
                [Environment]::SetEnvironmentVariable([string]$key,[string]$Environment[$key],'Process')
            }
        }
        try{
            $process=Start-Process -FilePath $FilePath -ArgumentList $quoted -WorkingDirectory $workingRoot -NoNewWindow -PassThru -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            [void]$process.Handle
            $processId=$process.Id
        }finally{
            if($Environment){foreach($key in $Environment.Keys){[Environment]::SetEnvironmentVariable([string]$key,$savedEnvironment[$key],'Process')}}
        }
        while(-not$process.HasExited){
            if($RelayOperatorStatus-and-not[string]::IsNullOrWhiteSpace($OperatorStatusPath)-and(Test-Path -LiteralPath $OperatorStatusPath)){
                $stream=[IO.File]::Open($OperatorStatusPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try{
                    [void]$stream.Seek($statusOffset,[IO.SeekOrigin]::Begin)
                    $reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding $false),$true,1024,$true)
                    try{
                        while(-not$reader.EndOfStream){
                            $line=$reader.ReadLine()
                            if($line-match '^(\[[1-8]/8\] |Pester totals:|FINAL STATUS:|Reason:|Total elapsed:|Report:|Technical log:)'){Write-Host $line}
                        }
                        $statusOffset=$stream.Position
                    }finally{$reader.Dispose()}
                }finally{$stream.Dispose()}
            }
            if($RelayOperatorStatus-and([DateTime]::UtcNow-$lastHeartbeat).TotalSeconds-ge30){
                $lastHeartbeat=[DateTime]::UtcNow
                Write-Host ("Certification is still running - {0:hh\:mm\:ss} elapsed" -f ([DateTime]::UtcNow-$started))
            }
            if($TimeoutSeconds-gt0-and([DateTime]::UtcNow-$started).TotalSeconds-ge$TimeoutSeconds){$timedOut=$true;break}
            Start-Sleep -Milliseconds 250
        }
        if($timedOut-and-not$process.HasExited){
            try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            try{[void]$process.WaitForExit(5000)}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
        }
        $process.Refresh()
        $terminationConfirmed=$process.HasExited
        if($terminationConfirmed){$exitCode=$process.ExitCode}
    }finally{
        if($null-ne$process-and-not$process.HasExited){
            try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            try{[void]$process.WaitForExit(5000)}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            $terminationConfirmed=$process.HasExited
        }
        if($null-ne$process){$process.Dispose()}
    }
    if(-not$terminationConfirmed){throw "PROCESS_TERMINATION_UNCONFIRMED: $Identity; logs preserved at $LogDirectory"}
    Write-TPMSafeTechnicalFileV1 -Path $stdoutPath
    Write-TPMSafeTechnicalFileV1 -Path $stderrPath
    $ended=[DateTime]::UtcNow
    $metadata=[ordered]@{
        SchemaVersion=1;Identity=$Identity;FilePath=[IO.Path]::GetFileName($FilePath);ArgumentCount=@($ArgumentList).Count
        Pid=$processId;StartedUtc=$started.ToString('o');EndedUtc=$ended.ToString('o')
        DurationMilliseconds=[long]($ended-$started).TotalMilliseconds
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StandardInput=$stdinPath;StandardOutput=$stdoutPath;StandardError=$stderrPath
    }
    # Second, later revalidation point (mirrors New-TPMCreateNewFileV1's own
    # pre-open recheck) immediately before this owned file is actually
    # opened -- narrows, but does not eliminate, the residual TOCTOU race.
    Assert-TPMNoReparseInChainV1 -Root $LogDirectoryRoot -Target $metadataPath -AllowMissingLeaf
    $metadataStream=New-Object IO.FileStream($metadataPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{
        $bytes=(New-Object Text.UTF8Encoding $false).GetBytes(($metadata|ConvertTo-Json -Depth 5))
        $metadataStream.Write($bytes,0,$bytes.Length)
    }finally{$metadataStream.Dispose()}
    return [pscustomobject]@{
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StdOutPath=$stdoutPath;StdErrPath=$stderrPath;MetadataPath=$metadataPath
        StandardInputPath=$stdinPath;Pid=$metadata.Pid
    }
}

function Stop-TPMPesterSchemaV1 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    throw "PESTER_RESULT_SCHEMA_INVALID: $Reason"
}

function Assert-TPMExactObjectFieldsV1 {
    param($Value,[string[]]$Expected,[string]$Label)
    if($null-eq$Value-or$Value-isnot[pscustomobject]){Stop-TPMPesterSchemaV1 "$Label must be an object"}
    $actual=@($Value.PSObject.Properties.Name)
    if(@($Expected|Where-Object{$_-cnotin$actual}).Count-ne0-or@($actual|Where-Object{$_-cnotin$Expected}).Count-ne0){Stop-TPMPesterSchemaV1 "$Label must contain the exact documented field set"}
    return $Value
}

function Assert-TPMResultIntegerV1 {
    param($Value,[string]$Label)
    $integralTypes=@([byte],[sbyte],[int16],[uint16],[int32],[uint32],[int64])
    if($null-eq$Value-or$Value-is[bool]-or$Value.GetType()-notin$integralTypes){Stop-TPMPesterSchemaV1 "$Label must be an integral numeric value"}
    try{$number=[long]$Value}catch{Stop-TPMPesterSchemaV1 "$Label is outside the supported integer range"}
    if($number-lt0-or$number-gt2147483647){Stop-TPMPesterSchemaV1 "$Label is outside the safe range 0..2147483647"}
    return $number
}

function Assert-TPMNonblankResultStringV1 {
    param($Value,[string]$Label)
    if($Value-isnot[string]-or[string]::IsNullOrWhiteSpace($Value)){Stop-TPMPesterSchemaV1 "$Label must be a nonblank string"}
    return [string]$Value
}

function Read-TPMPesterResultV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    try{
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Stop-TPMPesterSchemaV1 'result file is missing'}
        $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if([string]::IsNullOrWhiteSpace($raw)){Stop-TPMPesterSchemaV1 'result file is empty'}
        try{$result=$raw|ConvertFrom-Json -ErrorAction Stop}catch{Stop-TPMPesterSchemaV1 'result JSON is malformed or truncated'}
        $topFields=@('SchemaVersion','Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds','Failures','Categories','Engine')
        $result=Assert-TPMExactObjectFieldsV1 $result $topFields 'result'
        $version=Assert-TPMResultIntegerV1 $result.SchemaVersion 'SchemaVersion'
        if($version-ne1){Stop-TPMPesterSchemaV1 'unsupported SchemaVersion'}
        [void](Assert-TPMNonblankResultStringV1 $result.Engine 'Engine')
        foreach($name in @('Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds')){
            $result.$name=Assert-TPMResultIntegerV1 $result.$name $name
        }
        if($result.Discovered-ne($result.Passed+$result.Failed+$result.Skipped+$result.NotRun)){Stop-TPMPesterSchemaV1 'discovered total contradicts result totals'}
        if($result.FailedContainers-gt$result.Containers){Stop-TPMPesterSchemaV1 'failed container total exceeds container total'}
        $categoryFields=@('VirtualBetaTesterTotal','VirtualBetaTesterPassed','VirtualBetaTesterFailed','HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')
        $categories=Assert-TPMExactObjectFieldsV1 $result.Categories $categoryFields 'Categories'
        foreach($name in $categoryFields){$categories.$name=Assert-TPMResultIntegerV1 $categories.$name "Categories.$name"}
        if($categories.VirtualBetaTesterTotal-ne($categories.VirtualBetaTesterPassed+$categories.VirtualBetaTesterFailed)){Stop-TPMPesterSchemaV1 'Virtual Beta Tester totals contradict pass/fail totals'}
        if($categories.VirtualBetaTesterTotal-gt$result.Discovered-or$categories.VirtualBetaTesterPassed-gt$result.Passed-or$categories.VirtualBetaTesterFailed-gt$result.Failed){Stop-TPMPesterSchemaV1 'Virtual Beta Tester totals exceed global totals'}
        foreach($name in @('HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')){
            if($categories.$name-gt$categories.VirtualBetaTesterTotal){Stop-TPMPesterSchemaV1 "Categories.$name exceeds VirtualBetaTesterTotal"}
        }
        if($null-eq$result.Failures-or$result.Failures-isnot[array]){Stop-TPMPesterSchemaV1 'Failures must be a JSON array'}
        foreach($failure in @($result.Failures)){
            $entry=Assert-TPMExactObjectFieldsV1 $failure @('Name','Message') 'Failures entry'
            [void](Assert-TPMNonblankResultStringV1 $entry.Name 'Failures.Name')
            [void](Assert-TPMNonblankResultStringV1 $entry.Message 'Failures.Message')
        }
        if(@($result.Failures).Count-ne$result.Failed){Stop-TPMPesterSchemaV1 'failure-entry count does not equal Failed'}
        return $result
    }catch{
        if($_.Exception.Message-like'PESTER_RESULT_SCHEMA_INVALID:*'){throw}
        Stop-TPMPesterSchemaV1 'unexpected validation failure'
    }
}
Export-ModuleMember -Function ConvertTo-TPMWin32ArgumentV1,ConvertTo-TPMSafeTechnicalTextV1,Write-TPMSafeTechnicalFileV1,Invoke-TPMIsolatedProcessV1,Read-TPMPesterResultV1,Test-TPMTransientIOHResultV1,Invoke-TPMSafeFileRetryV1,New-TPMSanitizationExhaustedExceptionV1,Assert-TPMOwnedDirectoryV1,New-TPMOwnedDirectoryChainV1,New-TPMCreateNewFileV1,Test-TPMPathIsContainedV1,Assert-TPMNoReparseInChainV1,Get-TPMPathComponentsV1,Get-TPMCertificationGitIdentitySnapshotV1,New-TPMCertificationGitIdentityV1,Get-TPMCertificationRepositoryLockNameV1,Enter-TPMCertificationRepositoryLockV1,Exit-TPMCertificationRepositoryLockV1
