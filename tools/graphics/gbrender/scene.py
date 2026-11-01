"""Scene, camera, lights and render passes matching Factorio's sprite projection.

Projection (measured on base sprites, docs/graphics-pipeline.md): orthographic, no yaw, pitched
45 degrees below the horizon, no vertical stretch; 64 pixels per tile (the game's high-resolution
sprites, drawn at scale 0.5). North (+Y) is up on screen. Light from the left and slightly behind,
casting shadows to the east and a little to the south, like the base game's shadow sprites.

1 Blender unit = 1 tile. A model stands on z = 0 and is centred on the origin.
"""
import math
import os
import tempfile

import bpy
import numpy as np

TILE_PX = 64
PITCH_DEG = 45.0
SUN_ELEVATION_DEG = 40.0
SUN_AZIMUTH_DEG = 11.0  # light from the west, this many degrees towards the north
SAMPLES = 64
SEED = 0
ICON_RENDER_PX = 256
WORLD_COLOUR = (0.66, 0.63, 0.58)
WORLD_STRENGTH = 0.7
SUN_STRENGTH = 4.2
SUN_COLOUR = (1.0, 0.95, 0.88)
FILL_STRENGTH = 1.1  # shadowless light from the viewer's side, so south faces read (main pass only)

_A = math.radians(90.0 - PITCH_DEG)
UP = (0.0, math.cos(_A), math.sin(_A))  # camera up vector in world space
FORWARD = (0.0, math.sin(_A), -math.cos(_A))


def project(point: tuple) -> tuple:
    """Screen offset in tiles (x right, y down) of a world point, relative to the origin."""
    x, y, z = point
    return x, -(y * UP[1] + z * UP[2])


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.use_denoising = False
    scene.cycles.seed = SEED
    scene.cycles.max_bounces = 4
    scene.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    scene.cycles.filter_width = 1.5
    scene.render.film_transparent = True
    scene.render.use_persistent_data = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_percentage = 100

    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (*WORLD_COLOUR, 1.0)
    background.inputs["Strength"].default_value = WORLD_STRENGTH

    sun_data = bpy.data.lights.new("sun", type="SUN")
    sun_data.energy = SUN_STRENGTH
    sun_data.color = SUN_COLOUR
    sun_data.angle = math.radians(3.0)
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    # A sun light shines along its local -Z: aim it east-south-east and down.
    elevation = math.radians(SUN_ELEVATION_DEG)
    azimuth = math.radians(SUN_AZIMUTH_DEG)
    direction = (math.cos(elevation) * math.cos(azimuth), -math.cos(elevation) * math.sin(azimuth),
                 -math.sin(elevation))
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = _quaternion_from_minus_z(direction)

    fill_data = bpy.data.lights.new("fill", type="SUN")
    fill_data.energy = FILL_STRENGTH
    fill_data.use_shadow = False
    fill = bpy.data.objects.new("fill", fill_data)
    scene.collection.objects.link(fill)
    fill.rotation_mode = "QUATERNION"
    fill.rotation_quaternion = _quaternion_from_minus_z((0.35, 0.75, -0.55))

    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera_data.sensor_fit = "AUTO"
    camera_data.clip_start = 0.1
    camera_data.clip_end = 100.0
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = (_A, 0.0, 0.0)
    scene.camera = camera
    frame_camera(0.0, 0.0, 4.0, 4.0, TILE_PX)


def _quaternion_from_minus_z(direction: tuple):
    from mathutils import Vector
    return Vector(direction).to_track_quat("-Z", "Y")


def frame_camera(centre_x: float, centre_y: float, width: float, height: float, px_per_tile: int) -> None:
    """Points the camera so that screen point (centre_x, centre_y) in tiles (from `project`) is
    the image centre, with an image of width x height tiles at px_per_tile."""
    scene = bpy.context.scene
    camera = scene.camera
    scene.render.resolution_x = int(round(width * px_per_tile))
    scene.render.resolution_y = int(round(height * px_per_tile))
    camera.data.ortho_scale = max(width, height)
    distance = 20.0
    # Screen y grows downwards, the camera's up vector points up the screen.
    camera.location = (
        centre_x - FORWARD[0] * distance,
        -centre_y * UP[1] - FORWARD[1] * distance,
        -centre_y * UP[2] - FORWARD[2] * distance,
    )


def _render_to_array() -> np.ndarray:
    scene = bpy.context.scene
    handle, path = tempfile.mkstemp(suffix=".png")
    os.close(handle)
    try:
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(path)
        width, height = image.size
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
    finally:
        os.remove(path)
    return pixels.reshape(height, width, 4)[::-1].astype(np.float64)


def render_main(objects: list) -> np.ndarray:
    for obj in objects:
        obj.visible_camera = True
    catcher = bpy.data.objects.get("shadow-catcher")
    if catcher:
        catcher.hide_render = True
    bpy.data.objects["fill"].hide_render = False
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = WORLD_STRENGTH
    return _render_to_array()


def render_shadow(objects: list) -> np.ndarray:
    """The shadow the model casts on the ground, as black with the shadow's coverage in alpha."""
    catcher = bpy.data.objects.get("shadow-catcher")
    if catcher is None:
        bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0.0, 0.0, 0.0))
        catcher = bpy.context.active_object
        catcher.name = "shadow-catcher"
        catcher.is_shadow_catcher = True
    catcher.hide_render = False
    bpy.data.objects["fill"].hide_render = True
    for obj in objects:
        obj.visible_camera = False
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    image = _render_to_array()
    for obj in objects:
        obj.visible_camera = True
    alpha = np.clip(image[..., 3] * 1.15, 0.0, 1.0)
    alpha[alpha < 0.04] = 0.0
    shadow = np.zeros_like(image)
    shadow[..., 3] = alpha
    return shadow
