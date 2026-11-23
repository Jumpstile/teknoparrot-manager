# TPM Release Gate
STATUS: v1.0 RC9.1 is the latest published release (v1.0 RC9 is the previous one). Every later release (Version 1.0) must pass this gate first.
- [ ] Complete source engineering: all applicable universal progress UI operations, final/cancel/stall lifecycle, PostgreSQL safety, exact-candidate reconciliation of release:rc-required issues.
- [ ] Preserve proof of source SHA, changed files, dispositions, required runtime assets and private backup ref.
- [ ] Owner approves the real final progress-UI screenshot (not a mockup).
- [ ] OWNER explicitly authorizes testing after source engineering and screenshot approval.
- [ ] Then complete PS5.1/PS7 syntax/static/security/quality gates, Pester, CI, candidate packaging checks and owner smoke against the same frozen source. Earlier/stale results are not candidate proof.
- [ ] Verify exact package filename, manifest, assets, and SHA256 only after qualified packaging is authorized.
- [ ] Owner makes final release decision. Never auto-merge, tag, publish, push public WIP, or alter live TeknoParrot.
- [ ] Publish README/use instructions and release notes with each owner-approved version; omit AI attribution/coauthor trailers.
A PRE-TEST HOLD does not stop source coding. See the scoped docs/remediation contracts for implementation details.
