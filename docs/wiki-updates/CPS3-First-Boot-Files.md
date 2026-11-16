# CPS3 First-Boot Files (optional)

The first time each Capcom CPS3 game runs (Street Fighter III, JoJo, Red Earth, and the CPS3 multi-game), TeknoParrot builds a cache file, so the first start is slow. If you already own the matching cache (`.simms`) and save (`.nv`) files, TeknoParrot Manager can copy them into your TeknoParrot folder.

This step is optional. Your games work without it. Only the first start is slower.

---

## Your own files only

TeknoParrot Manager does not include, download, or point to these files. You browse to a folder or `.zip` you already have.

---

## When it shows up

At the end of a normal run, after the dgVoodoo2 step, only if a CPS3 game is registered. It does not show in a preview or an unattended run, and it is not in the main menu.

1. Answer `Copy CPS3 files you already have? (Y/N, default N)`.
2. Choose **F** for a folder, **Z** for a `.zip`, or **C** to cancel.
3. For a folder, pick the one that holds the `TeknoCPS` folder and `README.txt`.

If you say no, or pick nothing, nothing changes.

---

## All or nothing

TeknoParrot Manager checks the whole set first. A missing file, an extra file, or a file with the wrong size or checksum refuses the whole set and nothing is copied. This can take a while, because every file is read.

If your TeknoParrot folder already has all the files, it says nothing needs to be copied.

<details>
<summary>Details</summary>

- The set is compared with a built-in list of 103 files (name, size and SHA-256): 19 `.simms` caches, 83 `.nv` files, and `README.txt`. One `.simms` cache is checked but never installed. The checksum of the outer `.zip` is not checked, only the files inside it.
- Files go to `TeknoCPS\cps3-install\` (`.simms`) and `TeknoCPS\nvram\` (`.nv`) in your TeknoParrot folder.
- `.nv` files hold saves. They are copied only when absent. A different `.nv` file is never replaced.
- A different `.simms` cache is left alone, and you are asked `Replace them with the verified files from your location? (Y/N, default N)`. Yes replaces only those files and keeps a recovery copy until the new ones are checked.
- The copy is checked after it is done and rolled back if it fails. Close TeknoParrot and any CPS3 game first.
- Free space needed on the TeknoParrot drive: the size of the files plus 64 MB (twice that for a `.zip`).
- `Copied and verified N file(s)` means it worked. If the final state cannot be checked, TeknoParrot Manager says some CPS3 files may already be in the `TeknoCPS` folder and lists the files it could not check.
- The Eggman DAT and the Eggman Game Notes page describe these files. They are for reading only. Nothing is fetched from them.

</details>

Back to [[Home]].
