"""Logistics family (cobalt): the docking bay, the electromagnetic catapult, the teleporter."""
import math

from .. import parts
from .common import CRATE_HEIGHT, Model, crate

TELEPORTER_FRAMES = 16


def _docking_bay(_frame: int) -> None:
    crate("logistics")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    hazard = parts.material("hazard", "hazard", metallic=0.1, roughness=0.6, grime=0.3)
    glow = parts.emissive("logistics", 3.0)
    # Landing pad: a dark disc ringed with warning yellow and four beacons.
    parts.cylinder(0.3, 0.02, (0.0, 0.0, CRATE_HEIGHT), hazard)
    parts.cylinder(0.25, 0.03, (0.0, 0.0, CRATE_HEIGHT), frame_mat)
    for angle in range(4):
        a = math.radians(45 + 90 * angle)
        parts.sphere(0.03, (0.33 * math.cos(a), 0.33 * math.sin(a), CRATE_HEIGHT + 0.03), glow)
    # Fuel filler on the south-east corner.
    fuel = parts.material("export", "export", metallic=0.2, roughness=0.5, grime=0.3)
    parts.cylinder(0.06, 0.1, (0.28, -0.28, CRATE_HEIGHT), fuel, vertices=16)


def _catapult(_frame: int) -> None:
    crate("logistics")
    steel = parts.material("steel-light", "steel-light")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    copper = parts.material("copper", "copper", metallic=0.7, roughness=0.35, grime=0.2)
    glow = parts.emissive("logistics", 3.0)
    # A launch rail pitched up towards the north, wound with copper coils.
    tilt = math.radians(55)
    parts.box((0.42, 0.42, 0.08), (0.0, 0.05, CRATE_HEIGHT), frame_mat)
    length = 0.62
    for x in (-0.09, 0.09):
        rail = parts.box((0.05, 0.05, length), (0.0, 0.0, 0.0), steel)
        rail.rotation_euler = (-tilt, 0.0, 0.0)
        rail.location = (x, -0.05, CRATE_HEIGHT + 0.06)
    for i in range(3):
        t = 0.15 + 0.2 * i
        y = -0.05 + t * math.sin(tilt)
        z = CRATE_HEIGHT + 0.06 + t * math.cos(tilt) + 0.0
        parts.torus(0.13, 0.025, (0.0, y, z), copper, rotation=(-tilt, 0.0, 0.0))
    tip_t = length
    parts.sphere(0.035, (0.0, -0.05 + tip_t * math.sin(tilt), CRATE_HEIGHT + 0.06 + tip_t * math.cos(tilt)), glow)


def _teleporter(frame: int) -> None:
    steel = parts.material("steel", "steel")
    light = parts.material("steel-light", "steel-light", metallic=0.5, roughness=0.4)
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    hazard = parts.material("hazard", "hazard", metallic=0.1, roughness=0.6, grime=0.3, stripes=True)
    cobalt = parts.material("logistics", "logistics", metallic=0.25, roughness=0.45, grime=0.25)
    phase = frame / TELEPORTER_FRAMES
    warp = parts.emissive("warp", 2.2 + 0.8 * math.sin(2 * math.pi * phase))
    # Round platform with a hazard rim and a pad ringed with the warp colour.
    parts.cylinder(0.95, 0.06, (0.0, 0.0, 0.0), hazard, vertices=64)
    parts.cylinder(0.86, 0.14, (0.0, 0.0, 0.0), frame_mat, vertices=64)
    parts.cylinder(0.6, 0.04, (0.0, 0.0, 0.14), cobalt, vertices=64)
    parts.torus(0.42, 0.025, (0.0, 0.0, 0.19), warp)
    # Three pylons holding the field ring.
    for i in range(3):
        a = math.radians(90 + 120 * i)
        x, y = 0.74 * math.cos(a), 0.74 * math.sin(a)
        parts.box((0.16, 0.16, 1.0), (x, y, 0.12), steel)
        parts.box((0.18, 0.18, 0.08), (x, y, 0.6), cobalt)
    parts.torus(0.68, 0.05, (0.0, 0.0, 1.12), light)
    # Six emitters running round the ring, a sixth of a turn per cycle (seamless loop).
    emitters = []
    for i in range(6):
        a = 2 * math.pi * i / 6
        emitters.append(parts.sphere(0.055, (0.68 * math.cos(a), 0.68 * math.sin(a), 1.12), warp))
    parts.rotate_z(emitters, (2 * math.pi / 6) * phase)
    # The core: a floating sphere of the warp colour, breathing with the cycle.
    parts.sphere(0.14 + 0.015 * math.sin(2 * math.pi * phase), (0.0, 0.0, 0.66), warp)

MODELS = [
    Model("gb-docking-bay", 1, _docking_bay),
    Model("gb-catapult", 1, _catapult),
    Model("gb-teleporter", 2, _teleporter, frames=TELEPORTER_FRAMES, animation_speed=0.25),
]
