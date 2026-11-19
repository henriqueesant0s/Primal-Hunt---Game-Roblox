"""Builds clean undeformed rest-pose PrimalHunt_ArticulatedMonster_v2.glb (17 joints + S1/S2/S3 stages)
without overwriting any existing file.
Fixes v1's NLA/pose offset by reading AbyssMonster.blend rest-pose mesh data & bone head_local directly.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
PREVIEWS_DIR = ROOT_DIR / "previews"
PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)

SRC_MONSTER_BLEND = ROOT_DIR / "AbyssMonster.blend"
SRC_MANIFEST_V1 = ROOT_DIR / "monster_and_fauna_rig_manifest_v1.json"

OUT_MONSTER_GLB = ROOT_DIR / "PrimalHunt_ArticulatedMonster_v2.glb"
OUT_MONSTER_BLEND = ROOT_DIR / "PrimalHunt_ArticulatedMonster_v2.blend"
OUT_MANIFEST = ROOT_DIR / "monster_and_fauna_rig_manifest_v2.json"
OUT_PREVIEW = PREVIEWS_DIR / "articulated_monster_v2.png"

TARGET_STAGE1_HEIGHT_STUDS = 11.2


def assert_no_overwrites() -> None:
    targets = [OUT_MONSTER_GLB, OUT_MONSTER_BLEND, OUT_MANIFEST, OUT_PREVIEW]
    existing = [str(p) for p in targets if p.exists()]
    assert not existing, f"Safety abort: target file(s) already exist: {existing}"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def ensure_collection(name: str) -> bpy.types.Collection:
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def make_mat(
    name: str,
    color: Tuple[float, float, float],
    roughness: float = 0.45,
    metallic: float = 0.2,
    emission: Optional[Tuple[float, float, float]] = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
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


def create_mesh_object_from_bmesh(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
) -> Optional[bpy.types.Object]:
    if len(bm.faces) == 0:
        bm.free()
        return None
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.004)
    bad = [f for f in bm.faces if not f.is_valid or len(f.verts) < 3 or f.calc_area() < 1e-8]
    if bad:
        bmesh.ops.delete(bm, geom=bad, context="FACES")
    if len(bm.faces) == 0:
        bm.free()
        return None

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))

    verts_co = [v.co for v in bm.verts]
    center = Vector(
        (
            sum(v.x for v in verts_co) / len(verts_co),
            sum(v.y for v in verts_co) / len(verts_co),
            sum(v.z for v in verts_co) / len(verts_co),
        )
    )
    bmesh.ops.translate(bm, verts=list(bm.verts), vec=-center)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.location = center
    return obj


def blender_to_roblox_pos(pt: Vector) -> List[float]:
    return [round(-pt.x, 4), round(pt.z, 4), round(pt.y, 4)]


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


def main() -> None:
    assert_no_overwrites()
    reset_scene()
    col = ensure_collection("ArticulatedMonster_v2")
    origin_marker = create_origin_marker(col)

    palette = {
        "Hide": make_mat("MArt2_Mat_Hide", (0.14, 0.11, 0.15), 0.55, 0.05),
        "Carapace": make_mat("MArt2_Mat_Carapace", (0.08, 0.08, 0.10), 0.32, 0.35),
        "VoidCore": make_mat("MArt2_Mat_VoidCore", (0.015, 0.015, 0.03), 0.15, 0.0),
        "Bronze": make_mat("MArt2_Mat_Bronze", (0.54, 0.46, 0.38), 0.38, 0.85),
        "Bone": make_mat("MArt2_Mat_Bone", (0.88, 0.82, 0.73), 0.30, 0.10),
        "Neon": make_mat("MArt2_Mat_Neon", (1.0, 0.42, 0.09), 0.18, 0.0, (1.0, 0.35, 0.06), 6.0),
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
    arm = next(o for o in loaded if o.name == "Monster_Armature")

    # Measure undeformed rest-pose Z span directly from src_o.data.vertices
    all_z: List[float] = []
    for name in ("Monster_CoreBody_Skinned", "Monster_RibcageAndShackles_Skinned", "Monster_Stage1_Apex_Skinned"):
        src_o = next(o for o in loaded if o.name == name)
        for v in src_o.data.vertices:
            all_z.append(v.co.z)

    zmin = min(all_z)
    zmax = max(all_z)
    norm_scale = TARGET_STAGE1_HEIGHT_STUDS / max(0.1, zmax - zmin)
    t_norm = Matrix.Diagonal((norm_scale, norm_scale, norm_scale, 1.0)) @ Matrix.Translation((0.0, 0.0, -zmin))

    def bone_rest_pivot(bname: str) -> Vector:
        return t_norm @ arm.data.bones[bname].head_local

    joint_pivots_blender: Dict[str, Vector] = {
        "Root": Vector((0.0, 0.0, 0.0)),
        "Pelvis": bone_rest_pivot("pelvis"),
        "Chest": bone_rest_pivot("spine_2"),
        "Head": bone_rest_pivot("head"),
        "CrownL": (bone_rest_pivot("crown_1_1") + bone_rest_pivot("crown_2_1")) * 0.5,
        "CrownR": (bone_rest_pivot("crown_5_1") + bone_rest_pivot("crown_6_1")) * 0.5,
        "ArmUpL": bone_rest_pivot("arm_up_sh_l"),
        "ForeUpL": bone_rest_pivot("arm_up_lo_l"),
        "ArmUpR": bone_rest_pivot("arm_up_sh_r"),
        "ForeUpR": bone_rest_pivot("arm_up_lo_r"),
        "ArmLoL": bone_rest_pivot("arm_lo_up_l"),
        "ArmLoR": bone_rest_pivot("arm_lo_up_r"),
    }
    for tid in range(6):
        joint_pivots_blender[f"Tent{tid}"] = bone_rest_pivot(f"tent_{tid}_1")

    buckets: Dict[Tuple[str, str, str], bmesh.types.BMesh] = {}

    def get_bm(joint: str, stage_tag: str, mat_key: str) -> bmesh.types.BMesh:
        key = (joint, stage_tag, mat_key)
        bm = buckets.get(key)
        if bm is None:
            bm = bmesh.new()
            buckets[key] = bm
        return bm

    head_p = joint_pivots_blender["Head"]

    for src_name, stage_tag in source_specs:
        src_o = next(o for o in loaded if o.name == src_name)
        me = src_o.data
        vgroup_names = [vg.name for vg in src_o.vertex_groups]
        src_mats = [m.name.split(".")[0] if m else "" for m in me.materials]

        vert_joint: List[str] = []
        for v in me.vertices:
            j_weights: Dict[str, float] = {}
            for g in v.groups:
                if g.group < len(vgroup_names):
                    j = BONE_TO_JOINT.get(vgroup_names[g.group])
                    if j:
                        j_weights[j] = j_weights.get(j, 0.0) + g.weight
            best_j = max(j_weights.items(), key=lambda kv: kv[1])[0] if j_weights else "Chest"
            vert_joint.append(best_j)

        for poly in me.polygons:
            v_ids = list(poly.vertices)
            if len(v_ids) < 3:
                continue
            counts: Dict[str, int] = {}
            cent = Vector((0.0, 0.0, 0.0))
            for vid in v_ids:
                j = vert_joint[vid]
                counts[j] = counts.get(j, 0) + 1
                cent += t_norm @ me.vertices[vid].co
            cent /= float(len(v_ids))
            joint = max(counts.items(), key=lambda kv: kv[1])[0]

            raw_m = src_mats[poly.material_index] if poly.material_index < len(src_mats) else ""
            mat_key = "Hide"
            for k, bname in MAT_TO_BUCKET.items():
                if raw_m.startswith(k):
                    mat_key = bname
                    break

            if stage_tag in ("S1", "S2", "S3") and joint == "Head":
                if (cent - head_p).length > 1.05 or mat_key == "Carapace":
                    joint = "CrownL" if cent.x >= 0.0 else "CrownR"

            bm_dst = get_bm(joint, stage_tag, mat_key)
            v0 = bm_dst.verts.new(t_norm @ me.vertices[v_ids[0]].co)
            for i in range(1, len(v_ids) - 1):
                va = bm_dst.verts.new(t_norm @ me.vertices[v_ids[i]].co)
                vb = bm_dst.verts.new(t_norm @ me.vertices[v_ids[i + 1]].co)
                try:
                    bm_dst.faces.new((v0, va, vb))
                except ValueError:
                    pass

    objs: List[bpy.types.Object] = [origin_marker]
    for (joint, stage_tag, mat_key), bm_dst in sorted(buckets.items()):
        oname = f"MArt_{joint}_{stage_tag}_{mat_key}"
        obj = create_mesh_object_from_bmesh(oname, bm_dst, palette[mat_key], col)
        if obj is not None:
            objs.append(obj)

    for o in loaded:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)

    # Render clean preview centered on the upright rest-pose Monster
    scene = bpy.context.scene
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.04, 0.045, 0.055, 1.0)
        bg.inputs["Strength"].default_value = 0.9

    ld = bpy.data.lights.new("KeySun", "SUN")
    ld.energy = 4.0
    lo = bpy.data.objects.new("KeySun", ld)
    col.objects.link(lo)
    lo.location = (6.0, -12.0, 12.0)
    lo.rotation_euler = (math.radians(52), 0.0, math.radians(24))

    cam_d = bpy.data.cameras.new("PreviewCam")
    cam_d.lens = 35
    cam_o = bpy.data.objects.new("PreviewCam", cam_d)
    col.objects.link(cam_o)
    cam_o.location = (0.0, -22.0, 7.2)
    cam_o.rotation_euler = (Vector((0.0, 0.0, 6.2)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_o
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = str(OUT_PREVIEW)
    bpy.ops.render.render(write_still=True)

    bpy.data.objects.remove(lo, do_unlink=True)
    bpy.data.objects.remove(cam_o, do_unlink=True)

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

    fauna_data = json.loads(SRC_MANIFEST_V1.read_text(encoding="utf-8")).get("fauna", {})
    manifest = {
        "version": "v2",
        "monster": {
            "stage1HeightStuds": round(TARGET_STAGE1_HEIGHT_STUDS, 3),
            "meshCount": len(objs) - 1,
            "joints": {k: blender_to_roblox_pos(v) for k, v in joint_pivots_blender.items()},
        },
        "fauna": fauna_data,
    }
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("SUCCESS_V2:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
