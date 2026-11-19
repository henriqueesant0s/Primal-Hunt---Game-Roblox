"""Primal Hunt v4 — Colossal 22-Stud Monster + Lush Multi-Color Blender Trees + Destruction Debris.

Strict non-overwrite policy: writes only new *_v4 artifacts.
Builds:
1. PrimalHunt_ColossalMonster_v4.glb
   - Rest-pose extraction from AbyssMonster.blend across 17 Motor6D joints & 6 Material buckets
   - Target Stage-1 height = 22.0 studs (Stage 2 1.35x = 29.7 studs, Stage 3 1.75x = 38.5 studs)
   - Cruel anatomical upgrades baked per-joint (mandibles, gullet fangs, forearm scythe blades,
     upper/lower hooked gore-talons, dorsal neural spines, barbed harpoon tentacle tips)
2. PrimalHunt_LushTreesAndDestruction_v4.glb
   - 3 Lush Multi-Color 3D Tree Kits at X = 0, 28, 56:
     JungleCanopyTree3D, SwampMangroveTree3D, CrimsonMossTree3D
   - 3 Monster Destruction 3D Debris Assets at X = 84, 98, 110:
     ShatteredTreeStump3D, SplinteredLogChunk3D, CrushedRockDebris3D
3. colossal_monster_trees_v4_manifest.json + previews/colossal_monster_trees_destruction_v4.png
"""

from __future__ import annotations

import json
import math
import os
from collections import defaultdict
from typing import Dict, List, Sequence, Tuple

import bmesh
import bpy
from mathutils import Vector

ROOT = r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt"
SOURCE_BLEND = os.path.join(ROOT, "AbyssMonster.blend")
OUT_MONSTER_GLB = os.path.join(ROOT, "PrimalHunt_ColossalMonster_v4.glb")
OUT_TREES_GLB = os.path.join(ROOT, "PrimalHunt_LushTreesAndDestruction_v4.glb")
OUT_MANIFEST = os.path.join(ROOT, "colossal_monster_trees_v4_manifest.json")
OUT_PREVIEW = os.path.join(ROOT, "previews", "colossal_monster_trees_destruction_v4.png")

TARGET_STAGE1_HEIGHT_STUDS = 22.0

BONE_TO_JOINT: Dict[str, str] = {
    "root": "Pelvis", "pelvis": "Pelvis", "spine_1": "Pelvis",
    "spine_2": "Chest", "spine_3": "Chest", "neck": "Chest",
    "head": "Head",
    "crown_0_1": "CrownL", "crown_0_2": "CrownL", "crown_1_1": "CrownL", "crown_1_2": "CrownL",
    "crown_2_1": "CrownL", "crown_2_2": "CrownL", "crown_3_1": "CrownL", "crown_3_2": "CrownL",
    "crown_4_1": "CrownR", "crown_4_2": "CrownR", "crown_5_1": "CrownR", "crown_5_2": "CrownR",
    "crown_6_1": "CrownR", "crown_6_2": "CrownR", "crown_7_1": "CrownR", "crown_7_2": "CrownR",
    "arm_up_sh_l": "ArmUpL", "arm_up_up_l": "ArmUpL",
    "arm_up_lo_l": "ForeUpL", "arm_up_hd_l": "ForeUpL",
    "arm_up_sh_r": "ArmUpR", "arm_up_up_r": "ArmUpR",
    "arm_up_lo_r": "ForeUpR", "arm_up_hd_r": "ForeUpR",
    "arm_lo_up_l": "ArmLoL", "arm_lo_lo_l": "ArmLoL", "arm_lo_hd_l": "ArmLoL",
    "arm_lo_up_r": "ArmLoR", "arm_lo_lo_r": "ArmLoR", "arm_lo_hd_r": "ArmLoR",
    "tent_0_1": "Tent0", "tent_0_2": "Tent0", "tent_0_3": "Tent0", "tent_0_4": "Tent0", "tent_0_5": "Tent0",
    "tent_1_1": "Tent1", "tent_1_2": "Tent1", "tent_1_3": "Tent1", "tent_1_4": "Tent1", "tent_1_5": "Tent1",
    "tent_2_1": "Tent2", "tent_2_2": "Tent2", "tent_2_3": "Tent2", "tent_2_4": "Tent2", "tent_2_5": "Tent2",
    "tent_3_1": "Tent3", "tent_3_2": "Tent3", "tent_3_3": "Tent3", "tent_3_4": "Tent3", "tent_3_5": "Tent3",
    "tent_4_1": "Tent4", "tent_4_2": "Tent4", "tent_4_3": "Tent4", "tent_4_4": "Tent4", "tent_4_5": "Tent4",
    "tent_5_1": "Tent5", "tent_5_2": "Tent5", "tent_5_3": "Tent5", "tent_5_4": "Tent5", "tent_5_5": "Tent5",
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
    for p in (OUT_MONSTER_GLB, OUT_TREES_GLB, OUT_MANIFEST, OUT_PREVIEW):
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
    mat = make_mat("Mat_OriginMarker", (0.2, 0.2, 0.2), roughness=0.9)
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
            tan = Vector((0.0, 0.0, 1.0))
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


def add_foliage_cluster(bm: bmesh.types.BMesh, center: Vector, rx: float, ry: float, rz: float, tilt_ang: float = 0.0) -> None:
    """Adds a layered organic leaf-frond cluster dome (flattened polygonal bough canopy)."""
    pts = [
        center + Vector((0.0, 0.0, -rz * 0.42)),
        center,
        center + Vector((math.cos(tilt_ang) * rx * 0.12, math.sin(tilt_ang) * ry * 0.12, rz * 0.55)),
        center + Vector((math.cos(tilt_ang) * rx * 0.18, math.sin(tilt_ang) * ry * 0.18, rz * 0.92)),
    ]
    rads = [
        (rx * 0.72, ry * 0.72),
        (rx * 1.05, ry * 1.05),
        (rx * 0.78, ry * 0.78),
        (rx * 0.24, ry * 0.24),
    ]
    add_closed_loft(bm, pts, rads, segs=7, cap_start=True, cap_end=True)


def add_cruel_monster_geometry(
    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh],
    bones: Dict[str, Tuple[Vector, Vector]],
    norm_fn,
) -> None:
    def add_scaled_loft(key: Tuple[str, str, str], pts: Sequence[Vector], rads: Sequence[Tuple[float, float]], segs: int = 7) -> None:
        bm = buckets[key]
        scaled_pts = [norm_fn(p) for p in pts]
        s = (norm_fn(Vector((1, 0, 0))) - norm_fn(Vector((0, 0, 0)))).length
        add_closed_loft(bm, scaled_pts, [(rx * s, ry * s) for rx, ry in rads], segs=segs, cap_start=True, cap_end=True)

    def add_scaled_claw(key: Tuple[str, str, str], base: Vector, fwd: Vector, up: Vector, length: float, rx: float, ry: float, drop: float, steps: int = 5, segs: int = 6) -> None:
        s = (norm_fn(Vector((1, 0, 0))) - norm_fn(Vector((0, 0, 0)))).length
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

    for side in (-1.0, 1.0):
        m_pts = [
            Vector((side * 0.24, head_pos.y - 0.10, head_pos.z - 0.08)),
            Vector((side * 0.44, head_pos.y - 0.50, head_pos.z - 0.22)),
            Vector((side * 0.36, head_pos.y - 0.80, head_pos.z - 0.16)),
            Vector((side * 0.13, head_pos.y - 0.94, head_pos.z - 0.04)),
        ]
        add_scaled_loft(("Head", "All", "Carapace"), m_pts, [(0.115, 0.105), (0.10, 0.09), (0.08, 0.065), (0.018, 0.018)], segs=7)
        add_scaled_claw(("Head", "All", "Bone"), Vector((side * 0.18, head_pos.y - 0.82, head_pos.z - 0.09)), Vector((-side * 0.35, -0.85, 0.38)), Vector((0.0, 0.0, 1.0)), 0.30, 0.038, 0.026, 0.04, steps=4)
        eye_pts = [
            Vector((side * 0.14, head_pos.y - 0.48, head_pos.z + 0.31)),
            Vector((side * 0.28, head_pos.y - 0.44, head_pos.z + 0.35)),
            Vector((side * 0.39, head_pos.y - 0.34, head_pos.z + 0.40)),
        ]
        add_scaled_loft(("Head", "All", "Neon"), eye_pts, [(0.016, 0.014), (0.038, 0.024), (0.014, 0.010)], segs=6)

        for fi in range(5):
            ft = fi / 4.0
            fx = side * (0.05 + ft * 0.21)
            fy = head_pos.y - (0.68 - ft * 0.16)
            add_scaled_claw(("Head", "All", "Bone"), Vector((fx, fy, head_pos.z + 0.02)), Vector((-side * 0.08, -0.35, -0.92)), Vector((0.0, -1.0, 0.0)), 0.24 - fi * 0.015, 0.026, 0.022, 0.05, steps=4)
            add_scaled_claw(("Head", "All", "Bone"), Vector((fx * 1.15, fy - 0.04, head_pos.z - 0.16)), Vector((-side * 0.10, -0.45, 0.88)), Vector((0.0, -1.0, 0.0)), 0.21 - fi * 0.012, 0.024, 0.019, 0.04, steps=4)

    for jname, s_name_elbow, s_name_hand in (("ForeUpL", "arm_up_lo_l", "arm_up_hd_l"), ("ForeUpR", "arm_up_lo_r", "arm_up_hd_r")):
        side = 1.0 if s_name_elbow.endswith("_l") else -1.0
        eb = bones[s_name_elbow][0]
        hb = bones[s_name_hand][0]
        arm_dir = (hb - eb).normalized()
        out_dir = Vector((side * 0.55, 0.45, -0.68)).normalized()

        scythe_mount = [
            eb + arm_dir * 0.12 + Vector((0.0, 0.10, -0.05)),
            eb + arm_dir * 0.55 + out_dir * 0.36,
            hb + arm_dir * 0.38 + out_dir * 0.56,
            hb + arm_dir * 0.74 + out_dir * 0.28 + Vector((0.0, -0.45, -0.35)),
        ]
        add_scaled_loft((jname, "All", "Carapace"), scythe_mount, [(0.12, 0.075), (0.15, 0.055), (0.11, 0.038), (0.02, 0.015)], segs=6)
        blade_pts = [
            eb + arm_dir * 0.32 + out_dir * 0.38,
            hb + arm_dir * 0.20 + out_dir * 0.82,
            hb + arm_dir * 0.65 + out_dir * 0.72 + Vector((0.0, -0.58, -0.48)),
            hb + arm_dir * 0.90 + Vector((side * 0.24, -0.98, -0.86)),
        ]
        add_scaled_loft((jname, "All", "Bone"), blade_pts, [(0.065, 0.024), (0.11, 0.026), (0.085, 0.022), (0.012, 0.010)], segs=6)

        for off_y, off_z, len_c, sweep in [(-0.18, 0.08, 0.96, -0.25), (-0.04, 0.12, 1.10, -0.15), (0.09, 0.04, 1.00, 0.02), (-0.22, -0.09, 0.72, -0.40)]:
            add_scaled_claw((jname, "All", "Bone"), hb + Vector((side * 0.22, off_y, off_z)), Vector((side * 0.65, -0.58 + sweep * 0.3, -0.42)), Vector((-side * 0.3, -0.5, 0.75)), len_c, 0.058, 0.040, len_c * 0.38, steps=5, segs=6)

    for jname, s_name_hand in (("ArmLoL", "arm_lo_hd_l"), ("ArmLoR", "arm_lo_hd_r")):
        side = 1.0 if s_name_hand.endswith("_l") else -1.0
        hb = bones[s_name_hand][0]
        for off_x, off_y, len_c in [(-0.08, -0.05, 0.82), (0.0, -0.12, 0.92), (0.08, 0.02, 0.78)]:
            add_scaled_claw((jname, "All", "Bone"), hb + Vector((side * off_x, off_y, -0.04)), Vector((side * 0.35, -0.55, -0.75)), Vector((0.0, -0.6, 0.8)), len_c, 0.044, 0.032, len_c * 0.32, steps=4)

    for jname, base_p, sp_len in [
        ("Pelvis", bones["pelvis"][0] + Vector((0.0, 0.42, 0.10)), 0.58),
        ("Pelvis", bones["spine_1"][0] + Vector((0.0, 0.50, 0.12)), 0.72),
        ("Chest", bones["spine_2"][0] + Vector((0.0, 0.58, 0.12)), 0.86),
        ("Chest", (bones["spine_2"][0] + bones["spine_3"][0]) * 0.5 + Vector((0.0, 0.62, 0.10)), 0.98),
        ("Chest", bones["spine_3"][0] + Vector((0.0, 0.60, 0.08)), 1.12),
        ("Chest", bones["neck"][0] + Vector((0.0, 0.44, 0.05)), 0.82),
    ]:
        add_scaled_claw((jname, "All", "Carapace"), base_p - Vector((0.0, 0.14, 0.0)), Vector((0.0, 0.85, 0.52)), Vector((0.0, -0.5, 0.85)), sp_len * 0.64, 0.10, 0.145, -sp_len * 0.08, steps=4)
        add_scaled_claw((jname, "All", "Bone"), base_p + Vector((0.0, 0.22, 0.14)), Vector((0.0, 0.78, 0.62)), Vector((0.0, -0.6, 0.8)), sp_len * 0.72, 0.052, 0.092, sp_len * 0.18, steps=4)

    for ti in range(6):
        jname = f"Tent{ti}"
        h4, _t4 = bones[f"tent_{ti}_4"]
        h5, t5 = bones[f"tent_{ti}_5"]
        tan = (t5 - h5)
        if tan.length < 1e-4:
            tan = t5 - h4
        tan = tan.normalized()
        rx, ry = frame_on_tangent(tan)
        add_scaled_loft((jname, "All", "Carapace"), [t5 - tan * 0.22, t5, t5 + tan * 0.22], [(0.095, 0.095), (0.145, 0.145), (0.045, 0.045)], segs=7)
        add_scaled_claw((jname, "All", "Bone"), t5 - tan * 0.05, tan, ry, 0.72, 0.072, 0.044, 0.10, steps=4)
        for side in (-1.0, 1.0):
            barb_dir = (-tan * 0.75 + rx * (side * 0.66)).normalized()
            add_scaled_claw((jname, "All", "Bone"), t5 + tan * 0.08 + rx * (side * 0.04), barb_dir, ry, 0.40, 0.038, 0.026, 0.06, steps=3)


def build_colossal_monster_glb() -> dict:
    bpy.ops.wm.open_mainfile(filepath=SOURCE_BLEND)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    bones_local: Dict[str, Tuple[Vector, Vector]] = {
        b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones
    }

    min_z, max_z = 1e9, -1e9
    xs: List[float] = []
    ys: List[float] = []
    for mname, sk, _, _ in CANONICAL_MONSTER_SOURCES:
        obj = bpy.data.objects[mname]
        for v in obj.data.vertices:
            xs.append(v.co.x)
            ys.append(v.co.y)
            if sk in ("All", "S1"):
                min_z = min(min_z, v.co.z)
                max_z = max(max_z, v.co.z)

    center_x = 0.5 * (min(xs) + max(xs))
    center_y = 0.5 * (min(ys) + max(ys))
    scale_s = TARGET_STAGE1_HEIGHT_STUDS / max(0.5, max_z - min_z)

    def norm_pt(co: Vector) -> Vector:
        return Vector(((co.x - center_x) * scale_s, (co.y - center_y) * scale_s, (co.z - min_z) * scale_s))

    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh] = defaultdict(bmesh.new)

    for mname, stage_key, _, _ in CANONICAL_MONSTER_SOURCES:
        obj = bpy.data.objects[mname]
        me = obj.data
        vg_names = {g.index: g.name for g in obj.vertex_groups}
        mats = list(me.materials)

        v_joint: List[str] = []
        for v in me.vertices:
            best_w, best_j = -1.0, "Pelvis"
            for g in v.groups:
                bname = vg_names.get(g.group, "")
                if bname in BONE_TO_JOINT and g.weight > best_w:
                    best_w, best_j = g.weight, BONE_TO_JOINT[bname]
            v_joint.append(best_j)

        vert_cache: Dict[Tuple[str, str, str, int], bmesh.types.BMVert] = {}
        for poly in me.polygons:
            if len(poly.vertices) < 3:
                continue
            mat_name = mats[poly.material_index].name if poly.material_index < len(mats) and mats[poly.material_index] else "Mat_Monster_AbyssalHide"
            mbucket = MAT_TO_BUCKET.get(mat_name, "Hide")
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
                    bv = bm.verts.new(norm_pt(me.vertices[vi].co))
                    vert_cache[ckey] = bv
                fverts.append(bv)
            try:
                bm.faces.new(fverts)
            except ValueError:
                pass

    add_cruel_monster_geometry(buckets, bones_local, norm_pt)

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
    joint_pivots = {j: blender_to_roblox_pos(norm_pt(pt)) for j, pt in pivot_src.items()}

    clear_scene()
    col = bpy.data.collections.new("ColossalMonsterV4")
    bpy.context.scene.collection.children.link(col)
    add_origin_marker(col, "ORIGIN_MARKER")

    mat_map = {
        bname: make_mat(f"Mat_Monster_{bname}", (r, g, b), metallic=0.2 if bname in ("Bronze", "Carapace") else 0.0, roughness=rough, emission=em)
        for bname, (r, g, b, rough, em) in BUCKET_RGB.items()
    }

    mesh_entries = []
    for (jname, stage_key, mbucket), bm in sorted(buckets.items()):
        if len(bm.faces) == 0:
            bm.free()
            continue
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        part_name = f"MArt_{jname}_{stage_key}_{mbucket}"
        create_mesh_obj(part_name, bm, mat_map[mbucket], col)
        minS, maxS = STAGE_RANGE[stage_key]
        mesh_entries.append({"name": part_name, "joint": jname, "mat": mbucket, "minStage": minS, "maxStage": maxS})

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


def build_colored_tree_variant(
    col: bpy.types.Collection,
    prefix: str,
    offset_x: float,
    colors: Dict[str, Tuple[float, float, float]],
    height: float,
    spread: float,
    stilt_roots: bool = False,
) -> dict:
    off = Vector((offset_x, 0.0, 0.0))
    m_bark = make_mat(f"Mat_{prefix}_Bark", colors["Bark"], roughness=0.86)
    m_moss = make_mat(f"Mat_{prefix}_Moss", colors["Moss"], roughness=0.78)
    m_clow = make_mat(f"Mat_{prefix}_CanopyLow", colors["CanopyLow"], roughness=0.68)
    m_chigh = make_mat(f"Mat_{prefix}_CanopyHigh", colors["CanopyHigh"], roughness=0.64)
    m_fruit = make_mat(f"Mat_{prefix}_Biolum", colors["Biolum"], roughness=0.22, emission=2.2)

    bm_bark, bm_moss, bm_clow, bm_chigh, bm_fruit = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()

    # Main sculptural crooked trunk
    t_pts = [
        off + Vector((0.0, 0.0, 0.0)),
        off + Vector((0.8, -0.5, height * 0.28)),
        off + Vector((-0.6, 0.4, height * 0.62)),
        off + Vector((0.3, -0.2, height * 0.90)),
    ]
    add_closed_loft(bm_bark, t_pts, [(2.15, 2.05), (1.55, 1.48), (1.08, 1.02), (0.58, 0.55)], segs=7)

    # Buttress or stilt roots wrapped in moss
    n_roots = 5
    for ri in range(n_roots):
        ang = 2.0 * math.pi * ri / n_roots + 0.25
        rd = Vector((math.cos(ang), math.sin(ang), 0.0))
        r_top = height * (0.28 if stilt_roots else 0.18)
        r_out = 5.4 if stilt_roots else 4.0
        add_closed_loft(
            bm_bark,
            [off + rd * r_out + Vector((0, 0, -0.4)), off + rd * (r_out * 0.55) + Vector((0, 0, r_top * 0.55)), off + rd * 0.9 + Vector((0, 0, r_top))],
            [(0.55, 0.45), (0.72, 0.58), (0.68, 0.55)],
            segs=5,
        )
        add_closed_loft(
            bm_moss,
            [off + rd * (r_out * 0.85) + Vector((0, 0, 0.1)), off + rd * (r_out * 0.35) + Vector((0, 0, r_top * 0.65))],
            [(0.48, 0.35), (0.62, 0.42)],
            segs=5,
        )

    # 6 sweeping boughs + layered lush colored canopy pads + hanging bioluminescent fruit pods
    for bi in range(6):
        ba = 2.0 * math.pi * bi / 6.0 + 0.15
        bd = Vector((math.cos(ba), math.sin(ba), 0.0))
        b_start = off + Vector((0.0, 0.0, height * (0.58 + (bi % 2) * 0.12)))
        b_mid = b_start + bd * (spread * 0.52) + Vector((0.0, 0.0, height * 0.12))
        b_tip = b_start + bd * spread + Vector((0.0, 0.0, height * 0.16))
        add_closed_loft(bm_bark, [b_start, b_mid, b_tip], [(0.68, 0.62), (0.44, 0.40), (0.22, 0.20)], segs=5)

        # Lower emerald/shaded canopy cluster + upper bright foliage pad
        add_foliage_cluster(bm_clow, b_tip + Vector((0, 0, 0.6)), 4.8 + (bi % 2) * 1.1, 4.6, 3.2, tilt_ang=ba)
        add_foliage_cluster(bm_chigh, b_tip + bd * 0.8 + Vector((0, 0, 2.4)), 3.9, 3.8, 2.8, tilt_ang=ba + 0.5)

        # Glowing forest spore pods beneath alternate boughs
        if bi % 2 == 0:
            pod_c = b_tip - Vector((0.0, 0.0, 2.8))
            add_closed_loft(bm_fruit, [pod_c + Vector((0, 0, 0.6)), pod_c, pod_c - Vector((0, 0, 0.8))], [(0.14, 0.14), (0.48, 0.48), (0.10, 0.10)], segs=6)

    # Central summit crown canopy
    summit = off + Vector((0.2, -0.1, height * 0.96))
    add_foliage_cluster(bm_clow, summit, spread * 0.68, spread * 0.66, 4.2, tilt_ang=0.2)
    add_foliage_cluster(bm_chigh, summit + Vector((0.0, 0.0, 2.8)), spread * 0.56, spread * 0.54, 3.6, tilt_ang=1.4)

    meshes = []
    for suf, bm, m in (
        ("TrunkBark", bm_bark, m_bark),
        ("MossRoots", bm_moss, m_moss),
        ("CanopyLow", bm_clow, m_clow),
        ("CanopyHigh", bm_chigh, m_chigh),
        ("BiolumFruit", bm_fruit, m_fruit),
    ):
        nm = f"{prefix}_{suf}"
        create_mesh_obj(nm, bm, m, col)
        meshes.append(nm)

    return {"offsetRoblox": blender_to_roblox_pos(off), "meshes": meshes}


def build_destruction_debris_kits(col: bpy.types.Collection) -> dict:
    m_bark = make_mat("Mat_Debris_Bark", (0.24, 0.16, 0.11), roughness=0.88)
    m_wood = make_mat("Mat_Debris_Heartwood", (0.58, 0.42, 0.28), roughness=0.72)
    m_rock = make_mat("Mat_Debris_Basalt", (0.14, 0.14, 0.17), roughness=0.82)

    # 1. ShatteredTreeStump3D at X = 84
    off_stump = Vector((84.0, 0.0, 0.0))
    bm_sb, bm_sw = bmesh.new(), bmesh.new()
    add_closed_loft(bm_sb, [off_stump + Vector((0, 0, 0)), off_stump + Vector((0, 0, 2.8))], [(2.8, 2.7), (1.85, 1.80)], segs=7)
    for si in range(6):
        ang = 2.0 * math.pi * si / 6.0
        d = Vector((math.cos(ang), math.sin(ang), 0.0))
        add_closed_loft(bm_sw, [off_stump + d * 0.9 + Vector((0, 0, 2.1)), off_stump + d * 1.45 + Vector((0, 0, 4.6 + (si % 2) * 1.2))], [(0.62, 0.45), (0.10, 0.08)], segs=5)
    create_mesh_obj("Stump3D_BarkOuter", bm_sb, m_bark, col)
    create_mesh_obj("Stump3D_SplinterCore", bm_sw, m_wood, col)

    # 2. SplinteredLogChunk3D at X = 98
    off_log = Vector((98.0, 0.0, 0.0))
    bm_lb, bm_lw = bmesh.new(), bmesh.new()
    add_closed_loft(bm_lb, [off_log + Vector((0, -4.5, 0.9)), off_log + Vector((0.3, 0, 1.0)), off_log + Vector((0.1, 4.5, 0.95))], [(1.15, 1.05), (1.32, 1.25), (1.02, 0.98)], segs=7)
    add_closed_loft(bm_lw, [off_log + Vector((0, -4.2, 0.9)), off_log + Vector((0, -5.8, 1.0))], [(0.82, 0.65), (0.12, 0.10)], segs=5)
    add_closed_loft(bm_lw, [off_log + Vector((0.1, 4.2, 0.95)), off_log + Vector((0.2, 5.9, 1.05))], [(0.78, 0.62), (0.10, 0.08)], segs=5)
    create_mesh_obj("LogChunk3D_Bark", bm_lb, m_bark, col)
    create_mesh_obj("LogChunk3D_Heartwood", bm_lw, m_wood, col)

    # 3. CrushedRockDebris3D at X = 110
    off_rk = Vector((110.0, 0.0, 0.0))
    bm_rk = bmesh.new()
    for rx, ry, h in [(-1.4, -0.8, 1.8), (1.2, -0.5, 2.2), (0.2, 1.3, 1.6)]:
        p = off_rk + Vector((rx, ry, 0.0))
        add_closed_loft(bm_rk, [p, p + Vector((0.15, -0.1, h))], [(1.4, 1.1), (0.55, 0.42)], segs=5)
    create_mesh_obj("RockDebris3D_Basalt", bm_rk, m_rock, col)

    return {
        "ShatteredTreeStump3D": {"offsetRoblox": blender_to_roblox_pos(off_stump), "meshes": ["Stump3D_BarkOuter", "Stump3D_SplinterCore"]},
        "SplinteredLogChunk3D": {"offsetRoblox": blender_to_roblox_pos(off_log), "meshes": ["LogChunk3D_Bark", "LogChunk3D_Heartwood"]},
        "CrushedRockDebris3D": {"offsetRoblox": blender_to_roblox_pos(off_rk), "meshes": ["RockDebris3D_Basalt"]},
    }


def render_v4_preview() -> None:
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=OUT_MONSTER_GLB)
    for o in bpy.context.selected_objects:
        o.location.x -= 16.0
    bpy.ops.import_scene.gltf(filepath=OUT_TREES_GLB)

    scene = bpy.context.scene
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 850
    scene.render.filepath = OUT_PREVIEW

    world = bpy.data.worlds.new("DuskBrightV4")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.14, 0.16, 0.18, 1.0)
        bg.inputs[1].default_value = 1.6

    sun_d = bpy.data.lights.new("SunV4", type="SUN")
    sun_d.energy = 3.8
    sun_o = bpy.data.objects.new("SunV4", sun_d)
    sun_o.rotation_euler = (math.radians(48), 0, math.radians(-35))
    scene.collection.objects.link(sun_o)

    cam_d = bpy.data.cameras.new("CamV4")
    cam_d.lens = 28.0
    cam_o = bpy.data.objects.new("CamV4", cam_d)
    cam_o.location = (45.0, -96.0, 26.0)
    cam_o.rotation_euler = (Vector((46.0, 0.0, 12.0)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam_o)
    scene.camera = cam_o

    os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    assert_no_overwrites()
    monster_manifest = build_colossal_monster_glb()

    clear_scene()
    col = bpy.data.collections.new("LushTreesAndDestructionV4")
    bpy.context.scene.collection.children.link(col)
    add_origin_marker(col, "ORIGIN_MARKER")

    trees_manifest = {
        "JungleCanopyTree3D": build_colored_tree_variant(
            col, "JungleTree", 0.0,
            {"Bark": (0.27, 0.18, 0.12), "Moss": (0.16, 0.42, 0.18), "CanopyLow": (0.12, 0.34, 0.15), "CanopyHigh": (0.25, 0.50, 0.20), "Biolum": (0.18, 0.88, 0.72)},
            height=29.0, spread=9.5, stilt_roots=False,
        ),
        "SwampMangroveTree3D": build_colored_tree_variant(
            col, "MangroveTree", 28.0,
            {"Bark": (0.21, 0.16, 0.12), "Moss": (0.22, 0.44, 0.16), "CanopyLow": (0.16, 0.32, 0.14), "CanopyHigh": (0.36, 0.48, 0.18), "Biolum": (1.0, 0.68, 0.18)},
            height=26.0, spread=8.8, stilt_roots=True,
        ),
        "CrimsonMossTree3D": build_colored_tree_variant(
            col, "CrimsonTree", 56.0,
            {"Bark": (0.18, 0.13, 0.12), "Moss": (0.15, 0.36, 0.20), "CanopyLow": (0.36, 0.14, 0.12), "CanopyHigh": (0.58, 0.24, 0.16), "Biolum": (1.0, 0.38, 0.12)},
            height=25.0, spread=8.5, stilt_roots=False,
        ),
    }
    debris_manifest = build_destruction_debris_kits(col)

    bpy.ops.export_scene.gltf(
        filepath=OUT_TREES_GLB,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )

    manifest = {
        "monster": monster_manifest,
        "trees": trees_manifest,
        "debris": debris_manifest,
        "treesDebrisMeshCount": 1 + sum(len(t["meshes"]) for t in trees_manifest.values()) + sum(len(d["meshes"]) for d in debris_manifest.values()),
    }
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)

    render_v4_preview()
    print("V4 BUILD COMPLETE:", json.dumps({"monsterMeshes": monster_manifest["meshCount"], "treesDebrisMeshes": manifest["treesDebrisMeshCount"]}))


if __name__ == "__main__":
    main()
