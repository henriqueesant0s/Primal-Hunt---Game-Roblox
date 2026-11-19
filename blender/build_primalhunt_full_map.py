"""PRIMAL HUNT — Complete 3D Environment & Lobby Map Generator for Blender 5.3.

Generates C:/Users/Usuario/.gemini/antigravity/scratch/project_primalhunt/blender/PrimalHunt_FullMap.blend
matching 1:1 Roblox Studio scale (1 stud = 0.28 m) and coordinate mapping (+Y Blender = North / -Z Roblox,
-Y Blender = South / +Z Roblox, +Z Blender = Up / +Y Roblox).

All individual meshes are watertight, UV-mapped, under 15,000 triangles, and organized into
collections 01..09 with 6 review cameras and lighting.
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path
from typing import Dict, List, Tuple

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
BLEND_PATH = ROOT_DIR / "blender" / "PrimalHunt_FullMap.blend"
TEX_DIR = ROOT_DIR / "textures"
PREVIEWS_DIR = ROOT_DIR / "previews"
REPORT_PATH = ROOT_DIR / "blender_fullmap_stats.json"

TEX_DIR.mkdir(parents=True, exist_ok=True)
PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)

STUD = 0.28  # 1 stud = 0.28 meters
ARENA_HALF_STUDS = 400.0
TOTAL_HALF_STUDS = 450.0  # Includes outer volcanic perimeter escarpment
FAULT_ANGLE_RAD = math.radians(28.0)


def s2m(studs: float) -> float:
    return studs * STUD


def rbx_to_blender(xr: float, yr: float, zr: float) -> Vector:
    """Roblox (X east, Y up, Z south) -> Blender (X east, Y north, Z up) in meters."""
    return Vector((xr * STUD, -zr * STUD, yr * STUD))


# ---------------------------------------------------------------------------
# Deterministic Geology, Hydrology, and Route Planner (in Studs)
# ---------------------------------------------------------------------------

def _hash2_scalar(ix: int, iz: int, seed: int) -> float:
    n = (ix * 374761393 + iz * 668265263 + seed * 1442695041) & 0x7FFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _vnoise(x: float, z: float, scale: float, seed: int) -> float:
    sx = x / scale
    sz = z / scale
    ix = math.floor(sx)
    iz = math.floor(sz)
    fx = sx - ix
    fz = sz - iz
    ux = fx * fx * (3.0 - 2.0 * fx)
    uz = fz * fz * (3.0 - 2.0 * fz)
    n00 = _hash2_scalar(ix, iz, seed)
    n10 = _hash2_scalar(ix + 1, iz, seed)
    n01 = _hash2_scalar(ix, iz + 1, seed)
    n11 = _hash2_scalar(ix + 1, iz + 1, seed)
    return (n00 * (1.0 - ux) + n10 * ux) * (1.0 - uz) + (n01 * (1.0 - ux) + n11 * ux) * uz


def _fbm_scalar(x: float, z: float, base_scale: float, octaves: int, seed: int) -> float:
    acc = 0.0
    amp = 0.5
    norm = 0.0
    sc = base_scale
    for o in range(octaves):
        acc += amp * _vnoise(x, z, sc, seed + o * 73)
        norm += amp
        amp *= 0.5
        sc *= 0.5
    return acc / norm


def river_center_x(zr: float) -> float:
    """River originates in NW slopes, bends around the central helipad, and opens into SE marsh."""
    base = -150.0 + ((zr + 335.0) / 550.0) * 335.0
    meander = 36.0 * math.sin((zr + 140.0) * 0.0115)
    # Deflect channel around central helipad foundation at (0, -15)
    dx = base + meander
    dz = zr + 15.0
    dist_pad = math.hypot(dx, dz)
    if dist_pad < 72.0:
        # Push smoothly toward -X on north side and +X curve south-east
        push = (72.0 - dist_pad) * 0.85
        sign = -1.0 if zr < -5.0 else 1.0
        meander += sign * push
    return base + meander


def river_half_width(zr: float) -> float:
    if zr > 110.0:
        return 14.0 + min(34.0, (zr - 110.0) * 0.28)
    return 11.0 + 3.0 * math.sin(zr * 0.025)


def direct_road_x(zr: float) -> float:
    return -10.0 * math.sin((zr - 25.0) * 0.014)


def covered_route_x(zr: float) -> float:
    return 108.0 + 22.0 * math.sin(zr * 0.018)


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


# Cave specs in Roblox stud space: center of excavated interior, mouth exit, floor Y
CAVE_SPECS = [
    {
        "name": "Cave_NW",
        "chamber": (-336.0, -334.0),
        "mouth": (-294.0, -294.0),
        "spawn": (-342.0, -332.0),
        "floorY": 4.0,
    },
    {
        "name": "Cave_NC",
        "chamber": (15.0, -342.0),
        "mouth": (18.0, -288.0),
        "spawn": (8.0, -346.0),
        "floorY": 8.0,
    },
    {
        "name": "Cave_NE",
        "chamber": (248.0, -326.0),
        "mouth": (232.0, -276.0),
        "spawn": (254.0, -330.0),
        "floorY": 6.0,
    },
]


def _dist_to_segment_2d(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> Tuple[float, float]:
    abx, abz = bx - ax, bz - az
    len2 = abx * abx + abz * abz
    if len2 < 1e-6:
        return math.hypot(px - ax, pz - az), 0.0
    t = max(0.0, min(1.0, ((px - ax) * abx + (pz - az) * abz) / len2))
    qx, qz = ax + abx * t, az + abz * t
    return math.hypot(px - qx, pz - qz), t


def sample_terrain_studs(xr: float, zr: float) -> Dict[str, float]:
    """Returns terrain elevation (studs), river/marsh depth, road/pad blend, and slope hints."""
    # 1. Macro caldera ridges + 28-deg geological fault
    fault_proj = xr * math.cos(FAULT_ANGLE_RAD) + zr * math.sin(FAULT_ANGLE_RAD)
    ridge_wave = math.sin(fault_proj * 0.017) * 5.2 + math.cos(fault_proj * 0.036) * 2.4
    north_rise = _smoothstep(-160.0, -370.0, zr) * 18.0
    macro_noise = (_fbm_scalar(xr, zr, 145.0, 4, 420811) - 0.48) * 22.0
    micro_erosion = (_fbm_scalar(xr, zr, 36.0, 2, 918273) - 0.5) * 4.5
    raw_y = 2.0 + north_rise + ridge_wave + macro_noise + micro_erosion

    # 2. Outer caldera perimeter escarpment (365..450 studs)
    edge_d = max(abs(xr), abs(zr))
    escarpment = _smoothstep(355.0, 438.0, edge_d) * 78.0
    if escarpment > 0.1:
        raw_y += escarpment + (_fbm_scalar(xr, zr, 52.0, 2, 5511) - 0.5) * 14.0

    # 3. Flatten functional engineering zones
    # Central Helipad (0, -15)
    d_pad = math.hypot(xr, zr + 15.0)
    w_pad = 1.0 - _smoothstep(36.0, 62.0, d_pad)
    raw_y = raw_y * (1.0 - w_pad) + 1.5 * w_pad

    # South Relay Substation (0, +285)
    d_relay = math.hypot(xr, zr - 285.0)
    w_relay = 1.0 - _smoothstep(54.0, 86.0, d_relay)
    raw_y = raw_y * (1.0 - w_relay) + 4.0 * w_relay

    # Direct exposed service road from Helipad (+22) to Substation (+235)
    road_w = 0.0
    if 15.0 <= zr <= 245.0:
        d_road = abs(xr - direct_road_x(zr))
        road_w = 1.0 - _smoothstep(9.0, 22.0, d_road)
        road_target_y = 1.6 + _smoothstep(40.0, 240.0, zr) * 2.4
        raw_y = raw_y * (1.0 - road_w * 0.88) + road_target_y * (road_w * 0.88)

    # Covered forest route shelf along east bank
    cover_w = 0.0
    if -10.0 <= zr <= 245.0:
        d_cov = abs(xr - covered_route_x(zr))
        cover_w = 1.0 - _smoothstep(10.0, 24.0, d_cov)
        raw_y = raw_y * (1.0 - cover_w * 0.72) + 2.5 * (cover_w * 0.72)

    # 4. River & SE Marsh Basin carving
    rcx = river_center_x(zr)
    rhw = river_half_width(zr)
    d_river = abs(xr - rcx)
    # Marsh basin center at (+195, +195)
    d_marsh = math.hypot(xr - 195.0, zr - 195.0)
    marsh_w = 1.0 - _smoothstep(38.0, 92.0, d_marsh)

    river_w = 0.0
    if -335.0 <= zr <= 255.0:
        river_w = 1.0 - _smoothstep(rhw * 0.65, rhw * 2.1, d_river)
    water_carve = max(river_w, marsh_w)

    # River surface height descends in North, flat at Y=0.2 in central & south marsh
    water_surface_y = 0.2 + _smoothstep(-80.0, -335.0, zr) * 18.0
    if water_carve > 0.01 and w_pad < 0.5 and w_relay < 0.5:
        bed_target = water_surface_y - (1.8 if d_river < rhw * 0.8 or marsh_w > 0.4 else 0.5)
        raw_y = raw_y * (1.0 - water_carve) + bed_target * water_carve

    # 5. Excavate North Evolution Cave footprints & curved entrance aprons cleanly
    cave_w = 0.0
    for c in CAVE_SPECS:
        cx, cz = c["chamber"]
        mx, mz = c["mouth"]
        dc, _ = _dist_to_segment_2d(xr, zr, cx, cz, mx, mz)
        wc = 1.0 - _smoothstep(22.0, 44.0, dc)
        if wc > cave_w:
            cave_w = wc
            raw_y = raw_y * (1.0 - wc) + c["floorY"] * wc

    # Deep northern geothermal fissure hint
    lava_w = 0.0
    if zr < -350.0 and abs(xr + 85.0) < 38.0:
        lava_w = 1.0 - _smoothstep(6.0, 22.0, abs(xr + 85.0 - math.sin(zr * 0.1) * 8.0))
        raw_y -= lava_w * 3.5

    return {
        "y": raw_y,
        "water_surface": water_surface_y,
        "river_w": river_w,
        "marsh_w": marsh_w,
        "road_w": road_w,
        "pad_w": w_pad,
        "relay_w": w_relay,
        "cave_w": cave_w,
        "lava_w": lava_w,
    }


def terrain_y_m(xr: float, zr: float) -> float:
    return s2m(sample_terrain_studs(xr, zr)["y"])


# ---------------------------------------------------------------------------
# Procedural Texture Synthesis & Materials
# ---------------------------------------------------------------------------

def _tex_noise(u: np.ndarray, v: np.ndarray, freq: float, seed: int) -> np.ndarray:
    x = u * freq
    y = v * freq
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    sx = fx * fx * (3.0 - 2.0 * fx)
    sy = fy * fy * (3.0 - 2.0 * fy)
    p = max(2, int(freq))
    ix0, iy0 = ix % p, iy % p
    ix1, iy1 = (ix0 + 1) % p, (iy0 + 1) % p

    def h(a: np.ndarray, b: np.ndarray) -> np.ndarray:
        n = (a * 374761393 + b * 668265263 + seed * 1442695041) & 0x7FFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    n00, n10 = h(ix0, iy0), h(ix1, iy0)
    n01, n11 = h(ix0, iy1), h(ix1, iy1)
    return (n00 * (1.0 - sx) + n10 * sx) * (1.0 - sy) + (n01 * (1.0 - sx) + n11 * sx) * sy


def _save_and_pack(name: str, rgba: np.ndarray) -> bpy.types.Image:
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name=name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).reshape(-1))
    out = TEX_DIR / f"{name}.png"
    img.filepath_raw = str(out)
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def generate_caldera_terrain_texture(res: int = 512) -> bpy.types.Image:
    """Bakes a macro geology/mud/forest/road splat texture matching sample_terrain_studs."""
    rgba = np.zeros((res, res, 4), dtype=np.float32)
    step = (TOTAL_HALF_STUDS * 2.0) / res
    for iy in range(res):
        # v = 0 at Blender -Y (South, zr = +450), v = 1 at Blender +Y (North, zr = -450)
        zr = TOTAL_HALF_STUDS - (iy + 0.5) * step
        for ix in range(res):
            xr = -TOTAL_HALF_STUDS + (ix + 0.5) * step
            c = sample_terrain_studs(xr, zr)
            sx = sample_terrain_studs(xr + 4.0, zr)["y"] - c["y"]
            sz = sample_terrain_studs(xr, zr + 4.0)["y"] - c["y"]
            slope = math.hypot(sx, sz) / 4.0
            n = _fbm_scalar(xr, zr, 24.0, 2, 7711)

            # Base forest soil & leaf litter
            r = 0.14 + 0.08 * n
            g = 0.21 + 0.10 * n
            b = 0.11 + 0.05 * n

            # Exposed basalt on steep cliffs & 28-deg rock strata
            rock_w = _smoothstep(0.32, 0.72, slope)
            r = r * (1.0 - rock_w) + (0.14 + 0.08 * n) * rock_w
            g = g * (1.0 - rock_w) + (0.15 + 0.07 * n) * rock_w
            b = b * (1.0 - rock_w) + (0.17 + 0.07 * n) * rock_w

            # Mud & sediment along slow river bends & marsh
            wet = max(c["river_w"], c["marsh_w"])
            if wet > 0.05:
                mud_w = min(1.0, wet * 1.3)
                r = r * (1.0 - mud_w) + (0.16 + 0.06 * n) * mud_w
                g = g * (1.0 - mud_w) + (0.13 + 0.05 * n) * mud_w
                b = b * (1.0 - mud_w) + (0.09 + 0.03 * n) * mud_w

            # Drained gravel/roadbed along direct route
            if c["road_w"] > 0.15:
                rw = min(1.0, c["road_w"])
                r = r * (1.0 - rw) + (0.27 + 0.05 * n) * rw
                g = g * (1.0 - rw) + (0.26 + 0.05 * n) * rw
                b = b * (1.0 - rw) + (0.24 + 0.04 * n) * rw

            # Concrete foundations under helipad & relay substation
            conc = max(c["pad_w"], c["relay_w"])
            if conc > 0.2:
                r = r * (1.0 - conc) + 0.31 * conc
                g = g * (1.0 - conc) + 0.33 * conc
                b = b * (1.0 - conc) + 0.35 * conc

            # Geothermal fissure accent in deep far-north crack
            if c["lava_w"] > 0.25:
                lw = min(1.0, (c["lava_w"] - 0.25) * 1.6)
                r = r * (1.0 - lw) + 0.85 * lw
                g = g * (1.0 - lw) + 0.26 * lw
                b = b * (1.0 - lw) + 0.05 * lw

            rgba[iy, ix, 0] = r
            rgba[iy, ix, 1] = g
            rgba[iy, ix, 2] = b
            rgba[iy, ix, 3] = 1.0

    return _save_and_pack("tex_caldera_splat", rgba)


def _load_or_build_kit_textures() -> Dict[str, bpy.types.Image]:
    imgs: Dict[str, bpy.types.Image] = {}
    expected = {
        "Bark": "tex_volcanic_bark.png",
        "Canopy": "tex_canopy_foliage.png",
        "Basalt": "tex_basalt_strata.png",
        "Steel": "tex_rusted_steel.png",
        "Concrete": "tex_weathered_concrete.png",
        "Amber": "tex_industrial_amber.png",
    }
    for key, fname in expected.items():
        fpath = TEX_DIR / fname
        if fpath.exists():
            img = bpy.data.images.load(str(fpath), check_existing=True)
            img.pack()
            imgs[key] = img
    imgs["CalderaSplat"] = generate_caldera_terrain_texture(512)
    return imgs


def make_pbr_mat(
    name: str,
    base_color: Tuple[float, float, float],
    roughness: float = 0.7,
    metallic: float = 0.0,
    image: bpy.types.Image | None = None,
    emission: Tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Alpha"].default_value = alpha
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.location = (-340, 240)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha < 0.99:
        mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else "HASHED"
    return mat


# ---------------------------------------------------------------------------
# Geometry Utilities (Watertight BMesh Primitives)
# ---------------------------------------------------------------------------

def _ensure_collection(name: str) -> bpy.types.Collection:
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def _box_uv(bm: bmesh.types.BMesh, scale: float = 0.35) -> None:
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * scale, co.y * scale
            elif ax >= ay and ax >= az:
                u, v = co.y * scale, co.z * scale
            else:
                u, v = co.x * scale, co.z * scale
            loop[uv_layer].uv = (u, v)


def _planar_world_uv(bm: bmesh.types.BMesh, half_m: float) -> None:
    uv_layer = bm.loops.layers.uv.verify()
    span = half_m * 2.0
    for face in bm.faces:
        for loop in face.loops:
            co = loop.vert.co
            u = (co.x + half_m) / span
            v = (co.y + half_m) / span
            loop[uv_layer].uv = (u, v)


def _finalize_bm(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    world_uv_half_m: float | None = None,
    uv_scale: float = 0.35,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if world_uv_half_m is not None:
        _planar_world_uv(bm, world_uv_half_m)
    else:
        _box_uv(bm, uv_scale)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    col.objects.link(obj)
    return obj


def _add_box(bm: bmesh.types.BMesh, size_m: Vector, cframe_m: Matrix) -> None:
    res = bmesh.ops.create_cube(bm, size=1.0)
    xf = cframe_m @ Matrix.Diagonal((size_m.x, size_m.y, size_m.z, 1.0))
    for v in res["verts"]:
        v.co = xf @ v.co


def _add_tube(
    bm: bmesh.types.BMesh,
    pts: List[Vector],
    radii: List[float],
    sides: int = 8,
    twist: float = 0.0,
    ridge_amp: float = 0.0,
    seed: int = 1,
) -> None:
    rng = random.Random(seed)
    rings: List[List[bmesh.types.BMVert]] = []
    n_pts = len(pts)
    for i, pt in enumerate(pts):
        if i == 0:
            tan = (pts[1] - pts[0]).normalized()
        elif i == n_pts - 1:
            tan = (pts[-1] - pts[-2]).normalized()
        else:
            tan = (pts[i + 1] - pts[i - 1]).normalized()
        ref = Vector((0, 1, 0)) if abs(tan.y) < 0.9 else Vector((1, 0, 0))
        binorm = tan.cross(ref).normalized()
        norm = binorm.cross(tan).normalized()
        ring: List[bmesh.types.BMVert] = []
        r_base = radii[i]
        phase = twist * (i / max(1, n_pts - 1))
        for s in range(sides):
            ang = phase + (2.0 * math.pi * s) / sides
            ridge = 1.0 + ridge_amp * (math.sin(ang * 3.0 + i) * 0.6 + rng.uniform(-0.35, 0.35))
            r = max(0.02, r_base * ridge)
            ring.append(bm.verts.new(pt + (norm * math.cos(ang) + binorm * math.sin(ang)) * r))
        rings.append(ring)
    for i in range(n_pts - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(sides):
            s2 = (s + 1) % sides
            bm.faces.new((r0[s], r0[s2], r1[s2], r1[s]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def _add_faceted_canopy(
    bm: bmesh.types.BMesh,
    center: Vector,
    rx: float,
    ry: float,
    rz: float,
    yaw: float,
    seed: int,
) -> None:
    rng = random.Random(seed)
    res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    rot = Euler((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), yaw), "XYZ").to_matrix()
    for v in res["verts"]:
        p = v.co.copy()
        p.z *= 0.38 if p.z < 0 else 0.72
        ang = math.atan2(p.y, p.x)
        lobe = 1.0 + 0.24 * math.sin(ang * 5.0 + seed) + 0.12 * math.cos(ang * 3.0 - seed)
        j = 1.0 + rng.uniform(-0.08, 0.08)
        v.co = center + (rot @ Vector((p.x * rx * lobe * j, p.y * ry * lobe * j, p.z * rz)))


# ---------------------------------------------------------------------------
# 01) Caldera Terrain (4 watertight stitched quadrants) + Water Sheet
# ---------------------------------------------------------------------------

def build_terrain_collection(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("01_CalderaTerrain")
    objs: List[bpy.types.Object] = []
    half_m = s2m(TOTAL_HALF_STUDS)
    n_cells = 54  # 54x54 grid per quadrant -> ~6,200 tris per mesh (watertight slab)
    base_z = s2m(-18.0)

    quadrants = [
        ("Terrain_NW", -TOTAL_HALF_STUDS, 0.0, -TOTAL_HALF_STUDS, 0.0),
        ("Terrain_NE", 0.0, TOTAL_HALF_STUDS, -TOTAL_HALF_STUDS, 0.0),
        ("Terrain_SW", -TOTAL_HALF_STUDS, 0.0, 0.0, TOTAL_HALF_STUDS),
        ("Terrain_SE", 0.0, TOTAL_HALF_STUDS, 0.0, TOTAL_HALF_STUDS),
    ]
    for q_name, x0, x1, z0, z1 in quadrants:
        bm = bmesh.new()
        top_grid: List[List[bmesh.types.BMVert]] = []
        bot_grid: List[List[bmesh.types.BMVert]] = []
        for iz in range(n_cells + 1):
            tz = iz / n_cells
            zr = z0 + (z1 - z0) * tz
            row_t: List[bmesh.types.BMVert] = []
            row_b: List[bmesh.types.BMVert] = []
            for ix in range(n_cells + 1):
                tx = ix / n_cells
                xr = x0 + (x1 - x0) * tx
                zm = terrain_y_m(xr, zr)
                pos_t = rbx_to_blender(xr, 0.0, zr)
                pos_t.z = zm
                pos_b = Vector((pos_t.x, pos_t.y, base_z))
                row_t.append(bm.verts.new(pos_t))
                row_b.append(bm.verts.new(pos_b))
            top_grid.append(row_t)
            bot_grid.append(row_b)

        for iz in range(n_cells):
            for ix in range(n_cells):
                # Top surface (note: zr increases toward -Y Blender, check winding cleanly then recalc_normals)
                bm.faces.new((
                    top_grid[iz][ix],
                    top_grid[iz][ix + 1],
                    top_grid[iz + 1][ix + 1],
                    top_grid[iz + 1][ix],
                ))
                # Bottom surface
                bm.faces.new((
                    bot_grid[iz][ix],
                    bot_grid[iz + 1][ix],
                    bot_grid[iz + 1][ix + 1],
                    bot_grid[iz][ix + 1],
                ))

        # Close 4 perimeter skirts so quadrant mesh is strictly watertight
        for ix in range(n_cells):
            bm.faces.new((top_grid[0][ix], bot_grid[0][ix], bot_grid[0][ix + 1], top_grid[0][ix + 1]))
            bm.faces.new((top_grid[n_cells][ix], top_grid[n_cells][ix + 1], bot_grid[n_cells][ix + 1], bot_grid[n_cells][ix]))
        for iz in range(n_cells):
            bm.faces.new((top_grid[iz][0], top_grid[iz + 1][0], bot_grid[iz + 1][0], bot_grid[iz][0]))
            bm.faces.new((top_grid[iz][n_cells], bot_grid[iz][n_cells], bot_grid[iz + 1][n_cells], top_grid[iz + 1][n_cells]))

        objs.append(_finalize_bm(q_name, bm, mats["Terrain"], col, world_uv_half_m=half_m))

    # Translucent river & SE marsh water volume (thin slab along river + marsh)
    bm_w = bmesh.new()
    z_samples = 64
    x_samples = 16
    w_top: List[List[bmesh.types.BMVert]] = []
    w_bot: List[List[bmesh.types.BMVert]] = []
    for iz in range(z_samples + 1):
        zr = -335.0 + (iz / z_samples) * 600.0
        rcx = river_center_x(zr)
        hw = river_half_width(zr) + (55.0 if 115.0 <= zr <= 260.0 else 6.0)
        ws_y = s2m(sample_terrain_studs(rcx, zr)["water_surface"])
        row_t, row_b = [], []
        for ix in range(x_samples + 1):
            xr = rcx - hw + (ix / x_samples) * (2.0 * hw)
            p = rbx_to_blender(xr, 0.0, zr)
            row_t.append(bm_w.verts.new(Vector((p.x, p.y, ws_y))))
            row_b.append(bm_w.verts.new(Vector((p.x, p.y, ws_y - 0.14))))
        w_top.append(row_t)
        w_bot.append(row_b)

    for iz in range(z_samples):
        for ix in range(x_samples):
            bm_w.faces.new((w_top[iz][ix], w_top[iz][ix + 1], w_top[iz + 1][ix + 1], w_top[iz + 1][ix]))
            bm_w.faces.new((w_bot[iz][ix], w_bot[iz + 1][ix], w_bot[iz + 1][ix + 1], w_bot[iz][ix + 1]))
    for ix in range(x_samples):
        bm_w.faces.new((w_top[0][ix], w_bot[0][ix], w_bot[0][ix + 1], w_top[0][ix + 1]))
        bm_w.faces.new((w_top[z_samples][ix], w_top[z_samples][ix + 1], w_bot[z_samples][ix + 1], w_bot[z_samples][ix]))
    for iz in range(z_samples):
        bm_w.faces.new((w_top[iz][0], w_top[iz + 1][0], w_bot[iz + 1][0], w_bot[iz][0]))
        bm_w.faces.new((w_top[iz][x_samples], w_bot[iz][x_samples], w_bot[iz + 1][x_samples], w_top[iz + 1][x_samples]))

    objs.append(_finalize_bm("River_And_Marsh_Water", bm_w, mats["Water"], col))
    return objs


# ---------------------------------------------------------------------------
# 02) North Evolution Caves (3 vaulted roofs, 30+ studs high, curved basalt baffle)
# ---------------------------------------------------------------------------

def build_north_caves(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("02_NorthEvolutionCaves")
    objs: List[bpy.types.Object] = []

    for idx, c in enumerate(CAVE_SPECS):
        bm = bmesh.new()
        cx, cz = c["chamber"]
        mx, mz = c["mouth"]
        fy = c["floorY"]

        # Direction from chamber back toward mouth
        fwd = Vector((mx - cx, 0.0, mz - cz))
        yaw_r = math.atan2(fwd.x, fwd.z)
        # In Blender coords: chamber pos, looking toward mouth
        p_cham = rbx_to_blender(cx, fy, cz)
        p_mouth = rbx_to_blender(mx, fy, mz)
        mid = (p_cham + p_mouth) * 0.5
        dir_b = (p_mouth - p_cham).normalized()
        right_b = dir_b.cross(Vector((0, 0, 1))).normalized()
        basis = Matrix((
            (right_b.x, dir_b.x, 0, mid.x),
            (right_b.y, dir_b.y, 0, mid.y),
            (0, 0, 1, mid.z),
            (0, 0, 0, 1),
        ))

        half_w = s2m(28.0)
        roof_h = s2m(32.0)  # 32 studs clear height (> 30 studs for Stage 3 1.65x)
        depth_b = (p_mouth - p_cham).length + s2m(24.0)
        wall_t = s2m(7.0)

        # Left, right, back rock walls + overlapping angled arched basalt roof slabs
        _add_box(bm, Vector((wall_t, depth_b, roof_h)), basis @ Matrix.Translation((-half_w, 0.0, roof_h * 0.5)))
        _add_box(bm, Vector((wall_t, depth_b, roof_h)), basis @ Matrix.Translation((half_w, 0.0, roof_h * 0.5)))
        _add_box(bm, Vector((half_w * 2.3, wall_t * 1.4, roof_h)), basis @ Matrix.Translation((0.0, -depth_b * 0.5, roof_h * 0.5)))
        # Continuous overlapping vaulted roof ribs so ceiling is thick & rugged
        _add_box(bm, Vector((half_w * 2.4, depth_b + s2m(6.0), s2m(8.0))), basis @ Matrix.Translation((0.0, -s2m(2.0), roof_h + s2m(3.0))))
        _add_box(bm, Vector((half_w * 1.8, depth_b, s2m(7.0))), basis @ Matrix.Translation((0.0, 0.0, roof_h + s2m(5.8))))
        # Dark overhang brow at mouth so entrance looks dark from trail
        _add_box(
            bm,
            Vector((half_w * 2.2, s2m(11.0), s2m(9.5))),
            basis @ Matrix.Translation((0.0, depth_b * 0.45, roof_h - s2m(2.5))) * Matrix.Rotation(math.radians(-14), 4, "X"),
        )
        # Natural curved basalt baffle inside entrance hiding interior from trail while keeping >24 studs exit width
        _add_box(
            bm,
            Vector((s2m(17.0), s2m(10.0), roof_h * 0.92)),
            basis @ Matrix.Translation((s2m(9.5), depth_b * 0.12, roof_h * 0.46)) * Matrix.Rotation(math.radians(-22), 4, "Z"),
        )
        # Wet reflective basalt threshold slab outside mouth (helps exit readability from inside)
        _add_box(
            bm,
            Vector((s2m(34.0), s2m(20.0), s2m(1.2))),
            basis @ Matrix.Translation((-s2m(3.0), depth_b * 0.62, s2m(-0.3))),
        )
        objs.append(_finalize_bm(c["name"], bm, mats["Basalt"], col, uv_scale=0.14))

        # Subtle cool bioluminescent vein deep on interior wall (only faint local bounce, no blinding neon)
        bm_g = bmesh.new()
        _add_box(
            bm_g,
            Vector((s2m(1.8), s2m(2.0), s2m(6.0))),
            basis @ Matrix.Translation((-half_w + wall_t * 0.65, -depth_b * 0.18, s2m(6.5))) * Matrix.Rotation(math.radians(12), 4, "Y"),
        )
        objs.append(_finalize_bm(f"{c['name']}_WetMineralVein", bm_g, mats["CyanEmit"], col))

    return objs


# ---------------------------------------------------------------------------
# 03) Central Helipad (drained concrete deck, ramp, worn amber landing marks)
# ---------------------------------------------------------------------------

def build_central_helipad(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("03_CentralHelipad")
    objs: List[bpy.types.Object] = []
    cx, cy, cz = 0.0, 1.5, -15.0

    # Level concrete foundation & drainage apron
    bm_c = bmesh.new()
    _add_box(bm_c, Vector((s2m(64), s2m(64), s2m(3.6))), Matrix.Translation(rbx_to_blender(cx, cy + 0.2, cz)))
    # Drainage curb walls diverting river water cleanly
    for sx in (-1, 1):
        _add_box(bm_c, Vector((s2m(4.0), s2m(68), s2m(3.2))), Matrix.Translation(rbx_to_blender(cx + sx * 34.0, cy + 1.4, cz)))
    # Main southern exit ramp toward Relay route + eastern covered ramp
    _add_box(
        bm_c,
        Vector((s2m(20), s2m(18), s2m(2.2))),
        Matrix.Translation(rbx_to_blender(0.0, 2.3, cz + 38.0)) * Matrix.Rotation(math.radians(-10), 4, "X"),
    )
    _add_box(
        bm_c,
        Vector((s2m(18), s2m(18), s2m(2.2))),
        Matrix.Translation(rbx_to_blender(38.0, 2.3, cz)) * Matrix.Rotation(math.radians(-10), 4, "Y"),
    )
    objs.append(_finalize_bm("Helipad_FoundationAndRamps", bm_c, mats["Concrete"], col, uv_scale=0.22))

    # Painted dark steel landing deck + 4 corner beacon pylons
    bm_s = bmesh.new()
    _add_box(bm_s, Vector((s2m(52), s2m(52), s2m(0.8))), Matrix.Translation(rbx_to_blender(cx, 3.5, cz)))
    for corner_x, corner_z in [(-24, -24), (24, -24), (-24, 24), (24, 24)]:
        _add_box(bm_s, Vector((s2m(3.0), s2m(3.0), s2m(9.0))), Matrix.Translation(rbx_to_blender(cx + corner_x, 8.0, cz + corner_z)))
    objs.append(_finalize_bm("Helipad_SteelDeck", bm_s, mats["Steel"], col, uv_scale=0.25))

    # Worn amber landing skid strips (faded where ship skids touch down)
    bm_a = bmesh.new()
    for sx in (-12.0, 12.0):
        _add_box(bm_a, Vector((s2m(3.2), s2m(26), s2m(0.18))), Matrix.Translation(rbx_to_blender(sx, 3.95, cz)))
    for sz in (-18.0, 18.0):
        _add_box(bm_a, Vector((s2m(28), s2m(2.2), s2m(0.18))), Matrix.Translation(rbx_to_blender(0.0, 3.95, cz + sz)))
    for corner_x, corner_z in [(-24, -24), (24, -24), (-24, 24), (24, 24)]:
        _add_box(bm_a, Vector((s2m(2.2), s2m(2.2), s2m(1.2))), Matrix.Translation(rbx_to_blender(cx + corner_x, 13.0, cz + corner_z)))
    objs.append(_finalize_bm("Helipad_AmberLandingMarks", bm_a, mats["AmberEmit"], col))

    return objs


# ---------------------------------------------------------------------------
# 04) Adutora (North Intake -> Forest -> South Substation) & Tactical Catwalks
# ---------------------------------------------------------------------------

def build_adutora_and_catwalks(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("04_Adutora_And_Catwalks")
    objs: List[bpy.types.Object] = []

    # Adutora path in Roblox studs: starts in north intake (-95, -310) -> (-72, -160) -> (-56, -10) -> (-52, +140) -> (-42, +265)
    waypoints_rz = [-310.0, -230.0, -155.0, -80.0, -15.0, 60.0, 135.0, 205.0, 265.0]
    waypoints_rx = [-95.0, -84.0, -72.0, -64.0, -58.0, -54.0, -50.0, -46.0, -42.0]

    pts_m: List[Vector] = []
    radii_m: List[float] = []
    bm_piers = bmesh.new()
    bm_flanges = bmesh.new()

    for xr, zr in zip(waypoints_rx, waypoints_rz):
        gy = sample_terrain_studs(xr, zr)["y"]
        pipe_y = max(gy + 10.5, 11.5)
        p_m = rbx_to_blender(xr, pipe_y, zr)
        pts_m.append(p_m)
        radii_m.append(s2m(3.0))

        # Concrete saddle pier down into terrain
        pier_h = (pipe_y - gy) + 4.0
        _add_box(
            bm_piers,
            Vector((s2m(8.0), s2m(6.0), s2m(pier_h))),
            Matrix.Translation(rbx_to_blender(xr, gy + pier_h * 0.5 - 2.0, zr)),
        )
        # Rusted bolted collar ring at every pier
        _add_tube(
            bm_flanges,
            [p_m - Vector((0, 0.25, 0)), p_m + Vector((0, 0.25, 0))],
            [s2m(3.7), s2m(3.7)],
            sides=12,
        )

    bm_pipe = bmesh.new()
    _add_tube(bm_pipe, pts_m, radii_m, sides=12)

    objs.append(_finalize_bm("Adutora_MainConduit", bm_pipe, mats["Steel"], col, uv_scale=0.18))
    objs.append(_finalize_bm("Adutora_ConcretePiers", bm_piers, mats["Concrete"], col, uv_scale=0.22))
    objs.append(_finalize_bm("Adutora_RustedFlanges", bm_flanges, mats["RustedSteel"], col, uv_scale=0.3))

    # 4 Industrial Catwalks connecting high basalt pillars / overlooks
    catwalks = [
        ((-118.0, 32.0, -88.0), (108.0, 32.0, -88.0)),
        ((-125.0, 30.0, 96.0), (115.0, 30.0, 96.0)),
        ((-190.0, 36.0, 0.0), (-118.0, 32.0, -88.0)),
        ((190.0, 36.0, 0.0), (115.0, 30.0, 96.0)),
    ]
    bm_cw = bmesh.new()
    for a, b in catwalks:
        pa = rbx_to_blender(*a)
        pb = rbx_to_blender(*b)
        mid = (pa + pb) * 0.5
        vec = pb - pa
        length = vec.length
        yaw = math.atan2(vec.y, vec.x) - math.pi * 0.5
        xf = Matrix.Translation(mid) @ Matrix.Rotation(yaw, 4, "Z")
        _add_box(bm_cw, Vector((s2m(9.0), length, s2m(1.2))), xf)
        for rail_s in (-1, 1):
            _add_box(bm_cw, Vector((s2m(0.45), length, s2m(2.4))), xf @ Matrix.Translation((rail_s * s2m(4.3), 0.0, s2m(1.6))))
    objs.append(_finalize_bm("Tactical_Catwalks", bm_cw, mats["Steel"], col, uv_scale=0.28))

    return objs


# ---------------------------------------------------------------------------
# 05) 28 Fault-Aligned Basalt Pillars & Outcrops (25 - 65 studs tall)
# ---------------------------------------------------------------------------

def build_fault_pillars(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("05_FaultPillars_Verticality")
    # 28 pillars/outcrops aligned along the 28 deg geological fault
    specs = [
        # Ring around central arena & catwalk anchors
        (-118, -88, 34, 10), (108, -88, 35, 10), (-125, 96, 32, 11), (115, 96, 33, 10),
        (-190, 0, 39, 12), (190, 0, 38, 12),
        # NW & North flanks
        (-255, -165, 48, 13), (-165, -210, 42, 11), (-85, -225, 31, 9), (-290, -85, 52, 14),
        (-215, -62, 28, 9), (-145, -140, 27, 8), (-315, -215, 58, 14),
        # NE flanks
        (165, -210, 44, 12), (255, -155, 50, 13), (85, -215, 29, 9), (295, -75, 55, 14),
        (225, -58, 26, 9), (145, -135, 28, 9), (320, -210, 62, 15),
        # SW & SE flanks & substation approaches
        (-245, 145, 46, 12), (-175, 235, 40, 11), (-295, 210, 60, 15), (-85, 175, 26, 9),
        (250, 145, 45, 12), (175, 255, 39, 11), (305, 215, 64, 15), (90, 175, 25, 8),
    ]

    regions: Dict[str, bmesh.types.BMesh] = {
        "FaultPillars_NW": bmesh.new(),
        "FaultPillars_NE": bmesh.new(),
        "FaultPillars_SW": bmesh.new(),
        "FaultPillars_SE": bmesh.new(),
    }

    fault_dir_b = Vector((math.cos(FAULT_ANGLE_RAD), -math.sin(FAULT_ANGLE_RAD), 0.0)).normalized()
    for idx, (xr, zr, h_studs, r_studs) in enumerate(specs):
        r_key = (
            "FaultPillars_"
            + ("N" if zr < 0 else "S")
            + ("W" if xr < 0 else "E")
        )
        bm = regions[r_key]
        gy = sample_terrain_studs(xr, zr)["y"]
        base_b = rbx_to_blender(xr, gy - 4.0, zr)
        h_m = s2m(h_studs + 4.0)
        r_m = s2m(r_studs)

        # Primary sheared basalt column + stepped side ledge for jetpack / cover
        lean = fault_dir_b * (h_m * 0.14)
        _add_tube(
            bm,
            [base_b, base_b + lean * 0.4 + Vector((0, 0, h_m * 0.45)), base_b + lean + Vector((0, 0, h_m))],
            [r_m * 1.15, r_m * 0.92, r_m * 0.68],
            sides=7,
            twist=0.15,
            ridge_amp=0.14,
            seed=900 + idx,
        )
        # Adjacent lower terrace outcrop enabling monster climb / LOS break
        side_off = Vector((-fault_dir_b.y, fault_dir_b.x, 0.0)) * (r_m * 0.95)
        _add_tube(
            bm,
            [base_b + side_off, base_b + side_off + Vector((0, 0, h_m * 0.52))],
            [r_m * 0.85, r_m * 0.72],
            sides=6,
            ridge_amp=0.12,
            seed=1000 + idx,
        )

    objs: List[bpy.types.Object] = []
    for name, bm in regions.items():
        objs.append(_finalize_bm(name, bm, mats["Basalt"], col, uv_scale=0.14))
    return objs


# ---------------------------------------------------------------------------
# 06) South Relay Substation (0, 6, +285) — Recognizable silhouette from Hangar
# ---------------------------------------------------------------------------

def build_south_relay_substation(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("06_SouthRelaySubstation")
    objs: List[bpy.types.Object] = []
    rx, ry, rz = 0.0, 4.0, 285.0

    # Concrete deck, cable trenches & perimeter blast barriers with 3 wide gaps (28-34 studs)
    bm_c = bmesh.new()
    _add_box(bm_c, Vector((s2m(124), s2m(104), s2m(4.0))), Matrix.Translation(rbx_to_blender(rx, ry, rz)))
    # North wall interrupted by 34-stud wide central breach (xr = -17..+17 open)
    for sx in (-1, 1):
        _add_box(bm_c, Vector((s2m(42), s2m(6), s2m(16))), Matrix.Translation(rbx_to_blender(sx * 38.0, ry + 10.0, rz - 48.0)))
    # East & West walls interrupted by 30-stud wide flank breaches
    for sx in (-1, 1):
        _add_box(bm_c, Vector((s2m(6), s2m(34), s2m(16))), Matrix.Translation(rbx_to_blender(sx * 58.0, ry + 10.0, rz - 30.0)))
        _add_box(bm_c, Vector((s2m(6), s2m(34), s2m(16))), Matrix.Translation(rbx_to_blender(sx * 58.0, ry + 10.0, rz + 30.0)))
    # South rear barrier
    _add_box(bm_c, Vector((s2m(116), s2m(6), s2m(16))), Matrix.Translation(rbx_to_blender(0.0, ry + 10.0, rz + 48.0)))
    objs.append(_finalize_bm("Substation_ConcreteBunker", bm_c, mats["Concrete"], col, uv_scale=0.22))

    # Tall landmark transmission gantry (~48 studs high -> readable from Hangar & Helipad), transformers, catwalk & relay frame
    bm_s = bmesh.new()
    for sx in (-1, 1):
        _add_box(bm_s, Vector((s2m(5.0), s2m(5.0), s2m(48.0))), Matrix.Translation(rbx_to_blender(sx * 34.0, ry + 26.0, rz + 32.0)))
    _add_box(bm_s, Vector((s2m(80.0), s2m(6.0), s2m(5.5))), Matrix.Translation(rbx_to_blender(0.0, ry + 46.0, rz + 32.0)))
    # Maintenance walkway on south edge (Y = 20)
    _add_box(bm_s, Vector((s2m(104.0), s2m(14.0), s2m(1.6))), Matrix.Translation(rbx_to_blender(0.0, ry + 16.0, rz + 38.0)))
    # Two transformer housings flanking outer courtyard (leaving 56-stud free ring around PowerRelay for Stage 3!)
    for sx in (-1, 1):
        _add_box(bm_s, Vector((s2m(14.0), s2m(18.0), s2m(13.0))), Matrix.Translation(rbx_to_blender(sx * 40.0, ry + 8.5, rz - 18.0)))
    # PowerRelay structural cage (openings expose glowing cyan Core)
    _add_box(bm_s, Vector((s2m(18.0), s2m(18.0), s2m(3.0))), Matrix.Translation(rbx_to_blender(0.0, ry + 3.5, rz)))
    _add_box(bm_s, Vector((s2m(15.0), s2m(15.0), s2m(3.2))), Matrix.Translation(rbx_to_blender(0.0, ry + 21.5, rz)))
    for px, pz in [(-7.5, -7.5), (7.5, -7.5), (-7.5, 7.5), (7.5, 7.5)]:
        _add_box(bm_s, Vector((s2m(2.8), s2m(2.8), s2m(17.0))), Matrix.Translation(rbx_to_blender(px, ry + 12.0, rz + pz)))
    objs.append(_finalize_bm("Substation_GantryAndTransformers", bm_s, mats["Steel"], col, uv_scale=0.22))

    # PowerRelay Core (Cyan instrumentation glow) + Emergency Red containment beacons
    bm_core = bmesh.new()
    _add_box(bm_core, Vector((s2m(10.0), s2m(10.0), s2m(15.5))), Matrix.Translation(rbx_to_blender(0.0, ry + 12.0, rz)))
    objs.append(_finalize_bm("PowerRelay_Core", bm_core, mats["CyanEmit"], col))

    bm_red = bmesh.new()
    for bx, bz in [(-52, rz - 44), (52, rz - 44), (-52, rz + 44), (52, rz + 44), (-34, rz + 32), (34, rz + 32)]:
        _add_box(bm_red, Vector((s2m(2.4), s2m(2.4), s2m(2.4))), Matrix.Translation(rbx_to_blender(bx, ry + 20.0, bz)))
    objs.append(_finalize_bm("Substation_ContainmentBeacons", bm_red, mats["RedEmit"], col))

    return objs


# ---------------------------------------------------------------------------
# 07) 3-Tier Volcanic BioForest (Trunks, Branches, Faceted Canopies, Roots & Ferns)
# ---------------------------------------------------------------------------

def build_forest_3tiers(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("07_BioForest_3Tiers")
    rng = random.Random(420811)

    trunks_n, trunks_s = bmesh.new(), bmesh.new()
    canopy_n, canopy_s = bmesh.new(), bmesh.new()
    under_n, under_s = bmesh.new(), bmesh.new()

    # Validated clear zones: avoid Helipad, Relay, Caves, River center, Direct road
    tree_spots: List[Tuple[float, float, int]] = []
    attempts = 0
    while len(tree_spots) < 76 and attempts < 1400:
        attempts += 1
        xr = rng.uniform(-345.0, 345.0)
        zr = rng.uniform(-315.0, 315.0)
        if math.hypot(xr, zr + 15.0) < 62.0:
            continue
        if math.hypot(xr, zr - 285.0) < 76.0:
            continue
        if abs(xr - river_center_x(zr)) < river_half_width(zr) + 12.0:
            continue
        if math.hypot(xr - 195.0, zr - 195.0) < 58.0:
            continue
        if 10.0 <= zr <= 250.0 and abs(xr - direct_road_x(zr)) < 22.0:
            continue
        # Keep cave entrances & interior clear
        blocked_cave = False
        for c in CAVE_SPECS:
            dc, _ = _dist_to_segment_2d(xr, zr, c["chamber"][0], c["chamber"][1], c["mouth"][0], c["mouth"][1])
            if dc < 42.0:
                blocked_cave = True
                break
        if blocked_cave:
            continue
        # Min spacing 28 studs between trees
        if any(math.hypot(xr - tx, zr - tz) < 28.0 for tx, tz, _ in tree_spots):
            continue
        tier = 1 if (attempts % 3 != 0) else 2  # 1: tall canopy tree, 2: crooked midstory tree
        tree_spots.append((xr, zr, tier))

    for idx, (xr, zr, tier) in enumerate(tree_spots):
        gy = sample_terrain_studs(xr, zr)["y"]
        base_b = rbx_to_blender(xr, gy - 1.5, zr)
        bm_t = trunks_n if zr < 0 else trunks_s
        bm_c = canopy_n if zr < 0 else canopy_s
        bm_u = under_n if zr < 0 else under_s
        yaw = rng.uniform(0, math.tau)
        rot = Matrix.Rotation(yaw, 4, "Z")

        if tier == 1:
            # Tier 3 canopy tree: flared roots + forked trunk + irregular polygonal leaf tiers (zero spheres)
            h_m = s2m(rng.uniform(28.0, 39.0))
            lean = rot @ Vector((h_m * 0.12, 0.0, 0.0))
            _add_tube(
                bm_t,
                [base_b, base_b + lean * 0.4 + Vector((0, 0, h_m * 0.48)), base_b + lean + Vector((0, 0, h_m * 0.85))],
                [s2m(2.2), s2m(1.4), s2m(0.7)],
                sides=6,
                ridge_amp=0.14,
                seed=2000 + idx,
            )
            # 2 diverging main limbs
            for s_b in (-1, 1):
                limb_tip = base_b + lean + (rot @ Vector((s_b * s2m(8.5), s_b * s2m(3.0), h_m * 0.94)))
                _add_tube(
                    bm_t,
                    [base_b + lean * 0.6 + Vector((0, 0, h_m * 0.58)), limb_tip],
                    [s2m(0.85), s2m(0.38)],
                    sides=5,
                    seed=2200 + idx + s_b,
                )
                _add_faceted_canopy(bm_c, limb_tip + Vector((0, 0, s2m(2.0))), s2m(9.5), s2m(8.5), s2m(4.2), yaw + s_b, 2400 + idx + s_b)
            _add_faceted_canopy(bm_c, base_b + lean + Vector((0, 0, h_m * 0.96)), s2m(11.0), s2m(9.5), s2m(4.8), yaw, 2600 + idx)

            # Tier 1 buttress roots / fallen log at tree foot
            if idx % 2 == 0:
                ang = yaw + 0.8
                ra = base_b + Vector((math.cos(ang) * s2m(4.0), math.sin(ang) * s2m(4.0), s2m(1.0)))
                rb = base_b + Vector((math.cos(ang) * s2m(12.0), math.sin(ang) * s2m(12.0), s2m(0.6)))
                _add_tube(bm_u, [ra, (ra + rb) * 0.5 + Vector((0, 0, s2m(3.2))), rb], [s2m(1.3), s2m(0.95), s2m(0.5)], sides=6, seed=2800 + idx)
        else:
            # Tier 2 midstory crooked tree breaking sightlines
            h_m = s2m(rng.uniform(13.0, 17.5))
            lean = rot @ Vector((h_m * 0.2, s2m(1.2), 0.0))
            _add_tube(
                bm_t,
                [base_b, base_b + lean * 0.5 + Vector((0, 0, h_m * 0.45)), base_b + lean + Vector((0, 0, h_m * 0.85))],
                [s2m(1.1), s2m(0.7), s2m(0.35)],
                sides=6,
                seed=3000 + idx,
            )
            _add_faceted_canopy(bm_c, base_b + lean + Vector((0, 0, h_m * 0.90)), s2m(6.8), s2m(6.0), s2m(3.2), yaw, 3200 + idx)

    # Extra ground-level ferns / understory clusters near forest & marsh margins
    for f_i in range(44):
        fx = rng.uniform(-310.0, 310.0)
        fz = rng.uniform(-280.0, 260.0)
        if math.hypot(fx, fz + 15.0) < 55.0 or math.hypot(fx, fz - 285.0) < 68.0:
            continue
        gy = sample_terrain_studs(fx, fz)["y"]
        bm_u = under_n if fz < 0 else under_s
        _add_faceted_canopy(bm_u, rbx_to_blender(fx, gy + 1.2, fz), s2m(3.8), s2m(3.4), s2m(1.9), rng.uniform(0, 6.28), 3500 + f_i)

    return [
        _finalize_bm("Forest_Trunks_North", trunks_n, mats["Bark"], col, uv_scale=0.25),
        _finalize_bm("Forest_Trunks_South", trunks_s, mats["Bark"], col, uv_scale=0.25),
        _finalize_bm("Forest_Canopy_North", canopy_n, mats["Canopy"], col, uv_scale=0.20),
        _finalize_bm("Forest_Canopy_South", canopy_s, mats["Canopy"], col, uv_scale=0.20),
        _finalize_bm("Forest_Understory_North", under_n, mats["Canopy"], col, uv_scale=0.30),
        _finalize_bm("Forest_Understory_South", under_s, mats["Canopy"], col, uv_scale=0.30),
    ]


# ---------------------------------------------------------------------------
# 08) Hangar Lobby at Y = 600 studs (Z = +168 m) with South Cantilever Observatory
# ---------------------------------------------------------------------------

def build_hangar_lobby(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("08_HangarLobby_Y600")
    hy = 600.0  # Roblox Y=600 studs
    bm_shell = bmesh.new()
    bm_grates = bmesh.new()
    bm_cyan = bmesh.new()
    bm_amber = bmesh.new()
    bm_red = bmesh.new()
    bm_rubber = bmesh.new()
    bm_glass = bmesh.new()

    # Main floor (X: -62..+62, Z_r: -60..+50) with lowered Boarding Bay at Z_r: +4..+40, X: -22..+22
    # North floor (around LobbySpawn at Z_r = -46 and Command Table at Z_r = -16)
    _add_box(bm_shell, Vector((s2m(124), s2m(64), s2m(2.5))), Matrix.Translation(rbx_to_blender(0.0, hy - 1.25, -28.0)))
    # West & East wings alongside lowered boarding bay
    for sx in (-1, 1):
        _add_box(bm_shell, Vector((s2m(40), s2m(46), s2m(2.5))), Matrix.Translation(rbx_to_blender(sx * 42.0, hy - 1.25, 27.0)))
    # Lowered Boarding Bay floor (Y = 598.2) + ramp down from Command floor (Z_r = +4..+12)
    _add_box(bm_shell, Vector((s2m(44), s2m(46), s2m(2.0))), Matrix.Translation(rbx_to_blender(0.0, hy - 2.8, 27.0)))
    _add_box(
        bm_shell,
        Vector((s2m(26), s2m(12), s2m(1.5))),
        Matrix.Translation(rbx_to_blender(0.0, hy - 1.5, 8.0)) * Matrix.Rotation(math.radians(-11), 4, "X"),
    )
    # South gallery sill leading into cantilevered observatory (Z_r = +46..+56)
    _add_box(bm_shell, Vector((s2m(124), s2m(12), s2m(2.0))), Matrix.Translation(rbx_to_blender(0.0, hy - 1.0, 50.0)))

    # Modular side walls (14-stud module pillars + structural roof beams + roof deck)
    for sx in (-1, 1):
        _add_box(bm_shell, Vector((s2m(4), s2m(114), s2m(32))), Matrix.Translation(rbx_to_blender(sx * 60.0, hy + 16.0, -3.0)))
    _add_box(bm_shell, Vector((s2m(124), s2m(4), s2m(32))), Matrix.Translation(rbx_to_blender(0.0, hy + 16.0, -58.0)))
    _add_box(bm_shell, Vector((s2m(124), s2m(122), s2m(2.5))), Matrix.Translation(rbx_to_blender(0.0, hy + 32.0, 1.0)))

    # Columns & overhead roof beams every 16 studs
    for zr in (-44, -28, -12, 4, 20, 36):
        _add_box(bm_shell, Vector((s2m(118), s2m(3.0), s2m(3.2))), Matrix.Translation(rbx_to_blender(0.0, hy + 29.5, zr)))
        for sx in (-1, 1):
            _add_box(bm_shell, Vector((s2m(3.0), s2m(3.0), s2m(30.0))), Matrix.Translation(rbx_to_blender(sx * 56.5, hy + 15.0, zr)))

    # Underfloor illuminated cable trenches + slatted grates
    for sx in (-25.0, 25.0):
        _add_box(bm_grates, Vector((s2m(5.0), s2m(44.0), s2m(0.4))), Matrix.Translation(rbx_to_blender(sx, hy + 0.05, -24.0)))
        _add_box(bm_amber, Vector((s2m(0.8), s2m(42.0), s2m(0.5))), Matrix.Translation(rbx_to_blender(sx, hy - 0.5, -24.0)))

    # 1. Command Table at (0, 600, -16) — low profile (3.2 studs high) so Boarding Bay stays visible!
    _add_box(bm_shell, Vector((s2m(22.0), s2m(12.0), s2m(3.0))), Matrix.Translation(rbx_to_blender(0.0, hy + 1.5, -16.0)))
    # Mini holographic caldera relief + river + relay on Command Table
    _add_box(bm_cyan, Vector((s2m(15.0), s2m(8.5), s2m(0.4))), Matrix.Translation(rbx_to_blender(0.0, hy + 3.2, -16.0)))
    _add_box(bm_cyan, Vector((s2m(2.4), s2m(2.4), s2m(1.8))), Matrix.Translation(rbx_to_blender(0.0, hy + 4.1, -12.5)))  # Mini South Relay
    _add_box(bm_amber, Vector((s2m(2.0), s2m(2.0), s2m(0.9))), Matrix.Translation(rbx_to_blender(0.0, hy + 3.6, -16.2)))  # Mini Helipad

    # 2. Boarding Bay details: guide rails, rubber bumpers, worn amber skid strips, match board
    for sx in (-15.0, 15.0):
        _add_box(bm_rubber, Vector((s2m(2.2), s2m(34.0), s2m(1.4))), Matrix.Translation(rbx_to_blender(sx, hy - 1.1, 27.0)))
        _add_box(bm_amber, Vector((s2m(2.4), s2m(26.0), s2m(0.15))), Matrix.Translation(rbx_to_blender(sx * 0.65, hy - 1.72, 27.0)))
    _add_box(bm_cyan, Vector((s2m(24.0), s2m(0.6), s2m(6.0))), Matrix.Translation(rbx_to_blender(0.0, hy + 17.0, 48.0)))

    # 3. 4 Hunter Loadout Bays on West side (X_r = -46) with distinct equipment identities
    for b_idx, bz in enumerate([-34.0, -14.0, 6.0, 26.0]):
        _add_box(bm_shell, Vector((s2m(10.0), s2m(13.0), s2m(12.0))), Matrix.Translation(rbx_to_blender(-51.0, hy + 6.0, bz)))
        _add_box(bm_shell, Vector((s2m(8.0), s2m(11.0), s2m(2.8))), Matrix.Translation(rbx_to_blender(-45.0, hy + 1.4, bz)))
        # Functional props per role: 0=Medic(cyan med unit), 1=Trapper(amber cable spools), 2=Assault(red-dark armor plates), 3=Support(cyan power cells)
        target_bm = bm_cyan if b_idx in (0, 3) else (bm_amber if b_idx == 1 else bm_red)
        _add_box(target_bm, Vector((s2m(2.4), s2m(4.2), s2m(3.8))), Matrix.Translation(rbx_to_blender(-45.0, hy + 4.4, bz)))

    # 4. Containment Chamber on East side (X_r = +46) + power cable + mechanical lock
    _add_box(bm_shell, Vector((s2m(18.0), s2m(22.0), s2m(20.0))), Matrix.Translation(rbx_to_blender(46.0, hy + 10.0, -10.0)))
    _add_box(bm_glass, Vector((s2m(1.2), s2m(14.0), s2m(14.0))), Matrix.Translation(rbx_to_blender(37.5, hy + 9.0, -10.0)))
    _add_box(bm_red, Vector((s2m(6.0), s2m(8.0), s2m(12.0))), Matrix.Translation(rbx_to_blender(45.5, hy + 8.0, -10.0)))
    _add_box(bm_rubber, Vector((s2m(1.0), s2m(18.0), s2m(0.8))), Matrix.Translation(rbx_to_blender(42.0, hy + 0.4, -26.0)))

    # 5. Cantilevered Angled South Observatory (Z_r = +54..+68) — transparent glass floor & downward-sloped window!
    # So looking straight down at ~69 deg from Cam_2_ObservatoryToValley reveals the river curve & Relay unobstructed!
    _add_box(bm_glass, Vector((s2m(96.0), s2m(16.0), s2m(0.6))), Matrix.Translation(rbx_to_blender(0.0, hy - 0.3, 61.0)))
    _add_box(
        bm_glass,
        Vector((s2m(96.0), s2m(0.8), s2m(26.0))),
        Matrix.Translation(rbx_to_blender(0.0, hy + 12.0, 66.0)) * Matrix.Rotation(math.radians(-18), 4, "X"),
    )
    # Steel mullions framing the observatory glass
    for mx in (-46.0, -24.0, 24.0, 46.0):
        _add_box(
            bm_shell,
            Vector((s2m(1.8), s2m(1.8), s2m(26.0))),
            Matrix.Translation(rbx_to_blender(mx, hy + 12.0, 66.0)) * Matrix.Rotation(math.radians(-18), 4, "X"),
        )
    # Upper header & lower protective guard-rail at edge of glass deck
    _add_box(bm_shell, Vector((s2m(124.0), s2m(5.0), s2m(6.0))), Matrix.Translation(rbx_to_blender(0.0, hy + 28.0, 61.0)))
    _add_box(bm_amber, Vector((s2m(94.0), s2m(0.6), s2m(0.6))), Matrix.Translation(rbx_to_blender(0.0, hy + 3.4, 56.0)))

    return [
        _finalize_bm("Hangar_StructureAndBays", bm_shell, mats["Steel"], col, uv_scale=0.25),
        _finalize_bm("Hangar_FloorGrates", bm_grates, mats["DarkMetal"], col, uv_scale=0.5),
        _finalize_bm("Hangar_CyanInstrumentation", bm_cyan, mats["CyanEmit"], col),
        _finalize_bm("Hangar_AmberOperations", bm_amber, mats["AmberEmit"], col),
        _finalize_bm("Hangar_RedContainment", bm_red, mats["RedEmit"], col),
        _finalize_bm("Hangar_RubberAndCables", bm_rubber, mats["Rubber"], col),
        _finalize_bm("Hangar_ObservatoryGlass", bm_glass, mats["ClearGlass"], col),
    ]


# ---------------------------------------------------------------------------
# 09) Spawns & Scale Reference Markers (No Export)
# ---------------------------------------------------------------------------

def build_reference_markers(mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    col = _ensure_collection("09_ReferenceMarkers_NoExport")
    bm_m = bmesh.new()
    bm_h = bmesh.new()
    bm_p = bmesh.new()

    # 3 Monster Spawns (1 per North Cave)
    for c in CAVE_SPECS:
        sx, sz = c["spawn"]
        sy = c["floorY"]
        _add_box(bm_m, Vector((s2m(4.0), s2m(4.0), s2m(0.6))), Matrix.Translation(rbx_to_blender(sx, sy + 0.3, sz)))

    # Stage 3 Monster scale reference silhouette (1.65x scale -> ~11 studs tall) at Cave_NW mouth for Cam_5 check!
    _add_box(bm_m, Vector((s2m(6.5), s2m(5.5), s2m(11.5))), Matrix.Translation(rbx_to_blender(-302.0, 9.8, -302.0)))

    # 4 Hunter Spawns on Helipad + 5.5-stud Avatar scale dummy next to Ramp
    for hx, hz in [(-10, -25), (10, -25), (-10, -5), (10, -5)]:
        _add_box(bm_h, Vector((s2m(3.2), s2m(3.2), s2m(0.5))), Matrix.Translation(rbx_to_blender(hx, 4.15, hz)))
    _add_box(bm_h, Vector((s2m(2.2), s2m(1.4), s2m(5.5))), Matrix.Translation(rbx_to_blender(0.0, 6.7, 5.0)))

    # 28 Prey Habitat Markers (including 1 clearing right outside each cave mouth)
    prey_coords = [
        # Outside the 3 North caves (early food & route choice before hunter contact!)
        (-245.0, -245.0), (20.0, -235.0), (195.0, -225.0),
        # NW & North trails
        (-285.0, -145.0), (-185.0, -165.0), (-135.0, -265.0), (-55.0, -175.0), (-295.0, -25.0),
        # NE trails
        (135.0, -255.0), (275.0, -145.0), (165.0, -145.0), (65.0, -155.0), (295.0, -25.0),
        # Central river / forest flanks
        (-155.0, -45.0), (155.0, -45.0), (-145.0, 55.0), (145.0, 55.0), (-225.0, 20.0), (225.0, 20.0),
        # South & SE marsh habitats
        (-245.0, 125.0), (235.0, 125.0), (-145.0, 175.0), (155.0, 165.0), (235.0, 215.0),
        (-275.0, 235.0), (-95.0, 240.0), (105.0, 240.0), (285.0, 185.0),
    ]
    for px, pz in prey_coords:
        py = max(sample_terrain_studs(px, pz)["y"], sample_terrain_studs(px, pz)["water_surface"])
        _add_box(bm_p, Vector((s2m(2.8), s2m(2.8), s2m(0.8))), Matrix.Translation(rbx_to_blender(px, py + 0.4, pz)))

    return [
        _finalize_bm("Ref_MonsterSpawns_And_Stage3", bm_m, mats["RedEmit"], col),
        _finalize_bm("Ref_HunterSpawns_And_Avatar", bm_h, mats["CyanEmit"], col),
        _finalize_bm("Ref_PreyHabitats_28", bm_p, mats["AmberEmit"], col),
    ]


# ---------------------------------------------------------------------------
# Lighting, World Atmosphere & 6 Verification Cameras
# ---------------------------------------------------------------------------

def setup_lighting_and_cameras() -> List[bpy.types.Object]:
    col = _ensure_collection("10_LightingAndCameras")

    # Humid volcanic dusk Sky/World
    world = bpy.data.worlds.new("PrimalHunt_DuskWorld")
    bpy.context.scene.world = world
    if not world.use_nodes:
        world.use_nodes = True
    nt = world.node_tree
    bg = next((n for n in nt.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.14, 0.19, 0.25, 1.0)  # Cool sky fill in shadows
        bg.inputs["Strength"].default_value = 1.25

    # Low warm-amber raking dusk Sun to reveal terrain relief
    sun_data = bpy.data.lights.new(name="Sun_DuskRaking", type="SUN")
    sun_data.energy = 3.2
    sun_data.color = (1.0, 0.72, 0.50)
    sun_obj = bpy.data.objects.new("Sun_DuskRaking", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(68), math.radians(14), math.radians(-38)), "XYZ")
    col.objects.link(sun_obj)

    # Interior Hangar ceiling lights (practical warm-neutral illumination)
    for lx, lz, eng in [(-18, -28, 2200), (18, -28, 2200), (0, 12, 2600), (-34, 10, 1800), (34, -8, 1800)]:
        ldata = bpy.data.lights.new(name=f"HangarLamp_{lx}_{lz}", type="POINT")
        ldata.energy = eng
        ldata.color = (0.85, 0.93, 1.0)
        ldata.shadow_soft_size = 1.2
        lobj = bpy.data.objects.new(f"HangarLamp_{lx}_{lz}", ldata)
        lobj.location = rbx_to_blender(lx, 622.0, lz)
        col.objects.link(lobj)

    # Helipad, Relay & Cave Exit bounced fill lights
    for lname, rpos, col_rgb, eng in [
        ("HelipadKey", (0, 24, -15), (1.0, 0.78, 0.45), 3500),
        ("RelayCoreLight", (0, 22, 285), (0.35, 0.88, 1.0), 4200),
        ("CaveNWBounce", (-288, 14, -288), (0.55, 0.72, 0.85), 2400),
    ]:
        ldata = bpy.data.lights.new(name=lname, type="POINT")
        ldata.energy = eng
        ldata.color = col_rgb
        lobj = bpy.data.objects.new(lname, ldata)
        lobj.location = rbx_to_blender(*rpos)
        col.objects.link(lobj)

    cam_specs = [
        ("Cam_0_AerialCalderaOverview", Vector((96.0, -108.0, 94.0)), Vector((0.0, 0.0, 8.0))),
        ("Cam_1_HangarSpawnToBay", rbx_to_blender(0, 606.5, -46), rbx_to_blender(0, 603, 25)),
        ("Cam_2_ObservatoryToValley", rbx_to_blender(0, 611, 56), rbx_to_blender(0, 6, 220)),
        ("Cam_3_HelipadToRelay", rbx_to_blender(0, 11, -18), rbx_to_blender(0, 12, 285)),
        ("Cam_4_ForestSwampMargin", rbx_to_blender(115, 13, 125), rbx_to_blender(215, 5, 195)),
        ("Cam_5_NorthCaveExit", rbx_to_blender(-346, 12, -346), rbx_to_blender(-298, 9, -298)),
    ]

    cams: List[bpy.types.Object] = []
    for cname, pos, target in cam_specs:
        cdata = bpy.data.cameras.new(cname)
        cdata.lens = 24.0
        cdata.clip_end = 1500.0
        cobj = bpy.data.objects.new(cname, cdata)
        cobj.location = pos
        direction = (target - pos).normalized()
        cobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        col.objects.link(cobj)
        cams.append(cobj)
    bpy.context.scene.camera = cams[0]
    return cams


def render_previews(cams: List[bpy.types.Object]) -> List[str]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"

    files = [
        "Preview_0_Aerial.png",
        "Preview_1_Hangar.png",
        "Preview_2_Observatory.png",
        "Preview_3_HelipadToRelay.png",
        "Preview_4_ForestMarsh.png",
        "Preview_5_CaveExit.png",
    ]
    paths: List[str] = []
    for cam, fname in zip(cams, files):
        scene.camera = cam
        out_path = str(PREVIEWS_DIR / fname)
        scene.render.filepath = out_path
        bpy.ops.render.render(write_still=True)
        paths.append(out_path)
    scene.camera = cams[0]
    return paths


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    imgs = _load_or_build_kit_textures()

    mats = {
        "Terrain": make_pbr_mat("Mat_CalderaTerrain", (0.20, 0.22, 0.16), roughness=0.88, image=imgs["CalderaSplat"]),
        "Water": make_pbr_mat("Mat_ShallowWater", (0.14, 0.28, 0.26), roughness=0.14, alpha=0.68),
        "Basalt": make_pbr_mat("Mat_VolcanicBasalt", (0.18, 0.19, 0.21), roughness=0.82, image=imgs.get("Basalt")),
        "Concrete": make_pbr_mat("Mat_WeatheredConcrete", (0.35, 0.36, 0.37), roughness=0.88, image=imgs.get("Concrete")),
        "Steel": make_pbr_mat("Mat_PaintedSteel", (0.22, 0.26, 0.31), roughness=0.55, metallic=0.55, image=imgs.get("Steel")),
        "RustedSteel": make_pbr_mat("Mat_RustedFlange", (0.36, 0.18, 0.11), roughness=0.72, metallic=0.45, image=imgs.get("Steel")),
        "DarkMetal": make_pbr_mat("Mat_DarkGrate", (0.12, 0.14, 0.17), roughness=0.50, metallic=0.75),
        "Rubber": make_pbr_mat("Mat_MatteRubber", (0.05, 0.05, 0.06), roughness=0.92),
        "Bark": make_pbr_mat("Mat_VolcanicBark", (0.18, 0.13, 0.10), roughness=0.88, image=imgs.get("Bark")),
        "Canopy": make_pbr_mat("Mat_CanopyFoliage", (0.14, 0.33, 0.19), roughness=0.72, image=imgs.get("Canopy")),
        "ClearGlass": make_pbr_mat("Mat_ObservatoryGlass", (0.58, 0.78, 0.88), roughness=0.08, alpha=0.22),
        "CyanEmit": make_pbr_mat("Mat_CyanInstrument", (0.20, 0.85, 1.0), roughness=0.2, emission=(0.20, 0.85, 1.0), emission_strength=3.5),
        "AmberEmit": make_pbr_mat("Mat_AmberOperation", (0.95, 0.56, 0.12), roughness=0.35, emission=(0.95, 0.56, 0.12), emission_strength=2.2),
        "RedEmit": make_pbr_mat("Mat_RedContainment", (0.72, 0.08, 0.09), roughness=0.35, emission=(0.72, 0.08, 0.09), emission_strength=2.6),
    }

    all_objs: List[bpy.types.Object] = []
    all_objs.extend(build_terrain_collection(mats))
    all_objs.extend(build_north_caves(mats))
    all_objs.extend(build_central_helipad(mats))
    all_objs.extend(build_adutora_and_catwalks(mats))
    all_objs.extend(build_fault_pillars(mats))
    all_objs.extend(build_south_relay_substation(mats))
    all_objs.extend(build_forest_3tiers(mats))
    all_objs.extend(build_hangar_lobby(mats))
    all_objs.extend(build_reference_markers(mats))
    cams = setup_lighting_and_cameras()

    stats = {"objects": [], "maxTriangles": 0, "totalTriangles": 0}
    for o in all_objs:
        tris = len(o.data.polygons)
        stats["maxTriangles"] = max(stats["maxTriangles"], tris)
        stats["totalTriangles"] += tris
        stats["objects"].append({"name": o.name, "triangles": tris})

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    preview_paths = render_previews(cams)
    stats["blendPath"] = str(BLEND_PATH)
    stats["previews"] = preview_paths
    REPORT_PATH.write_text(json.dumps(stats, indent=2), encoding="utf-8")
    print("PRIMAL_HUNT_FULLMAP_READY")
    print(json.dumps({
        "blendPath": str(BLEND_PATH),
        "meshCount": len(all_objs),
        "maxTriangles": stats["maxTriangles"],
        "totalTriangles": stats["totalTriangles"],
        "previews": preview_paths,
    }, indent=2))


if __name__ == "__main__":
    main()
