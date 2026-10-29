# Galactic Bazaar

A Factorio 2.1 mod (Space Age optional) where every flow of the factory — items, fluids, energy,
storage, machine capacity, logistics — is a tradable asset on a simulated galactic market.
What it aims to be: [docs/brief.md](docs/brief.md). Work tracking:
[GitHub Project](https://github.com/users/AurelienBaraquin/projects/3).

The repository root is the mod folder: `info.json`, `data.lua`, `control.lua`, `locale/` and
`changelog.txt` are what Factorio reads.

## Prerequisites

- Factorio 2.1 (developed against 2.1.24). Space Age is not needed.
- For load checks from Linux/WSL: the headless server, which needs no account:

```bash
mkdir -p ~/.local/share/factorio-headless && cd ~/.local/share/factorio-headless
curl -fsSL https://factorio.com/get-download/2.1.24/headless/linux64 | tar -xJ
```

## Load check (headless)

Create a mods folder outside the repository that links to it, then create a map:

```bash
FACTORIO=~/.local/share/factorio-headless/factorio/bin/x64/factorio
MODS=$(mktemp -d)
ln -s "$PWD" "$MODS/galactic-bazaar"
echo '{"mods":[{"name":"base","enabled":true},{"name":"galactic-bazaar","enabled":true},
  {"name":"space-age","enabled":false},{"name":"quality","enabled":false},
  {"name":"elevated-rails","enabled":false},{"name":"recycler","enabled":false}]}' > "$MODS/mod-list.json"
"$FACTORIO" --mod-directory "$MODS" --create "$MODS/check.zip"
```

Exit code `0` and a `Loading mod galactic-bazaar` line in the output mean the mod loads. The
headless build **enables its bundled DLC mods unless `mod-list.json` disables them**: keep the
`false` entries for a vanilla check, and set them to `true` to check with Space Age.

Playing the mod in the Windows game from a WSL checkout is not set up yet (issue #5).
