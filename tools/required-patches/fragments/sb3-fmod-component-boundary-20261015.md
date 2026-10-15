# SB3 FMOD component-restoration boundary

This is a review delta for the SB3 guide-required FMOD components, not a claim that TPM installs or validates a complete FMOD setup.

## Exact binding

- Guide record 906 binds the 1.91 x64 SB3 build to `fnfmega.exe`; the official profile is `SB3.xml` at pinned upstream commit `d299c2b7af9704774428d6e14ba54129065e1560`, blob `8ff44ee510d1a6727ec75fa90e87ced0790c6ca7`.
- The exact Main ZIP is `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills PC][TP].zip`. Its size is 2,023,906,074 bytes. The guide build label omits `PC`; do not normalize the Main filename to the guide label.
- Main executable: `fnfmega.exe`, 650,752 bytes, SHA-256 `7F84AE68A35587EA87312ED59247EB0379F00826B8F2473A09155792A90AEEAD`.
- Independent exact-Main member receipt: `SB3-Fmod-Main-Independent-Member-Proof-20261015T071758Z.json`, SHA-256 `553D52FB96ABB68DD610D21BE2FF0455C2162AA44762CC0A720F4F17F0FCFCE5`.
- The matching component source set is `Unity Fmod x64_v1.10.10.zip`, original SHA-256 `399a8865b77b1d59b0bd3a252807d751bf547e9d096bdbc04b394ef1f6c93299`; its verified converted collection SHA-256 is `631b0551816dec94b15f06b8d673bfef42f79cf081a97d995133a7e9e6fc5d79`. The source mapping binds SB3 1.91 x64. These names and bytes do not prove installed DLL version metadata.
- Main FMOD members match the exact component-package member bytes:

| Member / target | Size | SHA-1 | SHA-256 |
|---|---:|---|---|
| `fnfmega_Data/Plugins/x86_64/fmod64.dll` | 1,755,648 | `F062F4158722FC833D470DAF2BD7333AC003A958` | `E3508221439C073EC01391680D14125C7B72BB32280BDC0A90D980A2AE143FD2` |
| `fnfmega_Data/Plugins/x86_64/fmodstudio64.dll` | 1,419,264 | `A3A614C1EA5891FEEEA06EC86FD7BA1DA441C853` | `CFE1D74BB4EA8BFD842EE8CBCCB3FDE61F366AD0BB01AF59965CCF304425DBAB` |

The guide and source-package name identify FMOD x64 v1.10.10. The DLL member evidence proves exact bytes and x64 machine type; it does not establish DLL file-version metadata or runtime compatibility in an installed game.

## Recipe behavior and limits

- The fragment contains two independent one-file `CreateFile` entries. Each is sourced from its exact Main ZIP member and targets the same relative member path.
- Each operation is absent-only. An exact after-state is treated as already applied; a different existing target is refused. Undo uses that operation's own creation receipt and exact file identity. The recipe does not replace existing files or create missing parent directories.
- `fnfmega.exe` must match its exact SHA-256 and `fnfmega_Data/Plugins/x86_64` must already exist as a safe directory. No hardware predicate is evidenced.
- The sibling FMOD DLL is deliberately not a prerequisite. The engine's `File` prerequisite checks safe file presence, not its hash or version; adding it would not prove a compatible pair. Restoring one absent component leaves any absent, exact, or foreign sibling untouched. Pair compatibility and pair completeness therefore remain unverified.
- The two entries are separate transactions, not an atomic pair. The engine's local-source resolver stages one exact source member per recipe entry. If review requires all-or-nothing installation or exact counterpart validation, this fragment is insufficient and must remain unintegrated until the engine contract supports that requirement.
- The guide separately requires BepInEx and the SB3 plugin. This fragment does not verify those prerequisites and is not a complete setup or launch-readiness result.

No DLL is included in this lane. The portable tests use synthetic text payloads and the frozen integration engine; they do not execute any game or DLL.
