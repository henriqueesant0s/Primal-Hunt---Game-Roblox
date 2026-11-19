"""Primal Hunt v5 — 5 Morphologically Diverse Articulated 3D Fauna Species.

Strict non-overwrite policy: writes only new *_v5 artifacts.
Builds at X = 0, 22, 44, 66, 88 (every foot strictly planted at Blender Z = 0.0 -> Roblox Y = 0.0):
1. SwampStalkerRaptor (Raptor3D at X=0)   — bipedal digitigrade hunter + tucked sickle fore-claws + whip tail
2. ThornbackBoar      (Boar3D at X=22)    — stocky armored war-boar + dorsal quill spines + upturned tusks
3. BiolumMantisStalker(Mantis3D at X=44)  — insectoid mantis ambush stalker + raised scythe forelimbs + compound eyes
4. MireCrocoSnapper   (Croc3D at X=66)    — low-slung swamp crocodilian + osteoderm scutes + snapping jaws
5. HornedCeratopsBull (Ceratops3D at X=88)— massive tri-horned frilled behemoth + club tail + pillar legs

Exports PrimalHunt_DiverseFaunaPack_v5.glb, diverse_fauna_v5_manifest.json, previews/diverse_fauna_pack_v5.png.
"""

from __future__ import annotations

import json
import math
import os
from typing import Dict, List, Sequence, Tuple

import bmesh
import bpy
from mathutils import Vector

ROOT = r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt"
OUT_GLB = os.path.join(ROOT, "PrimalHunt_DiverseFaunaPack_v5.glb")
OUT_MANIFEST = os.path.join(ROOT, "diverse_fauna_v5_manifest.json")
OUT_PREVIEW = os.path.join(ROOT, "previews", "diverse_fauna_pack_v5.png")


def assert_no_overwrites() -> None:
    for p in (OUT_GLB, OUT_MANIFEST, OUT_PREVIEW):
        if os.path.exists(p):
            raise RuntimeError(f"Refusing to overwrite existing output: {p}")


def blender_to_roblox_pos(pt: Vector) -> List[float]:
    return [round(-pt.x, 4), round(pt.z, 4), round(pt.y, 4)]


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name: str, rgba: Tuple[float, ...], metallic: float = 0.0, roughness: float = 0.65, emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        r, g, b = rgba[0], rgba[1], rgba[2]
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = (r, g, b, 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def create_mesh_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, col: bpy.types.Collection) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.data.materials.append(mat)
    col.objects.link(obj)
    return obj


def add_origin_marker(col: bpy.types.Collection) -> None:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.05)
    create_mesh_obj("ORIGIN_MARKER", bm, make_mat("Mat_OriginMarker", (0.2, 0.2, 0.2)), col)


def frame_on_tangent(tangent: Vector) -> Tuple[Vector, Vector]:
    t = tangent.normalized()
    up_ref = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.92 else Vector((1.0, 0.0, 0.0))
    right = t.cross(up_ref).normalized()
    up = right.cross(t).normalized()
    return right, up


def add_closed_loft(
    bm: bmesh.types.BMesh,
    pts: Sequence[Vector],
    radii: Sequence[Tuple[float, float]],
    segs: int = 8,
    cap_start: bool = True,
    cap_end: bool = True,
) -> None:
    if len(pts) < 2:
        return
    rings: List[List[bmesh.types.BMVert]] = []
    for i, p in enumerate(pts):
        if i == 0:
            tan = pts[1] - pts[0]
        elif i == len(pts) - 1:
            tan = pts[-1] - pts[-2]
        else:
            tan = pts[i + 1] - pts[i - 1]
        if tan.length < 1e-6:
            tan = Vector((0.0, -1.0, 0.0))
        rx, ry = frame_on_tangent(tan)
        rad_x, rad_y = radii[i]
        ring: List[bmesh.types.BMVert] = []
        for s in range(segs):
            ang = 2.0 * math.pi * s / segs
            ring.append(bm.verts.new(p + rx * (math.cos(ang) * rad_x) + ry * (math.sin(ang) * rad_y)))
        rings.append(ring)

    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(segs):
            sn = (s + 1) % segs
            try:
                bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
            except ValueError:
                pass
    if cap_start and len(rings[0]) >= 3:
        try:
            bm.faces.new(list(reversed(rings[0])))
        except ValueError:
            pass
    if cap_end and len(rings[-1]) >= 3:
        try:
            bm.faces.new(rings[-1])
        except ValueError:
            pass


def add_curved_claw(
    bm: bmesh.types.BMesh,
    base: Vector,
    fwd: Vector,
    up: Vector,
    length: float,
    rx: float,
    ry: float,
    drop: float,
    steps: int = 5,
    segs: int = 6,
) -> None:
    f = fwd.normalized()
    u = up.normalized()
    pts: List[Vector] = []
    rads: List[Tuple[float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        arc = math.sin(t * math.pi * 0.72) * (length * 0.14) - (t * t) * drop
        pts.append(base + f * (t * length) + u * arc)
        taper = max(0.03, (1.0 - t) ** 0.85)
        rads.append((rx * taper, ry * taper))
    add_closed_loft(bm, pts, rads, segs=segs, cap_start=True, cap_end=True)


def add_leg_chain(
    bm_hide: bmesh.types.BMesh,
    bm_armor: bmesh.types.BMesh,
    pts: Sequence[Vector],
    rads: Sequence[float],
    claw_dir: Vector = Vector((0.0, -1.0, -0.05)),
) -> None:
    add_closed_loft(bm_hide, pts, [(r, r * 0.92) for r in rads], segs=7)
    # Foot armor cap & 2 toes planted cleanly near Z = 0
    foot = pts[-1]
    side = 1.0 if foot.x >= 0 else -1.0
    if len(pts) >= 3:
        add_closed_loft(
            bm_armor,
            [pts[0] + Vector((side * rads[0] * 0.3, 0, rads[0] * 0.2)), pts[1] + Vector((side * rads[1] * 0.4, -rads[1] * 0.2, 0))],
            [(rads[0] * 0.55, rads[0] * 0.42), (rads[1] * 0.62, rads[1] * 0.44)],
            segs=6,
        )
    for sx in (-0.28, 0.28):
        td = (claw_dir + Vector((sx * 0.4, 0, 0))).normalized()
        add_curved_claw(bm_armor, foot + Vector((0, 0, rads[-1] * 0.35)), td, Vector((0, 0, 1)), rads[-1] * 1.9, rads[-1] * 0.32, rads[-1] * 0.28, rads[-1] * 0.25)


def finalize_species(
    species: str,
    prefix: str,
    col: bpy.types.Collection,
    off: Vector,
    trunk_z: float,
    pivots: Dict[str, Vector],
    parts: List[Tuple[str, bmesh.types.BMesh, bpy.types.Material]],
) -> dict:
    meshes: List[str] = []
    for suffix, bm, mat in parts:
        if len(bm.faces) > 0:
            nm = f"{prefix}_{suffix}"
            create_mesh_obj(nm, bm, mat, col)
            meshes.append(nm)
        else:
            bm.free()

    return {
        "species": species,
        "prefix": prefix,
        "offsetRoblox": blender_to_roblox_pos(off),
        "trunkPos": [0.0, round(trunk_z, 4), 0.0],
        "pivots": {k: blender_to_roblox_pos(v) for k, v in pivots.items()},
        "meshes": meshes,
    }


def build_swamp_stalker_raptor(col: bpy.types.Collection, offset_x: float) -> dict:
    """Species 1: Bipedal Jungle Raptor (feet at Z=0, torso Z=2.1, sickle fore-claws & whip tail)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat("Mat_Raptor_Hide", (0.14, 0.26, 0.19), roughness=0.68)
    m_armor = make_mat("Mat_Raptor_Armor", (0.09, 0.14, 0.11), metallic=0.12, roughness=0.46)
    m_glow = make_mat("Mat_Raptor_Glow", (1.0, 0.72, 0.16), roughness=0.20, emission=2.4)

    bm_bh, bm_ba, bm_bg = bmesh.new(), bmesh.new(), bmesh.new()
    bm_ha, bm_hg = bmesh.new(), bmesh.new()
    bm_th, bm_ta = bmesh.new(), bmesh.new()
    limbs = {k: (bmesh.new(), bmesh.new()) for k in ("LegFL", "LegFR", "LegBL", "LegBR")}

    # Sleek forward-canting theropod body
    add_closed_loft(
        bm_bh,
        [off + Vector((0, 1.35, 1.85)), off + Vector((0, 0.35, 2.08)), off + Vector((0, -0.65, 2.28)), off + Vector((0, -1.35, 2.52))],
        [(0.52, 0.56), (0.76, 0.82), (0.68, 0.75), (0.45, 0.52)],
        segs=8,
    )
    # Feather/quill crest along spine & bioluminescent flank stripes
    for qi in range(5):
        add_curved_claw(bm_ba, off + Vector((0, 0.9 - qi * 0.48, 2.58 + qi * 0.12)), Vector((0, 0.75, 0.65)), Vector((0, -0.5, 0.85)), 0.75, 0.09, 0.14, 0.12)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_bg, [off + Vector((sx * 0.68, 0.55, 2.08)), off + Vector((sx * 0.62, -0.85, 2.34))], [(0.08, 0.10), (0.07, 0.08)], segs=5)

    head_p = Vector((0.0, -1.55, 2.85))
    add_closed_loft(bm_ha, [off + head_p, off + head_p + Vector((0, -0.75, 0.12)), off + head_p + Vector((0, -1.55, -0.04))], [(0.42, 0.44), (0.34, 0.35), (0.14, 0.14)], segs=7)
    # Razor crest horns & glowing amber eyes
    add_curved_claw(bm_ha, off + head_p + Vector((0, -0.35, 0.38)), Vector((0, 0.75, 0.65)), Vector((0, -0.4, 0.9)), 0.95, 0.08, 0.15, 0.10)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_hg, [off + head_p + Vector((sx * 0.28, -0.62, 0.18)), off + head_p + Vector((sx * 0.24, -0.82, 0.16))], [(0.08, 0.07), (0.04, 0.04)], segs=6)

    tail_p = Vector((0.0, 1.45, 1.88))
    add_closed_loft(bm_th, [off + tail_p, off + tail_p + Vector((0, 1.45, 0.12)), off + tail_p + Vector((0, 3.05, 0.34))], [(0.44, 0.46), (0.24, 0.25), (0.08, 0.08)], segs=7)
    add_curved_claw(bm_ta, off + tail_p + Vector((0, 2.75, 0.34)), Vector((0, 0.92, 0.35)), Vector((0, 0, 1)), 0.92, 0.10, 0.18, 0.08)

    # Tucked raptorial forelimbs (LegFL, LegFR) & powerful digitigrade hind legs at Z = 0.05
    for k, sx in (("LegFL", 1.0), ("LegFR", -1.0)):
        add_leg_chain(limbs[k][0], limbs[k][1], [off + Vector((sx * 0.56, -0.95, 2.15)), off + Vector((sx * 0.68, -1.35, 1.72)), off + Vector((sx * 0.62, -1.78, 1.55))], [0.16, 0.12, 0.09], claw_dir=Vector((0, -0.85, -0.52)))
    for k, sx in (("LegBL", 1.0), ("LegBR", -1.0)):
        add_leg_chain(limbs[k][0], limbs[k][1], [off + Vector((sx * 0.55, 0.38, 1.88)), off + Vector((sx * 0.64, -0.05, 1.08)), off + Vector((sx * 0.58, 0.52, 0.48)), off + Vector((sx * 0.62, 0.18, 0.06))], [0.32, 0.22, 0.16, 0.20])

    return finalize_species(
        "SwampStalkerRaptor", "Raptor3D", col, off, 2.10,
        {
            "Head": head_p, "Tail": tail_p,
            "LegFL": Vector((0.56, -0.95, 2.15)), "LegFR": Vector((-0.56, -0.95, 2.15)),
            "LegBL": Vector((0.55, 0.38, 1.88)), "LegBR": Vector((-0.55, 0.38, 1.88)),
        },
        [
            ("Body_Hide", bm_bh, m_hide), ("Body_Armor", bm_ba, m_armor), ("Body_Glow", bm_bg, m_glow),
            ("Head_Armor", bm_ha, m_armor), ("Head_Glow", bm_hg, m_glow),
            ("Tail_Hide", bm_th, m_hide), ("Tail_Armor", bm_ta, m_armor),
            ("LegFL_Hide", limbs["LegFL"][0], m_hide), ("LegFL_Armor", limbs["LegFL"][1], m_armor),
            ("LegFR_Hide", limbs["LegFR"][0], m_hide), ("LegFR_Armor", limbs["LegFR"][1], m_armor),
            ("LegBL_Hide", limbs["LegBL"][0], m_hide), ("LegBL_Armor", limbs["LegBL"][1], m_armor),
            ("LegBR_Hide", limbs["LegBR"][0], m_hide), ("LegBR_Armor", limbs["LegBR"][1], m_armor),
        ],
    )


def build_thornback_boar(col: bpy.types.Collection, offset_x: float) -> dict:
    """Species 2: Armored Thornback Razor-Boar with upturned war-tusks & dorsal quills (feet at Z=0)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat("Mat_Boar_Hide", (0.28, 0.16, 0.12), roughness=0.78)
    m_armor = make_mat("Mat_Boar_Armor", (0.82, 0.75, 0.62), roughness=0.45)  # ivory/obsidian contrast
    m_glow = make_mat("Mat_Boar_Glow", (1.0, 0.42, 0.10), roughness=0.22, emission=2.2)

    bm_bh, bm_ba, bm_bg = bmesh.new(), bmesh.new(), bmesh.new()
    bm_ha, bm_hg = bmesh.new(), bmesh.new()
    bm_th, bm_ta = bmesh.new(), bmesh.new()
    limbs = {k: (bmesh.new(), bmesh.new()) for k in ("LegFL", "LegFR", "LegBL", "LegBR")}

    add_closed_loft(
        bm_bh,
        [off + Vector((0, 1.42, 1.48)), off + Vector((0, 0.35, 1.68)), off + Vector((0, -0.75, 1.82)), off + Vector((0, -1.45, 1.72))],
        [(0.78, 0.72), (1.05, 0.96), (1.16, 1.05), (0.92, 0.86)],
        segs=8,
    )
    # Bristling dorsal quill rack & shoulder hump armor
    for qi in range(7):
        add_curved_claw(bm_ba, off + Vector((0, 1.05 - qi * 0.36, 2.38 + (qi % 2) * 0.08)), Vector((0, 0.48, 0.88)), Vector((0, -0.8, 0.5)), 0.95 + (1 if qi >= 4 else 0) * 0.3, 0.11, 0.09, 0.15)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_bg, [off + Vector((sx * 0.88, -0.2, 1.82)), off + Vector((sx * 0.92, -0.95, 1.75))], [(0.11, 0.10), (0.08, 0.08)], segs=5)

    head_p = Vector((0.0, -1.62, 1.65))
    add_closed_loft(bm_bh, [off + head_p, off + head_p + Vector((0, -0.75, -0.06)), off + head_p + Vector((0, -1.28, -0.18))], [(0.86, 0.78), (0.64, 0.56), (0.34, 0.30)], segs=7)
    for sx in (-1.0, 1.0):
        add_curved_claw(bm_ha, off + head_p + Vector((sx * 0.42, -0.82, -0.15)), Vector((sx * 0.45, -0.58, 0.68)), Vector((0, -0.3, 0.95)), 1.15, 0.14, 0.12, -0.22)
        add_closed_loft(bm_hg, [off + head_p + Vector((sx * 0.44, -0.58, 0.25)), off + head_p + Vector((sx * 0.38, -0.75, 0.22))], [(0.09, 0.08), (0.05, 0.05)], segs=5)

    tail_p = Vector((0.0, 1.50, 1.48))
    add_closed_loft(bm_th, [off + tail_p, off + tail_p + Vector((0, 0.72, 0.15)), off + tail_p + Vector((0, 1.18, 0.48))], [(0.22, 0.20), (0.14, 0.12), (0.18, 0.18)], segs=6)

    for k, sx, y_off in (("LegFL", 1.0, -1.05), ("LegFR", -1.0, -1.05), ("LegBL", 1.0, 1.02), ("LegBR", -1.0, 1.02)):
        add_leg_chain(limbs[k][0], limbs[k][1], [off + Vector((sx * 0.78, y_off, 1.25)), off + Vector((sx * 0.84, y_off - 0.1, 0.65)), off + Vector((sx * 0.80, y_off, 0.05))], [0.32, 0.24, 0.22])

    return finalize_species(
        "ThornbackBoar", "Boar3D", col, off, 1.65,
        {
            "Head": head_p, "Tail": tail_p,
            "LegFL": Vector((0.78, -1.05, 1.25)), "LegFR": Vector((-0.78, -1.05, 1.25)),
            "LegBL": Vector((0.78, 1.02, 1.25)), "LegBR": Vector((-0.78, 1.02, 1.25)),
        },
        [
            ("Body_Hide", bm_bh, m_hide), ("Body_Armor", bm_ba, m_armor), ("Body_Glow", bm_bg, m_glow),
            ("Head_Armor", bm_ha, m_armor), ("Head_Glow", bm_hg, m_glow),
            ("Tail_Hide", bm_th, m_hide), ("Tail_Armor", bm_ta, m_armor),
            ("LegFL_Hide", limbs["LegFL"][0], m_hide), ("LegFL_Armor", limbs["LegFL"][1], m_armor),
            ("LegFR_Hide", limbs["LegFR"][0], m_hide), ("LegFR_Armor", limbs["LegFR"][1], m_armor),
            ("LegBL_Hide", limbs["LegBL"][0], m_hide), ("LegBL_Armor", limbs["LegBL"][1], m_armor),
            ("LegBR_Hide", limbs["LegBR"][0], m_hide), ("LegBR_Armor", limbs["LegBR"][1], m_armor),
        ],
    )


def build_biolum_mantis_stalker(col: bpy.types.Collection, offset_x: float) -> dict:
    """Species 3: Towering Bioluminescent Mantis Predator with huge scythe forelimbs & compound eyes."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat("Mat_Mantis_Hide", (0.10, 0.24, 0.22), roughness=0.52)
    m_armor = make_mat("Mat_Mantis_Armor", (0.14, 0.12, 0.18), metallic=0.25, roughness=0.38)
    m_glow = make_mat("Mat_Mantis_Glow", (0.24, 1.0, 0.64), roughness=0.18, emission=2.6)

    bm_bh, bm_ba, bm_bg = bmesh.new(), bmesh.new(), bmesh.new()
    bm_ha, bm_hg = bmesh.new(), bmesh.new()
    bm_th, bm_ta = bmesh.new(), bmesh.new()
    limbs = {k: (bmesh.new(), bmesh.new()) for k in ("LegFL", "LegFR", "LegBL", "LegBR")}

    # Narrow upright insectoid thorax
    add_closed_loft(
        bm_bh,
        [off + Vector((0, 0.65, 1.85)), off + Vector((0, 0.0, 2.35)), off + Vector((0, -0.55, 2.95)), off + Vector((0, -0.85, 3.55))],
        [(0.48, 0.42), (0.62, 0.54), (0.52, 0.48), (0.36, 0.34)],
        segs=7,
    )
    # Winged translucent carapace shields on back + glowing thorax core
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_ba, [off + Vector((sx * 0.22, -0.25, 2.95)), off + Vector((sx * 0.72, 0.65, 2.45)), off + Vector((sx * 0.55, 1.45, 1.95))], [(0.24, 0.12), (0.58, 0.16), (0.28, 0.10)], segs=6)
    add_closed_loft(bm_bg, [off + Vector((0, -0.35, 2.45)), off + Vector((0, -0.78, 3.15))], [(0.24, 0.22), (0.18, 0.16)], segs=6)

    head_p = Vector((0.0, -0.95, 3.75))
    add_closed_loft(bm_ha, [off + head_p, off + head_p + Vector((0, -0.55, 0.08))], [(0.68, 0.44), (0.24, 0.32)], segs=6)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_hg, [off + head_p + Vector((sx * 0.52, -0.28, 0.18)), off + head_p + Vector((sx * 0.64, -0.38, 0.24))], [(0.16, 0.16), (0.08, 0.08)], segs=6)
        add_curved_claw(bm_ha, off + head_p + Vector((sx * 0.18, -0.15, 0.42)), Vector((sx * 0.45, 0.35, 0.82)), Vector((0, -1, 0)), 1.05, 0.04, 0.04, 0.10)

    tail_p = Vector((0.0, 0.82, 1.82))
    add_closed_loft(bm_th, [off + tail_p, off + tail_p + Vector((0, 1.15, 0.42)), off + tail_p + Vector((0, 2.25, 0.85))], [(0.75, 0.58), (0.95, 0.72), (0.28, 0.24)], segs=7)
    add_closed_loft(bm_bg, [off + tail_p + Vector((0, 1.4, 0.62)), off + tail_p + Vector((0, 2.0, 0.85))], [(0.36, 0.28), (0.16, 0.14)], segs=6)

    # Raised serrated Raptorial Scythe-Arms (LegFL, LegFR) & Wide-Stance Walking Legs (LegBL, LegBR planted Z=0)
    for k, sx in (("LegFL", 1.0), ("LegFR", -1.0)):
        arm_base = off + Vector((sx * 0.52, -0.68, 3.10))
        elbow = off + Vector((sx * 1.15, -1.65, 2.65))
        wrist = off + Vector((sx * 0.95, -2.05, 1.65))
        add_closed_loft(limbs[k][0], [arm_base, elbow, wrist], [(0.22, 0.20), (0.26, 0.22), (0.14, 0.12)], segs=6)
        add_curved_claw(limbs[k][1], wrist, Vector((0, -0.75, -0.65)), Vector((0, -1, 0)), 1.45, 0.14, 0.07, 0.35)
    for k, sx in (("LegBL", 1.0), ("LegBR", -1.0)):
        hip = off + Vector((sx * 0.55, 0.25, 1.85))
        knee = off + Vector((sx * 1.65, 0.55, 2.35))
        ankle = off + Vector((sx * 1.85, 0.65, 0.95))
        foot = off + Vector((sx * 1.55, 0.45, 0.04))
        add_leg_chain(limbs[k][0], limbs[k][1], [hip, knee, ankle, foot], [0.22, 0.18, 0.14, 0.15])

    return finalize_species(
        "BiolumMantisStalker", "Mantis3D", col, off, 2.30,
        {
            "Head": head_p, "Tail": tail_p,
            "LegFL": Vector((0.52, -0.68, 3.10)), "LegFR": Vector((-0.52, -0.68, 3.10)),
            "LegBL": Vector((0.55, 0.25, 1.85)), "LegBR": Vector((-0.55, 0.25, 1.85)),
        },
        [
            ("Body_Hide", bm_bh, m_hide), ("Body_Armor", bm_ba, m_armor), ("Body_Glow", bm_bg, m_glow),
            ("Head_Armor", bm_ha, m_armor), ("Head_Glow", bm_hg, m_glow),
            ("Tail_Hide", bm_th, m_hide), ("Tail_Armor", bm_ta, m_armor),
            ("LegFL_Hide", limbs["LegFL"][0], m_hide), ("LegFL_Armor", limbs["LegFL"][1], m_armor),
            ("LegFR_Hide", limbs["LegFR"][0], m_hide), ("LegFR_Armor", limbs["LegFR"][1], m_armor),
            ("LegBL_Hide", limbs["LegBL"][0], m_hide), ("LegBL_Armor", limbs["LegBL"][1], m_armor),
            ("LegBR_Hide", limbs["LegBR"][0], m_hide), ("LegBR_Armor", limbs["LegBR"][1], m_armor),
        ],
    )


def build_mire_croco_snapper(col: bpy.types.Collection, offset_x: float) -> dict:
    """Species 4: Low-slung amphibious Swamp Crocodilian with snapping jaws & paddle tail (feet at Z=0)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat("Mat_Croc_Hide", (0.14, 0.21, 0.16), roughness=0.72)
    m_armor = make_mat("Mat_Croc_Armor", (0.08, 0.12, 0.10), roughness=0.48)
    m_glow = make_mat("Mat_Croc_Glow", (1.0, 0.85, 0.24), roughness=0.22, emission=2.0)

    bm_bh, bm_ba, bm_bg = bmesh.new(), bmesh.new(), bmesh.new()
    bm_ha, bm_hg = bmesh.new(), bmesh.new()
    bm_th, bm_ta = bmesh.new(), bmesh.new()
    limbs = {k: (bmesh.new(), bmesh.new()) for k in ("LegFL", "LegFR", "LegBL", "LegBR")}

    add_closed_loft(
        bm_bh,
        [off + Vector((0, 1.85, 0.82)), off + Vector((0, 0.55, 0.92)), off + Vector((0, -0.75, 0.94)), off + Vector((0, -1.75, 0.88))],
        [(0.78, 0.48), (1.05, 0.62), (0.98, 0.58), (0.72, 0.48)],
        segs=8,
    )
    # Row of twin dorsal osteoderm scutes
    for si in range(6):
        yp = 1.4 - si * 0.58
        for sx in (-0.36, 0.36):
            add_curved_claw(bm_ba, off + Vector((sx, yp, 1.38)), Vector((0, 0.45, 0.88)), Vector((0, -1, 0)), 0.46, 0.16, 0.10, 0.05)

    head_p = Vector((0.0, -1.90, 0.92))
    add_closed_loft(bm_ha, [off + head_p, off + head_p + Vector((0, -1.25, 0.02)), off + head_p + Vector((0, -2.35, -0.06))], [(0.68, 0.44), (0.45, 0.28), (0.24, 0.16)], segs=7)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_hg, [off + head_p + Vector((sx * 0.38, -0.45, 0.28)), off + head_p + Vector((sx * 0.36, -0.65, 0.28))], [(0.08, 0.08), (0.06, 0.06)], segs=5)

    tail_p = Vector((0.0, 1.95, 0.80))
    add_closed_loft(bm_th, [off + tail_p, off + tail_p + Vector((0, 1.45, -0.10)), off + tail_p + Vector((0, 3.15, -0.18))], [(0.58, 0.44), (0.28, 0.46), (0.08, 0.32)], segs=7)
    for ti in range(4):
        add_curved_claw(bm_ta, off + tail_p + Vector((0, 0.65 + ti * 0.65, 0.26 - ti * 0.06)), Vector((0, 0.55, 0.82)), Vector((0, -1, 0)), 0.48, 0.08, 0.18, 0.04)

    for k, sx, y_off in (("LegFL", 1.0, -1.25), ("LegFR", -1.0, -1.25), ("LegBL", 1.0, 1.35), ("LegBR", -1.0, 1.35)):
        add_leg_chain(limbs[k][0], limbs[k][1], [off + Vector((sx * 0.85, y_off, 0.72)), off + Vector((sx * 1.25, y_off - 0.12, 0.42)), off + Vector((sx * 1.18, y_off - 0.15, 0.05))], [0.28, 0.22, 0.20])

    return finalize_species(
        "MireCrocoSnapper", "Croc3D", col, off, 0.90,
        {
            "Head": head_p, "Tail": tail_p,
            "LegFL": Vector((0.85, -1.25, 0.72)), "LegFR": Vector((-0.85, -1.25, 0.72)),
            "LegBL": Vector((0.85, 1.35, 0.72)), "LegBR": Vector((-0.85, 1.35, 0.72)),
        },
        [
            ("Body_Hide", bm_bh, m_hide), ("Body_Armor", bm_ba, m_armor), ("Body_Glow", bm_bg, m_glow),
            ("Head_Armor", bm_ha, m_armor), ("Head_Glow", bm_hg, m_glow),
            ("Tail_Hide", bm_th, m_hide), ("Tail_Armor", bm_ta, m_armor),
            ("LegFL_Hide", limbs["LegFL"][0], m_hide), ("LegFL_Armor", limbs["LegFL"][1], m_armor),
            ("LegFR_Hide", limbs["LegFR"][0], m_hide), ("LegFR_Armor", limbs["LegFR"][1], m_armor),
            ("LegBL_Hide", limbs["LegBL"][0], m_hide), ("LegBL_Armor", limbs["LegBL"][1], m_armor),
            ("LegBR_Hide", limbs["LegBR"][0], m_hide), ("LegBR_Armor", limbs["LegBR"][1], m_armor),
        ],
    )


def build_horned_ceratops_bull(col: bpy.types.Collection, offset_x: float) -> dict:
    """Species 5: Colossal Tri-Horned Frilled Jungle Behemoth (feet at Z=0, trunk Z=2.55)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat("Mat_Cera_Hide", (0.20, 0.14, 0.22), roughness=0.76)
    m_armor = make_mat("Mat_Cera_Armor", (0.76, 0.68, 0.56), roughness=0.45)  # bone frill/horns
    m_glow = make_mat("Mat_Cera_Glow", (1.0, 0.32, 0.16), roughness=0.20, emission=2.4)

    bm_bh, bm_ba, bm_bg = bmesh.new(), bmesh.new(), bmesh.new()
    bm_ha, bm_hg = bmesh.new(), bmesh.new()
    bm_th, bm_ta = bmesh.new(), bmesh.new()
    limbs = {k: (bmesh.new(), bmesh.new()) for k in ("LegFL", "LegFR", "LegBL", "LegBR")}

    add_closed_loft(
        bm_bh,
        [off + Vector((0, 2.25, 2.35)), off + Vector((0, 0.75, 2.68)), off + Vector((0, -0.75, 2.82)), off + Vector((0, -2.05, 2.65))],
        [(1.25, 1.05), (1.68, 1.42), (1.76, 1.48), (1.35, 1.18)],
        segs=8,
    )
    add_closed_loft(bm_ba, [off + Vector((0, 1.8, 3.45)), off + Vector((0, 0.0, 3.92)), off + Vector((0, -1.6, 3.65))], [(0.92, 0.35), (1.28, 0.45), (0.98, 0.36)], segs=7)
    for sx in (-1.0, 1.0):
        add_closed_loft(bm_bg, [off + Vector((sx * 1.48, 0.85, 2.62)), off + Vector((sx * 1.52, -0.85, 2.75))], [(0.16, 0.14), (0.18, 0.15)], segs=5)

    head_p = Vector((0.0, -2.25, 2.55))
    # Armored Shield Frill + 3 Giant Horns
    add_closed_loft(bm_ha, [off + head_p + Vector((0, 0.25, 0.35)), off + head_p + Vector((0, 0.45, 1.65))], [(1.45, 0.42), (1.92, 0.32)], segs=8)
    add_closed_loft(bm_bh, [off + head_p, off + head_p + Vector((0, -1.25, -0.15)), off + head_p + Vector((0, -2.05, -0.35))], [(1.05, 0.88), (0.85, 0.70), (0.45, 0.38)], segs=7)
    for sx in (-1.0, 1.0):
        add_curved_claw(bm_ha, off + head_p + Vector((sx * 0.58, -0.85, 0.65)), Vector((sx * 0.15, -0.88, 0.42)), Vector((0, 0, 1)), 2.25, 0.24, 0.22, -0.35)
        add_closed_loft(bm_hg, [off + head_p + Vector((sx * 0.72, -1.05, 0.15)), off + head_p + Vector((sx * 0.68, -1.35, 0.12))], [(0.14, 0.12), (0.07, 0.07)], segs=5)
    # Nose horn
    add_curved_claw(bm_ha, off + head_p + Vector((0, -1.65, -0.05)), Vector((0, -0.58, 0.82)), Vector((0, -1, 0)), 1.05, 0.18, 0.16, -0.15)

    tail_p = Vector((0.0, 2.35, 2.30))
    add_closed_loft(bm_th, [off + tail_p, off + tail_p + Vector((0, 1.45, 0.15)), off + tail_p + Vector((0, 2.75, 0.38))], [(0.68, 0.62), (0.38, 0.35), (0.24, 0.22)], segs=7)
    add_closed_loft(bm_ta, [off + tail_p + Vector((0, 2.45, 0.35)), off + tail_p + Vector((0, 3.15, 0.45))], [(0.55, 0.52), (0.22, 0.20)], segs=6)

    for k, sx, y_off in (("LegFL", 1.0, -1.55), ("LegFR", -1.0, -1.55), ("LegBL", 1.0, 1.65), ("LegBR", -1.0, 1.65)):
        add_leg_chain(limbs[k][0], limbs[k][1], [off + Vector((sx * 1.42, y_off, 2.05)), off + Vector((sx * 1.52, y_off - 0.12, 1.05)), off + Vector((sx * 1.45, y_off, 0.06))], [0.52, 0.42, 0.44])

    return finalize_species(
        "HornedCeratopsBull", "Ceratops3D", col, off, 2.55,
        {
            "Head": head_p, "Tail": tail_p,
            "LegFL": Vector((1.42, -1.55, 2.05)), "LegFR": Vector((-1.42, -1.55, 2.05)),
            "LegBL": Vector((1.42, 1.65, 2.05)), "LegBR": Vector((-1.42, 1.65, 2.05)),
        },
        [
            ("Body_Hide", bm_bh, m_hide), ("Body_Armor", bm_ba, m_armor), ("Body_Glow", bm_bg, m_glow),
            ("Head_Armor", bm_ha, m_armor), ("Head_Glow", bm_hg, m_glow),
            ("Tail_Hide", bm_th, m_hide), ("Tail_Armor", bm_ta, m_armor),
            ("LegFL_Hide", limbs["LegFL"][0], m_hide), ("LegFL_Armor", limbs["LegFL"][1], m_armor),
            ("LegFR_Hide", limbs["LegFR"][0], m_hide), ("LegFR_Armor", limbs["LegFR"][1], m_armor),
            ("LegBL_Hide", limbs["LegBL"][0], m_hide), ("LegBL_Armor", limbs["LegBL"][1], m_armor),
            ("LegBR_Hide", limbs["LegBR"][0], m_hide), ("LegBR_Armor", limbs["LegBR"][1], m_armor),
        ],
    )


def render_preview() -> None:
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=OUT_GLB)
    scene = bpy.context.scene
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 750
    scene.render.filepath = OUT_PREVIEW

    world = bpy.data.worlds.new("FaunaV5Preview")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.14, 0.16, 0.18, 1.0)
        bg.inputs[1].default_value = 1.6

    sun_d = bpy.data.lights.new("Sun", type="SUN")
    sun_d.energy = 3.6
    sun_o = bpy.data.objects.new("Sun", sun_d)
    sun_o.rotation_euler = (math.radians(48), 0, math.radians(-35))
    scene.collection.objects.link(sun_o)

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 32.0
    cam_o = bpy.data.objects.new("Cam", cam_d)
    cam_o.location = (44.0, -48.0, 14.0)
    cam_o.rotation_euler = (Vector((44.0, 0.0, 2.2)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam_o)
    scene.camera = cam_o

    os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    assert_no_overwrites()
    clear_scene()
    col = bpy.data.collections.new("DiverseFaunaV5")
    bpy.context.scene.collection.children.link(col)
    add_origin_marker(col)

    manifests = [
        build_swamp_stalker_raptor(col, 0.0),
        build_thornback_boar(col, 22.0),
        build_biolum_mantis_stalker(col, 44.0),
        build_mire_croco_snapper(col, 66.0),
        build_horned_ceratops_bull(col, 88.0),
    ]

    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )

    total_meshes = 1 + sum(len(m["meshes"]) for m in manifests)
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fh:
        json.dump({"fauna": manifests, "totalMeshes": total_meshes}, fh, indent=2)

    render_preview()
    print("V5 FAUNA COMPLETE:", json.dumps({"speciesCount": len(manifests), "totalMeshes": total_meshes}))


if __name__ == "__main__":
    main()
