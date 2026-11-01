"""Materials of the visual identity (docs/visual-identity.md) and the primitives models are built from.

Every function returns the created object; sizes are in tiles, z = 0 is the ground.
"""
import math

import bpy

# Palette, linear RGB (Blender's working space); the comments give the sRGB hex of each
# base colour, before lighting and grime.
PALETTE = {
    "steel": (0.15, 0.14, 0.13),        # body plates, warm grey #6c6965
    "steel-light": (0.24, 0.23, 0.21),  # lids and tops, #86847e
    "frame": (0.07, 0.068, 0.066),      # frames, posts, plinths, #4b4a49
    "hazard": (0.80, 0.52, 0.04),       # base game's warning yellow, #e7bf38
    "trading": (0.05, 0.42, 0.45),      # family: trading, teal #3fadb3
    "logistics": (0.12, 0.25, 0.68),    # family: logistics, cobalt #6189d7
    "finance": (0.68, 0.45, 0.07),      # family: finance, brass gold #d7b34b
    "export": (0.86, 0.30, 0.05),       # direction: export, orange #ef953f
    "import": (0.15, 0.60, 0.17),       # direction: import, green #6ccb73
    "warp": (0.45, 0.16, 1.0),          # teleporter energy, violet #b36fff
    "copper": (0.55, 0.22, 0.08),
    "ceramic": (0.62, 0.60, 0.55),
    "screen": (0.012, 0.02, 0.025),
    "paper": (0.75, 0.72, 0.62),
}

_materials = {}


def material(name: str, colour: str, metallic: float = 0.35, roughness: float = 0.55,
             grime: float = 0.35, emission: float = 0.0, stripes: bool = False) -> bpy.types.Material:
    """A principled material with procedural grime (noise darkening, deterministic).
    `stripes` paints diagonal hazard stripes of the colour and black."""
    key = (name, colour, metallic, roughness, grime, emission, stripes)
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    base = PALETTE[colour]
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    coords = nodes.new("ShaderNodeTexCoord")
    colour_socket = None
    if stripes:
        wave = nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "DIAGONAL"
        wave.inputs["Scale"].default_value = 3.0
        links.new(coords.outputs["Object"], wave.inputs["Vector"])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].color = (*base, 1.0)
        ramp.color_ramp.elements[1].position = 0.5
        ramp.color_ramp.elements[1].color = (*PALETTE["frame"], 1.0)
        links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
        colour_socket = ramp.outputs["Color"]
    else:
        rgb = nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*base, 1.0)
        colour_socket = rgb.outputs[0]

    if grime > 0:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 28.0
        noise.inputs["Detail"].default_value = 6.0
        links.new(coords.outputs["Object"], noise.inputs["Vector"])
        dirt = nodes.new("ShaderNodeValToRGB")
        dirt.color_ramp.elements[0].position = 0.35
        dirt.color_ramp.elements[0].color = (1.0 - grime, 1.0 - grime * 1.05, 1.0 - grime * 1.2, 1.0)
        dirt.color_ramp.elements[1].position = 0.7
        dirt.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
        links.new(noise.outputs["Fac"], dirt.inputs["Fac"])
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        links.new(colour_socket, mix.inputs["A"])
        links.new(dirt.outputs["Color"], mix.inputs["B"])
        colour_socket = mix.outputs["Result"]
    links.new(colour_socket, bsdf.inputs["Base Color"])

    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*base, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
        # Glowing parts are drawn bright but light nothing: a sprite cannot light its neighbours,
        # and sampling them as lights made renders differ run to run.
        mat.cycles.emission_sampling = "NONE"
    _materials[key] = mat
    return mat


def emissive(colour: str, strength: float) -> bpy.types.Material:
    return material("glow-" + colour, colour, metallic=0.0, roughness=0.4, grime=0.0, emission=strength)


def _finish(obj, mat, bevel: float, smooth_sides: bool = False):
    obj.data.materials.append(mat)
    if smooth_sides:
        for polygon in obj.data.polygons:
            polygon.use_smooth = abs(polygon.normal.z) < 0.5
    if bevel > 0:
        modifier = obj.modifiers.new("bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        modifier.harden_normals = False
    return obj


def box(size: tuple, at: tuple, mat, bevel: float = 0.012, rotation: tuple = (0.0, 0.0, 0.0)):
    """A box of `size` whose bottom face is centred on `at`."""
    sx, sy, sz = size
    x, y, z = at
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z + sz / 2), rotation=rotation)
    obj = bpy.context.active_object
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, mat, bevel)


def cylinder(radius: float, depth: float, at: tuple, mat, vertices: int = 32, bevel: float = 0.01,
             rotation: tuple = (0.0, 0.0, 0.0)):
    """A cylinder standing on `at` (its axis along z before `rotation`)."""
    x, y, z = at
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                        location=(0.0, 0.0, 0.0))
    obj = bpy.context.active_object
    obj.data.transform(_translation(0.0, 0.0, depth / 2))
    obj.location = (x, y, z)
    obj.rotation_euler = rotation
    return _finish(obj, mat, bevel, smooth_sides=True)


def cone(radius1: float, radius2: float, depth: float, at: tuple, mat, vertices: int = 32,
         rotation: tuple = (0.0, 0.0, 0.0)):
    x, y, z = at
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth,
                                    location=(0.0, 0.0, 0.0))
    obj = bpy.context.active_object
    obj.data.transform(_translation(0.0, 0.0, depth / 2))
    obj.location = (x, y, z)
    obj.rotation_euler = rotation
    return _finish(obj, mat, 0.0, smooth_sides=True)


def torus(major: float, minor: float, at: tuple, mat, rotation: tuple = (0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48,
                                     minor_segments=12, location=at, rotation=rotation)
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def sphere(radius: float, at: tuple, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=at)
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def prism(points: list, z: float, height: float, mat, bevel: float = 0.004):
    """A flat plate extruded from a 2D polygon (x, y in tiles, counter-clockwise) from z upwards."""
    count = len(points)
    vertices = [(x, y, z) for x, y in points] + [(x, y, z + height) for x, y in points]
    faces = [list(range(count - 1, -1, -1)), list(range(count, 2 * count))]
    for i in range(count):
        j = (i + 1) % count
        faces.append([i, j, count + j, count + i])
    mesh = bpy.data.meshes.new("prism")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("prism", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return _finish(obj, mat, bevel)


def arrow(direction: int, length: float, width: float, at: tuple, mat, thickness: float = 0.02):
    """An arrow plate lying on z = at[2], pointing north (+1) or south (-1)."""
    x, y, z = at
    half, head = width / 2, length * 0.5
    shaft = width * 0.2
    outline = [(-shaft, -length / 2), (shaft, -length / 2), (shaft, length / 2 - head),
               (half, length / 2 - head), (0.0, length / 2), (-half, length / 2 - head),
               (-shaft, length / 2 - head)]
    if direction < 0:
        outline = [(px, -py) for px, py in reversed(outline)]
    return prism([(x + px, y + py) for px, py in outline], z, thickness, mat)


def _translation(x: float, y: float, z: float):
    from mathutils import Matrix
    return Matrix.Translation((x, y, z))


def rotate_z(objects: list, angle: float, pivot: tuple = (0.0, 0.0)) -> None:
    """Rotates objects about a vertical axis through `pivot` (for animation frames)."""
    px, py = pivot
    cos, sin = math.cos(angle), math.sin(angle)
    for obj in objects:
        x, y = obj.location.x - px, obj.location.y - py
        obj.location.x = px + x * cos - y * sin
        obj.location.y = py + x * sin + y * cos
        obj.rotation_euler.z += angle
