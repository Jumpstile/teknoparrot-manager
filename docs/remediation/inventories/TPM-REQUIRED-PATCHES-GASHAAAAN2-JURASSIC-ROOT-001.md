# Gashaaaan 2 Jurassic Park root DLL source inventory

ID: TPM-REQUIRED-PATCHES-GASHAAAAN2-JURASSIC-ROOT-001.

- Guide record: array index 478, exact ProfileId `Gashaaaan2`; guide Main set `Gashaaaan Refill! (2009-02-24)(JPN)[Konami PC][TP]`.
- Guide explicitly requires DLLs from Jurassic Park and names destination `\\IG2\\exec_root` alongside `gasya.exe`.
- Donor record: exact guide profile `JurassicPark`, unique, Main set `Jurassic Park (1.08)(2015)[Raw Thrills Linux PC][TP]`. The cached source inventory maps `jurassic_sound_dll.zip` to this same 1.08 game set and source role; no conflicting versioned donor association was found in the bounded records.
- Exact Gashaaaan executable member: `IG2/exec_root/gasya.exe`, 2,842,624 bytes, SHA1 `A7BB8F7364C764D3167C86315E7ECEA62953658F`, SHA256 `67BDEBF22D64E997A59423EC68A36CF234F0060B4FB32BAFBCE6E5A6C2D5FEB6`; unique member, Deflate. Proof: private `Drivers-Lane/Gashaaaan2-DLL-Source-Identity-20261015.json`, input executable receipt SHA256 `5C3D93B4D1C5FAF7B46EF5BD647F57731373126E0A8064A8DC408E18BC99451E`.
- Three exact source members in the exact Jurassic Park 1.08 Main ZIP:

| Target under `IG2/exec_root/` | Source member | Size | CRC32 | SHA1 | SHA256 |
|---|---|---:|---|---|---|
| `libogg.dll` | `libogg.dll` | 21,504 | `C9C701E0` | `DE9DB7F730A0B8273FE2D3ADB3AC6C56510C8972` | `E6B423A237ED5C1E2503F1B3E48855061A74343BDD8BBDB5DAD004C234513328` |
| `libvorbis.dll` | `libvorbis.dll` | 667,648 | `DEAD51EC` | `1537A1D208F2C5DC756B394393C9A3C77E962D95` | `971A471C5A7710BBFDAAA62D7A31EBC094B359FD374D015B602679E7CFEEAD69` |
| `libvorbisfile.dll` | `libvorbisfile.dll` | 33,792 | `24086D90` | `AE4F5F737532CE4774332733889BD62FF71BE596` | `76E8A51A1E2F9FFC42D00A53F1214D4653B13182BDD30A154BBB9AE2853A8B97` |

- The exact Gashaaaan Main central directory has four DLLs already in `IG2/exec_root` (`D3DX9_39.dll`, `ig2ACLib.dll`, `libavs-win32.dll`, `libbms.dll`); these three target names are absent from that ZIP. No live installation was examined.
- Candidate operations: three exact `CreateFile` operations, `BeforeState: Absent`; unknown present bytes must not be replaced. No executable modification, generated file, ABI, gameplay, or runtime-certification claim.
- Initial slice boundary excluded integration surfaces. Root later authorized this dedicated worktree to append the three entries to the central catalog, update only the engine catalog-header pin, update exact global census expectations and CI focused-test routing/execution, and add dated status notes to the PR-321 control board and reconciliation. The prior 69 catalog entries remain unchanged and ordered; this candidate is 72 entries and remains untested pending root's focused gate. No engine behavior change, Walking Dead DLLs (`pm/` donor paths remain unapproved), full dependency completion, payload execution, user-facing gameplay claim, or runtime certification.
- Source receipt: private `Drivers-Lane/Gashaaaan2-DLL-Source-Identity-20261015.json`. Catalog base pin is calculated from the current source at fragment-authoring time, never manually copied.
