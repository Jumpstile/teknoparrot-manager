# TPM Security -- Active Boundaries
- All external archives, paths, profiles, XML and tools are untrusted; validate identity, containment, signature/provenance and permissions before writes.
- Stage extraction, reject traversal/reparse/symlink hazards, and promote transactionally with rollback and last-known-good preservation.
- Encrypt or otherwise protect PostgreSQL credentials and trust policy; fail closed on restoration errors.
- Exclude secrets, controllers, tokens and private machine evidence from logs, support packages and WIP backups.
- Keep source work separate from live TeknoParrot. Security and certification procedures follow owner testing authorization.
