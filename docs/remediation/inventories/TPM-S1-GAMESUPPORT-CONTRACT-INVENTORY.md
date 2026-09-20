# TPM-S1 GameSupport Specification and System Invariant Inventory

Status: implementation basis for `TPM-S1-CURRENT-RELEASE-GAMESUPPORT-002`

## Governing specifications

| Specification | Authority used in this slice | Invariant extracted |
|---|---|---|
| `contracts/snapshots/TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628/snapshot-manifest.json` | Accepted immutable current-release evidence | SnapshotId, asset SHA, source-proof commit, and catalog counts are exact; source proof is semantic evidence, not official release provenance |
| `contracts/snapshots/TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628/delta.json` | Accepted machine-generated historical/current comparison | Added/removed/changed/unchanged counts and identities are regenerated and compared, never hand-edited |
| `contracts/_schema/GameSupportContractV1.3.schema.json` | Current additive static contract schema | Contract fields are static evidence and declarations; runtime state is excluded |
| `contracts/_schema/GameSupportContractRegistryV1.3.schema.json` | Current registry schema | One registry binds one SnapshotId, source identity, expected count, totals, audit, gate, and sorted contracts |
| Pinned `GameProfiles`, `GameSetup`, and `Metadata` roots | Source serialization contract | Profile filename stem is canonical identity; optional evidence joins by case-insensitive stem; raw source hashes remain evidence |
| `TPM-GAME-SUPPORT-CONTRACTS-001` | Historical contract compatibility | Historical 695 generation, schema routing, special declarations, and zero-UNCLASSIFIED gate remain intact |

## Contract rules

1. `HISTORICAL_PINNED_695` and `CURRENT_RELEASE_925` are explicit generation modes. No mode silently substitutes the other corpus.
2. Current mode requires SnapshotId `TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628`, source-proof commit `dc998e374608abbda373bb3c236db5b26b5afca7`, historical source root, and accepted delta evidence.
3. Current mode accepts no installed profile root, UserProfiles root, fixture root, DAT input, or live network lookup.
4. Current mode requires 925 GameProfiles, 383 GameSetup files, and 923 Metadata files. The accepted manifest remains authoritative for the 2231-file catalog total.
5. Profile codes compare case-insensitively for uniqueness and preserve source spelling in output. Ordering is deterministic.
6. GameProfile executable declarations have precedence. GameSetup `GameExecutableLocation` is a fallback only when the GameProfile has no executable declaration.
7. Equivalent declarations are normalized case-insensitively for comparison. Duplicate equivalent candidates collapse; contradictory declarations are never silently selected and produce a non-safe posture.
8. Missing or ambiguous executable evidence remains `REVIEW_MANUAL` or `BLOCKED_UNSUPPORTED`; it never becomes `AUTOMATED_SAFE` by default.
9. Static generation emits no runtime observations, launch results, privilege observations, controller identity, installed-file state, or owner-runtime claims.
10. Every current profile receives one validated schema 1.3 contract. `UNCLASSIFIED` is a generation failure.
11. `Source.Commit` records the pinned semantic proof identity. It is not relabeled as official release provenance; SnapshotId binds the accepted release evidence.
12. Output paths are rooted under the caller-owned output directory and are rejected if they escape that root.
13. Two clean runs from the same pinned roots and explicit timestamp produce byte-identical output.
14. Added identities and changed-profile matrix are generated from pinned roots and must match the accepted delta counts exactly: 230 added, 0 removed, 38 changed, 657 unchanged.
15. Existing schema 1.3 remains sufficient. No schema bump is allowed unless a current record cannot be represented without weakening an existing invariant.

## System invariant matrix

| ID | Invariant | Permanent evidence |
|---|---|---|
| S1-I01 | Explicit mode cannot cross-feed historical/current roots | Focused mode validation and current-source rejection tests |
| S1-I02 | Current count is exactly 925 | Current generation registry count and manifest check |
| S1-I03 | No case-insensitive duplicate profile identity | Registry validator and source inventory check |
| S1-I04 | No final `UNCLASSIFIED` | Registry release gate and focused test |
| S1-I05 | Snapshot/source binding is exact | Snapshot ID and proof commit assertions |
| S1-I06 | Added set is exactly 230 | Generated comparison artifact vs `delta.json` |
| S1-I07 | Changed set is exactly 38 | Generated matrix vs `delta.json` |
| S1-I08 | GameProfile executable wins over GameSetup | Precedence fixture |
| S1-I09 | Missing GameProfile executable uses GameSetup fallback | VirtuaRLimit/current source check |
| S1-I10 | Contradictory source declarations cannot become safe | Conflict fixture and posture assertion |
| S1-I11 | Static output contains no runtime observations | Contract schema and output scan |
| S1-I12 | Source evidence paths/hashes are deterministic | Dual-generation byte/hash comparison |
| S1-I13 | Output is contained below caller root | Containment test |
| S1-I14 | Historical 695 compatibility remains unchanged | Existing posture corpus and historical mode tests |
| S1-I15 | Special contract declarations remain exact | Showdown, cxbxr, ReVolt, rrv/Road Fighters checks |

## Adversarial review questions

- Can an omitted current root cause the generator to fall back to the historical 695 source? It must fail instead.
- Can a mutable master checkout or installed machine state enter current output? It must be rejected by mode inputs.
- Can a GameSetup executable silently override a GameProfile declaration? It must not.
- Can a conflict be hidden by choosing the first candidate? It must not.
- Can a duplicate profile differing only by case enter the registry? It must not.
- Can a runtime observation or launch result appear in a static contract? It must not.
- Can the accepted delta counts be asserted while the actual generated identities differ? The generator must compare identities, not counts alone.
- Can schema validation pass while `UNCLASSIFIED` remains? The registry release gate must still fail.
