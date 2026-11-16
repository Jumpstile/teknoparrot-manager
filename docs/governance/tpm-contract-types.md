# TPM Contract Types

Every TPM remediation slice names the contract types it touches.

## UX contract

Defines what the user sees, available choices, accepted values, result of each choice, invalid-input behavior, and forbidden ambiguity.

## Mutation contract

Defines files allowed to change, required backups, confirmation tokens, rollback behavior, and fail-closed rules.

## Progress contract

Defines the long-running operation, compact renderer, heartbeat/elapsed behavior, and banned legacy UI. Bounded or instant work records why no progress surface is needed.

## Repair contract

Defines affected inputs, excluded inputs, search/copy/save scope, backup requirements, and forbidden unrelated optional flows.

## Support evidence contract

Defines logs and reports captured, freshness timestamps, stale-evidence labeling, and fatal evidence that must surface to the user.

## Package/runtime contract

Binds exact source SHA, exact ZIP SHA, package contents, runtime-smoke checklist, and owner proof. Source tests cannot satisfy this contract alone.
