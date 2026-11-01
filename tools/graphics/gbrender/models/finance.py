"""Finance family (brass gold): the contract chest, the vault uplink, the rental warehouse."""
import math

from .. import parts
from .common import CRATE_HEIGHT, Model, crate


def _contract_chest(_frame: int) -> None:
    crate("finance")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    paper = parts.material("paper", "paper", metallic=0.0, roughness=0.8, grime=0.15)
    gold = parts.material("finance", "finance", metallic=0.6, roughness=0.3, grime=0.15)
    # A delivery slot with a document in it, and a wax-seal stamp.
    parts.box((0.5, 0.16, 0.03), (-0.04, 0.12, CRATE_HEIGHT), frame_mat, bevel=0.005)
    sheet = parts.box((0.38, 0.3, 0.01), (-0.04, -0.02, CRATE_HEIGHT + 0.03), paper, bevel=0.0)
    sheet.rotation_euler.z = math.radians(-6)
    parts.cylinder(0.09, 0.04, (0.18, -0.16, CRATE_HEIGHT + 0.03), gold, vertices=24)


def _vault_uplink(_frame: int) -> None:
    crate("finance")
    steel = parts.material("steel-light", "steel-light")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    gold = parts.material("finance", "finance", metallic=0.6, roughness=0.3, grime=0.15)
    glow = parts.emissive("finance", 3.0)
    # A round vault door on the lid, and an uplink antenna with a gold dish.
    parts.cylinder(0.24, 0.03, (-0.08, -0.06, CRATE_HEIGHT), frame_mat)
    parts.cylinder(0.2, 0.04, (-0.08, -0.06, CRATE_HEIGHT), gold)
    for angle in range(3):
        bar = parts.box((0.3, 0.03, 0.02), (-0.08, -0.06, CRATE_HEIGHT + 0.04), frame_mat, bevel=0.0)
        bar.rotation_euler.z = math.radians(60 * angle)
    parts.cylinder(0.025, 0.42, (0.26, 0.24, CRATE_HEIGHT), steel, vertices=12)
    parts.cone(0.12, 0.02, 0.06, (0.26, 0.20, CRATE_HEIGHT + 0.36), gold, rotation=(math.radians(-50), 0.0, 0.0))
    parts.sphere(0.025, (0.26, 0.24, CRATE_HEIGHT + 0.44), glow)


def _rental_warehouse(_frame: int) -> None:
    crate("finance")
    frame_mat = parts.material("frame", "frame", metallic=0.5, roughness=0.6)
    steel = parts.material("steel-light", "steel-light")
    gold = parts.material("finance", "finance", metallic=0.6, roughness=0.3, grime=0.15)
    hazard = parts.material("hazard", "hazard", metallic=0.1, roughness=0.6, grime=0.3, stripes=True)
    # A pitched roof (it stores someone else's goods), a roller shutter and a padlock on the front.
    roof = parts.prism([(-0.44, CRATE_HEIGHT), (0.44, CRATE_HEIGHT), (0.0, CRATE_HEIGHT + 0.2)], 0.0, 0.88,
                       steel)
    roof.rotation_euler.x = math.radians(90)
    roof.location.y = 0.44
    parts.box((0.86, 0.06, 0.03), (0.0, 0.0, CRATE_HEIGHT + 0.18), frame_mat)
    parts.box((0.5, 0.02, 0.3), (0.0, -0.435, 0.07), hazard, bevel=0.0)
    for z in (0.12, 0.18, 0.24, 0.30):
        parts.box((0.48, 0.015, 0.015), (0.0, -0.447, z), frame_mat, bevel=0.0)
    parts.box((0.08, 0.03, 0.08), (0.0, -0.46, 0.17), gold, bevel=0.006)
    parts.torus(0.03, 0.008, (0.0, -0.46, 0.27), gold, rotation=(math.radians(90), 0.0, 0.0))


MODELS = [
    Model("gb-contract-chest", 1, _contract_chest),
    Model("gb-vault-uplink", 1, _vault_uplink),
    Model("gb-rental-warehouse", 1, _rental_warehouse),
]
