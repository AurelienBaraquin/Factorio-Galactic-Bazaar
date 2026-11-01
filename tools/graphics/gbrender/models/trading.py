"""Trading family (teal): the trading hub, the export and import chests, the power substations."""
import math

from .. import parts
from .common import CRATE_HEIGHT, Model, crate, plinth

HUB_FRAMES = 16
DISH_SWEEP = math.radians(120.0)


def _cargo_chest(direction: int, colour: str):
    def build(_frame: int) -> None:
        crate("trading")
        hatch = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
        parts.box((0.7, 0.7, 0.02), (0.0, 0.0, CRATE_HEIGHT), hatch, bevel=0.006)
        parts.arrow(direction, 0.64, 0.6, (0.0, 0.0, CRATE_HEIGHT + 0.02),
                    parts.material(colour, colour, metallic=0.1, roughness=0.5, grime=0.2))
    return build


def _hub(frame: int) -> None:
    steel = parts.material("steel", "steel")
    light = parts.material("steel-light", "steel-light")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    teal = parts.material("trading", "trading", metallic=0.25, roughness=0.45, grime=0.25)
    screen = parts.material("screen", "screen", metallic=0.0, roughness=0.25, grime=0.0)
    glow = parts.emissive("trading", 3.0)
    plinth(1.9)
    # Main terminal block, two teal bands, and a roof cornice.
    parts.box((1.3, 1.0, 0.92), (0.0, 0.14, 0.12), steel)
    parts.box((1.32, 1.02, 0.07), (0.0, 0.14, 0.72), teal)
    parts.box((1.32, 1.02, 0.03), (0.0, 0.14, 0.86), teal)
    parts.box((1.4, 1.1, 0.06), (0.0, 0.14, 1.04), light)
    # South-facing screen showing a price chart.
    parts.box((0.9, 0.04, 0.46), (0.0, -0.37, 0.2), frame_mat, bevel=0.008)
    parts.box((0.82, 0.02, 0.38), (0.0, -0.39, 0.24), screen, bevel=0.0)
    chart = [(-0.36, 0.30), (-0.24, 0.38), (-0.12, 0.33), (0.0, 0.46), (0.12, 0.41), (0.24, 0.54), (0.36, 0.52)]
    for (x1, z1), (x2, z2) in zip(chart, chart[1:]):
        length = math.hypot(x2 - x1, z2 - z1)
        parts.box((length + 0.01, 0.01, 0.025), ((x1 + x2) / 2, -0.403, (z1 + z2) / 2 - 0.012), glow, bevel=0.0,
                  rotation=(0.0, -math.atan2(z2 - z1, x2 - x1), 0.0))
    # Side cabinets with vents.
    for x in (-0.8, 0.8):
        parts.box((0.26, 0.8, 0.56), (x, 0.1, 0.12), frame_mat)
        for z in (0.3, 0.4, 0.5):
            parts.box((0.27, 0.6, 0.025), (x, 0.1, z), steel, bevel=0.004)
    # Rooftop dish on a mast, sweeping back and forth.
    parts.cylinder(0.16, 0.08, (0.0, 0.3, 1.1), frame_mat)
    parts.cylinder(0.05, 0.3, (0.0, 0.3, 1.18), steel)
    angle = -DISH_SWEEP / 2 + DISH_SWEEP * frame / (HUB_FRAMES - 1)
    tilt = math.radians(-55)
    dish = [
        parts.cone(0.42, 0.08, 0.14, (0.0, 0.0, 0.0), light, rotation=(tilt, 0.0, 0.0)),
        parts.cylinder(0.018, 0.3, (0.0, 0.0, 0.0), frame_mat, vertices=8, rotation=(tilt, 0.0, 0.0)),
        parts.sphere(0.04, (0.0, 0.3 * math.sin(-tilt), 0.3 * math.cos(tilt)), glow),
    ]
    for obj in dish:
        obj.location.y += 0.3
        obj.location.z += 1.44
    parts.rotate_z(dish, angle, pivot=(0.0, 0.3))
    # Status lamps either side of the screen.
    for x in (-0.56, 0.56):
        parts.sphere(0.04, (x, -0.37, 0.6), glow)


def _substation(direction: int, colour: str):
    def build(_frame: int) -> None:
        steel = parts.material("steel", "steel")
        frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
        teal = parts.material("trading", "trading", metallic=0.25, roughness=0.45, grime=0.25)
        screen = parts.material("screen", "screen", metallic=0.0, roughness=0.25, grime=0.0)
        ceramic = parts.material("ceramic", "ceramic", metallic=0.0, roughness=0.35, grime=0.15)
        copper = parts.material("copper", "copper", metallic=0.7, roughness=0.35, grime=0.2)
        plinth(1.9)
        # Transformer tank with cooling fins on east and west.
        parts.box((1.1, 0.9, 0.86), (0.0, 0.05, 0.12), steel)
        parts.box((1.12, 0.92, 0.07), (0.0, 0.05, 0.84), teal)
        for x in (-1, 1):
            for y in (-0.3, -0.15, 0.0, 0.15, 0.3):
                parts.box((0.22, 0.04, 0.7), (x * 0.66, 0.05 + y, 0.14), frame_mat, bevel=0.005)
        # Direction panel on the south face: a lit arrow in the direction of the power flow on a dark
        # screen, so that the direction reads by shape as well as by colour.
        parts.box((0.74, 0.03, 0.64), (0.0, -0.41, 0.15), frame_mat, bevel=0.006)
        parts.box((0.68, 0.02, 0.58), (0.0, -0.425, 0.18), screen, bevel=0.0)
        arrow = parts.arrow(direction, 0.52, 0.54, (0.0, 0.0, 0.0), parts.emissive(colour, 1.5), thickness=0.03)
        arrow.rotation_euler = (math.radians(90), 0.0, 0.0)
        arrow.location = (0.0, -0.44, 0.47)
        # Three insulators with copper terminals on the lid.
        for x in (-0.32, 0.0, 0.32):
            for i, radius in enumerate((0.09, 0.075, 0.065, 0.055)):
                parts.cylinder(radius, 0.08, (x, 0.2, 0.98 + i * 0.08), ceramic, vertices=16)
            parts.cylinder(0.03, 0.1, (x, 0.2, 1.3), copper, vertices=12)
    return build


MODELS = [
    Model("gb-hub", 2, _hub, frames=HUB_FRAMES, animation_speed=0.15, run_mode="forward-then-backward"),
    Model("gb-export-chest", 1, _cargo_chest(1, "export")),
    Model("gb-import-chest", 1, _cargo_chest(-1, "import")),
    Model("gb-power-export", 2, _substation(1, "export")),
    Model("gb-power-import", 2, _substation(-1, "import")),
]
