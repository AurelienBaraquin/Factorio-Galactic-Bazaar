# Visual identity

What the mod's buildings look like and why. How the images are produced is in
[graphics-pipeline.md](graphics-pipeline.md); why procedural Blender renders, in
[ADR-0027](adr/0027-procedural-blender-render-pipeline.md).

## Principles

- **Native first.** The buildings must sit among vanilla ones without looking pasted in: the same
  projection, light direction, shadow length and muted, slightly warm and grimy metal as the base
  game. Colour is used as an accent, never on whole bodies.
- **Read the role at a glance.** One accent colour says the family (what kind of business the
  building does), a second the direction (what flows out, what flows in), a roof feature says
  which building it is.
- **One crate, many roles.** Every 1×1 building of the mod is the same crate (plinth, four corner
  posts, a coloured band, a lid) with its own lid or front feature, so the player learns the family
  once.
- **Vanilla stays vanilla.** Space Age graphics are never referenced (the expansion is optional).
  Buildings whose recipe is a modified vanilla machine and whose shape the game's own mechanics
  depend on keep the base sprite, tinted (see [Kept base sprites](#kept-base-sprites)).

## Palette

Body colours are shared; accents are per family and per direction. Values are the sRGB base colours
of the materials, before lighting and grime (the models hold their linear equivalents in
`tools/graphics/gbrender/parts.py`).

| Use | Colour | Hex |
|---|---|---|
| Body plates | warm grey steel | `#6c6965` |
| Lids and tops | light steel | `#86847e` |
| Frames, posts, plinths | dark steel | `#4b4a49` |
| Plinth edges of 2×2 buildings | base game warning yellow, diagonal stripes on dark steel | `#e7bf38` |
| **Trading** family | teal | `#3fadb3` |
| **Logistics** family | cobalt | `#6189d7` |
| **Finance** family | brass gold | `#d7b34b` |
| Direction **export** (goes to the market) | orange | `#ef953f` |
| Direction **import** (comes from the market) | green | `#6ccb73` |
| Teleporter energy | violet | `#b36fff` |

Export orange and import green were already the mod's codes (chests, manifolds, substations,
combinators); they are kept so that existing players read the new graphics the same way. The family
colours are chosen apart from them: no family is orange or green.

## Families and buildings

| Building | Family | Size | Silhouette | Render |
|---|---|---|---|---|
| Trading hub `gb-hub` | trading | 2×2 | terminal block on a striped plinth, south-facing price-chart screen, side cabinets, a rooftop dish sweeping 120° back and forth | 16-frame animation, always running |
| Export chest `gb-export-chest` | trading | 1×1 | crate, orange up arrow on the lid | still |
| Import chest `gb-import-chest` | trading | 1×1 | crate, green down arrow on the lid | still |
| Power export `gb-power-export` | trading | 2×2 | transformer with cooling fins and three insulators, orange panel with an up arrow | still |
| Power import `gb-power-import` | trading | 2×2 | the same transformer, green panel with a down arrow | still |
| Docking bay `gb-docking-bay` | logistics | 1×1 | crate, landing pad with four beacons, fuel filler | still |
| Electromagnetic catapult `gb-catapult` | logistics | 1×1 | crate, launch rail pitched north wound with copper coils | still |
| Teleporter `gb-teleporter` | logistics | 2×2 | round striped platform, three pylons holding a segmented ring that turns around a floating violet core | 16-frame animation, always running |
| Contract chest `gb-contract-chest` | finance | 1×1 | crate, document slot and a gold seal | still |
| Vault uplink `gb-vault-uplink` | finance | 1×1 | crate, round gold vault door, antenna with a gold dish | still |
| Rental warehouse `gb-rental-warehouse` | finance | 1×1 | crate under a pitched roof, striped roller shutter with a gold padlock | still |

Sizes follow the prototypes' selection boxes, which this work does not change: 1×1 crates are
about the steel chest's footprint (0.92 tile plinth) and height (0.6 tile), so the base game's
chest circuit connector, which they inherit, sits on them; 2×2 buildings stand on a 1.9-tile plinth
and rise to about 1.5 tiles (hub dish, teleporter ring), close to the accumulator's height.

## Icons

- Each rendered building's item icon is the building itself, seen from the game's angle, framed
  tight on a transparent background, rendered at 256 px and reduced to 64, 32, 16 and 8 px
  mipmaps in one file (the game infers the four levels from the file's 120 × 64 size).
- No outline, badge or text: the lid feature and the accent colours carry the meaning, and the game
  draws its own background and outline.
- Technologies show the icon of the building they unlock (unchanged rule); the telecommunications
  and finance technologies keep the base radar and coin icons, which say what they are better than a
  building would.

## Kept base sprites

| Building | Why it keeps the base sprite (tinted as before) |
|---|---|
| Buy, sell price combinators and order combinator | They are constant combinators: four direction sprites, and the game draws wires to fixed connection points and its own activity LEDs on them. A new model would have to match those points in every direction; the vanilla body, tinted green, orange or blue, also tells a circuit player what it is. |
| Fluid export and import manifolds | They are storage tanks: four-way sprites, a fluid window the game fills, and pipe connections whose covers are drawn by the game at fixed places. |
| Rental assembler | It is an assembling machine 2 (its recipe consumes one): animated working sprites, the game's recipe icon, pipe pictures and fluid box covers. Keeping it says "a machine you rent out", and the teal tint marks it. |
| Hidden catapult capacitor | Never drawn (`__core__/graphics/empty.png`). |
| Signals `gb-credits`, `gb-budget`, `gb-price-feed` | The base coin and info icons are what players already read as money and information in signal pickers. |

These choices can be revisited by a later issue; each would need its own connection-point or
fluid-box check in the game.
