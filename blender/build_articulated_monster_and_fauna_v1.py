"""Builds articulated multi-joint GLB rigs for PRIMAL HUNT without overwriting any existing files:
1. PrimalHunt_ArticulatedMonster_v1.glb
   - Partitions AbyssMonster.blend (rest pose) into 17 articulated joints
     (Pelvis, Chest, Head, CrownL, CrownR, ArmUpL, ForeUpL, ArmUpR, ForeUpR,
      ArmLoL, ArmLoR, Tent0..Tent5) plus evolutionary stage meshes (All, S1, S2, S3).
2. PrimalHunt_ArticulatedFauna_v1.glb
   - Tier 2 Goliath3D (armored volcanic quadruped predator, 7 articulated joints)
   - Tier 1 CoastalScavenger3D (estuary chitin stalker, 7 articulated joints)
3. monster_and_fauna_rig_manifest_v1.json
   - Exact Roblox-space coordinates (-X left when facing -Z, +Y up, -Z forward) for
     all Motor6D joint pivots and hierarchy.
4. previews/articulated_monster_and_fauna_v1.png
   - Eevee render verifying both articulated fauna & articulated monster rigs.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
PREVIEWS_DIR = ROOT_DIR / "previews"
PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)

SRC_MONSTER_BLEND = ROOT_DIR / "AbyssMonster.blend"

OUT_MONSTER_GLB = ROOT_DIR / "PrimalHunt_ArticulatedMonster_v1.glb"
OUT_FAUNA_GLB = ROOT_DIR / "PrimalHunt_ArticulatedFauna_v1.glb"
OUT_MONSTER_BLEND = ROOT_DIR / "PrimalHunt_ArticulatedMonster_v1.blend"
OUT_FAUNA_BLEND = ROOT_DIR / "PrimalHunt_ArticulatedFauna_v1.blend"
OUT_MANIFEST = ROOT_DIR / "monster_and_fauna_rig_manifest_v1.json"
OUT_PREVIEW = PREVIEWS_DIR / "articulated_monster_and_fauna_v1.png"

TARGET_STAGE1_HEIGHT_STUDS = 11.2


def assert_no_overwrites() -> None:
    targets = [
        OUT_MONSTER_GLB,
        OUT_FAUNA_GLB,
        OUT_MONSTER_BLEND,
        OUT_FAUNA_BLEND,
        OUT_MANIFEST,
        OUT_PREVIEW,
    ]
    existing = [str(p) for p in targets if p.exists()]
    assert not existing, f"Safety abort: target file(s) already exist: {existing}"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def ensure_collection(name: str, parent: Optional[bpy.types.Collection] = None) -> bpy.types.Collection:
    col = bpy.data.collections.new(name)
    if parent is None:
        bpy.context.scene.collection.children.link(col)
    else:
        parent.children.link(col)
    return col


def make_mat(
    name: str,
    color: Tuple[float, float, float],
    roughness: float = 0.45,
    metallic: float = 0.2,
    emission: Optional[Tuple[float, float, float]] = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    mat = bpy.data.materials.new(name=name)
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def create_origin_marker(col: bpy.types.Collection) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.05)
    mesh = bpy.data.meshes.new("ORIGIN_MARKER")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("ORIGIN_MARKER", mesh)
    col.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    return obj


def _set_smooth(mesh: bpy.types.Mesh, smooth: bool) -> None:
    if hasattr(mesh, "polygons"):
        for p in mesh.polygons:
            p.use_smooth = smooth


def create_mesh_object_from_bmesh(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    weld_dist: float = 0.004,
    smooth: bool = True,
) -> Optional[bpy.types.Object]:
    if len(bm.faces) == 0:
        bm.free()
        return None
    if weld_dist > 0.0 and len(bm.verts) > 0:
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=weld_dist)
    bad_faces = [f for f in bm.faces if not f.is_valid or len(f.verts) < 3 or f.calc_area() < 1e-8]
    if bad_faces:
        bmesh.ops.delete(bm, geom=bad_faces, context="FACES")
    if len(bm.faces) == 0:
        bm.free()
        return None

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))

    verts_co = [v.co for v in bm.verts]
    cx = sum(v.x for v in verts_co) / len(verts_co)
    cy = sum(v.y for v in verts_co) / len(verts_co)
    cz = sum(v.z for v in verts_co) / len(verts_co)
    center = Vector((cx, cy, cz))
    bmesh.ops.translate(bm, verts=list(bm.verts), vec=-center)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    _set_smooth(mesh, smooth)

    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.location = center
    return obj


def blender_to_roblox_pos(pt: Vector) -> List[float]:
    """Converts Blender world point (facing -Y) to Roblox character space (facing -Z, +Y up, -X left)."""
    return [round(-pt.x, 4), round(pt.z, 4), round(pt.y, 4)]


# ---------------------------------------------------------------------------
# Mesh Loft Helpers (Watertight Procedural Organ/Carapace Builders)
# ---------------------------------------------------------------------------

def _parallel_frames(pts: Sequence[Vector]) -> List[Tuple[Vector, Vector, Vector]]:
    n = len(pts)
    tangs: List[Vector] = []
    for i in range(n):
        t = (pts[1] - pts[0]) if i == 0 else ((pts[-1] - pts[-2]) if i == n - 1 else (pts[i + 1] - pts[i - 1]))
        tangs.append(t.normalized())
    ref = Vector((0.0, 0.0, 1.0)) if abs(tangs[0].z) < 0.88 else Vector((1.0, 0.0, 0.0))
    right = tangs[0].cross(ref).normalized()
    up = right.cross(tangs[0]).normalized()
    frames = [(tangs[0], right, up)]
    for i in range(1, n):
        rot = tangs[i - 1].rotation_difference(tangs[i])
        right = (rot @ right).normalized()
        up = right.cross(tangs[i]).normalized()
        frames.append((tangs[i], right, up))
    return frames


def add_closed_loft(
    bm: bmesh.types.BMesh,
    stations: Sequence[Tuple[Vector, float, float]],
    radial_segs: int = 10,
    dorsal_pinch: float = 0.0,
) -> None:
    pts = [s[0] for s in stations]
    frames = _parallel_frames(pts)
    rings: List[List[bmesh.types.BMVert]] = []
    for (c, rx, rz), (_t, rv, uv) in zip(stations, frames):
        ring: List[bmesh.types.BMVert] = []
        for s in range(radial_segs):
            th = (2.0 * math.pi * s) / radial_segs
            ct, st = math.cos(th), math.sin(th)
            ridge = dorsal_pinch * (max(0.0, st) ** 2)
            pos = c + rv * (ct * rx) + uv * ((st + ridge) * rz)
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(radial_segs):
            sn = (s + 1) % radial_segs
            try:
                bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
            except ValueError:
                pass

    # Cap ends
    c_start = bm.verts.new(pts[0])
    c_end = bm.verts.new(pts[-1])
    for s in range(radial_segs):
        sn = (s + 1) % radial_segs
        try:
            bm.faces.new((c_start, rings[0][sn], rings[0][s]))
            bm.faces.new((c_end, rings[-1][s], rings[-1][sn]))
        except ValueError:
            pass


# ---------------------------------------------------------------------------
# PART 1: Build Articulated 17-Joint 3D Monster from AbyssMonster.blend
# ---------------------------------------------------------------------------

BONE_TO_JOINT: Dict[str, str] = {
    "root": "Pelvis",
    "pelvis": "Pelvis",
    "spine_1": "Pelvis",
    "spine_2": "Chest",
    "spine_3": "Chest",
    "neck": "Chest",
    "head": "Head",
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
}
for _ci in range(4):
    BONE_TO_JOINT[f"crown_{_ci}_1"] = "CrownL"
    BONE_TO_JOINT[f"crown_{_ci}_2"] = "CrownL"
for _ci in range(4, 8):
    BONE_TO_JOINT[f"crown_{_ci}_1"] = "CrownR"
    BONE_TO_JOINT[f"crown_{_ci}_2"] = "CrownR"
for _ti in range(6):
    for _tk in range(1, 6):
        BONE_TO_JOINT[f"tent_{_ti}_{_tk}"] = f"Tent{_ti}"


MAT_TO_BUCKET = {
    "Mat_Monster_AbyssalHide": "Hide",
    "Mat_Monster_ObsidianCarapace": "Carapace",
    "Mat_Eclipse_DarkRibChitin": "Carapace",
    "Mat_Eclipse_VoidBlack": "VoidCore",
    "Mat_Eclipse_BronzeShackle": "Bronze",
    "Mat_Monster_BoneClaws": "Bone",
    "Mat_Furnace_OuterEmber": "Neon",
    "Mat_Furnace_MoltenHeart": "Neon",
    "Mat_Eclipse_BloodCorona_S1": "Neon",
    "Mat_Eclipse_BloodRim_S1": "Neon",
    "Mat_Eclipse_GoldCorona_S2": "Neon",
    "Mat_Eclipse_GoldRim_S2": "Neon",
    "Mat_Eclipse_SolarCorona_S3": "Neon",
    "Mat_Eclipse_SolarRim_S3": "Neon",
}


def build_articulated_monster(manifest: dict) -> List[bpy.types.Object]:
    reset_scene()
    col = ensure_collection("ArticulatedMonster_v1")
    origin_marker = create_origin_marker(col)

    palette = {
        "Hide": make_mat("MArt_Mat_Hide", (0.14, 0.11, 0.15), 0.55, 0.05),
        "Carapace": make_mat("MArt_Mat_Carapace", (0.08, 0.08, 0.10), 0.32, 0.35),
        "VoidCore": make_mat("MArt_Mat_VoidCore", (0.015, 0.015, 0.03), 0.15, 0.0),
        "Bronze": make_mat("MArt_Mat_Bronze", (0.54, 0.46, 0.38), 0.38, 0.85),
        "Bone": make_mat("MArt_Mat_Bone", (0.88, 0.82, 0.73), 0.30, 0.10),
        "Neon": make_mat("MArt_Mat_Neon", (1.0, 0.42, 0.09), 0.18, 0.0, (1.0, 0.35, 0.06), 6.0),
    }

    source_specs = [
        ("Monster_CoreBody_Skinned", "All"),
        ("Monster_RibcageAndShackles_Skinned", "All"),
        ("Monster_Stage1_Apex_Skinned", "S1"),
        ("Monster_Stage2_Tyrant_Skinned", "S2"),
        ("Monster_Stage3_EclipseGod_Skinned", "S3"),
    ]

    with bpy.data.libraries.load(str(SRC_MONSTER_BLEND), link=False) as (_df, data_to):
        data_to.objects = ["Monster_Armature"] + [s[0] for s in source_specs]

    loaded = [o for o in data_to.objects if o is not None]
    temp_col = ensure_collection("TEMP_SourceMonster")
    for o in loaded:
        temp_col.objects.link(o)

    arm = next(o for o in loaded if o.name == "Monster_Armature")
    if arm.animation_data is not None:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    # Measure rest-pose height across Core + Ribcage + Stage1
    deps = bpy.context.evaluated_depsgraph_get()
    all_z: List[float] = []
    for name in ("Monster_CoreBody_Skinned", "Monster_RibcageAndShackles_Skinned", "Monster_Stage1_Apex_Skinned"):
        src_o = next(o for o in loaded if o.name == name)
        ev = src_o.evaluated_get(deps)
        tmp = ev.to_mesh()
        for v in tmp.vertices:
            w = ev.matrix_world @ v.co
            all_z.append(w.z)
        ev.to_mesh_clear()

    zmin = min(all_z)
    zmax = max(all_z)
    height_raw = max(0.1, zmax - zmin)
    norm_scale = TARGET_STAGE1_HEIGHT_STUDS / height_raw
    arm_cx = arm.location.x
    arm_cy = arm.location.y

    t_norm = Matrix.Diagonal((norm_scale, norm_scale, norm_scale, 1.0)) @ Matrix.Translation((-arm_cx, -arm_cy, -zmin))

    def bone_world_pivot(bname: str) -> Vector:
        b = arm.data.bones[bname]
        return t_norm @ (arm.matrix_world @ b.head_local)

    joint_pivots_blender: Dict[str, Vector] = {
        "Root": Vector((0.0, 0.0, 0.0)),
        "Pelvis": bone_world_pivot("pelvis"),
        "Chest": bone_world_pivot("spine_2"),
        "Head": bone_world_pivot("head"),
        "CrownL": (bone_world_pivot("crown_1_1") + bone_world_pivot("crown_2_1")) * 0.5,
        "CrownR": (bone_world_pivot("crown_5_1") + bone_world_pivot("crown_6_1")) * 0.5,
        "ArmUpL": bone_world_pivot("arm_up_sh_l"),
        "ForeUpL": bone_world_pivot("arm_up_lo_l"),
        "ArmUpR": bone_world_pivot("arm_up_sh_r"),
        "ForeUpR": bone_world_pivot("arm_up_lo_r"),
        "ArmLoL": bone_world_pivot("arm_lo_up_l"),
        "ArmLoR": bone_world_pivot("arm_lo_up_r"),
    }
    for tid in range(6):
        joint_pivots_blender[f"Tent{tid}"] = bone_world_pivot(f"tent_{tid}_1")

    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh] = {}

    def get_bm(joint: str, stage_tag: str, mat_key: str) -> bmesh.types.BMesh:
        key = (joint, stage_tag, mat_key)
        bm = buckets.get(key)
        if bm is None:
            bm = bmesh.new()
            buckets[key] = bm
        return bm

    for src_name, stage_tag in source_specs:
        src_o = next(o for o in loaded if o.name == src_name)
        vgroup_names = [vg.name for vg in src_o.vertex_groups]
        ev = src_o.evaluated_get(deps)
        tmp = ev.to_mesh()
        xf = t_norm @ ev.matrix_world
        src_mats = [m.name.split(".")[0] if m else "" for m in tmp.materials]

        # Pre-resolve vertex dominant joint
        vert_joint: List[str] = []
        for v in src_o.data.vertices:
            j_weights: Dict[str, float] = {}
            for g in v.groups:
                if g.group < len(vgroup_names):
                    bname = vgroup_names[g.group]
                    j = BONE_TO_JOINT.get(bname)
                    if j:
                        j_weights[j] = j_weights.get(j, 0.0) + g.weight
            if j_weights:
                best_j = max(j_weights.items(), key=lambda kv: kv[1])[0]
            else:
                best_j = "Chest"
            vert_joint.append(best_j)

        head_p = joint_pivots_blender["Head"]
        # Map stage_tag polygons cleanly
        for poly in tmp.polygons:
            v_ids = list(poly.vertices)
            if len(v_ids) < 3:
                continue

            counts: Dict[str, int] = {}
            cent = Vector((0.0, 0.0, 0.0))
            for vid in v_ids:
                j = vert_joint[vid] if vid < len(vert_joint) else "Chest"
                counts[j] = counts.get(j, 0) + 1
                cent += xf @ tmp.vertices[vid].co
            cent /= float(len(v_ids))
            joint = max(counts.items(), key=lambda kv: kv[1])[0]

            raw_m = src_mats[poly.material_index] if poly.material_index < len(src_mats) else ""
            mat_key = "Hide"
            for k, bname in MAT_TO_BUCKET.items():
                if raw_m.startswith(k):
                    mat_key = bname
                    break

            # On Stage crown meshes, if Halo Corona / Outer Crown is weighted slightly to Head,
            # split outer tendrils/blades left vs right cleanly, leaving inner ring on Head.
            if stage_tag in ("S1", "S2", "S3") and joint == "Head":
                rel_h = cent - head_p
                if rel_h.length > 1.05 or mat_key == "Carapace":
                    joint = "CrownL" if cent.x >= 0.0 else "CrownR"

            bm_dst = get_bm(joint, stage_tag, mat_key)
            v0 = bm_dst.verts.new(xf @ tmp.vertices[v_ids[0]].co)
            for i in range(1, len(v_ids) - 1):
                va = bm_dst.verts.new(xf @ tmp.vertices[v_ids[i]].co)
                vb = bm_dst.verts.new(xf @ tmp.vertices[v_ids[i + 1]].co)
                try:
                    bm_dst.faces.new((v0, va, vb))
                except ValueError:
                    pass

        ev.to_mesh_clear()

    objs: List[bpy.types.Object] = [origin_marker]
    for (joint, stage_tag, mat_key), bm_dst in sorted(buckets.items()):
        oname = f"MArt_{joint}_{stage_tag}_{mat_key}"
        obj = create_mesh_object_from_bmesh(oname, bm_dst, palette[mat_key], col, weld_dist=0.004, smooth=True)
        if obj is not None:
            objs.append(obj)

    # Clean temporary source objects
    bpy.context.scene.collection.children.unlink(temp_col)
    bpy.data.collections.remove(temp_col)
    for o in loaded:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)

    manifest["monster"] = {
        "stage1HeightStuds": round(TARGET_STAGE1_HEIGHT_STUDS, 3),
        "meshCount": len(objs) - 1,
        "joints": {k: blender_to_roblox_pos(v) for k, v in joint_pivots_blender.items()},
    }

    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_MONSTER_BLEND))
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_MONSTER_GLB),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    return objs


# ---------------------------------------------------------------------------
# PART 2: Build Articulated 3D Fauna (Tier 2 Goliath3D + Tier 1 Scavenger3D)
# ---------------------------------------------------------------------------

def _add_armored_leg(
    bm_hide: bmesh.types.BMesh,
    bm_armor: bmesh.types.BMesh,
    hip: Vector,
    knee: Vector,
    ankle: Vector,
    foot: Vector,
    r_top: float,
    r_mid: float,
    r_paw: float,
    claw_spread: float,
) -> None:
    add_closed_loft(
        bm_hide,
        [
            (hip, r_top, r_top),
            (hip.lerp(knee, 0.5), r_top * 0.92, r_top * 0.92),
            (knee, r_mid, r_mid),
            (ankle, r_mid * 0.85, r_mid * 0.85),
            (foot, r_paw, r_paw * 0.55),
        ],
        radial_segs=8,
    )
    # Armored knee plate + 3 jagged ground claws
    add_closed_loft(
        bm_armor,
        [
            (hip + Vector((0, 0, r_top * 0.35)), r_top * 1.15, r_top * 0.65),
            (knee + Vector((0, -r_mid * 0.25, 0.12)), r_mid * 1.18, r_mid * 0.85),
            (knee.lerp(ankle, 0.4), r_mid * 0.65, r_mid * 0.55),
        ],
        radial_segs=6,
        dorsal_pinch=0.45,
    )
    for ox in (-claw_spread, 0.0, claw_spread):
        add_closed_loft(
            bm_armor,
            [
                (foot + Vector((ox, -r_paw * 0.45, r_paw * 0.28)), r_mid * 0.35, r_mid * 0.35),
                (foot + Vector((ox * 1.15, -r_paw * 1.35, 0.05)), r_mid * 0.08, r_mid * 0.08),
            ],
            radial_segs=5,
        )


def build_articulated_fauna(manifest: dict) -> List[bpy.types.Object]:
    reset_scene()
    col = ensure_collection("ArticulatedFauna_v1")
    origin_marker = create_origin_marker(col)

    mats = {
        "G_Hide": make_mat("FArt_Goliath_Hide", (0.38, 0.10, 0.10), 0.52, 0.05),
        "G_Armor": make_mat("FArt_Goliath_Armor", (0.14, 0.13, 0.16), 0.32, 0.35),
        "G_Magma": make_mat("FArt_Goliath_Magma", (1.0, 0.22, 0.04), 0.18, 0.0, (1.0, 0.18, 0.02), 6.0),
        "S_Hide": make_mat("FArt_Scav_Hide", (0.14, 0.20, 0.15), 0.48, 0.08),
        "S_Armor": make_mat("FArt_Scav_Armor", (0.68, 0.65, 0.54), 0.34, 0.18),
        "S_Glow": make_mat("FArt_Scav_Glow", (1.0, 0.72, 0.18), 0.18, 0.0, (1.0, 0.65, 0.12), 5.0),
    }

    objs: List[bpy.types.Object] = [origin_marker]

    def emit(name: str, bm: bmesh.types.BMesh, mat_key: str, smooth: bool = True) -> None:
        o = create_mesh_object_from_bmesh(name, bm, mats[mat_key], col, weld_dist=0.004, smooth=smooth)
        if o is not None:
            objs.append(o)

    # -----------------------------------------------------------------------
    # 1. TIER 2: Goliath3D (~7.2 studs long, ~4.6 studs tall, centered at X=0, feet Z=0, facing -Y)
    # -----------------------------------------------------------------------
    g_body_hide = bmesh.new()
    g_body_armor = bmesh.new()
    g_body_magma = bmesh.new()

    # Broad hunched quadruped ribcage & muscular chest
    add_closed_loft(
        g_body_hide,
        [
            (Vector((0.0, 2.35, 2.05)), 0.72, 0.68),
            (Vector((0.0, 1.35, 2.22)), 1.08, 1.02),
            (Vector((0.0, 0.10, 2.38)), 1.24, 1.18),
            (Vector((0.0, -1.25, 2.55)), 1.48, 1.32),
            (Vector((0.0, -2.35, 2.52)), 1.05, 0.96),
        ],
        radial_segs=12,
        dorsal_pinch=0.32,
    )
    # 5 Overlapping jagged dorsal carapace plates + dorsal ridge blades
    for idx, (py, pz, w, sp_h) in enumerate(
        (
            (-1.95, 3.32, 1.38, 0.92),
            (-1.10, 3.62, 1.54, 1.12),
            (-0.20, 3.55, 1.36, 1.02),
            (0.75, 3.25, 1.14, 0.84),
            (1.65, 2.86, 0.88, 0.66),
        )
    ):
        add_closed_loft(
            g_body_armor,
            [
                (Vector((0, py + 0.55, pz - 0.15)), w * 0.78, 0.28),
                (Vector((0, py, pz + 0.14)), w, 0.34),
                (Vector((0, py - 0.45, pz + 0.22)), w * 0.88, 0.24),
            ],
            radial_segs=7,
            dorsal_pinch=0.55,
        )
        add_closed_loft(
            g_body_armor,
            [
                (Vector((0, py - 0.12, pz + 0.18)), 0.22, 0.26),
                (Vector((0, py + 0.36, pz + 0.18 + sp_h)), 0.03, 0.04),
            ],
            radial_segs=5,
        )
    # Glowing magma rib vents along sides & spine fissures
    for sgn in (1.0, -1.0):
        for py in (-1.45, -0.55, 0.35):
            add_closed_loft(
                g_body_magma,
                [
                    (Vector((sgn * 1.10, py - 0.10, 2.75)), 0.10, 0.10),
                    (Vector((sgn * 1.34, py, 2.15)), 0.12, 0.10),
                    (Vector((sgn * 1.05, py + 0.12, 1.65)), 0.07, 0.07),
                ],
                radial_segs=6,
            )

    emit("Goliath3D_Body_Hide", g_body_hide, "G_Hide", smooth=True)
    emit("Goliath3D_Body_Armor", g_body_armor, "G_Armor", smooth=False)
    emit("Goliath3D_Body_Magma", g_body_magma, "G_Magma", smooth=True)

    # Head assembly (neck pivot (0, -2.35, 2.55))
    g_head_armor = bmesh.new()
    g_head_magma = bmesh.new()
    add_closed_loft(
        g_head_armor,
        [
            (Vector((0.0, -2.25, 2.65)), 0.94, 0.82),
            (Vector((0.0, -3.00, 2.75)), 0.78, 0.64),
            (Vector((0.0, -3.82, 2.60)), 0.46, 0.36),
        ],
        radial_segs=8,
        dorsal_pinch=0.45,
    )
    # Hinged lower jaw + molten maw core
    add_closed_loft(
        g_head_armor,
        [
            (Vector((0.0, -2.45, 2.18)), 0.64, 0.28),
            (Vector((0.0, -3.65, 1.98)), 0.36, 0.18),
        ],
        radial_segs=7,
    )
    add_closed_loft(
        g_head_magma,
        [
            (Vector((0.0, -2.95, 2.25)), 0.24, 0.18),
            (Vector((0.0, -3.45, 2.28)), 0.18, 0.14),
        ],
        radial_segs=6,
    )
    for sgn in (1.0, -1.0):
        # Twin huge swept curved bull-demon horns (~4.55 studs tip height!)
        add_closed_loft(
            g_head_armor,
            [
                (Vector((sgn * 0.58, -2.65, 3.12)), 0.24, 0.24),
                (Vector((sgn * 1.10, -3.15, 3.72)), 0.16, 0.16),
                (Vector((sgn * 1.24, -3.65, 4.48)), 0.03, 0.03),
            ],
            radial_segs=7,
        )
        # Upper tusks + glowing predator eyes
        add_closed_loft(
            g_head_armor,
            [
                (Vector((sgn * 0.28, -3.52, 2.40)), 0.08, 0.08),
                (Vector((sgn * 0.30, -3.62, 2.04)), 0.015, 0.015),
            ],
            radial_segs=5,
        )
        bmesh.ops.create_icosphere(
            g_head_magma, subdivisions=1, radius=0.14, matrix=Matrix.Translation((sgn * 0.56, -3.18, 2.86))
        )

    emit("Goliath3D_Head_Armor", g_head_armor, "G_Armor", smooth=False)
    emit("Goliath3D_Head_Magma", g_head_magma, "G_Magma", smooth=True)

    # 4 Articulated Goliath Legs (Blender +X is Left, -X is Right!)
    g_legs = {
        "LegFL": (Vector((1.35, -1.65, 2.15)), Vector((1.62, -1.25, 1.15)), Vector((1.48, -1.55, 0.45)), Vector((1.50, -1.85, 0.10)), 0.56, 0.42, 0.46, 0.24),
        "LegFR": (Vector((-1.35, -1.65, 2.15)), Vector((-1.62, -1.25, 1.15)), Vector((-1.48, -1.55, 0.45)), Vector((-1.50, -1.85, 0.10)), 0.56, 0.42, 0.46, 0.24),
        "LegBL": (Vector((1.12, 1.72, 2.08)), Vector((1.35, 1.32, 1.10)), Vector((1.25, 1.95, 0.42)), Vector((1.24, 1.65, 0.10)), 0.48, 0.36, 0.40, 0.20),
        "LegBR": (Vector((-1.12, 1.72, 2.08)), Vector((-1.35, 1.32, 1.10)), Vector((-1.25, 1.95, 0.42)), Vector((-1.24, 1.65, 0.10)), 0.48, 0.36, 0.40, 0.20),
    }
    for lname, (p0, p1, p2, p3, rt, rm, rp, cs) in g_legs.items():
        lh = bmesh.new()
        la = bmesh.new()
        _add_armored_leg(lh, la, p0, p1, p2, p3, rt, rm, rp, cs)
        emit(f"Goliath3D_{lname}_Hide", lh, "G_Hide", smooth=True)
        emit(f"Goliath3D_{lname}_Armor", la, "G_Armor", smooth=False)

    # Articulated Tail (pivot (0, 2.15, 2.05))
    g_tail_h = bmesh.new()
    g_tail_a = bmesh.new()
    add_closed_loft(
        g_tail_h,
        [
            (Vector((0.0, 2.10, 2.05)), 0.62, 0.58),
            (Vector((0.0, 2.95, 1.95)), 0.42, 0.38),
            (Vector((0.0, 3.75, 2.08)), 0.26, 0.24),
            (Vector((0.0, 4.45, 2.38)), 0.12, 0.12),
        ],
        radial_segs=8,
    )
    add_closed_loft(
        g_tail_a,
        [
            (Vector((0.0, 3.75, 2.12)), 0.36, 0.36),
            (Vector((0.0, 4.42, 2.42)), 0.48, 0.42),
            (Vector((0.0, 4.88, 2.60)), 0.08, 0.08),
        ],
        radial_segs=6,
        dorsal_pinch=0.5,
    )
    emit("Goliath3D_Tail_Hide", g_tail_h, "G_Hide", smooth=True)
    emit("Goliath3D_Tail_Armor", g_tail_a, "G_Armor", smooth=False)

    # -----------------------------------------------------------------------
    # 2. TIER 1: CoastalScavenger3D (Placed cleanly at X = 20.0 in Blender)
    # -----------------------------------------------------------------------
    SX = 20.0
    soff = Vector((SX, 0.0, 0.0))
    s_body_h = bmesh.new()
    s_body_a = bmesh.new()
    s_body_g = bmesh.new()

    add_closed_loft(
        s_body_h,
        [
            (soff + Vector((0.0, 1.22, 1.05)), 0.38, 0.36),
            (soff + Vector((0.0, 0.48, 1.22)), 0.62, 0.54),
            (soff + Vector((0.0, -0.35, 1.32)), 0.68, 0.58),
            (soff + Vector((0.0, -1.12, 1.30)), 0.50, 0.44),
        ],
        radial_segs=10,
        dorsal_pinch=0.35,
    )
    for py, pz, w in ((-0.75, 1.82, 0.68), (0.0, 1.80, 0.72), (0.72, 1.58, 0.54)):
        add_closed_loft(
            s_body_a,
            [
                (soff + Vector((0.0, py + 0.32, pz - 0.06)), w * 0.78, 0.14),
                (soff + Vector((0.0, py, pz + 0.08)), w, 0.18),
                (soff + Vector((0.0, py - 0.28, pz + 0.12)), w * 0.85, 0.14),
            ],
            radial_segs=6,
            dorsal_pinch=0.55,
        )
    for sgn in (1.0, -1.0):
        for py in (-0.52, 0.10, 0.62):
            bmesh.ops.create_icosphere(
                s_body_g, subdivisions=1, radius=0.09, matrix=Matrix.Translation(soff + Vector((sgn * 0.58, py, 1.36)))
            )

    emit("Scavenger3D_Body_Hide", s_body_h, "S_Hide", smooth=True)
    emit("Scavenger3D_Body_Armor", s_body_a, "S_Armor", smooth=False)
    emit("Scavenger3D_Body_Glow", s_body_g, "S_Glow", smooth=True)

    # Scavenger Head (neck pivot (20, -1.12, 1.30))
    s_head_a = bmesh.new()
    s_head_g = bmesh.new()
    add_closed_loft(
        s_head_a,
        [
            (soff + Vector((0.0, -1.06, 1.34)), 0.46, 0.38),
            (soff + Vector((0.0, -1.62, 1.48)), 0.38, 0.30),
            (soff + Vector((0.0, -2.26, 1.36)), 0.16, 0.14),
        ],
        radial_segs=7,
        dorsal_pinch=0.55,
    )
    # Twin raptor head-crest blades
    for sgn in (1.0, -1.0):
        add_closed_loft(
            s_head_a,
            [
                (soff + Vector((sgn * 0.24, -1.38, 1.62)), 0.10, 0.10),
                (soff + Vector((sgn * 0.42, -0.92, 1.98)), 0.02, 0.03),
            ],
            radial_segs=5,
        )
        bmesh.ops.create_icosphere(
            s_head_g, subdivisions=1, radius=0.075, matrix=Matrix.Translation(soff + Vector((sgn * 0.30, -1.72, 1.54)))
        )
        bmesh.ops.create_icosphere(
            s_head_g, subdivisions=1, radius=0.055, matrix=Matrix.Translation(soff + Vector((sgn * 0.24, -1.90, 1.48)))
        )

    emit("Scavenger3D_Head_Armor", s_head_a, "S_Armor", smooth=False)
    emit("Scavenger3D_Head_Glow", s_head_g, "S_Glow", smooth=True)

    # 4 Articulated Scavenger Raptor Legs
    s_legs = {
        "LegFL": (soff + Vector((0.66, -0.78, 1.18)), soff + Vector((1.05, -0.58, 0.68)), soff + Vector((0.88, -0.82, 0.26)), soff + Vector((0.86, -1.02, 0.06))),
        "LegFR": (soff + Vector((-0.66, -0.78, 1.18)), soff + Vector((-1.05, -0.58, 0.68)), soff + Vector((-0.88, -0.82, 0.26)), soff + Vector((-0.86, -1.02, 0.06))),
        "LegBL": (soff + Vector((0.60, 0.80, 1.12)), soff + Vector((0.96, 0.55, 0.64)), soff + Vector((0.82, 0.96, 0.24)), soff + Vector((0.80, 0.78, 0.06))),
        "LegBR": (soff + Vector((-0.60, 0.80, 1.12)), soff + Vector((-0.96, 0.55, 0.64)), soff + Vector((-0.82, 0.96, 0.24)), soff + Vector((-0.80, 0.78, 0.06))),
    }
    for lname, (p0, p1, p2, p3) in s_legs.items():
        lh = bmesh.new()
        la = bmesh.new()
        _add_armored_leg(lh, la, p0, p1, p2, p3, 0.22, 0.15, 0.18, 0.09)
        # Merge leg hide+armor per leg for fewer mesh parts while keeping crisp silhouette
        emit(f"Scavenger3D_{lname}_Hide", lh, "S_Hide", smooth=True)
        emit(f"Scavenger3D_{lname}_Armor", la, "S_Armor", smooth=False)

    # Articulated Stinger Tail (pivot (20, 1.15, 1.10))
    s_tail_a = bmesh.new()
    s_tail_g = bmesh.new()
    add_closed_loft(
        s_tail_a,
        [
            (soff + Vector((0.0, 1.10, 1.10)), 0.30, 0.28),
            (soff + Vector((0.0, 1.72, 1.06)), 0.18, 0.16),
            (soff + Vector((0.0, 2.26, 1.32)), 0.10, 0.10),
            (soff + Vector((0.0, 2.02, 1.76)), 0.04, 0.04),
        ],
        radial_segs=7,
    )
    bmesh.ops.create_icosphere(
        s_tail_g, subdivisions=1, radius=0.11, matrix=Matrix.Translation(soff + Vector((0.0, 2.02, 1.78)))
    )
    emit("Scavenger3D_Tail_Armor", s_tail_a, "S_Armor", smooth=False)
    emit("Scavenger3D_Tail_Glow", s_tail_g, "S_Glow", smooth=True)

    manifest["fauna"] = {
        "Goliath3D": {
            "centerBlender": [0.0, 0.0, 0.0],
            "bodyCenter": blender_to_roblox_pos(Vector((0.0, -0.2, 2.35))),
            "joints": {
                "Head": blender_to_roblox_pos(Vector((0.0, -2.35, 2.55))),
                "LegFL": blender_to_roblox_pos(Vector((1.35, -1.65, 2.15))),
                "LegFR": blender_to_roblox_pos(Vector((-1.35, -1.65, 2.15))),
                "LegBL": blender_to_roblox_pos(Vector((1.12, 1.72, 2.08))),
                "LegBR": blender_to_roblox_pos(Vector((-1.12, 1.72, 2.08))),
                "Tail": blender_to_roblox_pos(Vector((0.0, 2.10, 2.05))),
            },
        },
        "Scavenger3D": {
            "centerBlender": [SX, 0.0, 0.0],
            "bodyCenter": blender_to_roblox_pos(Vector((0.0, -0.1, 1.25))),
            "joints": {
                "Head": blender_to_roblox_pos(Vector((0.0, -1.12, 1.30))),
                "LegFL": blender_to_roblox_pos(Vector((0.66, -0.78, 1.18))),
                "LegFR": blender_to_roblox_pos(Vector((-0.66, -0.78, 1.18))),
                "LegBL": blender_to_roblox_pos(Vector((0.60, 0.80, 1.12))),
                "LegBR": blender_to_roblox_pos(Vector((-0.60, 0.80, 1.12))),
                "Tail": blender_to_roblox_pos(Vector((0.0, 1.10, 1.10))),
            },
        },
    }

    # Render Eevee verification preview of both articulated Fauna creatures + floor disc
    scene = bpy.context.scene
    bm_fl = bmesh.new()
    bmesh.ops.create_cube(bm_fl, size=1.0, matrix=Matrix.Translation((9.0, 0.0, -0.1)) @ Matrix.Diagonal((36.0, 20.0, 0.2, 1.0)))
    fl_mesh = bpy.data.meshes.new("TEMP_PreviewFloor")
    bm_fl.to_mesh(fl_mesh)
    bm_fl.free()
    fl_obj = bpy.data.objects.new("TEMP_PreviewFloor", fl_mesh)
    col.objects.link(fl_obj)
    fl_obj.data.materials.append(make_mat("TEMP_Floor", (0.04, 0.045, 0.055), 0.75, 0.1))

    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.04, 0.045, 0.055, 1.0)
        bg.inputs["Strength"].default_value = 0.8

    for lname, lpos, lrot, pwr in (
        ("KeySun", (6.0, -12.0, 12.0), (50.0, 0.0, 24.0), 4.0),
        ("RimArea", (10.0, 10.0, 8.0), (-55.0, 0.0, 15.0), 1800.0),
    ):
        ld = bpy.data.lights.new(lname, "SUN" if lname == "KeySun" else "AREA")
        ld.energy = pwr
        lo = bpy.data.objects.new(lname, ld)
        col.objects.link(lo)
        lo.location = lpos
        lo.rotation_euler = tuple(math.radians(a) for a in lrot)

    cam_d = bpy.data.cameras.new("PreviewCam")
    cam_d.lens = 36
    cam_o = bpy.data.objects.new("PreviewCam", cam_d)
    col.objects.link(cam_o)
    cam_o.location = (9.5, -16.5, 6.2)
    direction = Vector((9.5, 0.0, 2.0)) - cam_o.location
    cam_o.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_o

    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = str(OUT_PREVIEW)
    bpy.ops.render.render(write_still=True)

    # Remove temp render lights/floor/cam before exporting GLB
    for helper in list(col.objects):
        if helper not in objs:
            bpy.data.objects.remove(helper, do_unlink=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_FAUNA_BLEND))
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_FAUNA_GLB),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    return objs


def main() -> None:
    assert_no_overwrites()
    manifest: dict = {"version": "v1"}
    build_articulated_monster(manifest)
    build_articulated_fauna(manifest)
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("SUCCESS:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
