# ADR-0027 — Procedural Blender render pipeline for the mod's graphics

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: owner (all art made by AI, procedural Blender renders, decisions log 2026-10-29;
  "Start #48" with the Blender download; approved the updated graphics constraint of
  [brief.md](../brief.md) on 2026-11-01, "Approve the wording"); implementing agent (engine, versions,
  layout below)
- **Supersedes**: none

## Context

Until 0.1.39 every building of the mod was a base-game sprite with a tint. Issue #48 asks for a
final visual identity, produced by AI agents only, matching Factorio's projection and lighting, with
icons and mipmaps, reproducible and installable without root in WSL. The decisions log
(2026-10-29) already rules out 2D image generators (they break the projection and lighting) and Space
Age graphics (optional expansion). The game expects 64 px per tile sprites at scale 0.5, separate
shadow layers and frame sheets; the renders must line up with the base buildings around them.

## Options considered

1. **Blender, Cycles on the CPU, models scripted in Python** — runs headless in WSL from the portable
   build, no GPU; physically based light and shadows; procedural textures keep it file-free; a fixed
   seed and sample count make it reproducible. Slower than a rasteriser (about 4 minutes for all).
2. **Blender, Eevee** — faster, but needs an OpenGL/EGL context, which a headless WSL session does not
   reliably have; its soft shadows and screen-space effects are harder to make identical run to run.
3. **A custom software rasteriser in Python** — no download, fully controlled, but lighting, bevels and
   shadows would all be hand-written, and the result would look nothing like the base game.
4. **Keep tinted base sprites** — free and always valid, but fails the issue: the mod would have no
   identity of its own and several buildings looked identical.

## Decision

Option 1. The official portable **Blender 4.5.15 LTS** is installed by
`tools/graphics/setup-blender.sh` (pinned version and SHA256, checked against the published checksum
file) under `~/.local/opt/`, never in the repository. Models are Python functions built from shared
primitives and a palette (`tools/graphics/gbrender/`); `tools/graphics/render.py` renders each with an
orthographic camera pitched 45° below the horizon (measured on base sprites), a sun from the west, a
main pass and a shadow pass (shadow catcher), crops, lays out animation sheets, writes icons with
four mipmaps through its own deterministic PNG writer, and **generates `prototypes/sprites.lua`**
(sizes, shifts, frames) so that no shift is copied by hand. `prototypes/graphics.lua` turns it into
sprite tables; `spec/graphics_spec.lua` checks the files against it.

Buildings whose shape the game's own mechanics depend on and whose recipe consumes a vanilla
machine (combinators, manifolds, rental assembler) keep their tinted base sprites
([visual-identity.md](../visual-identity.md#kept-base-sprites)).

## Consequences

- Positive: every building of the mod's own has a coherent look in the game's projection; graphics
  are code, reviewed and re-rendered like code; the same script gives the same bytes; the sprite
  descriptions cannot drift from the files.
- Negative / trade-offs accepted: a 1.2 GB tool outside the repository for whoever re-renders; renders
  are fixed to one Blender version (another version may change pixels); procedural models are simpler
  than the base game's hand-made art; glowing parts have no light or glow layer yet.
- Follow-up: the owner's in-game check (list in [graphics-pipeline.md](../graphics-pipeline.md));
  possible later work on night glow layers and on the kept base sprites.
