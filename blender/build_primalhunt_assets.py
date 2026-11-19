"""PRIMAL HUNT — Blender 5.3 procedural 3D environment kit builder for Roblox Studio.

Builds watertight, UV-mapped, textured mesh kits (Trees, Rocks, Foliage, Ruins),
saves PrimalHunt_EnvironmentKit.blend, exports 4 GLB files, writes textures/, and
emits asset_manifest.json for post-import Roblox Studio verification.
"""

from __future__ import annotations

import json
import math
import os
import random
from pathlib import Path
from typing import Dict, List, Tuple

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
BLEND_DIR = ROOT_DIR / "blender"
TEX_DIR = ROOT_DIR / "textures"
MANIFEST_PATH = ROOT_DIR / "asset_manifest.json"
BLEND_PATH = BLEND_DIR / "PrimalHunt_EnvironmentKit.blend"

BLEND_DIR.mkdir(parents=True, exist_ok=True)
TEX_DIR.mkdir(parents=True, exist_ok=True)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------------------
# Procedural RGBA texture synthesis (packed + saved as PNGs for repair fallback)
# ---------------------------------------------------------------------------

def _hash2(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0x7FFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _value_noise(u: np.ndarray, v: np.ndarray, freq: float, seed: int) -> np.ndarray:
    x = u * freq
    y = v * freq
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    sx = fx * fx * (3.0 - 2.0 * fx)
    sy = fy * fy * (3.0 - 2.0 * fy)
    p = int(freq)
    ix0 = ix % p
    iy0 = iy % p
    ix1 = (ix0 + 1) % p
    iy1 = (iy0 + 1) % p
    n00 = _hash2(ix0, iy0, seed)
    n10 = _hash2(ix1, iy0, seed)
    n01 = _hash2(ix0, iy1, seed)
    n11 = _hash2(ix1, iy1, seed)
    nx0 = n00 * (1.0 - sx) + n10 * sx
    nx1 = n01 * (1.0 - sx) + n11 * sx
    return nx0 * (1.0 - sy) + nx1 * sy


def _fbm(u: np.ndarray, v: np.ndarray, base_freq: float, octaves: int, seed: int) -> np.ndarray:
    acc = np.zeros_like(u)
    amp = 0.5
    norm = 0.0
    freq = base_freq
    for oct_idx in range(octaves):
        acc += amp * _value_noise(u, v, freq, seed + oct_idx * 97)
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return acc / norm


def _make_image(name: str, rgba: np.ndarray) -> bpy.types.Image:
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name=name, width=w, height=h, alpha=True)
    flat = np.clip(rgba, 0.0, 1.0).astype(np.float32).reshape(-1)
    img.pixels.foreach_set(flat)
    png_path = TEX_DIR / f"{name}.png"
    img.filepath_raw = str(png_path)
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def build_textures() -> Dict[str, bpy.types.Image]:
    size = 256
    lin = np.linspace(0.0, 1.0, size, endpoint=False)
    u, v = np.meshgrid(lin, lin)

    # 1. Volcanic dark bark with vertical furrows & damp moss streaks
    bark_f = _fbm(u * 2.5, v * 0.5, 6.0, 4, 101)
    moss_m = np.clip((_fbm(u, v, 5.0, 3, 202) - 0.52) * 3.0, 0.0, 1.0)
    furrow = np.abs(np.sin((u * 18.0 + bark_f * 2.2) * math.pi)) * 0.5 + bark_f * 0.5
    bark_rgb = np.zeros((size, size, 4), dtype=np.float32)
    bark_rgb[..., 0] = 0.14 + 0.16 * furrow - 0.05 * moss_m
    bark_rgb[..., 1] = 0.10 + 0.11 * furrow + 0.14 * moss_m
    bark_rgb[..., 2] = 0.08 + 0.07 * furrow + 0.02 * moss_m
    bark_rgb[..., 3] = 1.0

    # 2. Multi-tone caldera canopy foliage (rich damp emerald / olive / mineral teal)
    leaf_f = _fbm(u, v, 8.0, 4, 303)
    vein = _fbm(u * 1.4, v * 1.4, 16.0, 2, 404)
    canopy_rgb = np.zeros((size, size, 4), dtype=np.float32)
    canopy_rgb[..., 0] = 0.09 + 0.14 * leaf_f + 0.05 * vein
    canopy_rgb[..., 1] = 0.22 + 0.24 * leaf_f + 0.07 * vein
    canopy_rgb[..., 2] = 0.13 + 0.10 * leaf_f + 0.04 * (1.0 - vein)
    canopy_rgb[..., 3] = 1.0

    # 3. Stratified volcanic basalt with damp fissures & subtle iron-oxide veining
    strata = _fbm(u * 0.7, v * 2.4, 5.0, 4, 505)
    crack = np.clip(1.0 - np.abs(_fbm(u, v, 7.0, 3, 606) - 0.5) * 9.0, 0.0, 1.0)
    rust_stain = np.clip((_fbm(u, v, 4.0, 3, 707) - 0.58) * 3.2, 0.0, 1.0)
    basalt_rgb = np.zeros((size, size, 4), dtype=np.float32)
    basalt_rgb[..., 0] = 0.15 + 0.14 * strata - 0.08 * crack + 0.15 * rust_stain
    basalt_rgb[..., 1] = 0.16 + 0.13 * strata - 0.08 * crack + 0.07 * rust_stain
    basalt_rgb[..., 2] = 0.18 + 0.14 * strata - 0.07 * crack
    basalt_rgb[..., 3] = 1.0

    # 4. Weathered painted industrial steel with rust around joints/bolts
    steel_grain = _fbm(u, v, 10.0, 3, 808)
    edge_rust = np.clip(
        np.maximum(np.abs(u - 0.5), np.abs(v - 0.5)) * 2.2 - 0.55 + (steel_grain - 0.45),
        0.0,
        1.0,
    )
    steel_rgb = np.zeros((size, size, 4), dtype=np.float32)
    steel_rgb[..., 0] = 0.19 + 0.12 * steel_grain + 0.25 * edge_rust
    steel_rgb[..., 1] = 0.23 + 0.12 * steel_grain + 0.04 * edge_rust
    steel_rgb[..., 2] = 0.27 + 0.13 * steel_grain - 0.10 * edge_rust
    steel_rgb[..., 3] = 1.0

    # 5. Stained wet concrete with dark damp skirt & mineral grit
    conc_f = _fbm(u, v, 9.0, 4, 909)
    damp_band = np.clip((0.38 - v) * 2.6, 0.0, 1.0)
    conc_rgb = np.zeros((size, size, 4), dtype=np.float32)
    conc_rgb[..., 0] = (0.36 + 0.14 * conc_f) * (1.0 - 0.35 * damp_band)
    conc_rgb[..., 1] = (0.37 + 0.14 * conc_f) * (1.0 - 0.28 * damp_band)
    conc_rgb[..., 2] = (0.38 + 0.13 * conc_f) * (1.0 - 0.32 * damp_band)
    conc_rgb[..., 3] = 1.0

    # 6. Chipped industrial amber / containment metal
    amber_n = _fbm(u, v, 8.0, 3, 1010)
    chip = np.clip((amber_n - 0.63) * 4.5, 0.0, 1.0)
    amber_rgb = np.zeros((size, size, 4), dtype=np.float32)
    amber_rgb[..., 0] = 0.78 * (1.0 - chip) + 0.25 * chip
    amber_rgb[..., 1] = 0.44 * (1.0 - chip) + 0.22 * chip
    amber_rgb[..., 2] = 0.10 * (1.0 - chip) + 0.22 * chip
    amber_rgb[..., 3] = 1.0

    return {
        "VolcanicBark": _make_image("tex_volcanic_bark", bark_rgb),
        "CanopyFoliage": _make_image("tex_canopy_foliage", canopy_rgb),
        "BasaltStrata": _make_image("tex_basalt_strata", basalt_rgb),
        "RustedSteel": _make_image("tex_rusted_steel", steel_rgb),
        "WeatheredConcrete": _make_image("tex_weathered_concrete", conc_rgb),
        "IndustrialAmber": _make_image("tex_industrial_amber", amber_rgb),
    }


def make_material(
    name: str,
    image: bpy.types.Image,
    roughness: float,
    metallic: float,
    fallback_linear: Tuple[float, float, float],
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*fallback_linear, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    tex_node = nodes.new("ShaderNodeTexImage")
    tex_node.image = image
    tex_node.location = (-360, 260)
    links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# ---------------------------------------------------------------------------
# Watertight BMesh sculpting primitives
# ---------------------------------------------------------------------------

def _apply_box_uv(bm: bmesh.types.BMesh, scale: float = 0.35) -> None:
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


def _add_swept_tube(
    bm: bmesh.types.BMesh,
    points: List[Vector],
    radii: List[float],
    sides: int = 7,
    twist: float = 0.0,
    ridge_amp: float = 0.0,
    seed: int = 1,
) -> None:
    """Appends a closed manifold swept tube along 3D spine points."""
    rng = random.Random(seed)
    rings: List[List[bmesh.types.BMVert]] = []
    n_pts = len(points)
    for i, pt in enumerate(points):
        if i == 0:
            tangent = (points[1] - points[0]).normalized()
        elif i == n_pts - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[i + 1] - points[i - 1]).normalized()
        ref = Vector((0, 1, 0)) if abs(tangent.y) < 0.9 else Vector((1, 0, 0))
        binorm = tangent.cross(ref).normalized()
        norm = binorm.cross(tangent).normalized()

        ring: List[bmesh.types.BMVert] = []
        r_base = radii[i]
        phase = twist * (i / max(1, n_pts - 1))
        for s in range(sides):
            ang = phase + (2.0 * math.pi * s) / sides
            ridge = 1.0 + ridge_amp * (math.sin(ang * 3.0 + i * 0.7) * 0.6 + rng.uniform(-0.35, 0.35))
            r = max(0.03, r_base * ridge)
            offset = (norm * math.cos(ang) + binorm * math.sin(ang)) * r
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    for i in range(n_pts - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        for s in range(sides):
            s_next = (s + 1) % sides
            bm.faces.new((r0[s], r0[s_next], r1[s_next], r1[s]))

    # End caps for strict watertight manifoldness
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def _add_faceted_canopy_tier(
    bm: bmesh.types.BMesh,
    center: Vector,
    rx: float,
    ry: float,
    rz: float,
    yaw: float,
    tilt_x: float,
    seed: int,
) -> None:
    """Appends an angular, layered polygonal foliage cluster (never a sphere)."""
    rng = random.Random(seed)
    res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    rot = Euler((tilt_x, rng.uniform(-0.18, 0.18), yaw), "XYZ").to_matrix()
    for v in res["verts"]:
        p = v.co.copy()
        # Flatten underside, notch edges asymmetrically, keep crisp botanical facets
        if p.z < 0.0:
            p.z *= 0.38
        else:
            p.z *= 0.72
        ang = math.atan2(p.y, p.x)
        lobe = 1.0 + 0.24 * math.sin(ang * 5.0 + seed) + 0.12 * math.cos(ang * 3.0 - seed * 0.5)
        jitter = 1.0 + rng.uniform(-0.08, 0.08)
        scaled = Vector((p.x * rx * lobe * jitter, p.y * ry * lobe * jitter, p.z * rz))
        v.co = center + (rot @ scaled)


def _add_basalt_column(
    bm: bmesh.types.BMesh,
    base_center: Vector,
    height: float,
    r_bottom: float,
    r_top: float,
    lean: Vector,
    sides: int,
    seed: int,
    step_notch: bool = False,
) -> None:
    rng = random.Random(seed)
    pts: List[Vector] = []
    radii: List[float] = []
    segs = 6
    for i in range(segs + 1):
        t = i / segs
        pos = base_center + lean * t + Vector((0, 0, height * t))
        if step_notch and i >= 4:
            # Flat-topped perch shoulder offset cleanly to +X
            pos += Vector((0.15 * height * (t - 0.5), 0.0, 0.0))
        pts.append(pos)
        r = r_bottom * (1.0 - t) + r_top * t
        if step_notch and i == 4:
            r *= 1.12
        radii.append(r * rng.uniform(0.93, 1.07))
    _add_swept_tube(bm, pts, radii, sides=sides, twist=0.18, ridge_amp=0.14, seed=seed)


def _add_box_prism(bm: bmesh.types.BMesh, size: Vector, matrix: Matrix) -> List[bmesh.types.BMVert]:
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    scale_m = Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    xf = matrix @ scale_m
    for v in verts:
        v.co = xf @ v.co
    return verts


def _finalize_object(
    name: str,
    bm: bmesh.types.BMesh,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uv(bm, scale=0.32)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(material)
    collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------
# Kit Builders (Trees, Rocks, Foliage, Ruins)
# ---------------------------------------------------------------------------

def build_trees_kit(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    created: List[bpy.types.Object] = []

    # 1. CanopyTree_Tall (~10.5 m -> ~37.5 studs)
    bm_t = bmesh.new()
    # Main sweeping trunk
    _add_swept_tube(
        bm_t,
        [
            Vector((0.0, 0.0, -0.15)),
            Vector((0.18, 0.08, 1.8)),
            Vector((0.42, -0.12, 4.2)),
            Vector((0.68, -0.25, 6.6)),
            Vector((0.92, -0.15, 8.6)),
        ],
        [0.62, 0.48, 0.39, 0.30, 0.16],
        sides=8,
        twist=0.6,
        ridge_amp=0.18,
        seed=11,
    )
    # 4 buttress roots gripping soil at Z = 0
    for r_i, ang in enumerate([0.2, 1.75, 3.3, 4.9]):
        ca, sa = math.cos(ang), math.sin(ang)
        _add_swept_tube(
            bm_t,
            [
                Vector((ca * 0.32, sa * 0.32, 1.55)),
                Vector((ca * 0.92, sa * 0.92, 0.55)),
                Vector((ca * 1.55, sa * 1.55, -0.12)),
            ],
            [0.24, 0.19, 0.09],
            sides=6,
            ridge_amp=0.15,
            seed=20 + r_i,
        )
    # 3 primary asymmetric upper limbs (+X limb extends noticeably farther for orientation marker)
    _add_swept_tube(
        bm_t,
        [Vector((0.55, -0.18, 5.5)), Vector((1.65, 0.15, 7.2)), Vector((2.55, 0.35, 8.8))],
        [0.24, 0.16, 0.08],
        sides=6,
        ridge_amp=0.12,
        seed=31,
    )
    _add_swept_tube(
        bm_t,
        [Vector((0.62, -0.20, 6.1)), Vector((-0.65, 0.95, 7.9)), Vector((-1.45, 1.55, 9.2))],
        [0.22, 0.14, 0.08],
        sides=6,
        ridge_amp=0.12,
        seed=32,
    )
    _add_swept_tube(
        bm_t,
        [Vector((0.74, -0.18, 6.8)), Vector((0.35, -1.45, 8.3)), Vector((0.05, -2.15, 9.5))],
        [0.20, 0.13, 0.07],
        sides=6,
        ridge_amp=0.12,
        seed=33,
    )
    created.append(_finalize_object("CanopyTree_Tall__Trunk", bm_t, mats["Bark"], col))

    bm_c = bmesh.new()
    canopy_tiers = [
        (Vector((0.95, -0.15, 9.55)), 2.55, 2.25, 1.25, 0.3, 0.05, 41),
        (Vector((2.45, 0.35, 8.95)), 2.15, 1.85, 1.05, 1.1, -0.10, 42),
        (Vector((-1.35, 1.50, 9.35)), 2.05, 1.90, 1.05, 2.2, 0.08, 43),
        (Vector((0.10, -2.05, 9.60)), 1.85, 1.70, 0.95, 3.6, -0.06, 44),
        (Vector((0.40, 0.20, 7.75)), 1.65, 1.45, 0.85, 4.4, 0.12, 45),
    ]
    for c_pos, rx, ry, rz, yaw, tx, sd in canopy_tiers:
        _add_faceted_canopy_tier(bm_c, c_pos, rx, ry, rz, yaw, tx, sd)
    created.append(_finalize_object("CanopyTree_Tall__Canopy", bm_c, mats["Canopy"], col))

    # 2. CanopyTree_Broad (~9.0 m -> ~32 studs)
    bm_t2 = bmesh.new()
    _add_swept_tube(
        bm_t2,
        [Vector((0, 0, -0.15)), Vector((-0.15, 0.1, 1.6)), Vector((-0.35, 0.2, 3.8)), Vector((-0.10, 0.05, 5.8))],
        [0.72, 0.54, 0.44, 0.30],
        sides=8,
        twist=0.5,
        ridge_amp=0.20,
        seed=51,
    )
    for b_idx, tip in enumerate([Vector((2.3, 1.1, 7.6)), Vector((-2.4, -0.6, 7.4)), Vector((0.4, -2.2, 7.9))]):
        _add_swept_tube(
            bm_t2,
            [Vector((-0.15, 0.08, 4.5)), (tip + Vector((-0.15, 0.08, 4.5))) * 0.5 + Vector((0, 0, 0.4)), tip],
            [0.27, 0.18, 0.09],
            sides=6,
            ridge_amp=0.14,
            seed=55 + b_idx,
        )
    for r_i, ang in enumerate([0.6, 2.2, 4.0]):
        ca, sa = math.cos(ang), math.sin(ang)
        _add_swept_tube(
            bm_t2,
            [Vector((ca * 0.36, sa * 0.36, 1.3)), Vector((ca * 1.1, sa * 1.1, 0.45)), Vector((ca * 1.75, sa * 1.75, -0.1))],
            [0.26, 0.18, 0.09],
            sides=6,
            ridge_amp=0.16,
            seed=61 + r_i,
        )
    created.append(_finalize_object("CanopyTree_Broad__Trunk", bm_t2, mats["Bark"], col))

    bm_c2 = bmesh.new()
    for idx, (c_pos, rx, ry, rz) in enumerate([
        (Vector((2.35, 1.10, 7.85)), 2.55, 2.10, 1.15),
        (Vector((-2.35, -0.55, 7.65)), 2.35, 2.05, 1.10),
        (Vector((0.35, -2.15, 8.10)), 2.20, 1.95, 1.15),
        (Vector((-0.10, 0.25, 8.45)), 2.40, 2.15, 1.25),
    ]):
        _add_faceted_canopy_tier(bm_c2, c_pos, rx, ry, rz, idx * 1.3, 0.06, 70 + idx)
    created.append(_finalize_object("CanopyTree_Broad__Canopy", bm_c2, mats["Canopy"], col))

    # 3. MidstoryTree_Crooked (~4.2 m -> ~15 studs, breaks mid-height LOS)
    bm_t3 = bmesh.new()
    _add_swept_tube(
        bm_t3,
        [Vector((0, 0, -0.1)), Vector((0.28, -0.12, 1.0)), Vector((0.55, 0.18, 2.2)), Vector((0.25, 0.32, 3.4))],
        [0.30, 0.22, 0.16, 0.09],
        sides=7,
        ridge_amp=0.16,
        seed=81,
    )
    _add_swept_tube(
        bm_t3,
        [Vector((0.42, 0.05, 1.8)), Vector((-0.65, -0.45, 2.8)), Vector((-1.05, -0.75, 3.6))],
        [0.14, 0.10, 0.06],
        sides=6,
        ridge_amp=0.12,
        seed=82,
    )
    created.append(_finalize_object("MidstoryTree_Crooked__Trunk", bm_t3, mats["Bark"], col))

    bm_c3 = bmesh.new()
    for idx, (c_pos, rx, ry, rz) in enumerate([
        (Vector((0.28, 0.30, 3.65)), 1.55, 1.35, 0.85),
        (Vector((-1.00, -0.70, 3.75)), 1.35, 1.25, 0.78),
        (Vector((0.75, -0.45, 2.65)), 1.20, 1.05, 0.70),
    ]):
        _add_faceted_canopy_tier(bm_c3, c_pos, rx, ry, rz, idx * 1.9, -0.07, 90 + idx)
    created.append(_finalize_object("MidstoryTree_Crooked__Canopy", bm_c3, mats["Canopy"], col))

    return created


def build_rocks_kit(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    created: List[bpy.types.Object] = []

    # 1. BasaltFaultSpire (~12.6 m -> ~45 studs, 28 deg fault line spires + flat perch step on +X)
    bm_r1 = bmesh.new()
    _add_basalt_column(bm_r1, Vector((-0.6, 0.2, -0.3)), 12.6, 2.55, 1.15, Vector((1.4, 0.6, 0.0)), sides=7, seed=201)
    _add_basalt_column(bm_r1, Vector((1.65, -0.35, -0.3)), 8.8, 2.10, 1.45, Vector((0.8, 0.2, 0.0)), sides=6, seed=202, step_notch=True)
    _add_basalt_column(bm_r1, Vector((-2.1, -0.7, -0.3)), 6.2, 1.85, 1.10, Vector((0.5, -0.3, 0.0)), sides=6, seed=203)
    created.append(_finalize_object("BasaltFaultSpire__Rock", bm_r1, mats["Basalt"], col))

    # 2. VolcanicCliffSlab (~7.8 m -> ~28 studs, fractured stepped outcrop)
    bm_r2 = bmesh.new()
    _add_basalt_column(bm_r2, Vector((0.0, 0.0, -0.25)), 7.8, 3.4, 2.4, Vector((1.8, -0.7, 0.0)), sides=7, seed=211)
    _add_basalt_column(bm_r2, Vector((2.1, 0.8, -0.25)), 5.0, 2.4, 1.9, Vector((0.9, -0.4, 0.0)), sides=6, seed=212)
    created.append(_finalize_object("VolcanicCliffSlab__Rock", bm_r2, mats["Basalt"], col))

    # 3. CalderaBoulderGroup (~2.6 m -> ~9.3 studs)
    bm_r3 = bmesh.new()
    boulders = [
        (Vector((-0.9, 0.2, 0.85)), 1.55, 1.25, 1.35, 0.4, 221),
        (Vector((1.05, -0.35, 0.55)), 1.10, 0.95, 0.85, 1.6, 222),
        (Vector((0.25, 1.10, 0.45)), 0.88, 0.78, 0.70, 2.8, 223),
    ]
    for pos, rx, ry, rz, yaw, sd in boulders:
        rng = random.Random(sd)
        res = bmesh.ops.create_icosphere(bm_r3, subdivisions=2, radius=1.0)
        rot = Euler((0.12, -0.08, yaw), "XYZ").to_matrix()
        for v in res["verts"]:
            p = v.co.copy()
            fac = 1.0 + 0.20 * math.sin(p.x * 3.1 + p.z * 2.7 + sd) + rng.uniform(-0.08, 0.08)
            p.x *= rx * fac
            p.y *= ry * fac
            p.z = max(-pos.z + 0.02, p.z * rz * fac)
            v.co = pos + (rot @ p)
    created.append(_finalize_object("CalderaBoulderGroup__Rock", bm_r3, mats["Basalt"], col))

    return created


def build_foliage_kit(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    created: List[bpy.types.Object] = []

    # 1. ButtressRootArch (~2.4 m -> ~8.5 studs)
    bm_f1 = bmesh.new()
    _add_swept_tube(
        bm_f1,
        [
            Vector((-2.6, -0.2, -0.15)),
            Vector((-1.5, 0.2, 1.45)),
            Vector((0.0, 0.35, 2.35)),
            Vector((1.4, -0.1, 1.55)),
            Vector((2.4, -0.35, -0.15)),
        ],
        [0.42, 0.36, 0.30, 0.32, 0.44],
        sides=7,
        twist=0.8,
        ridge_amp=0.18,
        seed=301,
    )
    created.append(_finalize_object("ButtressRootArch__Root", bm_f1, mats["Bark"], col))

    # 2. VolcanicFernCluster (~1.1 m -> ~4 studs, thick volumetric 3D fronds)
    bm_f2 = bmesh.new()
    for f_i in range(7):
        ang = (2.0 * math.pi * f_i) / 7.0 + (f_i % 2) * 0.22
        ca, sa = math.cos(ang), math.sin(ang)
        len_m = 1.25 + (f_i % 3) * 0.22
        h_m = 0.85 + (f_i % 2) * 0.22
        pts = [
            Vector((ca * 0.08, sa * 0.08, 0.02)),
            Vector((ca * len_m * 0.45, sa * len_m * 0.45, h_m)),
            Vector((ca * len_m * 0.85, sa * len_m * 0.85, h_m * 0.72)),
            Vector((ca * len_m * 1.15, sa * len_m * 1.15, h_m * 0.25)),
        ]
        # Asymmetric wider blade cross-section flattened vertically
        rings: List[List[bmesh.types.BMVert]] = []
        widths = [0.08, 0.28, 0.22, 0.05]
        thicks = [0.05, 0.04, 0.03, 0.02]
        for s_idx, pt in enumerate(pts):
            t_vec = (pts[min(s_idx + 1, 3)] - pts[max(s_idx - 1, 0)]).normalized()
            side_v = Vector((-sa, ca, 0.0)).normalized()
            up_v = side_v.cross(t_vec).normalized()
            w = widths[s_idx]
            th = thicks[s_idx]
            rings.append([
                bm_f2.verts.new(pt + side_v * w),
                bm_f2.verts.new(pt + up_v * th),
                bm_f2.verts.new(pt - side_v * w),
                bm_f2.verts.new(pt - up_v * th),
            ])
        for s_idx in range(len(rings) - 1):
            r0, r1 = rings[s_idx], rings[s_idx + 1]
            for k in range(4):
                k2 = (k + 1) % 4
                bm_f2.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
        bm_f2.faces.new(list(reversed(rings[0])))
        bm_f2.faces.new(rings[-1])
    created.append(_finalize_object("VolcanicFernCluster__Foliage", bm_f2, mats["Canopy"], col))

    # 3. FallenHollowLog (~3.4 m long, ~1.25 m high)
    bm_f3 = bmesh.new()
    _add_swept_tube(
        bm_f3,
        [
            Vector((-1.7, 0.0, 0.58)),
            Vector((-0.6, 0.12, 0.52)),
            Vector((0.6, -0.05, 0.46)),
            Vector((1.7, -0.15, 0.36)),
        ],
        [0.58, 0.46, 0.38, 0.28],
        sides=8,
        twist=0.35,
        ridge_amp=0.16,
        seed=321,
    )
    created.append(_finalize_object("FallenHollowLog__Log", bm_f3, mats["Bark"], col))

    return created


def build_ruins_kit(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> List[bpy.types.Object]:
    created: List[bpy.types.Object] = []

    # 1. AdutoraPipeSaddle (~4.8 m tall -> ~17 studs)
    bm_u1c = bmesh.new()
    _add_box_prism(bm_u1c, Vector((2.6, 2.2, 0.6)), Matrix.Translation((0.0, 0.0, 0.3)))
    _add_box_prism(bm_u1c, Vector((1.6, 1.5, 2.2)), Matrix.Translation((0.0, 0.0, 1.7)))
    created.append(_finalize_object("AdutoraPipeSaddle__Concrete", bm_u1c, mats["Concrete"], col))

    bm_u1p = bmesh.new()
    # Heavy adutora conduit + bolted end flanges
    _add_swept_tube(
        bm_u1p,
        [Vector((-2.2, 0.0, 3.6)), Vector((0.0, 0.0, 3.6)), Vector((2.2, 0.0, 3.6))],
        [0.95, 0.95, 0.95],
        sides=12,
        seed=401,
    )
    for fx in (-2.05, 0.0, 2.05):
        _add_swept_tube(
            bm_u1p,
            [Vector((fx - 0.14, 0.0, 3.6)), Vector((fx + 0.14, 0.0, 3.6))],
            [1.18, 1.18],
            sides=12,
            seed=402,
        )
    created.append(_finalize_object("AdutoraPipeSaddle__Pipe", bm_u1p, mats["Steel"], col))

    # 2. BrokenBlastBarrier (~2.5 m tall -> ~9 studs, asymmetric shear on -X)
    bm_u2c = bmesh.new()
    _add_box_prism(bm_u2c, Vector((3.6, 1.4, 0.55)), Matrix.Translation((0.0, 0.0, 0.275)))
    _add_box_prism(
        bm_u2c,
        Vector((2.6, 0.72, 1.95)),
        Matrix.Translation((0.45, 0.0, 1.45)) * Matrix.Rotation(math.radians(-6), 4, "Y"),
    )
    created.append(_finalize_object("BrokenBlastBarrier__Concrete", bm_u2c, mats["Concrete"], col))

    bm_u2r = bmesh.new()
    for rz in (1.1, 1.65, 2.15):
        _add_swept_tube(
            bm_u2r,
            [Vector((-0.85, -0.1, rz)), Vector((-1.45, 0.12, rz + 0.12))],
            [0.06, 0.05],
            sides=6,
            seed=411,
        )
    created.append(_finalize_object("BrokenBlastBarrier__Rebar", bm_u2r, mats["Steel"], col))

    # 3. AbandonedSurveyRig (~2.8 m tall -> ~10 studs)
    bm_u3h = bmesh.new()
    _add_box_prism(bm_u3h, Vector((2.1, 1.6, 0.35)), Matrix.Translation((0.0, 0.0, 0.175)))
    _add_box_prism(bm_u3h, Vector((1.35, 1.05, 1.45)), Matrix.Translation((-0.15, 0.0, 1.05)))
    _add_box_prism(bm_u3h, Vector((0.65, 0.85, 0.85)), Matrix.Translation((0.65, 0.15, 0.75)))
    created.append(_finalize_object("AbandonedSurveyRig__Housing", bm_u3h, mats["Amber"], col))

    bm_u3a = bmesh.new()
    _add_swept_tube(
        bm_u3a,
        [Vector((0.65, 0.15, 1.15)), Vector((0.78, 0.22, 2.10)), Vector((0.92, 0.30, 2.80))],
        [0.08, 0.055, 0.035],
        sides=6,
        seed=421,
    )
    created.append(_finalize_object("AbandonedSurveyRig__Antenna", bm_u3a, mats["Steel"], col))

    return created


def _world_extents_m(objs: List[bpy.types.Object]) -> Tuple[Vector, Vector]:
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            mn.x = min(mn.x, wc.x)
            mn.y = min(mn.y, wc.y)
            mn.z = min(mn.z, wc.z)
            mx.x = max(mx.x, wc.x)
            mx.y = max(mx.y, wc.y)
            mx.z = max(mx.z, wc.z)
    return mn, mx


def export_kit(
    kit_name: str,
    category: str,
    objs: List[bpy.types.Object],
    asymmetric_features: List[str],
) -> dict:
    # Center each model group's X/Y independently? No—keep every logical model centered near X=0,Y=0
    # by packing models side-by-side along +X inside the kit GLB, OR keep all at origin so we separate them in Studio!
    # Packing side-by-side by +8m along X makes preview in Blender super clean AND separation in Studio effortless!
    groups: Dict[str, List[bpy.types.Object]] = {}
    for o in objs:
        model_key = o.name.split("__")[0]
        groups.setdefault(model_key, []).append(o)

    model_entries = []
    offset_x = 0.0
    for model_key, parts in groups.items():
        for p in parts:
            p.location.x += offset_x
        bpy.context.view_layer.update()
        mn, mx = _world_extents_m(parts)
        dims = mx - mn
        tris = sum(sum(len(poly.vertices) - 2 for poly in p.data.polygons) for p in parts)
        part_names = [p.name for p in parts]
        model_entries.append(
            {
                "modelName": model_key,
                "category": category,
                "parts": part_names,
                "triangles": tris,
                "dimensionsMeters": [round(dims.x, 3), round(dims.y, 3), round(dims.z, 3)],
                "expectedHeightStuds": round(dims.z / 0.28, 3),
            }
        )
        offset_x += max(6.0, dims.x + 3.0)

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

    glb_path = ROOT_DIR / f"{kit_name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_image_format="AUTO",
    )

    return {
        "kitName": kit_name,
        "category": category,
        "glbPath": str(glb_path),
        "meshCount": len(objs),
        "asymmetricFeatures": asymmetric_features,
        "models": model_entries,
    }


def main() -> None:
    clear_scene()
    textures = build_textures()
    mats = {
        "Bark": make_material("Mat_VolcanicBark", textures["VolcanicBark"], 0.88, 0.0, (0.19, 0.13, 0.10)),
        "Canopy": make_material("Mat_CanopyFoliage", textures["CanopyFoliage"], 0.72, 0.0, (0.14, 0.34, 0.19)),
        "Basalt": make_material("Mat_BasaltStrata", textures["BasaltStrata"], 0.78, 0.05, (0.21, 0.22, 0.25)),
        "Steel": make_material("Mat_RustedSteel", textures["RustedSteel"], 0.62, 0.65, (0.28, 0.31, 0.36)),
        "Concrete": make_material("Mat_WeatheredConcrete", textures["WeatheredConcrete"], 0.90, 0.0, (0.38, 0.39, 0.40)),
        "Amber": make_material("Mat_IndustrialAmber", textures["IndustrialAmber"], 0.55, 0.45, (0.76, 0.43, 0.12)),
    }

    manifest = {"project": "PRIMAL HUNT", "kits": []}

    specs = [
        (
            "PrimalHunt_TreesKit",
            "Trees",
            build_trees_kit,
            ["Tall tree leans toward +X with longer primary limb on +X", "Broad tree root flare asymmetric toward +X/+Y"],
        ),
        (
            "PrimalHunt_RocksKit",
            "Rocks",
            build_rocks_kit,
            ["BasaltFaultSpire stepped perch shoulder sits on +X side", "VolcanicCliffSlab leans toward +X/-Y fault plane"],
        ),
        (
            "PrimalHunt_FoliageKit",
            "Foliage",
            build_foliage_kit,
            ["FallenHollowLog wider root flare at -X and tapered splinter at +X", "ButtressRootArch arches slightly toward +Y"],
        ),
        (
            "PrimalHunt_RuinsKit",
            "Ruins",
            build_ruins_kit,
            ["BrokenBlastBarrier sheared wall missing on -X exposing bent rebar", "AbandonedSurveyRig antenna mast sits on +X"],
        ),
    ]

    scene_col = bpy.context.scene.collection
    for kit_name, category, builder_fn, asym in specs:
        col = bpy.data.collections.new(kit_name)
        scene_col.children.link(col)
        objs = builder_fn(col, mats)
        # Shift entire collection visually along Y by category index in .blend
        cat_idx = len(manifest["kits"])
        for o in objs:
            o.location.y += cat_idx * 10.0
        manifest["kits"].append(export_kit(kit_name, category, objs, asym))

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("PRIMAL_HUNT_ASSETS_BUILT_OK")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
