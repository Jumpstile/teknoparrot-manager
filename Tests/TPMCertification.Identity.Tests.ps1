BeforeAll {
    $script:executionModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Execution.psm1'
    Import-Module $script:executionModulePath -Force

    function New-TestGitRepository {
        param([Parameter(Mandatory=$true)][string]$Root)
        $repo=Join-Path $Root 'repo'
        New-Item -ItemType Directory -Path $repo -Force|Out-Null
        & git -C $repo init -q
        & git -C $repo checkout -q -B main
        & git -C $repo -c user.name=TPM-Test -c user.email=tpm-test@example.invalid commit --allow-empty -q -m baseline
        $head=(& git -C $repo rev-parse HEAD).Trim()
        & git -C $repo update-ref refs/remotes/origin/main $head
        & git -C $repo config remote.origin.url https://example.invalid/tpm.git
        & git -C $repo config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        & git -C $repo config branch.main.remote origin
        & git -C $repo config branch.main.merge refs/heads/main
        return $repo
    }
}

Describe 'Certification checkout identity and serialization guard' {
    It 'records a clean branch, exact HEAD, cached remote SHA, and stable ref snapshots' {
        $repo=New-TestGitRepository -Root $TestDrive
        $start=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        $end=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        $head=(& git -C $repo rev-parse HEAD).Trim()
        $identity=New-TPMCertificationGitIdentityV1 -Start $start -End $end -ExpectedBranch 'main' -ExpectedCommit $head

        $identity.IdentityValid|Should -BeTrue
        $identity.RefMutationDetected|Should -BeFalse
        $identity.Start.Branch|Should -Be 'main'
        $identity.Start.Commit|Should -Be $head
        $identity.Start.RemoteRef|Should -Be 'origin/main'
        $identity.Start.RemoteCommit|Should -Be $head
        $identity.Start.Clean|Should -BeTrue
        $identity.Start.RefSnapshotSha256|Should -Match '^[0-9a-f]{64}$'
        $identity.Start.ReflogSnapshotSha256|Should -Match '^[0-9a-f]{64}$'
    }

    It 'rejects a checkout that switches away and back even when final branch and SHA match' {
        $repo=New-TestGitRepository -Root $TestDrive
        & git -C $repo checkout -q -b other
        & git -C $repo checkout -q main
        $head=(& git -C $repo rev-parse HEAD).Trim()
        & git -C $repo update-ref refs/remotes/origin/main $head
        $start=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        & git -C $repo checkout -q other
        & git -C $repo checkout -q main
        $end=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        $identity=New-TPMCertificationGitIdentityV1 -Start $start -End $end -ExpectedBranch 'main' -ExpectedCommit $head

        $identity.IdentityValid|Should -BeFalse
        $identity.RefMutationDetected|Should -BeTrue
        $identity.RefMutationReason|Should -Match 'CERTIFICATION_REFLOG_MUTATED'
        $identity.End.Branch|Should -Be 'main'
        $identity.End.Commit|Should -Be $head
    }

    It 'fails a supplied expected branch or commit mismatch' {
        $repo=New-TestGitRepository -Root $TestDrive
        $snapshot=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        $identity=New-TPMCertificationGitIdentityV1 -Start $snapshot -End $snapshot -ExpectedBranch 'review/not-this-branch' -ExpectedCommit ('b'*40)

        $identity.IdentityValid|Should -BeFalse
        $identity.RefMutationDetected|Should -BeFalse
        $identity.RefMutationReason|Should -Match 'CERTIFICATION_EXPECTED_BRANCH_MISMATCH'
        $identity.RefMutationReason|Should -Match 'CERTIFICATION_EXPECTED_COMMIT_MISMATCH'
    }

    It 'fails closed when ref or reflog snapshots are unavailable' {
        $repo=New-TestGitRepository -Root $TestDrive
        $snapshot=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo
        $snapshot.RefSnapshotSha256=$null
        $snapshot.ReflogSnapshotSha256=$null
        $identity=New-TPMCertificationGitIdentityV1 -Start $snapshot -End $snapshot -ExpectedBranch 'main' -ExpectedCommit $snapshot.Commit

        $identity.IdentityValid|Should -BeFalse
        $identity.RefMutationReason|Should -Match 'CERTIFICATION_REF_SNAPSHOT_UNAVAILABLE'
        $identity.RefMutationReason|Should -Match 'CERTIFICATION_REFLOG_SNAPSHOT_UNAVAILABLE'
    }

    It 'does not synthesize a stable ref snapshot when Git identity reads fail' {
        $repo=Join-Path $TestDrive 'not-a-git-repository'
        New-Item -ItemType Directory -Path $repo -Force|Out-Null
        $snapshot=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $repo

        $snapshot.Branch|Should -BeNullOrEmpty
        $snapshot.Commit|Should -BeNullOrEmpty
        $snapshot.RemoteRef|Should -BeNullOrEmpty
        $snapshot.RemoteCommit|Should -BeNullOrEmpty
        $snapshot.Clean|Should -BeFalse
        $snapshot.RefSnapshotSha256|Should -BeNullOrEmpty
        $snapshot.ReflogSnapshotSha256|Should -BeNullOrEmpty
    }

    It 'prevents a second certification process from entering the same checkout lock' {
        $repo=Join-Path $TestDrive 'lock-repo'
        New-Item -ItemType Directory -Path $repo -Force|Out-Null
        $lock=Enter-TPMCertificationRepositoryLockV1 -RepositoryPath $repo
        try{
            $module=$script:executionModulePath.Replace("'","''")
            $path=$repo.Replace("'","''")
            $code="Import-Module '$module' -Force; try { Enter-TPMCertificationRepositoryLockV1 -RepositoryPath '$path' | Out-Null; exit 0 } catch { if (`$_.Exception.Message -like 'CERTIFICATION_ALREADY_RUNNING:*') { exit 17 }; exit 18 }"
            $process=Start-Process (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-Command',$code) -Wait -PassThru
            $process.ExitCode|Should -Be 17
        }finally{Exit-TPMCertificationRepositoryLockV1 -Lock $lock}
    }
}
