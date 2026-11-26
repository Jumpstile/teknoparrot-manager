# Region Setup (menu 11)

Some games can start in a country you pick, like USA or Europe. The country changes things like the language. Region setup sets it for you.

---

## Set a region

1. Choose **11** in the main menu.
2. Pick a country from the list. The number in brackets is how many games offer it. Type **0** to go back and change nothing.
3. Choose **A** for all the games that offer it, or **L** to browse and pick some.
4. TeknoParrot Manager tells you how many games will change and asks `Change them now? (Y/N)`. The default is N.
5. Your game settings are backed up and checked first. Then the games are changed.

Want to undo it? Choose **A** (back to automatic) in the country list. It shows only when some game is not on its automatic setting.

---

## The question after you register new games

After AutoSync or Register only adds new games that offer a region choice, TeknoParrot Manager asks once which country they should start in. Type **0** to leave them as they are. Nothing is asked in a preview or an unattended run.

This question only changes new games that are still on automatic. A region you chose before is kept. In Region setup you are asking for the change yourself, so it can replace an earlier choice.

---

<details>
<summary>Details</summary>

- Only countries that your games really offer are listed. A game never gets a region it does not have. It stays as it is and is named in the result Details (press **D**).
- Games left on their Auto or Default setting usually start as Japan.
- A game with no Auto or Default choice has nothing to go back to, so it is never changed by the question after registration and is not touched by **A**.
- Each game file is read again just before it is changed, saved in one step, and read back to check it.
- Region setup handles a game's Region setting, or its PCB region and dongle region together. Other settings, like an export flag, are not touched.

</details>

Back to [[Home]].
