# TPM -- Architecture Quick Reference (2026-10-25)
- Source is separate from installed/live TeknoParrot. Runtime root: <TeknoParrotRoot>\TeknoParrotManager\ (Logs, Reports, SupportPackages, State, Cache, Manifests, Backups, Temp, Assets). Verify real directories.
- Local Git worktrees only; NAS/SMB is for data and mirrors, not active Git worktrees.
- Stage untrusted archives in unique temp directories; validate containment, provenance and executable signatures before transactional promotion.
- PostgreSQL credentials and trust policy need protected storage, recoverable restoration, and fail-closed error reporting; no secrets in source/logs.
- Option A shared progress: accurate determinate totals only with known denominators; otherwise indeterminate; correct start/finish/failure/cancel, no fake 100%, bounded repaint, no footer overlap, all applicable operation families.
- PS5.1/PS7, path safety, state persistence, package allowlist and exact-source release gates are governed by SECURITY.md, docs/remediation/ and versioned implementation contracts.
- PRE-TEST HOLD is active; no test evidence or screenshot approval may be inferred from source changes.
