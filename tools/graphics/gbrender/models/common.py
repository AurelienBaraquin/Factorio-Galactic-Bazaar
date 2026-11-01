"""Shared silhouettes: the 1x1 crate every chest of the mod is built on, and the 2x2 plinth."""
from dataclasses import dataclass
from typing import Callable

from .. import parts


@dataclass(frozen=True)
class Model:
    """A building to render. `build(frame)` creates its objects for one animation frame and returns
    them; `size` is the selection box edge in tiles; `frames` > 1 renders an animation sheet."""
    name: str
    size: int
    build: Callable
    frames: int = 1
    line_length: int = 8
    animation_speed: float = 1.0
    run_mode: str = "forward"


CRATE_HEIGHT = 0.6


def crate(family: str) -> list:
    """The 1x1 crate, about the steel chest's footprint and height (so the base game's chest circuit
    connector sits on it): plinth, body, four corner posts, a family-coloured band and a lid."""
    steel = parts.material("steel", "steel")
    light = parts.material("steel-light", "steel-light")
    frame = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    band = parts.material(family, family, metallic=0.25, roughness=0.45, grime=0.25)
    objects = [
        parts.box((0.92, 0.92, 0.06), (0.0, 0.0, 0.0), frame),
        parts.box((0.84, 0.84, 0.5), (0.0, 0.0, 0.06), steel),
        parts.box((0.86, 0.86, 0.08), (0.0, 0.0, 0.36), band),
        parts.box((0.86, 0.86, 0.04), (0.0, 0.0, CRATE_HEIGHT - 0.04), light),
    ]
    for x in (-0.4, 0.4):
        for y in (-0.4, 0.4):
            objects.append(parts.box((0.1, 0.1, CRATE_HEIGHT + 0.02), (x, y, 0.0), frame))
    # Front panel ribs, so the south face reads as a crate.
    for x in (-0.2, 0.0, 0.2):
        objects.append(parts.box((0.05, 0.02, 0.26), (x, -0.425, 0.08), frame, bevel=0.006))
    return objects


def plinth(size: float, height: float = 0.12) -> list:
    """A square 2x2 foundation: dark slab with hazard-striped edges."""
    frame = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    hazard = parts.material("hazard", "hazard", metallic=0.1, roughness=0.6, grime=0.3, stripes=True)
    return [
        parts.box((size, size, height * 0.6), (0.0, 0.0, 0.0), hazard),
        parts.box((size - 0.12, size - 0.12, height), (0.0, 0.0, 0.0), frame),
    ]
