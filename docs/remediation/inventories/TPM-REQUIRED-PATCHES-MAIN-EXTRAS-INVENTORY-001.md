# Main-extra component restoration inventory

Status: Required specification/system-invariant inventory for the three-entry Issue #351 follow-up slice `TPM-REQUIRED-PATCH-MAIN-EXTRAS-20261015`. This branch is a local 61-entry candidate over the unchanged 58-entry parent checkpoint; owner-runtime acceptance is separate.

## Scope and exact bindings

The recipes restore only three guide-named components from exact local Main ZIPs. Guide `ArrayIndex` and `SourcePath` are distinct identifiers and are recorded separately in `docs/remediation/slices/TPM-REQUIRED-PATCH-MAIN-EXTRAS-BOUNDARY-v2-20261015.md`.

| ID | Profile / build / executable | Main source member -> target | Source size / SHA-1 / SHA-256 |
|---|---|---|---|
| `maimai-green-freeglut-main-restore` | `MaiMaiGreen` / `maimai GreeN (2013)[Sega RingEdge 2][TP]` / `maimai/maimai_dump_.exe` SHA-256 `B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029` | `maimai/freeglut.dll` -> `maimai/freeglut.dll` | 218624 / `C06C86B2D660C60DD9C57DEF62E7D9DB9960DE27` / `C0968C2D0D9DB9263304A7E0B86F41125A9642E20EA96741B9F75F15E424298E` |
| `maimai-green-libcurl-main-restore` | `MaiMaiGreen` / `maimai GreeN (2013)[Sega RingEdge 2][TP]` / `maimai/maimai_dump_.exe` SHA-256 `B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029` | `maimai/libcurl.dll` -> `maimai/libcurl.dll` | 325632 / `DEAD9B68373A54EF43E63BC10CD651CF8D320264` / `D86C6E191F0411DE94EA0724DE1C26E7EA58ED1564A6438006B111C07D05BEEE` |
| `rabbids-hollywood-operator-main-restore` | `RabbidsHollywood` / `Rabbids Hollywood (2018)[Adrenaline PC][TP]` / `Game.exe` SHA-256 `979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D` | `RabbidsHollywood_Operator.exe` -> `RabbidsHollywood_Operator.exe` | 503296 / `5B2046A677A426B56AF20F873305B52826FFD00F` / `B3622686EF6CE75F17805137857417B6F1B50A2AE962E979B20AAE67E69777B7` |

Each exact source member was read from its named Main archive with ZIP method 8 (Deflate). The whole Main archive was not hashed. The private source proof records archive identities, member metadata, and the exact source executable pins.

## Specification inventory (REQUIRED)

Governing contract: schema-3 recipe catalog and the existing required-patch source/target and transaction invariants. This slice changes no engine behavior.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| MEX-SPEC-001 | Every row binds its exact ProfileId, BuildName, executable path/hash, Main SourceSet/SourceEntry, source size, SHA-1, and SHA-256. SHA-1 identifies source metadata; runtime payload integrity uses SHA-256. | Implemented in candidate | Schema-3 catalog and exact three-entry fragment | `binds three exact source members and the integrated 61-entry catalog`; private member proof | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| MEX-SPEC-002 | Each entry has one `CreateFile` operation, exact source/target member path, `BeforeState: Absent`, and matching source/after/payload SHA-256. | Implemented in candidate | Catalog rows and unchanged transaction engine | Source/aggregate assertion; synthetic apply, read-back, repeat, undo, and foreign-byte refusal | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| MEX-SPEC-003 | Existing target bytes are never replaced. Exact-after bytes are idempotent; unrecognized existing bytes are refused; undo requires the exact transaction receipt. | Existing engine invariant; candidate behavior verified | Existing planner, apply, read-back, and undo functions | Focused portable test for all three recipes on PS7 and PS5.1 | Issue #351 / slice / `TPM-TRUTH-001`, `TPM-EVIDENCE-001` |
| MEX-SPEC-004 | No dependency, architecture, hardware, registry, `.conf`, or cross-file atomicity claim is inferred from the guide note. | Implemented in candidate metadata | Empty prerequisites; three independent single-file operations | Fragment metadata checks; corrected boundary | Issue #351 / slice / `TPM-TRUTH-001` |
| MEX-SPEC-005 | The aggregate catalog has 61 unique recipe IDs across 23 ProfileIds, 53 `CreateFile` and eight `ReplaceFile` operations; the engine pin equals the catalog's exact SHA-256. | Verified in candidate | Catalog, engine hash pin, CI focused test route | PS7 and PS5.1 focused aggregate guards: 13 selected passed each, zero failed/skipped/inconclusive; 1,483 manager tests not run | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |

## Deliberate limits

- The MaiMai DLLs are independent repairs; the engine does not apply them atomically.
- The Rabbids operator executable is distinct from the Assembly-CSharp trigger/crosshair component and BepInEx operator plugin. This recipe does not execute it or modify operator configuration/registry state.
- No installed target was inspected or modified. No dependency, architecture compatibility, complete setup, launch-readiness, owner-runtime, or gameplay claim is made.
- No full Main, Support, or canonical suite was run in this bounded lane. Broader gates remain with the root integration owner.
