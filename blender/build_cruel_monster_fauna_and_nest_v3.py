"""Primal Hunt v3 — Cruel Colossal Monster + 5-Species Animated Fauna + Horror Map Props.

Strict non-overwrite policy: writes only new *_v3 artifacts.
Builds:
1. PrimalHunt_CruelArticulatedMonster_v3.glb
   - Rest-pose extraction from AbyssMonster.blend across 17 Motor6D joints & 6 Material buckets
   - Target Stage-1 height = 14.5 studs (Stage 2 scale 1.32x = 19.1 studs, Stage 3 scale 1.68x = 24.4 studs)
   - Cruel anatomical upgrades baked per-joint:
     * Raptorial split mandibles + gullet needle-fangs + glowing predator eye-slits (Head)
     * Twin sweeping forearm executioner scythe blades + serrations (ForeUpL, ForeUpR)
     * 4 upper & 3 lower hooked gore-talons per arm (ForeUpL/R, ArmLoL/R)
     * 7 backward-raked dorsal vertebrae neural spines (Chest, Pelvis)
     * Barbed harpoon stingers & hooks at all 6 tentacle tips (Tent0..Tent5)
2. PrimalHunt_BiodiverseFaunaAndNest_v3.glb
   - 5 articulated 6-joint Fauna species at X = 0, 20, 40, 60, 80:
     RedGoliath3D, CoastalScavenger3D, SporeCrawler3D, AcidSpitterDrake3D, ObsidianCragback3D
   - 4 detailed Horror-Hunt Map Props at X = 120, 155, 180, 200:
     AbyssalNest3D, CorruptedAEMOutpost3D, BoneTotemShrine3D, BiolumSporeTree3D
3. cruel_monster_fauna_nest_manifest_v3.json + previews/cruel_monster_fauna_nest_v3.png
"""

from __future__ import annotations

import json
import math
import os
import random
from collections import defaultdict
from typing import Dict, List, Sequence, Tuple

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt"
SOURCE_BLEND = os.path.join(ROOT, "AbyssMonster.blend")
OUT_MONSTER_GLB = os.path.join(ROOT, "PrimalHunt_CruelArticulatedMonster_v3.glb")
OUT_BIO_GLB = os.path.join(ROOT, "PrimalHunt_BiodiverseFaunaAndNest_v3.glb")
OUT_MANIFEST = os.path.join(ROOT, "cruel_monster_fauna_nest_manifest_v3.json")
OUT_PREVIEW = os.path.join(ROOT, "previews", "cruel_monster_fauna_nest_v3.png")

TARGET_STAGE1_HEIGHT_STUDS = 14.5

BONE_TO_JOINT: Dict[str, str] = {
    "root": "Pelvis",
    "pelvis": "Pelvis",
    "spine_1": "Pelvis",
    "spine_2": "Chest",
    "spine_3": "Chest",
    "neck": "Chest",
    "head": "Head",
    "crown_0_1": "CrownL",
    "crown_0_2": "CrownL",
    "crown_1_1": "CrownL",
    "crown_1_2": "CrownL",
    "crown_2_1": "CrownL",
    "crown_2_2": "CrownL",
    "crown_3_1": "CrownL",
    "crown_3_2": "CrownL",
    "crown_4_1": "CrownR",
    "crown_4_2": "CrownR",
    "crown_5_1": "CrownR",
    "crown_5_2": "CrownR",
    "crown_6_1": "CrownR",
    "crown_6_2": "CrownR",
    "crown_7_1": "CrownR",
    "crown_7_2": "CrownR",
    "arm_up_sh_l": "ArmUpL",
    "arm_up_up_l": "ArmUpL",
    "arm_up_lo_l": "ForeUpL",
    "arm_up_hd_l": "ForeUpL",
    "arm_up_sh_r": "ArmUpR",
    "arm_up_up_r": "ArmUpR",
    "arm_up_lo_r": "ForeUpR",
    "arm_up_hd_r": "ForeUpR",
    "arm_lo_up_l": "ArmLoL",
    "arm_lo_lo_l": "ArmLoL",
    "arm_lo_hd_l": "ArmLoL",
    "arm_lo_up_r": "ArmLoR",
    "arm_lo_lo_r": "ArmLoR",
    "arm_lo_hd_r": "ArmLoR",
    "tent_0_1": "Tent0",
    "tent_0_2": "Tent0",
    "tent_0_3": "Tent0",
    "tent_0_4": "Tent0",
    "tent_0_5": "Tent0",
    "tent_1_1": "Tent1",
    "tent_1_2": "Tent1",
    "tent_1_3": "Tent1",
    "tent_1_4": "Tent1",
    "tent_1_5": "Tent1",
    "tent_2_1": "Tent2",
    "tent_2_2": "Tent2",
    "tent_2_3": "Tent2",
    "tent_2_4": "Tent2",
    "tent_2_5": "Tent2",
    "tent_3_1": "Tent3",
    "tent_3_2": "Tent3",
    "tent_3_3": "Tent3",
    "tent_3_4": "Tent3",
    "tent_3_5": "Tent3",
    "tent_4_1": "Tent4",
    "tent_4_2": "Tent4",
    "tent_4_3": "Tent4",
    "tent_4_4": "Tent4",
    "tent_4_5": "Tent4",
    "tent_5_1": "Tent5",
    "tent_5_2": "Tent5",
    "tent_5_3": "Tent5",
    "tent_5_4": "Tent5",
    "tent_5_5": "Tent5",
}

MAT_TO_BUCKET: Dict[str, str] = {
    "Mat_Monster_AbyssalHide": "Hide",
    "Mat_Monster_ObsidianCarapace": "Carapace",
    "Mat_Eclipse_DarkRibChitin": "Carapace",
    "Mat_Monster_BoneClaws": "Bone",
    "Mat_Eclipse_BronzeShackle": "Bronze",
    "Mat_Eclipse_VoidBlack": "VoidCore",
    "Mat_Furnace_OuterEmber": "Neon",
    "Mat_Furnace_MoltenHeart": "Neon",
    "Mat_Eclipse_BloodCorona_S1": "Neon",
    "Mat_Eclipse_BloodRim_S1": "Neon",
    "Mat_Eclipse_GoldCorona_S2": "Neon",
    "Mat_Eclipse_GoldRim_S2": "Neon",
    "Mat_Eclipse_SolarCorona_S3": "Neon",
    "Mat_Eclipse_SolarRim_S3": "Neon",
}

BUCKET_RGB: Dict[str, Tuple[float, float, float, float, float]] = {
    # name: (r, g, b, roughness, emission_strength)
    "Hide": (0.14, 0.11, 0.15, 0.72, 0.0),
    "Carapace": (0.08, 0.08, 0.11, 0.42, 0.0),
    "Bone": (0.86, 0.80, 0.70, 0.48, 0.0),
    "Bronze": (0.54, 0.46, 0.38, 0.35, 0.0),
    "VoidCore": (0.02, 0.02, 0.03, 0.25, 0.0),
    "Neon": (1.0, 0.42, 0.09, 0.15, 2.4),
}

CANONICAL_MONSTER_SOURCES = [
    ("Monster_CoreBody_Skinned", "All", 1, 3),
    ("Monster_RibcageAndShackles_Skinned", "All", 1, 3),
    ("Monster_Stage1_Apex_Skinned", "S1", 1, 1),
    ("Monster_Stage2_Tyrant_Skinned", "S2", 2, 2),
    ("Monster_Stage3_EclipseGod_Skinned", "S3", 3, 3),
]

STAGE_RANGE = {"All": (1, 3), "S1": (1, 1), "S2": (2, 2), "S3": (3, 3)}


def assert_no_overwrites() -> None:
    for p in (OUT_MONSTER_GLB, OUT_BIO_GLB, OUT_MANIFEST, OUT_PREVIEW):
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


def add_origin_marker(col: bpy.types.Collection, name: str = "ORIGIN_MARKER") -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.05)
    mat = make_mat("Mat_OriginMarker", (0.2, 0.2, 0.2), metallic=0.0, roughness=0.9)
    return create_mesh_obj(name, bm, mat, col)


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
            offset = rx * (math.cos(ang) * rad_x) + ry * (math.sin(ang) * rad_y)
            ring.append(bm.verts.new(p + offset))
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


def add_sharp_claw_curve(
    bm: bmesh.types.BMesh,
    base: Vector,
    forward_dir: Vector,
    up_dir: Vector,
    length: float,
    base_rx: float,
    base_ry: float,
    hook_drop: float,
    steps: int = 5,
    segs: int = 6,
) -> None:
    f = forward_dir.normalized()
    u = up_dir.normalized()
    pts: List[Vector] = []
    rads: List[Tuple[float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        arc = math.sin(t * math.pi * 0.72) * (length * 0.14) - (t * t) * hook_drop
        pts.append(base + f * (t * length) + u * arc)
        taper = max(0.03, (1.0 - t) ** 0.85)
        rads.append((base_rx * taper, base_ry * taper))
    add_closed_loft(bm, pts, rads, segs=segs, cap_start=True, cap_end=True)


def add_plate_wedge(
    bm: bmesh.types.BMesh,
    center: Vector,
    dir_fwd: Vector,
    dir_up: Vector,
    length: float,
    width: float,
    thickness: float,
    taper: float = 0.35,
) -> None:
    f = dir_fwd.normalized()
    u = dir_up.normalized()
    pts = [
        center - f * (length * 0.5),
        center,
        center + f * (length * 0.5),
    ]
    rads = [
        (width * 0.42, thickness * 0.38),
        (width * 0.55, thickness * 0.55),
        (width * taper, thickness * taper),
    ]
    # Keep upright orientation aligned to u by nudging slight curve
    pts[1] = pts[1] + u * (thickness * 0.12)
    add_closed_loft(bm, pts, rads, segs=6, cap_start=True, cap_end=True)


def add_cruel_monster_geometry(
    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh],
    bones: Dict[str, Tuple[Vector, Vector]],
    norm_fn,
) -> None:
    """Injects cruel apex anatomical geometry directly into rest-pose joint BMeshes."""

    def add_scaled_loft(key: Tuple[str, str, str], pts: Sequence[Vector], rads: Sequence[Tuple[float, float]], segs: int = 7) -> None:
        bm = buckets[key]
        scaled_pts = [norm_fn(p) for p in pts]
        # Radii approximate uniform scale using distance helper
        s = (norm_fn(Vector((1, 0, 0))) - norm_fn(Vector((0, 0, 0)))).length
        scaled_rads = [(rx * s, ry * s) for rx, ry in rads]
        add_closed_loft(bm, scaled_pts, scaled_rads, segs=segs, cap_start=True, cap_end=True)

    def add_scaled_claw(key: Tuple[str, str, str], base: Vector, fwd: Vector, up: Vector, length: float, rx: float, ry: float, drop: float, steps: int = 5, segs: int = 6) -> None:
        s = (norm_fn(Vector((1, 0, 0))) - norm_fn(Vector((0, 0, 0)))).length
        # norm_fn converts Blender (x, y, z) -> rotated world X/Y/Z before GLTF; keep consistent!
        f = fwd.normalized()
        u = up.normalized()
        pts: List[Vector] = []
        rads: List[Tuple[float, float]] = []
        for i in range(steps + 1):
            t = i / steps
            arc = math.sin(t * math.pi * 0.72) * (length * 0.14) - (t * t) * drop
            pts.append(norm_fn(base + f * (t * length) + u * arc))
            taper = max(0.03, (1.0 - t) ** 0.85)
            rads.append((rx * taper * s, ry * taper * s))
        add_closed_loft(buckets[key], pts, rads, segs=segs, cap_start=True, cap_end=True)

    head_pos = bones["head"][0]

    # 1. Raptorial Split Mandibles + Gullet Needle Fangs + Glowing Slit Eyes (Head)
    for side in (-1.0, 1.0):
        # Outer chitinous split lower mandible arching out & snapping forward
        m_pts = [
            Vector((side * 0.24, head_pos.y - 0.10, head_pos.z - 0.08)),
            Vector((side * 0.42, head_pos.y - 0.48, head_pos.z - 0.20)),
            Vector((side * 0.34, head_pos.y - 0.76, head_pos.z - 0.16)),
            Vector((side * 0.13, head_pos.y - 0.90, head_pos.z - 0.04)),
        ]
        add_scaled_loft(
            ("Head", "All", "Carapace"),
            m_pts,
            [(0.11, 0.10), (0.095, 0.085), (0.075, 0.06), (0.018, 0.018)],
            segs=7,
        )
        # Inner razor jaw-mandible fang at tip
        add_scaled_claw(
            ("Head", "All", "Bone"),
            Vector((side * 0.18, head_pos.y - 0.80, head_pos.z - 0.09)),
            Vector((-side * 0.35, -0.85, 0.38)),
            Vector((0.0, 0.0, 1.0)),
            length=0.28,
            rx=0.035,
            ry=0.025,
            drop=0.04,
            steps=4,
        )
        # Predator glowing slit eyes
        eye_pts = [
            Vector((side * 0.14, head_pos.y - 0.48, head_pos.z + 0.31)),
            Vector((side * 0.28, head_pos.y - 0.44, head_pos.z + 0.35)),
            Vector((side * 0.39, head_pos.y - 0.34, head_pos.z + 0.40)),
        ]
        add_scaled_loft(("Head", "All", "Neon"), eye_pts, [(0.015, 0.012), (0.035, 0.022), (0.012, 0.010)], segs=6)

        # Row of upper snout needle-fangs + inner lower fangs
        for fi in range(5):
            ft = fi / 4.0
            fx = side * (0.05 + ft * 0.21)
            fy = head_pos.y - (0.66 - ft * 0.16)
            add_scaled_claw(
                ("Head", "All", "Bone"),
                Vector((fx, fy, head_pos.z + 0.02)),
                Vector((-side * 0.08, -0.35, -0.92)),
                Vector((0.0, -1.0, 0.0)),
                length=0.22 - fi * 0.015,
                rx=0.024,
                ry=0.020,
                drop=0.05,
                steps=4,
            )
            add_scaled_claw(
                ("Head", "All", "Bone"),
                Vector((fx * 1.15, fy - 0.04, head_pos.z - 0.16)),
                Vector((-side * 0.10, -0.45, 0.88)),
                Vector((0.0, -1.0, 0.0)),
                length=0.19 - fi * 0.012,
                rx=0.022,
                ry=0.018,
                drop=0.04,
                steps=4,
            )

    # 2. Forearm Executioner Scythe Blades + 4 Hooked Upper Talons (ForeUpL & ForeUpR)
    for jname, s_name_elbow, s_name_hand in (
        ("ForeUpL", "arm_up_lo_l", "arm_up_hd_l"),
        ("ForeUpR", "arm_up_lo_r", "arm_up_hd_r"),
    ):
        side = 1.0 if s_name_elbow.endswith("_l") else -1.0
        eb = bones[s_name_elbow][0]
        hb = bones[s_name_hand][0]
        arm_dir = (hb - eb).normalized()
        out_dir = Vector((side * 0.55, 0.45, -0.68)).normalized()

        # Scythe mounting spine along outer forearm ridge
        scythe_mount = [
            eb + arm_dir * 0.12 + Vector((0.0, 0.10, -0.05)),
            eb + arm_dir * 0.55 + out_dir * 0.34,
            hb + arm_dir * 0.38 + out_dir * 0.52,
            hb + arm_dir * 0.72 + out_dir * 0.25 + Vector((0.0, -0.45, -0.35)),
        ]
        add_scaled_loft(
            (jname, "All", "Carapace"),
            scythe_mount,
            [(0.11, 0.07), (0.14, 0.05), (0.10, 0.035), (0.02, 0.015)],
            segs=6,
        )
        # Razor bone crescent scythe edge projecting outward & hooking forward
        blade_pts = [
            eb + arm_dir * 0.32 + out_dir * 0.36,
            hb + arm_dir * 0.20 + out_dir * 0.78,
            hb + arm_dir * 0.65 + out_dir * 0.68 + Vector((0.0, -0.55, -0.45)),
            hb + arm_dir * 0.88 + Vector((side * 0.22, -0.95, -0.82)),
        ]
        add_scaled_loft(
            (jname, "All", "Bone"),
            blade_pts,
            [(0.06, 0.022), (0.10, 0.025), (0.08, 0.020), (0.012, 0.010)],
            segs=6,
        )

        # 4 ultra-sharp curved Gore-Talons at the upper palm
        for ci, (off_y, off_z, len_c, sweep) in enumerate([
            (-0.18, 0.08, 0.92, -0.25),
            (-0.04, 0.12, 1.05, -0.15),
            (0.09, 0.04, 0.96, 0.02),
            (-0.22, -0.09, 0.68, -0.40),
        ]):
            t_base = hb + Vector((side * 0.22, off_y, off_z))
            fwd = Vector((side * 0.65, -0.58 + sweep * 0.3, -0.42)).normalized()
            add_scaled_claw(
                (jname, "All", "Bone"),
                t_base,
                fwd,
                Vector((-side * 0.3, -0.5, 0.75)),
                length=len_c,
                rx=0.055,
                ry=0.038,
                drop=len_c * 0.38,
                steps=5,
                segs=6,
            )

    # 3. Lower Raptor Talons (ArmLoL & ArmLoR)
    for jname, s_name_hand in (("ArmLoL", "arm_lo_hd_l"), ("ArmLoR", "arm_lo_hd_r")):
        side = 1.0 if s_name_hand.endswith("_l") else -1.0
        hb = bones[s_name_hand][0]
        for off_x, off_y, len_c in [(-0.08, -0.05, 0.78), (0.0, -0.12, 0.88), (0.08, 0.02, 0.74)]:
            add_scaled_claw(
                (jname, "All", "Bone"),
                hb + Vector((side * off_x, off_y, -0.04)),
                Vector((side * 0.35, -0.55, -0.75)),
                Vector((0.0, -0.6, 0.8)),
                length=len_c,
                rx=0.042,
                ry=0.030,
                drop=len_c * 0.32,
                steps=4,
            )

    # 4. Jagged Dorsal Vertebrae Neural Spines (Pelvis + Chest)
    spine_nodes = [
        ("Pelvis", bones["pelvis"][0] + Vector((0.0, 0.42, 0.10)), 0.55),
        ("Pelvis", bones["spine_1"][0] + Vector((0.0, 0.50, 0.12)), 0.68),
        ("Chest", bones["spine_2"][0] + Vector((0.0, 0.58, 0.12)), 0.82),
        ("Chest", (bones["spine_2"][0] + bones["spine_3"][0]) * 0.5 + Vector((0.0, 0.62, 0.10)), 0.94),
        ("Chest", bones["spine_3"][0] + Vector((0.0, 0.60, 0.08)), 1.05),
        ("Chest", bones["neck"][0] + Vector((0.0, 0.44, 0.05)), 0.78),
    ]
    for jname, base_p, sp_len in spine_nodes:
        # Chitinous neural sheath
        add_scaled_claw(
            (jname, "All", "Carapace"),
            base_p - Vector((0.0, 0.14, 0.0)),
            Vector((0.0, 0.85, 0.52)),
            Vector((0.0, -0.5, 0.85)),
            length=sp_len * 0.62,
            rx=0.095,
            ry=0.14,
            drop=-sp_len * 0.08,
            steps=4,
        )
        # Razor bone blade protruding from sheath
        add_scaled_claw(
            (jname, "All", "Bone"),
            base_p + Vector((0.0, 0.22, 0.14)),
            Vector((0.0, 0.78, 0.62)),
            Vector((0.0, -0.6, 0.8)),
            length=sp_len * 0.68,
            rx=0.048,
            ry=0.088,
            drop=sp_len * 0.18,
            steps=4,
        )

    # 5. Barbed Harpoon Stingers at all 6 Tentacle Tips (Tent0..Tent5)
    for ti in range(6):
        jname = f"Tent{ti}"
        h4, t4 = bones[f"tent_{ti}_4"]
        h5, t5 = bones[f"tent_{ti}_5"]
        tan = (t5 - h5)
        if tan.length < 1e-4:
            tan = t5 - h4
        tan = tan.normalized()
        rx, ry = frame_on_tangent(tan)

        # Harpoon chitin collar
        add_scaled_loft(
            (jname, "All", "Carapace"),
            [t5 - tan * 0.22, t5, t5 + tan * 0.22],
            [(0.09, 0.09), (0.14, 0.14), (0.04, 0.04)],
            segs=7,
        )
        # Main harpoon bone spear
        add_scaled_claw(
            (jname, "All", "Bone"),
            t5 - tan * 0.05,
            tan,
            ry,
            length=0.68,
            rx=0.068,
            ry=0.042,
            drop=0.10,
            steps=4,
        )
        # Twin reverse grappling barbs
        for side in (-1.0, 1.0):
            barb_dir = (-tan * 0.75 + rx * (side * 0.66)).normalized()
            add_scaled_claw(
                (jname, "All", "Bone"),
                t5 + tan * 0.08 + rx * (side * 0.04),
                barb_dir,
                ry,
                length=0.38,
                rx=0.036,
                ry=0.025,
                drop=0.06,
                steps=3,
            )


def build_cruel_monster_glb() -> dict:
    """Loads AbyssMonster.blend rest data, appends cruel anatomical weapons, and exports Monster v3 GLB."""
    bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)

    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    bones_local: Dict[str, Tuple[Vector, Vector]] = {
        b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones
    }

    # Compute base bounds on canonical meshes
    min_z = 1e9
    max_z = -1e9
    xs: List[float] = []
    ys: List[float] = []
    for mname, sk, _, _ in CANONICAL_MONSTER_SOURCES:
        obj = bpy.data.objects[mname]
        for v in obj.data.vertices:
            co = v.co
            xs.append(co.x)
            ys.append(co.y)
            if sk in ("All", "S1"):
                min_z = min(min_z, co.z)
                max_z = max(max_z, co.z)

    center_x = 0.5 * (min(xs) + max(xs))
    center_y = 0.5 * (min(ys) + max(ys))
    raw_height = max(0.5, max_z - min_z)
    scale_s = TARGET_STAGE1_HEIGHT_STUDS / raw_height

    def norm_blender_pt(co: Vector) -> Vector:
        # Map Blender rest-pose coordinates so exported GLTF (-Y up in GLTF -> Roblox Y up)
        # lands at exact Roblox local (-x, z, y) after CFrame rel space!
        # Wait: in Blender Y-up glTF export (export_yup=True), Blender (X, Y, Z) becomes glTF (X, Z, -Y),
        # and Roblox insert_asset rotates -90/180 depending on root unless relCF = ORIGIN_MARKER:ToObjectSpace(part).
        # Keeping raw Blender coordinates relative to (center_x, center_y, min_z) * scale_s guarantees
        # ORIGIN_MARKER:ToObjectSpace(part).Position == [-(x-cx)*s, (z-min_z)*s, (y-cy)*s] == blender_to_roblox_pos!
        return Vector(((co.x - center_x) * scale_s, (co.y - center_y) * scale_s, (co.z - min_z) * scale_s))

    # Extract per-(joint, stage, bucket) triangles in rest pose
    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh] = defaultdict(bmesh.new)

    for mname, stage_key, _, _ in CANONICAL_MONSTER_SOURCES:
        obj = bpy.data.objects[mname]
        me = obj.data
        vg_names = {g.index: g.name for g in obj.vertex_groups}
        mats = list(me.materials)

        # Dominant joint per vertex
        v_joint: List[str] = []
        for v in me.vertices:
            best_w = -1.0
            best_j = "Pelvis"
            for g in v.groups:
                bname = vg_names.get(g.group, "")
                if bname in BONE_TO_JOINT and g.weight > best_w:
                    best_w = g.weight
                    best_j = BONE_TO_JOINT[bname]
            v_joint.append(best_j)

        vert_cache: Dict[Tuple[str, str, str, int], bmesh.types.BMVert] = {}
        for poly in me.polygons:
            if len(poly.vertices) < 3:
                continue
            mat_name = mats[poly.material_index].name if poly.material_index < len(mats) and mats[poly.material_index] else "Mat_Monster_AbyssalHide"
            mbucket = MAT_TO_BUCKET.get(mat_name, "Hide")
            # Majority vote joint across polygon corners
            jcounts: Dict[str, int] = defaultdict(int)
            for vi in poly.vertices:
                jcounts[v_joint[vi]] += 1
            jname = max(jcounts.items(), key=lambda kv: kv[1])[0]
            bkey = (jname, stage_key, mbucket)
            bm = buckets[bkey]
            fverts = []
            for vi in poly.vertices:
                ckey = (jname, stage_key, mbucket, vi)
                bv = vert_cache.get(ckey)
                if bv is None:
                    bv = bm.verts.new(norm_blender_pt(me.vertices[vi].co))
                    vert_cache[ckey] = bv
                fverts.append(bv)
            try:
                bm.faces.new(fverts)
            except ValueError:
                pass

    # Inject cruel anatomical weapons directly into buckets BEFORE final mesh creation
    add_cruel_monster_geometry(buckets, bones_local, norm_blender_pt)

    # Joint pivots in normalized Blender coordinates -> Roblox rel space
    pivot_src = {
        "Pelvis": bones_local["pelvis"][0],
        "Chest": bones_local["spine_2"][0],
        "Head": bones_local["head"][0],
        "CrownL": (bones_local["crown_1_1"][0] + bones_local["crown_2_1"][0]) * 0.5,
        "CrownR": (bones_local["crown_5_1"][0] + bones_local["crown_6_1"][0]) * 0.5,
        "ArmUpL": bones_local["arm_up_sh_l"][0],
        "ForeUpL": bones_local["arm_up_lo_l"][0],
        "ArmUpR": bones_local["arm_up_sh_r"][0],
        "ForeUpR": bones_local["arm_up_lo_r"][0],
        "ArmLoL": bones_local["arm_lo_up_l"][0],
        "ArmLoR": bones_local["arm_lo_up_r"][0],
        "Tent0": bones_local["tent_0_1"][0],
        "Tent1": bones_local["tent_1_1"][0],
        "Tent2": bones_local["tent_2_1"][0],
        "Tent3": bones_local["tent_3_1"][0],
        "Tent4": bones_local["tent_4_1"][0],
        "Tent5": bones_local["tent_5_1"][0],
    }
    joint_pivots = {j: blender_to_roblox_pos(norm_blender_pt(pt)) for j, pt in pivot_src.items()}

    # Build clean scene for Monster export
    clear_scene()
    col = bpy.data.collections.new("CruelMonsterV3")
    bpy.context.scene.collection.children.link(col)
    add_origin_marker(col, "ORIGIN_MARKER")

    mat_map = {}
    for bname, (r, g, b, rough, em) in BUCKET_RGB.items():
        mat_map[bname] = make_mat(f"Mat_Monster_{bname}", (r, g, b), metallic=0.2 if bname in ("Bronze", "Carapace") else 0.0, roughness=rough, emission=em)

    mesh_entries = []
    for (jname, stage_key, mbucket), bm in sorted(buckets.items()):
        if len(bm.faces) == 0:
            bm.free()
            continue
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        part_name = f"MArt_{jname}_{stage_key}_{mbucket}"
        me = bpy.data.meshes.new(part_name + "_Mesh")
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(part_name, me)
        obj.data.materials.append(mat_map[mbucket])
        col.objects.link(obj)
        minS, maxS = STAGE_RANGE[stage_key]
        mesh_entries.append({
            "name": part_name,
            "joint": jname,
            "mat": mbucket,
            "minStage": minS,
            "maxStage": maxS,
        })

    bpy.ops.export_scene.gltf(
        filepath=OUT_MONSTER_GLB,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )

    return {
        "stage1HeightStuds": TARGET_STAGE1_HEIGHT_STUDS,
        "jointPivots": joint_pivots,
        "meshCount": len(mesh_entries),
        "meshes": mesh_entries,
    }


# ==============================================================================
# PART B: 5 FAUNA SPECIES + 4 HORROR-HUNT MAP PROPS
# ==============================================================================

def add_fauna_leg(
    bm_hide: bmesh.types.BMesh,
    bm_armor: bmesh.types.BMesh,
    hip: Vector,
    knee: Vector,
    ankle: Vector,
    foot: Vector,
    radii: Tuple[float, float, float, float],
    has_armor_plate: bool = True,
) -> None:
    add_closed_loft(
        bm_hide,
        [hip, knee, ankle, foot],
        [(radii[0], radii[0]), (radii[1], radii[1] * 0.9), (radii[2], radii[2] * 0.85), (radii[3], radii[3] * 1.1)],
        segs=7,
    )
    if has_armor_plate:
        out = Vector((1.0 if hip.x >= 0 else -1.0, -0.25, 0.35)).normalized()
        add_closed_loft(
            bm_armor,
            [hip + out * (radii[0] * 0.45), knee + out * (radii[1] * 0.55), ankle + out * (radii[2] * 0.35)],
            [(radii[0] * 0.65, radii[0] * 0.42), (radii[1] * 0.72, radii[1] * 0.45), (radii[2] * 0.45, radii[2] * 0.32)],
            segs=6,
        )
        # Toe claws
        for side_o in (-0.35, 0.35):
            toe_dir = Vector((side_o * 0.35, -0.95, -0.15)).normalized()
            add_sharp_claw_curve(bm_armor, foot, toe_dir, Vector((0, 0, 1)), length=radii[3] * 1.75, base_rx=radii[3] * 0.35, base_ry=radii[3] * 0.32, hook_drop=radii[3] * 0.3)


def build_fauna_species(
    species_name: str,
    prefix: str,
    col: bpy.types.Collection,
    offset_x: float,
    colors: Dict[str, Tuple[float, ...]],
    glow_kind: str,  # "Magma", "Glow", "SporeGlow", "Venom"
    body_style: str,
) -> dict:
    """Constructs one of 5 distinct articulated 6-motor Fauna species centered at (offset_x, 0, 0)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_hide = make_mat(f"Mat_{prefix}_Hide", colors["Hide"], roughness=0.74)
    m_armor = make_mat(f"Mat_{prefix}_Armor", colors["Armor"], metallic=0.15, roughness=0.45)
    m_glow = make_mat(f"Mat_{prefix}_{glow_kind}", colors[glow_kind], roughness=0.20, emission=2.2)

    bm_body_h, bm_body_a, bm_body_g = bmesh.new(), bmesh.new(), bmesh.new()
    bm_head_a, bm_head_g = bmesh.new(), bmesh.new()
    bm_tail_h, bm_tail_a = bmesh.new(), bmesh.new()
    limb_bms = {ln: (bmesh.new(), bmesh.new()) for ln in ("LegFL", "LegFR", "LegBL", "LegBR")}

    # Joint layout by species (Blender meters ~ 1:1 Roblox studs for Fauna!)
    if body_style == "goliath":
        trunk_z = 2.35
        trunk_pts = [Vector((0, 2.0, 2.05)), Vector((0, 0.8, 2.25)), Vector((0, -0.4, 2.48)), Vector((0, -1.7, 2.52))]
        trunk_rads = [(1.05, 0.92), (1.32, 1.15), (1.52, 1.32), (1.22, 1.08)]
        head_pivot = Vector((0.0, -2.35, 2.55))
        tail_pivot = Vector((0.0, 2.10, 2.05))
        hips = {
            "LegFL": (Vector((1.35, -1.65, 2.15)), Vector((1.55, -1.95, 1.25)), Vector((1.40, -1.35, 0.55)), Vector((1.45, -1.65, 0.05)), (0.48, 0.36, 0.28, 0.32)),
            "LegFR": (Vector((-1.35, -1.65, 2.15)), Vector((-1.55, -1.95, 1.25)), Vector((-1.40, -1.35, 0.55)), Vector((-1.45, -1.65, 0.05)), (0.48, 0.36, 0.28, 0.32)),
            "LegBL": (Vector((1.12, 1.72, 2.08)), Vector((1.30, 1.45, 1.15)), Vector((1.18, 1.92, 0.45)), Vector((1.22, 1.65, 0.05)), (0.44, 0.34, 0.26, 0.30)),
            "LegBR": (Vector((-1.12, 1.72, 2.08)), Vector((-1.30, 1.45, 1.15)), Vector((-1.18, 1.92, 0.45)), Vector((-1.22, 1.65, 0.05)), (0.44, 0.34, 0.26, 0.30)),
        }
        # Dorsal armor ridges + glowing magma belly fissures + armored horn head + spiked tail
        for p, r in zip(trunk_pts[:-1], trunk_rads[:-1]):
            add_plate_wedge(bm_body_a, p + off + Vector((0, 0, r[1] * 0.95)), Vector((0, -1, 0.2)), Vector((0, 0, 1)), 1.05, r[0] * 1.45, 0.48)
        for mi in (-0.35, 0.0, 0.35):
            add_closed_loft(bm_body_g, [Vector((mi, -1.4, 1.65)) + off, Vector((mi, -0.4, 1.50)) + off, Vector((mi, 0.8, 1.55)) + off], [(0.16, 0.12), (0.24, 0.15), (0.14, 0.10)], segs=6)
        add_closed_loft(bm_head_a, [head_pivot + off, head_pivot + Vector((0, -1.1, 0.12)) + off, head_pivot + Vector((0, -1.95, -0.10)) + off], [(0.92, 0.78), (0.78, 0.65), (0.38, 0.28)], segs=8)
        for s in (-1.0, 1.0):
            add_sharp_claw_curve(bm_head_a, head_pivot + Vector((s * 0.45, -1.1, 0.35)) + off, Vector((s * 0.35, -0.85, 0.45)), Vector((0, 0, 1)), 1.25, 0.18, 0.16, -0.25)
            add_closed_loft(bm_head_g, [head_pivot + Vector((s * 0.55, -1.25, 0.18)) + off, head_pivot + Vector((s * 0.65, -1.55, 0.12)) + off], [(0.12, 0.09), (0.04, 0.04)], segs=6)
        add_closed_loft(bm_tail_h, [tail_pivot + off, tail_pivot + Vector((0, 1.25, 0.15)) + off, tail_pivot + Vector((0, 2.45, 0.45)) + off], [(0.72, 0.64), (0.45, 0.40), (0.16, 0.15)], segs=7)
        for ti in range(3):
            add_plate_wedge(bm_tail_a, tail_pivot + Vector((0, 0.6 + ti * 0.75, 0.35 + ti * 0.15)) + off, Vector((0, 1, 0.35)), Vector((0, 0, 1)), 0.55, 0.42, 0.38)

    elif body_style == "scavenger":
        trunk_z = 1.25
        trunk_pts = [Vector((0, 0.95, 1.15)), Vector((0, 0.2, 1.28)), Vector((0, -0.5, 1.32)), Vector((0, -1.0, 1.30))]
        trunk_rads = [(0.48, 0.44), (0.62, 0.55), (0.68, 0.58), (0.52, 0.48)]
        head_pivot = Vector((0.0, -1.12, 1.30))
        tail_pivot = Vector((0.0, 1.10, 1.10))
        hips = {
            "LegFL": (Vector((0.66, -0.78, 1.18)), Vector((0.86, -0.95, 0.70)), Vector((0.76, -0.62, 0.30)), Vector((0.82, -0.82, 0.03)), (0.22, 0.16, 0.12, 0.15)),
            "LegFR": (Vector((-0.66, -0.78, 1.18)), Vector((-0.86, -0.95, 0.70)), Vector((-0.76, -0.62, 0.30)), Vector((-0.82, -0.82, 0.03)), (0.22, 0.16, 0.12, 0.15)),
            "LegBL": (Vector((0.60, 0.80, 1.12)), Vector((0.78, 0.62, 0.65)), Vector((0.70, 0.95, 0.28)), Vector((0.76, 0.76, 0.03)), (0.20, 0.15, 0.11, 0.14)),
            "LegBR": (Vector((-0.60, 0.80, 1.12)), Vector((-0.78, 0.62, 0.65)), Vector((-0.70, 0.95, 0.28)), Vector((-0.76, 0.76, 0.03)), (0.20, 0.15, 0.11, 0.14)),
        }
        add_closed_loft(bm_body_a, [Vector((0, 0.6, 1.62)) + off, Vector((0, -0.2, 1.72)) + off, Vector((0, -0.9, 1.65)) + off], [(0.38, 0.18), (0.52, 0.22), (0.36, 0.16)], segs=6)
        add_closed_loft(bm_body_g, [Vector((0, 0.3, 1.38)) + off, Vector((0, -0.5, 1.44)) + off], [(0.35, 0.24), (0.38, 0.26)], segs=6)
        add_closed_loft(bm_head_a, [head_pivot + off, head_pivot + Vector((0, -0.65, 0.08)) + off, head_pivot + Vector((0, -1.2, -0.05)) + off], [(0.42, 0.36), (0.32, 0.26), (0.12, 0.10)], segs=7)
        for s in (-1.0, 1.0):
            add_sharp_claw_curve(bm_head_a, head_pivot + Vector((s * 0.28, -0.65, 0.02)) + off, Vector((s * 0.18, -0.95, -0.1)), Vector((0, 0, 1)), 0.58, 0.07, 0.05, 0.08)
            add_closed_loft(bm_head_g, [head_pivot + Vector((s * 0.26, -0.78, 0.16)) + off, head_pivot + Vector((s * 0.20, -1.0, 0.14)) + off], [(0.08, 0.06), (0.04, 0.04)], segs=6)
        add_closed_loft(bm_tail_h, [tail_pivot + off, tail_pivot + Vector((0, 0.78, 0.18)) + off, tail_pivot + Vector((0, 1.45, 0.55)) + off], [(0.32, 0.28), (0.18, 0.16), (0.06, 0.06)], segs=6)
        add_sharp_claw_curve(bm_tail_a, tail_pivot + Vector((0, 1.25, 0.45)) + off, Vector((0, 0.65, 0.72)), Vector((0, -1, 0)), 0.62, 0.11, 0.08, 0.10)

    elif body_style == "sporecrawler":
        # Wide fungal carapace crab with glowing spore dome pods & heavy pincer legs
        trunk_z = 1.65
        trunk_pts = [Vector((0, 1.3, 1.55)), Vector((0, 0.2, 1.72)), Vector((0, -0.8, 1.78)), Vector((0, -1.4, 1.60))]
        trunk_rads = [(1.10, 0.72), (1.58, 0.92), (1.42, 0.85), (0.95, 0.65)]
        head_pivot = Vector((0.0, -1.55, 1.52))
        tail_pivot = Vector((0.0, 1.45, 1.58))
        hips = {
            "LegFL": (Vector((1.30, -1.05, 1.48)), Vector((1.88, -1.45, 1.20)), Vector((1.72, -1.05, 0.52)), Vector((1.65, -1.25, 0.04)), (0.34, 0.26, 0.19, 0.22)),
            "LegFR": (Vector((-1.30, -1.05, 1.48)), Vector((-1.88, -1.45, 1.20)), Vector((-1.72, -1.05, 0.52)), Vector((-1.65, -1.25, 0.04)), (0.34, 0.26, 0.19, 0.22)),
            "LegBL": (Vector((1.22, 1.15, 1.45)), Vector((1.80, 1.45, 1.15)), Vector((1.65, 1.05, 0.50)), Vector((1.60, 1.28, 0.04)), (0.32, 0.24, 0.18, 0.21)),
            "LegBR": (Vector((-1.22, 1.15, 1.45)), Vector((-1.80, 1.45, 1.15)), Vector((-1.65, 1.05, 0.50)), Vector((-1.60, 1.28, 0.04)), (0.32, 0.24, 0.18, 0.21)),
        }
        # Dorsal fungal dome shield + 5 bulging bioluminescent spore pustules
        add_closed_loft(bm_body_a, [Vector((0, 1.15, 2.08)) + off, Vector((0, 0.0, 2.38)) + off, Vector((0, -1.15, 2.02)) + off], [(1.25, 0.32), (1.72, 0.42), (1.10, 0.28)], segs=8)
        for px, py, pz, pr in [(0.0, 0.0, 2.72, 0.46), (0.68, 0.45, 2.42, 0.32), (-0.68, 0.45, 2.42, 0.32), (0.58, -0.55, 2.36, 0.30), (-0.58, -0.55, 2.36, 0.30)]:
            add_closed_loft(bm_body_g, [Vector((px, py, pz - pr * 0.45)) + off, Vector((px, py, pz + pr * 0.45)) + off], [(pr * 0.85, pr * 0.85), (pr * 0.42, pr * 0.42)], segs=7)
        add_closed_loft(bm_head_a, [head_pivot + off, head_pivot + Vector((0, -0.72, -0.08)) + off], [(0.75, 0.50), (0.48, 0.34)], segs=7)
        for s in (-1.0, 1.0):
            add_sharp_claw_curve(bm_head_a, head_pivot + Vector((s * 0.45, -0.45, -0.05)) + off, Vector((s * 0.22, -0.95, 0.0)), Vector((0, 0, 1)), 0.92, 0.16, 0.12, 0.08)
            add_closed_loft(bm_head_g, [head_pivot + Vector((s * 0.32, -0.60, 0.18)) + off, head_pivot + Vector((s * 0.36, -0.82, 0.16)) + off], [(0.11, 0.10), (0.06, 0.06)], segs=6)
        add_closed_loft(bm_tail_h, [tail_pivot + off, tail_pivot + Vector((0, 0.85, 0.28)) + off, tail_pivot + Vector((0, 1.45, 0.72)) + off], [(0.55, 0.42), (0.36, 0.28), (0.18, 0.15)], segs=7)
        add_sharp_claw_curve(bm_tail_a, tail_pivot + Vector((0, 1.28, 0.62)) + off, Vector((0, 0.4, 0.92)), Vector((0, -1, 0)), 0.78, 0.16, 0.12, 0.22)

    elif body_style == "spitterdrake":
        # Lean agile venom-wyvern predator with flared acid-hood, venomous neck-sac, razor tail
        trunk_z = 2.05
        trunk_pts = [Vector((0, 1.65, 1.80)), Vector((0, 0.45, 2.02)), Vector((0, -0.65, 2.15)), Vector((0, -1.65, 2.38))]
        trunk_rads = [(0.62, 0.58), (0.88, 0.78), (0.84, 0.75), (0.65, 0.62)]
        head_pivot = Vector((0.0, -1.95, 2.55))
        tail_pivot = Vector((0.0, 1.75, 1.75))
        hips = {
            "LegFL": (Vector((0.88, -1.25, 1.98)), Vector((1.12, -1.55, 1.15)), Vector((0.96, -0.98, 0.48)), Vector((1.05, -1.35, 0.04)), (0.28, 0.20, 0.15, 0.20)),
            "LegFR": (Vector((-0.88, -1.25, 1.98)), Vector((-1.12, -1.55, 1.15)), Vector((-0.96, -0.98, 0.48)), Vector((-1.05, -1.35, 0.04)), (0.28, 0.20, 0.15, 0.20)),
            "LegBL": (Vector((0.78, 1.35, 1.78)), Vector((0.98, 0.95, 1.05)), Vector((0.85, 1.55, 0.42)), Vector((0.92, 1.25, 0.04)), (0.30, 0.22, 0.15, 0.20)),
            "LegBR": (Vector((-0.78, 1.35, 1.78)), Vector((-0.98, 0.95, 1.05)), Vector((-0.85, 1.55, 0.42)), Vector((-0.92, 1.25, 0.04)), (0.30, 0.22, 0.15, 0.20)),
        }
        # Cobra venom hood & glowing toxic belly sac
        add_closed_loft(bm_body_g, [Vector((0, -1.0, 1.58)) + off, Vector((0, -1.65, 1.72)) + off], [(0.48, 0.42), (0.55, 0.48)], segs=7)
        for s in (-1.0, 1.0):
            add_plate_wedge(bm_body_a, Vector((s * 0.72, -1.42, 2.38)) + off, Vector((s * 0.45, -0.45, 0.65)), Vector((0, 0, 1)), 0.95, 0.62, 0.14)
        add_closed_loft(bm_head_a, [head_pivot + off, head_pivot + Vector((0, -1.05, 0.06)) + off, head_pivot + Vector((0, -1.85, -0.14)) + off], [(0.58, 0.48), (0.45, 0.36), (0.18, 0.14)], segs=7)
        add_closed_loft(bm_head_g, [head_pivot + Vector((0, -0.75, -0.35)) + off, head_pivot + Vector((0, -1.35, -0.38)) + off], [(0.35, 0.28), (0.18, 0.14)], segs=6)
        add_closed_loft(bm_tail_h, [tail_pivot + off, tail_pivot + Vector((0, 1.55, 0.25)) + off, tail_pivot + Vector((0, 3.10, 0.85)) + off], [(0.48, 0.44), (0.26, 0.24), (0.09, 0.08)], segs=7)
        add_plate_wedge(bm_tail_a, tail_pivot + Vector((0, 2.75, 0.78)) + off, Vector((0, 0.85, 0.42)), Vector((0, 0, 1)), 0.85, 0.35, 0.12)

    else:  # "cragback" -> ObsidianCragback3D (giant armored basalt ankylo-behemoth)
        trunk_z = 2.75
        trunk_pts = [Vector((0, 2.45, 2.45)), Vector((0, 1.0, 2.72)), Vector((0, -0.5, 2.88)), Vector((0, -2.1, 2.78))]
        trunk_rads = [(1.45, 1.15), (1.88, 1.48), (1.98, 1.52), (1.52, 1.22)]
        head_pivot = Vector((0.0, -2.55, 2.68))
        tail_pivot = Vector((0.0, 2.55, 2.42))
        hips = {
            "LegFL": (Vector((1.72, -1.82, 2.35)), Vector((1.95, -2.05, 1.35)), Vector((1.82, -1.65, 0.60)), Vector((1.86, -1.85, 0.05)), (0.58, 0.48, 0.40, 0.46)),
            "LegFR": (Vector((-1.72, -1.82, 2.35)), Vector((-1.95, -2.05, 1.35)), Vector((-1.82, -1.65, 0.60)), Vector((-1.86, -1.85, 0.05)), (0.58, 0.48, 0.40, 0.46)),
            "LegBL": (Vector((1.58, 1.92, 2.25)), Vector((1.80, 1.72, 1.25)), Vector((1.68, 2.08, 0.55)), Vector((1.72, 1.90, 0.05)), (0.54, 0.44, 0.38, 0.44)),
            "LegBR": (Vector((-1.58, 1.92, 2.25)), Vector((-1.80, 1.72, 1.25)), Vector((-1.68, 2.08, 0.55)), Vector((-1.72, 1.90, 0.05)), (0.54, 0.44, 0.38, 0.44)),
        }
        # Massive interlocking dorsal basalt crag plates + magma fissures + club tail
        for bi in range(4):
            y_pos = 1.65 - bi * 1.10
            for sx in (-0.82, 0.0, 0.82):
                add_plate_wedge(bm_body_a, Vector((sx, y_pos, 3.85 if sx == 0 else 3.55)) + off, Vector((sx * 0.25, -0.35, 0.85)), Vector((0, 0, 1)), 1.35, 0.85, 0.72)
        for mx in (-0.52, 0.0, 0.52):
            add_closed_loft(bm_body_g, [Vector((mx, 1.5, 3.42)) + off, Vector((mx, -1.6, 3.48)) + off], [(0.16, 0.14), (0.18, 0.14)], segs=6)
        add_closed_loft(bm_head_a, [head_pivot + off, head_pivot + Vector((0, -1.25, -0.05)) + off, head_pivot + Vector((0, -2.05, -0.22)) + off], [(1.18, 0.92), (1.05, 0.82), (0.68, 0.52)], segs=7)
        for s in (-1.0, 1.0):
            add_sharp_claw_curve(bm_head_a, head_pivot + Vector((s * 0.65, -1.15, 0.32)) + off, Vector((s * 0.45, -0.82, 0.42)), Vector((0, 0, 1)), 1.48, 0.22, 0.20, -0.22)
            add_closed_loft(bm_head_g, [head_pivot + Vector((s * 0.75, -1.35, 0.12)) + off, head_pivot + Vector((s * 0.82, -1.65, 0.05)) + off], [(0.14, 0.10), (0.06, 0.06)], segs=6)
        add_closed_loft(bm_tail_h, [tail_pivot + off, tail_pivot + Vector((0, 1.65, 0.18)) + off, tail_pivot + Vector((0, 3.05, 0.45)) + off], [(0.82, 0.72), (0.48, 0.42), (0.32, 0.28)], segs=7)
        # Spiked boulder club at end of tail
        club_p = tail_pivot + Vector((0, 3.25, 0.52)) + off
        add_closed_loft(bm_tail_a, [club_p - Vector((0, 0.55, 0)), club_p + Vector((0, 0.55, 0))], [(0.78, 0.72), (0.45, 0.42)], segs=7)

    # Trunk base body loft (all species)
    add_closed_loft(bm_body_h, [p + off for p in trunk_pts], trunk_rads, segs=8)

    # Limbs
    for lname, (hip, knee, ankle, foot, rads) in hips.items():
        bm_lh, bm_la = limb_bms[lname]
        add_fauna_leg(bm_lh, bm_la, hip + off, knee + off, ankle + off, foot + off, rads, has_armor_plate=True)

    # Create named Mesh Objects cleanly
    mesh_objs = []
    for suffix, bm, mat in (
        ("Body_Hide", bm_body_h, m_hide),
        ("Body_Armor", bm_body_a, m_armor),
        (f"Body_{glow_kind}", bm_body_g, m_glow),
        ("Head_Armor", bm_head_a, m_armor),
        (f"Head_{glow_kind}", bm_head_g, m_glow),
        ("Tail_Hide", bm_tail_h, m_hide),
        ("Tail_Armor", bm_tail_a, m_armor),
    ):
        if len(bm.faces) > 0:
            nm = f"{prefix}_{suffix}"
            create_mesh_obj(nm, bm, mat, col)
            mesh_objs.append(nm)
        else:
            bm.free()

    for lname, (bm_lh, bm_la) in limb_bms.items():
        if len(bm_lh.faces) > 0:
            nm = f"{prefix}_{lname}_Hide"
            create_mesh_obj(nm, bm_lh, m_hide, col)
            mesh_objs.append(nm)
        else:
            bm_lh.free()
        if len(bm_la.faces) > 0:
            nm = f"{prefix}_{lname}_Armor"
            create_mesh_obj(nm, bm_la, m_armor, col)
            mesh_objs.append(nm)
        else:
            bm_la.free()

    trunk_pos = Vector((0.0, 0.0, trunk_z))
    return {
        "species": species_name,
        "prefix": prefix,
        "offsetRoblox": blender_to_roblox_pos(off),
        "trunkPos": blender_to_roblox_pos(trunk_pos),
        "pivots": {
            "Head": blender_to_roblox_pos(head_pivot),
            "Tail": blender_to_roblox_pos(tail_pivot),
            "LegFL": blender_to_roblox_pos(hips["LegFL"][0]),
            "LegFR": blender_to_roblox_pos(hips["LegFR"][0]),
            "LegBL": blender_to_roblox_pos(hips["LegBL"][0]),
            "LegBR": blender_to_roblox_pos(hips["LegBR"][0]),
        },
        "meshes": mesh_objs,
    }


def build_abyssal_nest_prop(col: bpy.types.Collection, offset_x: float) -> dict:
    """Sunken Predator Evolution Nest (radius ~12 studs, height ~11 studs)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_rock = make_mat("Mat_Nest_Basalt", (0.09, 0.09, 0.11), roughness=0.82)
    m_bone = make_mat("Mat_Nest_Bone", (0.76, 0.69, 0.58), roughness=0.55)
    m_flesh = make_mat("Mat_Nest_Flesh", (0.24, 0.08, 0.10), roughness=0.62)
    m_egg = make_mat("Mat_Nest_Cocoon", (0.35, 0.10, 0.08), roughness=0.38)
    m_magma = make_mat("Mat_Nest_Ember", (1.0, 0.30, 0.06), roughness=0.18, emission=2.8)

    bm_rock, bm_ribs, bm_webs, bm_eggs, bm_core = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()

    # Sunken volcanic crater bowl (10 segments ring)
    ring_segs = 10
    for i in range(ring_segs):
        a0 = 2.0 * math.pi * i / ring_segs
        a1 = 2.0 * math.pi * (i + 1) / ring_segs
        p0 = Vector((math.cos(a0) * 10.2, math.sin(a0) * 10.2, 0.2)) + off
        p1 = Vector((math.cos(a1) * 10.2, math.sin(a1) * 10.2, 0.2)) + off
        pm = (p0 + p1) * 0.5 + Vector((math.cos((a0 + a1) * 0.5) * 1.4, math.sin((a0 + a1) * 0.5) * 1.4, 2.2))
        add_closed_loft(bm_rock, [p0, pm, p1], [(2.2, 1.3), (2.6, 2.2), (2.2, 1.3)], segs=6)

        # Towering inward-arching leviathan fossil ribs forming predator shrine cage
        r_dir = Vector((math.cos(a0), math.sin(a0), 0.0))
        rib_pts = [
            r_dir * 9.8 + Vector((0, 0, 1.2)) + off,
            r_dir * 11.4 + Vector((0, 0, 5.2)) + off,
            r_dir * 7.8 + Vector((0, 0, 9.2)) + off,
            r_dir * 4.5 + Vector((0, 0, 10.8)) + off,
        ]
        add_closed_loft(bm_ribs, rib_pts, [(0.62, 0.45), (0.55, 0.40), (0.38, 0.28), (0.08, 0.08)], segs=6)

        # Torn flesh-sinew webbing draped between adjacent ribs
        if i % 2 == 0:
            r_mid = Vector((math.cos(a0 + math.pi / ring_segs), math.sin(a0 + math.pi / ring_segs), 0.0))
            add_closed_loft(
                bm_webs,
                [r_dir * 9.5 + Vector((0, 0, 5.5)) + off, r_mid * 8.4 + Vector((0, 0, 3.8)) + off, Vector((math.cos(a1), math.sin(a1), 0)) * 9.5 + Vector((0, 0, 5.5)) + off],
                [(0.32, 0.14), (0.48, 0.18), (0.32, 0.14)],
                segs=5,
            )

    # Central metamorphosis crater floor + organic egg-sac nodes
    add_closed_loft(bm_core, [off + Vector((0, 0, 0.05)), off + Vector((0, 0, 0.65))], [(6.8, 6.8), (4.6, 4.6)], segs=8)
    for ang, dist, h in [(0.3, 4.2, 3.2), (2.1, 4.8, 3.8), (4.0, 4.0, 3.0), (5.3, 4.6, 3.5)]:
        ep = Vector((math.cos(ang) * dist, math.sin(ang) * dist, 0.4)) + off
        add_closed_loft(bm_eggs, [ep, ep + Vector((0, 0, h * 0.55)), ep + Vector((0, 0, h))], [(1.05, 1.05), (1.35, 1.35), (0.45, 0.45)], segs=7)

    names = []
    for suf, bm, m in (
        ("BaseRock", bm_rock, m_rock),
        ("RibCage", bm_ribs, m_bone),
        ("FleshWebs", bm_webs, m_flesh),
        ("EggCluster", bm_eggs, m_egg),
        ("MagmaCore", bm_core, m_magma),
    ):
        nm = f"Nest3D_{suf}"
        create_mesh_obj(nm, bm, m, col)
        names.append(nm)
    return {"offsetRoblox": blender_to_roblox_pos(off), "meshes": names}


def build_corrupted_outpost_prop(col: bpy.types.Collection, offset_x: float) -> dict:
    """Claw-torn AEM Research Relay / Generator Ruin (~11 studs tall)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_conc = make_mat("Mat_Outpost_Concrete", (0.20, 0.21, 0.22), roughness=0.88)
    m_steel = make_mat("Mat_Outpost_Steel", (0.14, 0.16, 0.19), metallic=0.55, roughness=0.45)
    m_mach = make_mat("Mat_Outpost_Machinery", (0.36, 0.28, 0.14), metallic=0.35, roughness=0.55)
    m_claw = make_mat("Mat_Outpost_WebSlash", (0.06, 0.06, 0.08), roughness=0.65)
    m_warn = make_mat("Mat_Outpost_Warning", (1.0, 0.16, 0.08), roughness=0.20, emission=3.0)

    bm_c, bm_s, bm_m, bm_w, bm_g = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()

    # Heavy tilted concrete foundation pad
    add_closed_loft(bm_c, [off + Vector((0, 0, 0.0)), off + Vector((0.2, 0.1, 0.9))], [(4.2, 3.6), (3.8, 3.2)], segs=6)
    # 4 corner steel I-pillars + upper radio mast leaning 8 degrees from Monster slam
    for px, py in [(-2.6, -2.0), (2.6, -2.0), (-2.6, 2.0), (2.6, 2.0)]:
        add_closed_loft(bm_s, [Vector((px, py, 0.8)) + off, Vector((px + 0.35, py + 0.15, 5.4)) + off], [(0.34, 0.34), (0.28, 0.28)], segs=5)
    # Roof comms truss + bent radar mast
    add_closed_loft(bm_s, [Vector((0.2, 0.1, 5.4)) + off, Vector((0.4, 0.2, 6.2)) + off], [(3.4, 2.8), (3.2, 2.6)], segs=6)
    add_closed_loft(bm_s, [Vector((0.4, 0.2, 6.2)) + off, Vector((1.6, -0.5, 11.4)) + off], [(0.32, 0.32), (0.14, 0.14)], segs=6)
    # Torn field generator & power cell unit inside shelter
    add_closed_loft(bm_m, [Vector((0.0, -0.6, 0.9)) + off, Vector((0.2, -0.6, 3.8)) + off], [(1.8, 1.2), (1.6, 1.1)], segs=6)
    # 3 diagonal predator claw-tear steel ribs + hanging severed cables
    for ci in range(3):
        add_sharp_claw_curve(bm_w, Vector((-1.8 + ci * 1.1, -1.8, 4.4)) + off, Vector((0.65, -0.15, -0.75)), Vector((0, -1, 0)), 3.8, 0.12, 0.08, 0.45)
    # Beacon strobe orb atop bent mast & emergency bulkhead strip
    add_closed_loft(bm_g, [Vector((1.55, -0.45, 11.2)) + off, Vector((1.72, -0.55, 11.9)) + off], [(0.42, 0.42), (0.22, 0.22)], segs=6)
    add_closed_loft(bm_g, [Vector((-1.2, -1.85, 3.2)) + off, Vector((1.2, -1.85, 3.3)) + off], [(0.14, 0.10), (0.14, 0.10)], segs=5)

    names = []
    for suf, bm, m in (
        ("ConcreteBase", bm_c, m_conc),
        ("SteelFrame", bm_s, m_steel),
        ("Machinery", bm_m, m_mach),
        ("VinesSlashes", bm_w, m_claw),
        ("WarningGlow", bm_g, m_warn),
    ):
        nm = f"Outpost3D_{suf}"
        create_mesh_obj(nm, bm, m, col)
        names.append(nm)
    return {"offsetRoblox": blender_to_roblox_pos(off), "meshes": names}


def build_bone_totem_prop(col: bpy.types.Collection, offset_x: float) -> dict:
    """Hunter-warning Obsidian & Leviathan Bone Territorial Totem (~10 studs tall)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_basalt = make_mat("Mat_Totem_Basalt", (0.08, 0.08, 0.10), roughness=0.80)
    m_bone = make_mat("Mat_Totem_Bone", (0.82, 0.76, 0.64), roughness=0.48)
    m_hide = make_mat("Mat_Totem_Hide", (0.18, 0.11, 0.13), roughness=0.72)
    m_rune = make_mat("Mat_Totem_Runes", (1.0, 0.36, 0.10), roughness=0.18, emission=2.6)

    bm_c, bm_b, bm_s, bm_r = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    add_closed_loft(bm_c, [off + Vector((0, 0, 0.0)), off + Vector((0, 0, 1.8))], [(2.8, 2.8), (1.9, 1.9)], segs=7)
    # Impaled central spire bone + crossed curved rib-stakes
    add_closed_loft(bm_b, [off + Vector((0, 0, 1.4)), off + Vector((0.15, -0.1, 6.2)), off + Vector((0.35, -0.2, 10.2))], [(0.62, 0.55), (0.42, 0.36), (0.10, 0.10)], segs=6)
    for a in (0.4, 2.5, 4.6):
        d = Vector((math.cos(a), math.sin(a), 0.0))
        add_sharp_claw_curve(bm_b, off + d * 1.4 + Vector((0, 0, 1.4)), Vector((d.x * 0.45, d.y * 0.45, 0.85)), d, 5.4, 0.28, 0.22, -0.6)
    # Torn beast hide banner hanging from crossbar + skull trophy
    add_closed_loft(bm_s, [off + Vector((-1.4, 0, 6.5)), off + Vector((0, 0, 6.8)), off + Vector((1.4, 0, 6.5))], [(0.24, 0.22), (0.55, 0.45), (0.24, 0.22)], segs=6)
    add_closed_loft(bm_r, [off + Vector((0.1, -0.58, 3.2)), off + Vector((0.2, -0.45, 5.8))], [(0.22, 0.14), (0.14, 0.10)], segs=5)

    names = []
    for suf, bm, m in (
        ("Cairn", bm_c, m_basalt),
        ("Bones", bm_b, m_bone),
        ("HideBanner", bm_s, m_hide),
        ("Runes", bm_r, m_rune),
    ):
        nm = f"Totem3D_{suf}"
        create_mesh_obj(nm, bm, m, col)
        names.append(nm)
    return {"offsetRoblox": blender_to_roblox_pos(off), "meshes": names}


def build_biolum_tree_prop(col: bpy.types.Collection, offset_x: float) -> dict:
    """Twisted Alien Coastal Mangrove / Spore Tree with hanging Lantern Pods (~22 studs tall)."""
    off = Vector((offset_x, 0.0, 0.0))
    m_bark = make_mat("Mat_Tree_Bark", (0.11, 0.10, 0.10), roughness=0.86)
    m_vines = make_mat("Mat_Tree_Vines", (0.13, 0.18, 0.14), roughness=0.72)
    m_pod = make_mat("Mat_Tree_SporeLantern", (0.18, 0.88, 0.72), roughness=0.18, emission=2.4)

    bm_bark, bm_vines, bm_pods = bmesh.new(), bmesh.new(), bmesh.new()
    # Main twisted gnarled trunk + 4 buttress roots
    add_closed_loft(
        bm_bark,
        [off + Vector((0, 0, 0.0)), off + Vector((0.6, -0.4, 6.0)), off + Vector((-0.8, 0.5, 13.5)), off + Vector((0.4, 0.2, 19.5))],
        [(1.85, 1.85), (1.35, 1.30), (0.98, 0.92), (0.42, 0.42)],
        segs=7,
    )
    for ra in (0.2, 1.7, 3.4, 5.0):
        rd = Vector((math.cos(ra), math.sin(ra), 0.0))
        add_closed_loft(bm_bark, [off + rd * 4.2 + Vector((0, 0, 0.0)), off + rd * 2.1 + Vector((0, 0, 2.8)), off + rd * 1.1 + Vector((0, 0, 5.6))], [(0.65, 0.52), (0.52, 0.42), (0.45, 0.45)], segs=5)
    # 5 sweeping crooked canopy boughs + hanging tendril vines + spore lantern pods
    for bi in range(5):
        ba = 2.0 * math.pi * bi / 5.0 + 0.3
        bd = Vector((math.cos(ba), math.sin(ba), 0.0))
        tip = off + Vector((0.0, 0.0, 17.5 + (bi % 2) * 2.2)) + bd * 7.8
        add_closed_loft(bm_bark, [off + Vector((0.0, 0.0, 14.5)), off + bd * 3.8 + Vector((0, 0, 17.2)), tip], [(0.55, 0.52), (0.38, 0.35), (0.14, 0.14)], segs=5)
        add_closed_loft(bm_vines, [tip, tip - Vector((0, 0, 3.4)), tip - Vector((0, 0, 6.2))], [(0.35, 0.35), (0.58, 0.48), (0.14, 0.14)], segs=5)
        pod_p = tip - Vector((0, 0, 6.4))
        add_closed_loft(bm_pods, [pod_p + Vector((0, 0, 0.45)), pod_p, pod_p - Vector((0, 0, 0.65))], [(0.16, 0.16), (0.42, 0.42), (0.12, 0.12)], segs=6)

    names = []
    for suf, bm, m in (("Bark", bm_bark, m_bark), ("VinesCanopy", bm_vines, m_vines), ("SporeLanterns", bm_pods, m_pod)):
        nm = f"SporeTree3D_{suf}"
        create_mesh_obj(nm, bm, m, col)
        names.append(nm)
    return {"offsetRoblox": blender_to_roblox_pos(off), "meshes": names}


def render_v3_preview() -> None:
    """Loads both GLBs side-by-side into a clean showcase stage and renders previews/cruel_monster_fauna_nest_v3.png."""
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=OUT_MONSTER_GLB)
    for o in bpy.context.selected_objects:
        o.location.x -= 8.0

    bpy.ops.import_scene.gltf(filepath=OUT_BIO_GLB)

    scene = bpy.context.scene
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.filepath = OUT_PREVIEW

    world = bpy.data.worlds.new("DuskPreview")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.04, 0.05, 0.06, 1.0)
        bg.inputs[1].default_value = 1.2

    # Key + crimson rim light
    sun_d = bpy.data.lights.new("DuskKey", type="SUN")
    sun_d.energy = 3.2
    sun_d.color = (1.0, 0.85, 0.68)
    sun_o = bpy.data.objects.new("DuskKey", sun_d)
    sun_o.rotation_euler = (math.radians(52), 0.0, math.radians(-35))
    scene.collection.objects.link(sun_o)

    rim_d = bpy.data.lights.new("HorrorRim", type="AREA")
    rim_d.energy = 4500.0
    rim_d.size = 24.0
    rim_d.color = (0.25, 0.72, 0.95)
    rim_o = bpy.data.objects.new("HorrorRim", rim_d)
    rim_o.location = (80.0, 38.0, 26.0)
    scene.collection.objects.link(rim_o)

    cam_d = bpy.data.cameras.new("PreviewCam")
    cam_d.lens = 28.0
    cam_o = bpy.data.objects.new("PreviewCam", cam_d)
    cam_o.location = (65.0, -78.0, 26.0)
    direction = Vector((82.0, 0.0, 5.5)) - cam_o.location
    cam_o.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam_o)
    scene.camera = cam_o

    os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    assert_no_overwrites()

    # 1. Monster v3
    monster_manifest = build_cruel_monster_glb()

    # 2. 5 Fauna + 4 Horror Map Props v3
    clear_scene()
    col = bpy.data.collections.new("BioAndPropsV3")
    bpy.context.scene.collection.children.link(col)
    add_origin_marker(col, "ORIGIN_MARKER")

    fauna_defs = [
        ("RedGoliath", "Goliath3D", 0.0, {"Hide": (0.24, 0.09, 0.08), "Armor": (0.11, 0.10, 0.13), "Magma": (1.0, 0.34, 0.08)}, "Magma", "goliath"),
        ("CoastalScavenger", "Scavenger3D", 20.0, {"Hide": (0.14, 0.22, 0.24), "Armor": (0.10, 0.13, 0.16), "Glow": (0.20, 0.90, 0.85)}, "Glow", "scavenger"),
        ("SporeCrawler", "SporeCrawler3D", 40.0, {"Hide": (0.16, 0.20, 0.14), "Armor": (0.12, 0.11, 0.15), "SporeGlow": (0.45, 0.98, 0.32)}, "SporeGlow", "sporecrawler"),
        ("AcidSpitterDrake", "AcidDrake3D", 60.0, {"Hide": (0.12, 0.16, 0.18), "Armor": (0.09, 0.11, 0.12), "Venom": (0.55, 1.0, 0.16)}, "Venom", "spitterdrake"),
        ("ObsidianCragback", "Cragback3D", 80.0, {"Hide": (0.10, 0.09, 0.10), "Armor": (0.06, 0.06, 0.08), "Magma": (1.0, 0.28, 0.05)}, "Magma", "cragback"),
    ]
    fauna_manifests = []
    for sp, pref, ox, cols, gk, st in fauna_defs:
        fauna_manifests.append(build_fauna_species(sp, pref, col, ox, cols, gk, st))

    props_manifest = {
        "AbyssalNest3D": build_abyssal_nest_prop(col, 120.0),
        "CorruptedAEMOutpost3D": build_corrupted_outpost_prop(col, 155.0),
        "BoneTotemShrine3D": build_bone_totem_prop(col, 180.0),
        "BiolumSporeTree3D": build_biolum_tree_prop(col, 200.0),
    }

    bpy.ops.export_scene.gltf(
        filepath=OUT_BIO_GLB,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )

    manifest = {
        "monster": monster_manifest,
        "fauna": fauna_manifests,
        "props": props_manifest,
        "bioTotalMeshCount": 1 + sum(len(f["meshes"]) for f in fauna_manifests) + sum(len(p["meshes"]) for p in props_manifest.values()),
    }
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)

    render_v3_preview()
    print("V3 BUILD COMPLETE:", json.dumps({"monsterMeshes": monster_manifest["meshCount"], "bioMeshes": manifest["bioTotalMeshCount"]}))


if __name__ == "__main__":
    main()
