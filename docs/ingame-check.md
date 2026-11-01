# In-game check: screenshots and translations in the real client

The headless server that runs the FactorioTest suite ([testing.md](testing.md)) draws nothing and
translates nothing. The in-game check starts the Windows Factorio client from WSL, lets the mod build
a scene and walk its window by itself, and brings back screenshots and every text the client could not
translate. It needs no one at the keyboard, and it never touches the player's saves, settings or mods.

```bash
python3 tools/ingame/run.py                 # French then English
python3 tools/ingame/run.py --locale fr     # one language
```

The client's window appears for about a minute per language and closes by itself. The results go to
`tools/ingame/.work/<locale>/` (ignored by git). The exit code is 1 when a name or a window text is
not translated, when the check recorded an error, or when it did not finish within `--timeout`
seconds (300 by default; the last steps reached are printed from `progress.txt`).

## Prerequisites

- WSL on Windows, with Factorio 2.1 from Steam at its default place, or `--factorio <path to
  factorio.exe>`. Steam must be able to start the game; a running Steam is enough.
- Python 3 (standard library only). The check is run by hand; it is not part of the pre-commit hook.

## What it does

`tools/ingame/run.py`, for each language:

1. builds a sandbox in `%LOCALAPPDATA%\Temp\gb-ingame-check` with its own `config.ini` (write-data in
   the sandbox, the chosen `locale`) and its own mods folder. The player's `%APPDATA%\Factorio` is never
   read or written, and the script refuses a sandbox inside it.
2. deploys the mod there (`tools/build.py deploy`), adds `tests/ingame_check/`, which the mod zip does
   not ship, and the helper mod `tools/ingame/gb-ingame-check`. The mod list enables base, the mod and
   the helper only (no Space Age: the owner's client does not have it).
3. starts the client on the helper's empty scenario (`--load-scenario gb-ingame-check/check
   --disable-audio`). Steam restarts the client under its own process, so the script follows the check
   through its files, not through the process it started.
4. waits for `script-output/gb-ingame/done.json`, then stops the client: only the `factorio.exe` whose
   command line names the sandbox's `config.ini`, so a game the player has open is never stopped. A
   client left over from an interrupted run is stopped the same way before starting.
5. copies the screenshots, `report.json`, `progress.txt` and the client's log to
   `tools/ingame/.work/<locale>/`, and prints what is not translated.

In the game, `control.lua` loads `tests/ingame_check/init.lua` only when the helper mod is active,
like the FactorioTest suite with `factorio-test`. It runs its steps on `on_tick` (one per tick at most,
each in `pcall`, an error recorded and the check continued):

| Step | Screenshots |
|---|---|
| Research everything; clear a ground of grass; lay out a steel chest, an accumulator and every building of the mod in rows (`tests/ingame_check/plan.lua`), substations and hubs in the lanes between rows, an energy interface, a red wire through every building with a circuit connector, and an export chest out of every hub's range; wait 300 ticks | |
| By day, alt mode, night, and each building close up (zoom 2) | `scene-day`, `scene-alt`, `scene-night`, `entity/<name>`, `isolated-alt` |
| The hub and the teleporter, 8 frames 4 ticks apart | `anim/<name>-<n>` |
| Cut the power (energy interface and accumulator), wait 600 ticks | `scene-unpowered-alt` |
| Open the Galactic Bazaar window bound to the hub, then each tab; ask the client to translate every caption, tooltip and list item of the window | `gui/<tab>` |
| Ask the client to translate the name of every `gb-` entity, item, recipe, technology, fluid, signal, setting, control (by its `[controls]` key; one linked to a game control is not listed in the controls settings, so not checked) and Tips and tricks entry, and the description of every entity and technology; wait for every answer (600 ticks at most) | |
| Open the technology screen on Overdraft 1, shoot it in the same tick (it pauses a single-player game), write the report | `technology-tree` |

`report.json` lists the screenshots, the number of texts checked, the `missing` translations (kind
and localised string), the descriptions the game shows as none (`no_description`, for information) and
the `errors`.

## Reading the results

The screenshots are for a person (or an agent) to look at; nothing compares them automatically. What
to look for is the list of [graphics-pipeline.md](graphics-pipeline.md) ("Checking in the game"):
shadows, wire ends, alt-mode icons, animations, icons at small size, night. A building that shows the
game's "low power" icon right after the scene is built may still be filling its buffer (the
teleporter takes at most 24 MW).

## Open questions

- Icons at small size (inventory, quickbar) are not shot yet: the check opens no inventory.
