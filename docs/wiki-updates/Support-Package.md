# Support Package (menu 17)

When something goes wrong and you ask for help, send a support package. It is one ZIP file with your logs and reports. It leaves out game files. TPM hides passwords and your Windows user name in it, but hiding is not a guarantee, so look it over before you send it.

---

## Make one

1. Choose **17** in the main menu.
2. Choose **1** (Create Support Package).
3. Wait for the result. It says `Support package created.` and the file name.
4. Press **O** to open the folder that holds it. Press **B** to go back.
5. Send the ZIP. Say which game and which step failed.

The ZIP is saved in the `SupportPackages` folder inside `TeknoParrotManager`, in your TeknoParrot folder.

Choose **2** to open the TeknoParrot Manager logs and reports folders instead. Choose **3** to go back.

---

## If TeknoParrotUI is the problem

You can add its info file first. At the menu, press **D** to see the steps:

1. Open TeknoParrotUI and choose **Troubleshooting**.
2. Choose **Save information to a text file**.
3. Save it as `TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt` in the `Reports` folder inside `TeknoParrotManager`.
4. Come back and choose **1**.

---

## If it says "partial"

`Support package created, but it is partial.` means some information could not be collected. The ZIP still works. Send it, and say it is marked partial. Press **D** on the result to see what is missing.

<details>
<summary>Details</summary>

- Included: logs and reports from the current run, plus clearly labeled background information about TeknoParrot Manager, TeknoParrot, and your games.
- Hidden: game files are not included, and TPM hides passwords and other credentials, but hiding is not a guarantee. Folders are never picked at random.
- The TeknoParrot Manager log is kept under 5 MB. At start, a log over 5 MB is kept as one "previous" log and a new log begins. The support package includes both.
- The package result starts with `What failed:` and `What TPM did not change:`. The second part says that making a package does not change your game files, profiles, passwords or emulator files.
- The package holds cleaned copies of the profiles of games that need help, never your original profile files. It also holds a list that says, for each registered profile, whether it was included, and a short file about the running copy of TPM (script path and SHA-256, PowerShell version, Windows and version label).
- If TPM cannot read the registration record, or the profile list does not finish, the package is marked partial.
- The registration record is included in a cleaned form. See [[Registration Ledger]].
- It also says how the last finished job ended (for example a setup that stopped), even if you restarted TeknoParrot Manager since then. Personal folder names are removed.
- If the ZIP is ready but a temporary folder could not be removed, the result says so. You can delete that folder yourself. Its path is under Details.
- If no package was made, check the TeknoParrot Manager log, then try again. See [[Troubleshooting]].

</details>

Back to [[Home]].
