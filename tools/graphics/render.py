"""Render driver: builds each procedural model, renders its sprite (or animation sheet), its shadow
and its icon, writes them under graphics/, and regenerates prototypes/sprites.lua.

  blender --background --factory-startup --python tools/graphics/render.py [-- name ...]

With no name every model is rendered. See docs/graphics-pipeline.md.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from gbrender import parts, png, scene  # noqa: E402
from gbrender.models import MODELS  # noqa: E402

MANIFEST = os.path.join(HERE, "manifest.json")
SPRITES_LUA = os.path.join(ROOT, "prototypes", "sprites.lua")
MOD_PATH = "__galactic-bazaar__/"
ICON_SIZE = 64
ICON_MIPMAPS = 4
MARGIN = 1  # transparent pixels kept around a cropped sprite
CANVAS_MARGIN = 0.5  # tiles of canvas kept beyond the farthest point of a model and its shadow


def _clear() -> None:
    parts._materials.clear()
    scene.reset()


def _mesh_objects() -> list:
    import bpy
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def _corners() -> list:
    """World-space corners of every mesh's bounding box in the scene."""
    from mathutils import Vector
    return [tuple(obj.matrix_world @ Vector(corner)) for obj in _mesh_objects() for corner in obj.bound_box]


def _canvas(model) -> tuple:
    """Canvas size in pixels, centred on the origin's projection, that holds every frame of the
    model and of its shadow (a point at height z casts its shadow z / tan(elevation) away along
    the sun's direction) with CANVAS_MARGIN tiles to spare."""
    run_x, run_y = scene.shadow_run()
    reach_x, reach_y = 0.0, 0.0
    for frame in range(model.frames):
        _clear()
        model.build(frame)
        for x, y, z in _corners():
            for point in ((x, y, z), (x + run_x * z, y + run_y * z, 0.0)):
                screen_x, screen_y = scene.project(point)
                reach_x = max(reach_x, abs(screen_x))
                reach_y = max(reach_y, abs(screen_y))
    half_width = math.ceil((reach_x + CANVAS_MARGIN) * scene.TILE_PX)
    half_height = math.ceil((reach_y + CANVAS_MARGIN) * scene.TILE_PX)
    return 2 * half_width, 2 * half_height


def _crop(images: list, canvas: tuple) -> tuple:
    """Crops images to their common covered area plus MARGIN transparent pixels. Fails when that
    area touches the canvas edge: the render was cut off."""
    left, top, right, bottom = png.alpha_bbox(images)
    width, height = canvas
    if left == 0 or top == 0 or right == width or bottom == height:
        raise RuntimeError("render cut off by the canvas edge: enlarge CANVAS_MARGIN")
    left, top, right, bottom = left - MARGIN, top - MARGIN, right + MARGIN, bottom + MARGIN
    crops = [image[top:bottom, left:right] for image in images]
    return crops, (left, top, right, bottom)


def _entity_y(canvas: tuple, size: int) -> float:
    """Pixel row of the entity position: the origin projects to the canvas centre, and the
    selection box's south edge (y = -size/2), size/2 * UP[1] tiles below it, must land size/2
    tiles below the entity position."""
    return canvas[1] / 2.0 + (size / 2.0) * scene.UP[1] * scene.TILE_PX - (size / 2.0) * scene.TILE_PX


def _shift(box: tuple, canvas: tuple, size: int) -> list:
    left, top, right, bottom = box
    centre_x, centre_y = (left + right) / 2.0, (top + bottom) / 2.0
    return [round((centre_x - canvas[0] / 2.0) / scene.TILE_PX, 4),
            round((centre_y - _entity_y(canvas, size)) / scene.TILE_PX, 4)]


def _vertical_extension(box: tuple, canvas: tuple, size: int) -> float:
    """How far the sprite rises above the selection box, in tiles rounded up to 0.05."""
    selection_top = _entity_y(canvas, size) - (size / 2.0) * scene.TILE_PX
    overhang = max(0.0, (selection_top - (box[1] + MARGIN)) / scene.TILE_PX)
    return math.ceil(overhang * 20.0 - 1e-9) / 20.0


def _render_icon(model):
    _clear()
    model.build(0)
    corners = [scene.project(corner) for corner in _corners()]
    xs, ys = [c[0] for c in corners], [c[1] for c in corners]
    edge = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.04
    scene.frame_camera((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, edge, edge,
                       scene.ICON_RENDER_PX / edge)
    image = scene.render_main(_mesh_objects())
    return png.mipmapped_icon(image, ICON_SIZE, ICON_MIPMAPS)


def render(model) -> dict:
    canvas = _canvas(model)
    mains, shadows = [], []
    for frame in range(model.frames):
        _clear()
        model.build(frame)
        scene.frame_camera(0.0, 0.0, canvas[0] / scene.TILE_PX, canvas[1] / scene.TILE_PX, scene.TILE_PX)
        objects = _mesh_objects()
        mains.append(scene.render_main(objects))
        shadows.append(scene.render_shadow(objects))
    main_crops, main_box = _crop(mains, canvas)
    shadow_crops, shadow_box = _crop(shadows, canvas)

    folder = os.path.join(ROOT, "graphics", "entity", model.name)
    os.makedirs(folder, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "graphics", "icons"), exist_ok=True)
    line_length = min(model.frames, model.line_length)
    entry = {"size": model.size,
             "drawing_box_vertical_extension": _vertical_extension(main_box, canvas, model.size)}
    for layer, crops, box in (("main", main_crops, main_box), ("shadow", shadow_crops, shadow_box)):
        suffix = "" if layer == "main" else "-shadow"
        relative = "graphics/entity/{0}/{0}{1}.png".format(model.name, suffix)
        png.write(os.path.join(ROOT, relative), png.sheet(crops, line_length))
        entry[layer] = {
            "filename": MOD_PATH + relative,
            "width": crops[0].shape[1],
            "height": crops[0].shape[0],
            "shift": _shift(box, canvas, model.size),
        }
        if model.frames > 1:
            entry[layer].update({"frame_count": model.frames, "line_length": line_length,
                                 "animation_speed": model.animation_speed, "run_mode": model.run_mode})
    icon = "graphics/icons/{0}.png".format(model.name)
    png.write(os.path.join(ROOT, icon), _render_icon(model))
    entry["icon"] = {"filename": MOD_PATH + icon, "icon_size": ICON_SIZE, "mipmaps": ICON_MIPMAPS}
    return entry


def _lua(value, indent: str = "") -> str:
    if isinstance(value, dict):
        inner = indent + "  "
        lines = ["{"]
        for key in sorted(value):
            name = key if key.isidentifier() else '["{}"]'.format(key)
            lines.append("{}{} = {},".format(inner, name, _lua(value[key], inner)))
        lines.append(indent + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        return "{ " + ", ".join(_lua(item, indent) for item in value) + " }"
    if isinstance(value, str):
        return '"{}"'.format(value)
    if isinstance(value, float):
        return repr(value)
    return str(value)


def write_lua(manifest: dict) -> None:
    header = ("-- Generated by tools/graphics/render.py from the procedural models in tools/graphics/gbrender/.\n"
              "-- Do not edit: re-render instead (docs/graphics-pipeline.md). Sizes in pixels, shifts in tiles,\n"
              "-- sprites at 64 px per tile (drawn at scale 0.5); icons carry their mipmaps side by side.\n")
    with open(SPRITES_LUA, "w", encoding="utf-8") as handle:
        handle.write(header + "return " + _lua(manifest) + "\n")


def main(argv: list) -> None:
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    known = {model.name: model for model in MODELS}
    unknown = [name for name in names if name not in known]
    if unknown:
        sys.exit("unknown model(s): " + ", ".join(unknown))
    manifest = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as handle:
            manifest = json.load(handle)
    for model in MODELS:
        if names and model.name not in names:
            continue
        print("rendering", model.name, flush=True)
        manifest[model.name] = render(model)
    manifest = {name: manifest[name] for name in sorted(manifest) if name in known}
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    write_lua(manifest)


main(sys.argv)
