# Registration Ledger

AutoSync, Register only, and manual registration keep a record of what a run chose and what it did. If your PC crashes or you close the window, the record still tells what happened.

The record is one file: `TeknoParrotManager\State\TPM-RegistrationLedger.json` in your TeknoParrot folder. You do not need to open it. Keep it when you ask for help. The [[Support Package]] reads it.

---

## If it says the record is unusable

If the file is damaged, unreadable, too big, or not a file TeknoParrot Manager can trust, you see "Action required". TeknoParrot Manager starts no extraction or registration and does not touch the file.

What to do:

1. Do not delete or edit the file.
2. Make a [[Support Package]].
3. Ask for help before you run again.

---

<details>
<summary>Details</summary>

**What is recorded**

- Before the first write: the ZIPs AutoSync chose, or the game folders Register only will act on. If this cannot be saved and read back, the run stops and changes nothing.
- Each profile write is noted first. It is marked `VERIFIED` only after the saved profile is read back and its game path and executable match. A write that could not be read back stays `WRITE_ATTEMPTED_UNVERIFIED`.
- Each game folder ends as `VERIFIED`, `PARTIAL`, `SKIPPED` (with a reason), `FAILED_BEFORE_WRITE`, or `WRITE_ATTEMPTED_UNVERIFIED`.
- Work that an earlier run never finished shows as `INTERRUPTED_UNKNOWN` on the next run. It is never reported as success.
- A fatal error adds a short cleaned note, cut at 500 characters.

**Limits**

- The file is capped at 1 MiB. When it is full, the oldest finished runs are dropped first, then the oldest interrupted ones. A run that is still going is never dropped. Each drop is counted in `TrimmedOperations` inside the file and written to the log. If there is still no room, the run is refused and nothing changes.
- It records AutoSync extraction and registration writes. Other jobs that edit profiles, like path repair in the health check, are not recorded.
- If the record cannot be updated after a profile was already written, the screen can still list the games it registered. The warning, the log, and the last saved record show the doubt.

**What the support package adds**

The package has a cleaned copy of the record, and a short file about the running copy of TeknoParrot Manager: script path and SHA-256, PowerShell version, Windows, and the version label. If a `TPM-PackageIdentity.json` file sits beside the script, its package id and source commit are added. A normal release has no such file, so those fields say `unavailable`.

</details>

Back to [[Home]].
