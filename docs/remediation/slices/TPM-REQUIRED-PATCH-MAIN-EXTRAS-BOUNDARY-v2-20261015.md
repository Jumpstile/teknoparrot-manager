# MaiMai GreeN and Rabbids Hollywood Main-component boundary (corrected)

Status: local Issue #351 candidate boundary for the three-entry Main-source delta. This version supersedes the earlier boundary's ambiguous guide-index labels; it does not overwrite that historical artifact.

## Exact guide bindings

The Full Guide records are identified by zero-based `ArrayIndex`, not by `SourcePath`:

| ArrayIndex | ProfileId | Build/archive label | Setup executable | Guide SourcePath |
|---:|---|---|---|---:|
| 740 | `MaiMaiGreen` | `maimai GreeN (2013)[Sega RingEdge 2][TP]` | `maimai/maimai_dump_.exe` | `[514]` |
| 1031 | `RabbidsHollywood` | `Rabbids Hollywood (2018)[Adrenaline PC][TP]` | `Game.exe` | `[702]` |

The guide note for MaiMai GreeN names `freeglut.dll` and `libcurl.dll` in the main folder. The Rabbids note names `RabbidsHollywood_Operator.exe` for operator settings. These records do not establish a complete setup or launch-readiness claim.

## Source and target pins

All three recipes use one Main archive member apiece, exact executable identity, and a single `CreateFile` operation with `BeforeState: Absent`. The ZIP member pins below were read from the exact named archives; each member uses ZIP method 8 (Deflate). No complete-archive hash is claimed.

| Profile | Executable SHA-256 | Main source member | Size | Source SHA-1 | Source SHA-256 | Target |
|---|---|---|---:|---|---|---|
| `MaiMaiGreen` | `B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029` | `maimai/freeglut.dll` | 218624 | `C06C86B2D660C60DD9C57DEF62E7D9DB9960DE27` | `C0968C2D0D9DB9263304A7E0B86F41125A9642E20EA96741B9F75F15E424298E` | `maimai/freeglut.dll` |
| `MaiMaiGreen` | `B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029` | `maimai/libcurl.dll` | 325632 | `DEAD9B68373A54EF43E63BC10CD651CF8D320264` | `D86C6E191F0411DE94EA0724DE1C26E7EA58ED1564A6438006B111C07D05BEEE` | `maimai/libcurl.dll` |
| `RabbidsHollywood` | `979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D` | `RabbidsHollywood_Operator.exe` | 503296 | `5B2046A677A426B56AF20F873305B52826FFD00F` | `B3622686EF6CE75F17805137857417B6F1B50A2AE962E979B20AAE67E69777B7` | `RabbidsHollywood_Operator.exe` |

The source-set labels in the schema-3 catalog are `maimai GreeN (2013)[Sega RingEdge 2][TP].zip` and `Rabbids Hollywood (2018)[Adrenaline PC][TP].zip`. The three source members were independently hashed from their Main archives; payloads were not extracted or executed.

## Deliberate limits

- These are independent absent-target repairs. Existing target bytes are not overwritten; exact-after targets are idempotently recognized; foreign bytes are refused; undo is receipt-bound.
- `RabbidsHollywood_Operator.exe` is separate from the existing `Assembly-CSharp.dll` and BepInEx operator-plugin recipes. This recipe does not execute it, edit registry or `.conf` state, or assert that operator setup is complete.
- The two MaiMai DLLs are separate transactions, not an atomic pair. No dependency, architecture, compatibility, or launch-readiness assertion is added.
- No installed game target was inspected or changed. Owner runtime and gameplay proof remain pending.

The corrected private source proof is `ManagedGuide-Main-Component-Restore-Proof-20261015T092737Z-v3.json` (SHA-256 `7F912B203320D1B4BB0DBE7037DD38DFA6DEEF45E23E5480CA48647497047ACD`). Its exact Main ZIP member proof is `MaiMai-Rabbids-Main-Exact-Member-Proof-20261015T092737Z.json` (SHA-256 `F19F55F9534AF82EEF679953543FA4DCBDEA795F0053CEFB05A3915DB858F05C`). Both remain outside the repository. Earlier boundary and source-proof files remain unchanged as historical evidence.
