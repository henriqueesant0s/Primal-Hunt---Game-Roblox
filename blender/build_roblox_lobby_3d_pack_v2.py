"""Builds the 3 separate Roblox-ready 3D Lobby GLB packs (v2) + verification .blend
strictly preserving all existing files on disk (zero overwrites).

Fixes vs v1:
  - Links loaded collections from OrbitalDropshipLobby.blend to active Scene before reading
    matrix_world so ALL localized bays/panels/bulkheads preserve their true spatial offsets.
  - Uses verified Assault_R15_Rig local bone axes (inward-tucked arms holding weapons cleanly).
  - Auto-grounds each evaluated Hunter class (Trapper, Medic, Support) so boots rest at Z = 0.75.

Outputs (brand new _v2 files):
  - Lobby3D_HangarArchitecture_v2.glb
  - Lobby3D_MonsterCenterpiece_v2.glb
  - Lobby3D_ClassBasesAndHunters_v2.glb
  - Lobby3D_CompleteAssembly_v2.blend
  - lobby_3d_roblox_manifest_v2.json
  - previews/lobby3d_assembly_v2_view_1..2.png
"""

from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
PREVIEWS_DIR = ROOT_DIR / "previews"
PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)

# Read-only source files (NEVER modified)
SRC_HANGAR_BLEND = ROOT_DIR / "OrbitalDropshipLobby.blend"
SRC_MONSTER_BLEND = ROOT_DIR / "AbyssMonster.blend"
SRC_ASSAULT_BLEND = Path(
    r"C:\Users\Usuario\.gemini\antigravity\brain\ab208d61-aaf3-4da6-93fd-78e81f4ae04f\.user_uploaded\media_1794977980551_12fd0102.blend"
)

# Strictly new output paths (guarded against overwrite)
HANGAR_GLB = ROOT_DIR / "Lobby3D_HangarArchitecture_v2.glb"
MONSTER_GLB = ROOT_DIR / "Lobby3D_MonsterCenterpiece_v2.glb"
CLASSES_GLB = ROOT_DIR / "Lobby3D_ClassBasesAndHunters_v2.glb"
ASSEMBLY_BLEND = ROOT_DIR / "Lobby3D_CompleteAssembly_v2.blend"
MANIFEST_JSON = ROOT_DIR / "lobby_3d_roblox_manifest_v2.json"
PREVIEW_1 = PREVIEWS_DIR / "lobby3d_assembly_v2_view_1.png"
PREVIEW_2 = PREVIEWS_DIR / "lobby3d_assembly_v2_view_2.png"

STUDS_PER_METER = 1.0 / 0.28  # 3.5714285714...
DAIS_TOP_Z_STUDS = 0.485 * STUDS_PER_METER  # ~1.7321 studs

# Class flanking layout in Blender stud-space (Blender X = Roblox X, Blender Y = -Roblox Z, Blender Z = Roblox Y)
CLASS_PLACEMENTS = [
    {"role": "Assault", "bx": -16.0, "by": -21.0, "rx": -16.0, "rz": 21.0, "accent": (0.90, 0.85, 0.72)},
    {"role": "Trapper", "bx": -23.5, "by": -11.0, "rx": -23.5, "rz": 11.0, "accent": (1.00, 0.69, 0.00)},
    {"role": "Medic",   "bx":  16.0, "by": -21.0, "rx":  16.0, "rz": 21.0, "accent": (0.22, 1.00, 0.08)},
    {"role": "Support", "bx":  23.5, "by": -11.0, "rx":  23.5, "rz": 11.0, "accent": (0.00, 0.90, 1.00)},
]
SPAWN_TARGET_BLENDER = Vector((0.0, -40.0, 0.0))  # LobbySpawn in Roblox (0, 600, +40) -> Blender (0, -40, 0)
HUNTER_SCALE = 1.20  # 1.20x R15 (~6.27 studs tall) on top of 0.75-stud pedestals


def assert_no_overwrites() -> None:
    targets = [HANGAR_GLB, MONSTER_GLB, CLASSES_GLB, ASSEMBLY_BLEND, MANIFEST_JSON, PREVIEW_1, PREVIEW_2]
    existing = [str(p) for p in targets if p.exists()]
    assert not existing, f"Safety abort: target file(s) already exist: {existing}"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def ensure_collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
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
    alpha: float = 1.0,
    emission: Tuple[float, float, float] | None = None,
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
    bsdf.inputs["Alpha"].default_value = alpha
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 0.99 and hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def create_palette() -> Dict[str, bpy.types.Material]:
    return {
        "DarkSteel": make_mat("V2_Mat_DarkSteel", (0.07, 0.085, 0.105), 0.42, 0.85),
        "ArmorGrey": make_mat("V2_Mat_ArmorGrey", (0.21, 0.24, 0.28), 0.48, 0.55),
        "HeavyArmor": make_mat("V2_Mat_HeavyArmor", (0.28, 0.32, 0.38), 0.45, 0.65),
        "Grating": make_mat("V2_Mat_Grating", (0.045, 0.055, 0.065), 0.58, 0.72),
        "HazardYellow": make_mat("V2_Mat_HazardYellow", (0.85, 0.54, 0.03), 0.45, 0.15),
        "Glass": make_mat("V2_Mat_Glass", (0.22, 0.64, 0.82), 0.10, 0.0, alpha=0.30),
        "NeonCyan": make_mat("V2_Mat_NeonCyan", (0.0, 0.85, 1.0), 0.15, 0.0, emission=(0.0, 0.85, 1.0), emission_strength=4.5),
        "NeonAmber": make_mat("V2_Mat_NeonAmber", (1.0, 0.44, 0.04), 0.15, 0.0, emission=(1.0, 0.44, 0.04), emission_strength=4.5),
        "NeonCrimson": make_mat("V2_Mat_NeonCrimson", (1.0, 0.20, 0.08), 0.15, 0.0, emission=(1.0, 0.22, 0.06), emission_strength=5.2),
        "NeonGreen": make_mat("V2_Mat_NeonGreen", (0.18, 1.0, 0.10), 0.15, 0.0, emission=(0.18, 1.0, 0.10), emission_strength=4.5),
        "NeonIvory": make_mat("V2_Mat_NeonIvory", (0.92, 0.86, 0.68), 0.15, 0.0, emission=(0.92, 0.86, 0.68), emission_strength=4.0),
        "VoidFlesh": make_mat("V2_Mat_VoidFlesh", (0.11, 0.08, 0.10), 0.68, 0.05),
        "ObsidianPlates": make_mat("V2_Mat_ObsidianPlates", (0.055, 0.055, 0.075), 0.28, 0.55),
        "ShacklesAndVoid": make_mat("V2_Mat_ShacklesAndVoid", (0.38, 0.30, 0.22), 0.38, 0.80),
        "BoneClaws": make_mat("V2_Mat_BoneClaws", (0.78, 0.72, 0.62), 0.35, 0.08),
        "SolarFurnace": make_mat("V2_Mat_SolarFurnace", (1.0, 0.35, 0.05), 0.12, 0.0, emission=(1.0, 0.36, 0.06), emission_strength=8.0),
        "Skin": make_mat("V2_Mat_Skin", (0.68, 0.52, 0.42), 0.62, 0.0),
        "Hair": make_mat("V2_Mat_Hair", (0.09, 0.08, 0.07), 0.72, 0.0),
        "TrapperCloth": make_mat("V2_Mat_TrapperCloth", (0.18, 0.20, 0.14), 0.75, 0.05),
        "TrapperArmor": make_mat("V2_Mat_TrapperArmor", (0.34, 0.30, 0.19), 0.45, 0.55),
        "MedicCloth": make_mat("V2_Mat_MedicCloth", (0.16, 0.22, 0.20), 0.70, 0.05),
        "MedicArmor": make_mat("V2_Mat_MedicArmor", (0.76, 0.80, 0.82), 0.35, 0.35),
        "SupportCloth": make_mat("V2_Mat_SupportCloth", (0.14, 0.18, 0.25), 0.72, 0.05),
        "SupportArmor": make_mat("V2_Mat_SupportArmor", (0.22, 0.32, 0.44), 0.40, 0.62),
    }


def apply_box_uv(bm: bmesh.types.BMesh, scale: float = 0.25) -> None:
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                loop[uv_layer].uv = (co.x * scale, co.y * scale)
            elif ax >= ay and ax >= az:
                loop[uv_layer].uv = (co.y * scale, co.z * scale)
            else:
                loop[uv_layer].uv = (co.x * scale, co.z * scale)


def create_mesh_object_from_bmesh(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    recenter: bool = True,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_box_uv(bm, scale=0.20)
    bmesh.ops.triangulate(bm, faces=bm.faces)

    center = Vector((0.0, 0.0, 0.0))
    if recenter and len(bm.verts) > 0:
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        zs = [v.co.z for v in bm.verts]
        center = Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, (min(zs) + max(zs)) * 0.5))
        for v in bm.verts:
            v.co -= center

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = center
    col.objects.link(obj)
    return obj


def bm_add_box(bm: bmesh.types.BMesh, size: Tuple[float, float, float], xf: Matrix = Matrix.Identity(4)) -> None:
    res = bmesh.ops.create_cube(bm, size=1.0)
    m = xf @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    for v in res["verts"]:
        v.co = m @ v.co


def bm_add_cyl(
    bm: bmesh.types.BMesh,
    radius1: float,
    radius2: float,
    depth: float,
    segments: int = 12,
    xf: Matrix = Matrix.Identity(4),
) -> None:
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
    )
    for v in res["verts"]:
        v.co = xf @ v.co


def add_origin_marker(col: bpy.types.Collection, mat: bpy.types.Material, marker_name: str) -> bpy.types.Object:
    bm = bmesh.new()
    bm_add_box(bm, (0.6, 0.6, 0.6), Matrix.Identity(4))
    return create_mesh_object_from_bmesh(marker_name, bm, mat, col, recenter=False)


def append_world_mesh_into_bmesh(
    dst_bm: bmesh.types.BMesh,
    src_obj: bpy.types.Object,
    world_xf: Matrix,
) -> int:
    mesh = src_obj.data
    added_tris = 0
    for poly in mesh.polygons:
        v_ids = list(poly.vertices)
        if len(v_ids) < 3:
            continue
        v0 = dst_bm.verts.new(world_xf @ mesh.vertices[v_ids[0]].co)
        for i in range(1, len(v_ids) - 1):
            va = dst_bm.verts.new(world_xf @ mesh.vertices[v_ids[i]].co)
            vb = dst_bm.verts.new(world_xf @ mesh.vertices[v_ids[i + 1]].co)
            try:
                dst_bm.faces.new((v0, va, vb))
                added_tris += 1
            except ValueError:
                pass
    return added_tris


# ---------------------------------------------------------------------------
# PART 1: Build 3D Orbital Dropship Hangar Architecture
# ---------------------------------------------------------------------------

def build_hangar_pack(palette: Dict[str, bpy.types.Material]) -> Tuple[bpy.types.Collection, List[bpy.types.Object]]:
    col = ensure_collection("Pack1_HangarArchitecture")

    with bpy.data.libraries.load(str(SRC_HANGAR_BLEND), link=False) as (data_from, data_to):
        data_to.collections = [
            "01_Floor_And_Substructure",
            "02_Walls_Pillars_And_Ceiling",
            "03_Panoramic_Observation_Bay",
            "05_Hunter_Loadout_Bays",
            "06_Dropship_Airlock_And_Monster_Pod",
        ]

    loaded_cols = [c for c in data_to.collections if c is not None]
    # CRITICAL: link temporary collections to scene & update view_layer BEFORE reading matrix_world!
    for c in loaded_cols:
        bpy.context.scene.collection.children.link(c)
    bpy.context.view_layer.update()

    HANGAR_MAT_MAP = {
        "Mat_Hull_DarkSteel": ("DarkSteel", palette["DarkSteel"]),
        "Mat_Wall_ArmorGrey": ("ArmorGrey", palette["ArmorGrey"]),
        "Mat_Floor_Grating": ("Grating", palette["Grating"]),
        "Mat_Trim_HazardYellow": ("HazardYellow", palette["HazardYellow"]),
        "Mat_Glass_Observation": ("Glass", palette["Glass"]),
        "Mat_Neon_Cyan": ("NeonCyan", palette["NeonCyan"]),
        "Mat_Neon_AmberAlert": ("NeonAmber", palette["NeonAmber"]),
    }

    def classify_zone(obj: bpy.types.Object, col_name: str) -> str | None:
        n = obj.name
        if n in ("MonsterPod_DisplayPlatform", "MonsterPod_HazardRing", "MonsterPod_ContainmentArches"):
            return None
        if col_name == "01_Floor_And_Substructure":
            if "Octagon" in n or "Ramp" in n:
                return "Hangar_CenterDais"
            return "Hangar_Floor"
        if col_name == "03_Panoramic_Observation_Bay":
            return "Hangar_NorthObs"
        if col_name == "05_Hunter_Loadout_Bays":
            return "Hangar_WestBays"
        if col_name == "06_Dropship_Airlock_And_Monster_Pod":
            if "MonsterPod" in n:
                return "Hangar_EastGen"
            return "Hangar_SouthAirlock"
        if col_name == "02_Walls_Pillars_And_Ceiling":
            if "West" in n:
                return "Hangar_WestWall"
            if "East" in n:
                return "Hangar_EastWall"
            return "Hangar_Ceiling"
        return "Hangar_Misc"

    scale_to_studs = Matrix.Diagonal((STUDS_PER_METER, STUDS_PER_METER, STUDS_PER_METER, 1.0))
    zone_mat_bms: Dict[Tuple[str, str], Tuple[bmesh.types.BMesh, bpy.types.Material]] = {}
    garbage_objs: List[bpy.types.Object] = []

    for c in loaded_cols:
        for obj in c.all_objects:
            garbage_objs.append(obj)
            if obj.type != "MESH" or len(obj.data.polygons) == 0:
                continue
            zone = classify_zone(obj, c.name)
            if zone is None:
                continue
            src_mat_name = obj.data.materials[0].name if obj.data.materials else "Mat_Wall_ArmorGrey"
            mat_suffix, v_mat = HANGAR_MAT_MAP.get(src_mat_name, ("ArmorGrey", palette["ArmorGrey"]))
            key = (zone, mat_suffix)
            if key not in zone_mat_bms:
                zone_mat_bms[key] = (bmesh.new(), v_mat)
            bm, _ = zone_mat_bms[key]
            append_world_mesh_into_bmesh(bm, obj, scale_to_studs @ obj.matrix_world)

    created_objs: List[bpy.types.Object] = []
    for (zone, mat_suffix), (bm, mat) in sorted(zone_mat_bms.items()):
        if len(bm.faces) == 0:
            bm.free()
            continue
        created_objs.append(create_mesh_object_from_bmesh(f"{zone}_{mat_suffix}", bm, mat, col, recenter=True))

    # Unlink & remove temporary loaded collections/objects without purging palette
    for c in loaded_cols:
        bpy.context.scene.collection.children.unlink(c)
        bpy.data.collections.remove(c)
    for o in garbage_objs:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)

    return col, created_objs


# ---------------------------------------------------------------------------
# PART 2: Build Central 3D Monster + Containment Base + Tactical Console
# ---------------------------------------------------------------------------

def load_stage_pedestal_meshes() -> Dict[str, bpy.types.Mesh]:
    names = ["Stage_Pedestal_Base", "Stage_Pedestal_Deck", "Stage_Pedestal_AmberRing", "Stage_Pedestal_HazardTabs"]
    with bpy.data.libraries.load(str(SRC_ASSAULT_BLEND), link=False) as (data_from, data_to):
        data_to.objects = list(names)

    out_meshes: Dict[str, bpy.types.Mesh] = {}
    for o in data_to.objects:
        if o is not None and o.type == "MESH":
            m_copy = o.data.copy()
            m_copy.name = f"TemplateMesh_{o.name}"
            m_copy.use_fake_user = True
            out_meshes[o.name] = m_copy
            bpy.data.objects.remove(o, do_unlink=True)
    return out_meshes


def build_pedestal_instance(
    prefix: str,
    center_xy: Tuple[float, float],
    base_z: float,
    yaw_rad: float,
    diameter_studs: float,
    height_studs: float,
    pedestal_meshes: Dict[str, bpy.types.Mesh],
    palette: Dict[str, bpy.types.Material],
    col: bpy.types.Collection,
    accent_mat: bpy.types.Material,
) -> List[bpy.types.Object]:
    s_xy = diameter_studs / 1.676
    s_z = height_studs / 0.115
    xf = (
        Matrix.Translation((center_xy[0], center_xy[1], base_z + height_studs))
        @ Matrix.Rotation(yaw_rad, 4, "Z")
        @ Matrix.Diagonal((s_xy, s_xy, s_z, 1.0))
    )
    spec = [
        ("Stage_Pedestal_Base", f"{prefix}_DarkSteel", palette["DarkSteel"]),
        ("Stage_Pedestal_Deck", f"{prefix}_HeavyArmor", palette["HeavyArmor"]),
        ("Stage_Pedestal_HazardTabs", f"{prefix}_HazardYellow", palette["HazardYellow"]),
        ("Stage_Pedestal_AmberRing", f"{prefix}_NeonAccent", accent_mat),
    ]
    objs: List[bpy.types.Object] = []
    for src_name, obj_name, mat in spec:
        mesh = pedestal_meshes[src_name]
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.transform(bm, matrix=xf, verts=bm.verts)
        objs.append(create_mesh_object_from_bmesh(obj_name, bm, mat, col, recenter=True))
    return objs


def build_monster_centerpiece_pack(
    palette: Dict[str, bpy.types.Material],
    pedestal_meshes: Dict[str, bpy.types.Mesh],
) -> Tuple[bpy.types.Collection, List[bpy.types.Object]]:
    col = ensure_collection("Pack2_MonsterCenterpiece")
    objs: List[bpy.types.Object] = []

    # 1. Central Containment Pedestal resting flush on Octagon Dais (Z = DAIS_TOP_Z_STUDS = ~1.732)
    ped_diam = 19.5
    ped_h = 0.85
    objs.extend(
        build_pedestal_instance(
            prefix="MonsterStage",
            center_xy=(0.0, 0.0),
            base_z=DAIS_TOP_Z_STUDS,
            yaw_rad=0.0,
            diameter_studs=ped_diam,
            height_studs=ped_h,
            pedestal_meshes=pedestal_meshes,
            palette=palette,
            col=col,
            accent_mat=palette["NeonCrimson"],
        )
    )
    deck_top_z = DAIS_TOP_Z_STUDS + ped_h  # ~2.582 studs

    # 4 Diagonal Containment Pylons with snapped chain links around rim
    bm_pylon_steel = bmesh.new()
    bm_pylon_haz = bmesh.new()
    bm_pylon_neon = bmesh.new()
    for a_deg in (45, 135, 225, 315):
        ang = math.radians(a_deg)
        r = ped_diam * 0.43
        px, py = math.cos(ang) * r, math.sin(ang) * r
        yaw = ang + math.pi * 0.5
        base_xf = Matrix.Translation((px, py, deck_top_z)) @ Matrix.Rotation(yaw, 4, "Z")
        bm_add_box(bm_pylon_steel, (1.8, 1.4, 2.8), base_xf @ Matrix.Translation((0.0, 0.0, 1.4)))
        bm_add_box(bm_pylon_steel, (2.2, 1.8, 0.55), base_xf @ Matrix.Translation((0.0, 0.0, 0.275)))
        bm_add_box(bm_pylon_haz, (1.5, 0.45, 0.45), base_xf @ Matrix.Translation((0.0, 0.6, 2.3)))
        bm_add_box(bm_pylon_neon, (0.32, 0.32, 2.1), base_xf @ Matrix.Translation((0.0, -0.68, 1.45)))
        in_dir = Vector((-px, -py, 0.0)).normalized()
        for c_i in range(3):
            p_c = Vector((px, py, deck_top_z + 1.8 - c_i * 0.45)) + in_dir * (0.9 + c_i * 0.55)
            bm_add_box(bm_pylon_steel, (0.36, 0.52, 0.24), Matrix.Translation(p_c) @ Matrix.Rotation(yaw + c_i * 0.4, 4, "Z"))

    objs.append(create_mesh_object_from_bmesh("MonsterStage_Pylons_DarkSteel", bm_pylon_steel, palette["DarkSteel"], col))
    objs.append(create_mesh_object_from_bmesh("MonsterStage_Pylons_HazardYellow", bm_pylon_haz, palette["HazardYellow"], col))
    objs.append(create_mesh_object_from_bmesh("MonsterStage_Pylons_NeonCrimson", bm_pylon_neon, palette["NeonCrimson"], col))

    # 2. Central 3D Tactical Role Terminal Console in front of South Ramp (Blender Y = -27.5, Z = 0, facing -Y)
    bm_con_steel = bmesh.new()
    bm_con_haz = bmesh.new()
    bm_con_scr = bmesh.new()
    con_xf = Matrix.Translation((0.0, -27.5, 0.0))
    bm_add_box(bm_con_steel, (8.6, 3.4, 0.45), con_xf @ Matrix.Translation((0.0, 0.0, 0.225)))
    bm_add_box(bm_con_steel, (6.8, 2.2, 2.75), con_xf @ Matrix.Translation((0.0, 0.2, 1.60)))
    bm_add_box(bm_con_steel, (7.6, 2.4, 0.65), con_xf @ Matrix.Translation((0.0, 0.05, 3.15)) @ Matrix.Rotation(math.radians(32), 4, "X"))
    bm_add_box(bm_con_haz, (8.8, 0.45, 0.14), con_xf @ Matrix.Translation((0.0, -1.65, 0.48)))
    bm_add_box(bm_con_scr, (6.8, 1.85, 0.14), con_xf @ Matrix.Translation((0.0, -0.05, 3.55)) @ Matrix.Rotation(math.radians(32), 4, "X"))
    objs.append(create_mesh_object_from_bmesh("CentralTerminal_DarkSteel", bm_con_steel, palette["DarkSteel"], col))
    objs.append(create_mesh_object_from_bmesh("CentralTerminal_HazardYellow", bm_con_haz, palette["HazardYellow"], col))
    objs.append(create_mesh_object_from_bmesh("CentralTerminal_NeonScreen", bm_con_scr, palette["NeonCyan"], col))

    # 3. 3D Monster Arauto do Eclipse Abissal posed from AbyssMonster.blend at exact center (0, 0, deck_top_z)
    with bpy.data.libraries.load(str(SRC_MONSTER_BLEND), link=False) as (data_from, data_to):
        data_to.objects = [
            "Monster_Armature",
            "Monster_CoreBody_Skinned",
            "Monster_RibcageAndShackles_Skinned",
            "Monster_Stage3_EclipseGod_Skinned",
        ]
        data_to.actions = ["Monster_Intro_Roar"]

    loaded_monster_objs = [o for o in data_to.objects if o is not None]
    arm = next(o for o in loaded_monster_objs if o.type == "ARMATURE")
    temp_col = ensure_collection("TEMP_Monster_Eval")
    for o in loaded_monster_objs:
        temp_col.objects.link(o)

    act = next((a for a in data_to.actions if a is not None and a.name.startswith("Monster_Intro_Roar")), None)
    if act is not None:
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = act
        if hasattr(act, "slots") and act.slots:
            arm.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(30)
    bpy.context.view_layer.update()

    deps = bpy.context.evaluated_depsgraph_get()
    skin_meshes = [
        o for o in loaded_monster_objs
        if o.type == "MESH" and o.name.startswith(("Monster_CoreBody_Skinned", "Monster_RibcageAndShackles_Skinned", "Monster_Stage3_EclipseGod_Skinned"))
    ]

    eval_tris: Dict[str, bmesh.types.BMesh] = {
        "VoidFlesh": bmesh.new(),
        "ObsidianPlates": bmesh.new(),
        "ShacklesAndVoid": bmesh.new(),
        "BoneClaws": bmesh.new(),
        "SolarFurnace": bmesh.new(),
    }

    MAT_TO_BUCKET = {
        "Mat_Monster_AbyssalHide": "VoidFlesh",
        "Mat_Monster_ObsidianCarapace": "ObsidianPlates",
        "Mat_Eclipse_DarkRibChitin": "ObsidianPlates",
        "Mat_Eclipse_BronzeShackle": "ShacklesAndVoid",
        "Mat_Eclipse_VoidBlack": "ShacklesAndVoid",
        "Mat_Monster_BoneClaws": "BoneClaws",
        "Mat_Furnace_OuterEmber": "SolarFurnace",
        "Mat_Furnace_MoltenHeart": "SolarFurnace",
        "Mat_Eclipse_SolarCorona_S3": "SolarFurnace",
        "Mat_Eclipse_SolarRim_S3": "SolarFurnace",
    }

    all_z = []
    for src_o in skin_meshes:
        ev = src_o.evaluated_get(deps)
        tmp_mesh = ev.to_mesh()
        for v in tmp_mesh.vertices:
            w = ev.matrix_world @ v.co
            all_z.append(w.z)
        ev.to_mesh_clear()

    m_zmin = min(all_z)
    m_zmax = max(all_z)
    m_height = max(0.1, m_zmax - m_zmin)
    m_cx = arm.location.x
    m_cy = arm.location.y
    target_monster_height_studs = 19.0
    m_scale = target_monster_height_studs / m_height

    monster_place_xf = (
        Matrix.Translation((0.0, 0.0, deck_top_z - 0.04))
        @ Matrix.Diagonal((m_scale, m_scale, m_scale, 1.0))
        @ Matrix.Translation((-m_cx, -m_cy, -m_zmin))
    )

    for src_o in skin_meshes:
        ev = src_o.evaluated_get(deps)
        tmp_mesh = ev.to_mesh()
        src_mats = [m.name.split(".")[0] if m else "" for m in tmp_mesh.materials]
        xf = monster_place_xf @ ev.matrix_world

        for poly in tmp_mesh.polygons:
            raw_m = src_mats[poly.material_index] if poly.material_index < len(src_mats) else ""
            bucket = None
            for k, bname in MAT_TO_BUCKET.items():
                if raw_m.startswith(k):
                    bucket = bname
                    break
            if bucket is None:
                bucket = "VoidFlesh"
            bm_dst = eval_tris[bucket]
            v_ids = list(poly.vertices)
            if len(v_ids) < 3:
                continue
            v0 = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[0]].co)
            for i in range(1, len(v_ids) - 1):
                va = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[i]].co)
                vb = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[i + 1]].co)
                try:
                    bm_dst.faces.new((v0, va, vb))
                except ValueError:
                    pass
        ev.to_mesh_clear()

    BUCKET_TO_OBJ_MAT = {
        "VoidFlesh": ("Monster3D_VoidFlesh", palette["VoidFlesh"]),
        "ObsidianPlates": ("Monster3D_ObsidianPlates", palette["ObsidianPlates"]),
        "ShacklesAndVoid": ("Monster3D_RibcageAndShackles", palette["ShacklesAndVoid"]),
        "BoneClaws": ("Monster3D_BoneClawsAndTeeth", palette["BoneClaws"]),
        "SolarFurnace": ("Monster3D_SolarFurnace_Neon", palette["SolarFurnace"]),
    }

    for bkey, bm_dst in eval_tris.items():
        if len(bm_dst.faces) == 0:
            bm_dst.free()
            continue
        oname, omat = BUCKET_TO_OBJ_MAT[bkey]
        objs.append(create_mesh_object_from_bmesh(oname, bm_dst, omat, col, recenter=True))

    bpy.context.scene.collection.children.unlink(temp_col)
    bpy.data.collections.remove(temp_col)
    for o in loaded_monster_objs:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in data_to.actions:
        if a is not None and a.users == 0:
            bpy.data.actions.remove(a)

    return col, objs


# ---------------------------------------------------------------------------
# PART 3: Build Flanking 3D Class Pedestals & Heroic 3D Class Models
# ---------------------------------------------------------------------------

def build_class_plaque(
    role: str,
    center_xy: Tuple[float, float],
    yaw_rad: float,
    accent_mat: bpy.types.Material,
    palette: Dict[str, bpy.types.Material],
    col: bpy.types.Collection,
) -> List[bpy.types.Object]:
    fwd = Matrix.Rotation(yaw_rad, 4, "Z") @ Vector((0.0, -1.0, 0.0))
    totem_xy = Vector((center_xy[0], center_xy[1], 0.0)) + fwd * 4.45
    xf = Matrix.Translation(totem_xy) @ Matrix.Rotation(yaw_rad, 4, "Z")

    bm_body = bmesh.new()
    bm_body_haz = bmesh.new()
    bm_scr = bmesh.new()
    bm_add_box(bm_body, (4.2, 1.35, 0.35), xf @ Matrix.Translation((0.0, 0.0, 0.175)))
    bm_add_box(bm_body, (3.6, 0.90, 2.25), xf @ Matrix.Translation((0.0, 0.05, 1.30)))
    bm_add_box(bm_body, (3.9, 1.05, 0.45), xf @ Matrix.Translation((0.0, 0.0, 2.55)) @ Matrix.Rotation(math.radians(32), 4, "X"))
    bm_add_box(bm_body_haz, (3.8, 0.25, 0.12), xf @ Matrix.Translation((0.0, -0.58, 0.40)))
    bm_add_box(bm_scr, (3.4, 0.90, 0.10), xf @ Matrix.Translation((0.0, -0.10, 2.84)) @ Matrix.Rotation(math.radians(32), 4, "X"))

    return [
        create_mesh_object_from_bmesh(f"ClassPlaque_{role}_DarkSteel", bm_body, palette["DarkSteel"], col),
        create_mesh_object_from_bmesh(f"ClassPlaque_{role}_HazardYellow", bm_body_haz, palette["HazardYellow"], col),
        create_mesh_object_from_bmesh(f"ClassPlaque_{role}_Screen", bm_scr, accent_mat, col),
    ]


def pose_r15_rig(arm: bpy.types.Object, role: str) -> None:
    """Verified poses using true bone local axes (Left/RightUpperArm z_axis=-Z -> rz +10 tucks Left IN, rz -10 tucks Right IN)."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)

    def set_rot(bname: str, rx: float, ry: float, rz: float) -> None:
        if bname in arm.pose.bones:
            arm.pose.bones[bname].rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))

    if role == "Assault":
        set_rot("LowerTorso", 0, 0, -4)
        set_rot("UpperTorso", -2, 0, 6)
        set_rot("Head", 2, 0, -2)
        set_rot("LeftUpperLeg", -6, 0, -2)
        set_rot("LeftLowerLeg", 8, 0, 0)
        set_rot("RightUpperLeg", 6, 0, 2)
        set_rot("RightLowerLeg", 4, 0, 0)
        set_rot("LeftUpperArm", -26, 0, 12)
        set_rot("LeftLowerArm", -48, 0, 0)
        set_rot("RightUpperArm", -40, 0, -8)
        set_rot("RightLowerArm", -36, 0, 0)
    elif role == "Trapper":
        set_rot("LowerTorso", -3, 0, -8)
        set_rot("UpperTorso", -4, 0, 10)
        set_rot("Head", 4, 0, -4)
        set_rot("LeftUpperLeg", -8, 0, -3)
        set_rot("LeftLowerLeg", 12, 0, 0)
        set_rot("RightUpperLeg", 8, 0, 3)
        set_rot("RightLowerLeg", 6, 0, 0)
        set_rot("LeftUpperArm", -34, 0, 14)
        set_rot("LeftLowerArm", -56, 0, 0)
        set_rot("RightUpperArm", -44, 0, -10)
        set_rot("RightLowerArm", -38, 0, 0)
    elif role == "Medic":
        set_rot("LowerTorso", 0, 0, 6)
        set_rot("UpperTorso", -2, 0, -8)
        set_rot("Head", 2, 0, 2)
        set_rot("LeftUpperLeg", 5, 0, -2)
        set_rot("RightUpperLeg", -6, 0, 2)
        set_rot("RightLowerLeg", 8, 0, 0)
        set_rot("LeftUpperArm", -28, 0, 10)
        set_rot("LeftLowerArm", -62, 0, 0)
        set_rot("RightUpperArm", -42, 0, -10)
        set_rot("RightLowerArm", -34, 0, 0)
    elif role == "Support":
        set_rot("LowerTorso", -2, 0, -8)
        set_rot("UpperTorso", -3, 0, 10)
        set_rot("Head", 3, 0, -4)
        set_rot("LeftUpperLeg", -7, 0, -4)
        set_rot("LeftLowerLeg", 10, 0, 0)
        set_rot("RightUpperLeg", 7, 0, 4)
        set_rot("RightLowerLeg", 6, 0, 0)
        set_rot("LeftUpperArm", -38, 0, 14)
        set_rot("LeftLowerArm", -54, 0, 0)
        set_rot("RightUpperArm", -48, 0, -12)
        set_rot("RightLowerArm", -34, 0, 0)


def build_class_weapon_in_bmesh(
    role: str,
    bms: Dict[str, bmesh.types.BMesh],
    hand_xf: Matrix,
) -> None:
    """Attaches a class-exclusive 3D sci-fi weapon gripped horizontally/forward-slightly-angled in RightHand palm."""
    # RightHand palm in rest space is (-0.391, -0.030, 0.564); with upper arm -42° X and forearm -36° X (total -78° X),
    # rest +Z rotated by -78° around X points along -Y (forward!), and rest -Y points along -Z (down!).
    # So to point gun barrel FORWARD in posed hand, local gun forward aligns along rest +Z or adjust cleanly with +72 deg X!
    gun_xf = hand_xf @ Matrix.Translation((-0.391, -0.06, 0.55)) @ Matrix.Rotation(math.radians(68), 4, "X")

    if role == "Assault":
        bm_add_box(bms["WeaponSteel"], (0.09, 0.72, 0.16), gun_xf @ Matrix.Translation((0.0, -0.20, 0.02)))
        bm_add_box(bms["WeaponSteel"], (0.11, 0.28, 0.12), gun_xf @ Matrix.Translation((0.0, -0.44, 0.0)))
        bm_add_cyl(bms["WeaponSteel"], 0.032, 0.032, 0.42, 8, gun_xf @ Matrix.Translation((0.0, -0.72, 0.04)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
        bm_add_box(bms["WeaponSteel"], (0.06, 0.12, 0.20), gun_xf @ Matrix.Translation((0.0, -0.32, -0.11)) @ Matrix.Rotation(math.radians(15), 4, "X"))
        bm_add_box(bms["WeaponNeon"], (0.105, 0.34, 0.04), gun_xf @ Matrix.Translation((0.0, -0.33, 0.06)))
        bm_add_cyl(bms["WeaponNeon"], 0.038, 0.022, 0.08, 8, gun_xf @ Matrix.Translation((0.0, -0.94, 0.04)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
    elif role == "Trapper":
        bm_add_box(bms["DarkSteel"], (0.08, 0.56, 0.13), gun_xf @ Matrix.Translation((0.0, -0.18, 0.02)))
        bm_add_cyl(bms["Armor"], 0.055, 0.055, 0.22, 10, gun_xf @ Matrix.Translation((0.0, -0.28, -0.04)))
        for sx in (-0.055, 0.055):
            bm_add_box(bms["DarkSteel"], (0.025, 0.44, 0.045), gun_xf @ Matrix.Translation((sx, -0.58, 0.03)))
        bm_add_cyl(bms["NeonAccent"], 0.024, 0.005, 0.50, 8, gun_xf @ Matrix.Translation((0.0, -0.68, 0.03)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
    elif role == "Medic":
        bm_add_box(bms["Armor"], (0.085, 0.52, 0.14), gun_xf @ Matrix.Translation((0.0, -0.18, 0.02)))
        bm_add_cyl(bms["DarkSteel"], 0.028, 0.028, 0.32, 8, gun_xf @ Matrix.Translation((0.0, -0.56, 0.04)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
        bm_add_cyl(bms["NeonAccent"], 0.044, 0.044, 0.19, 10, gun_xf @ Matrix.Translation((0.0, -0.24, -0.07)))
        bm_add_cyl(bms["NeonAccent"], 0.036, 0.020, 0.06, 8, gun_xf @ Matrix.Translation((0.0, -0.73, 0.04)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
    else:
        bm_add_box(bms["DarkSteel"], (0.12, 0.64, 0.18), gun_xf @ Matrix.Translation((0.0, -0.20, 0.02)))
        bm_add_box(bms["Armor"], (0.14, 0.36, 0.14), gun_xf @ Matrix.Translation((0.0, -0.38, 0.03)))
        for rz in (-0.01, 0.06):
            bm_add_cyl(bms["DarkSteel"], 0.026, 0.026, 0.44, 8, gun_xf @ Matrix.Translation((0.0, -0.66, rz)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
        bm_add_cyl(bms["NeonAccent"], 0.065, 0.065, 0.10, 12, gun_xf @ Matrix.Translation((0.0, -0.56, 0.03)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
        bm_add_box(bms["NeonAccent"], (0.145, 0.24, 0.04), gun_xf @ Matrix.Translation((0.0, -0.30, 0.09)))


def append_custom_class_gear(
    role: str,
    arm: bpy.types.Object,
    bms: Dict[str, bmesh.types.BMesh],
    place_xf: Matrix,
) -> None:
    def bone_world(bname: str) -> Matrix:
        pb = arm.pose.bones[bname]
        return place_xf @ arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted()

    m_head = bone_world("Head")
    m_ut = bone_world("UpperTorso")
    m_lt = bone_world("LowerTorso")
    m_lua = bone_world("LeftUpperArm")
    m_rua = bone_world("RightUpperArm")
    m_lla = bone_world("LeftLowerArm")
    m_rla = bone_world("RightLowerArm")
    m_lul = bone_world("LeftUpperLeg")
    m_rul = bone_world("RightUpperLeg")
    m_lll = bone_world("LeftLowerLeg")
    m_rll = bone_world("RightLowerLeg")
    m_rh = bone_world("RightHand")

    bm_add_box(bms["DarkSteel"], (0.60, 0.34, 0.13), m_lt @ Matrix.Translation((0.0, 0.0, 0.60)))
    bm_add_box(bms["Armor"], (0.14, 0.05, 0.08), m_lt @ Matrix.Translation((0.0, -0.17, 0.60)))
    for side, m_ul, m_ll in [(-1.0, m_rul, m_rll), (1.0, m_lul, m_lll)]:
        bm_add_box(bms["Armor"], (0.06, 0.24, 0.18), m_ul @ Matrix.Translation((side * 0.295, 0.0, 0.44)))
        bm_add_box(bms["DarkSteel"], (0.24, 0.08, 0.11), m_ll @ Matrix.Translation((side * 0.148, -0.145, 0.22)))
        bm_add_box(bms["Armor"], (0.30, 0.30, 0.14), m_ll @ Matrix.Translation((side * 0.148, 0.0, 0.14)))
        bm_add_box(bms["DarkSteel"], (0.28, 0.08, 0.07), m_ll @ Matrix.Translation((side * 0.148, -0.16, 0.035)))

    if role == "Trapper":
        bm_add_box(bms["Cloth"], (0.39, 0.40, 0.37), m_head @ Matrix.Translation((0.0, 0.01, 1.30)))
        bm_add_box(bms["Armor"], (0.37, 0.26, 0.15), m_head @ Matrix.Translation((0.0, -0.05, 1.38)))
        for lx in (-0.075, 0.075):
            bm_add_cyl(bms["DarkSteel"], 0.055, 0.055, 0.07, 10, m_head @ Matrix.Translation((lx, -0.19, 1.31)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
            bm_add_cyl(bms["NeonAccent"], 0.038, 0.038, 0.02, 10, m_head @ Matrix.Translation((lx, -0.228, 1.31)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
        bm_add_box(bms["DarkSteel"], (0.06, 0.12, 0.14), m_head @ Matrix.Translation((0.20, 0.0, 1.29)))
        bm_add_cyl(bms["DarkSteel"], 0.012, 0.008, 0.42, 6, m_head @ Matrix.Translation((0.21, 0.03, 1.54)))
        bm_add_cyl(bms["NeonAccent"], 0.022, 0.022, 0.04, 8, m_head @ Matrix.Translation((0.21, 0.03, 1.75)))

        bm_add_box(bms["Armor"], (0.58, 0.34, 0.34), m_ut @ Matrix.Translation((0.0, 0.0, 0.90)))
        bm_add_box(bms["DarkSteel"], (0.10, 0.37, 0.46), m_ut @ Matrix.Translation((0.0, 0.0, 0.90)) @ Matrix.Rotation(math.radians(32), 4, "Y"))
        bm_add_box(bms["Armor"], (0.28, 0.32, 0.15), m_lua @ Matrix.Translation((0.46, 0.0, 1.02)) @ Matrix.Rotation(math.radians(-14), 4, "Y"))
        bm_add_box(bms["DarkSteel"], (0.24, 0.28, 0.12), m_rua @ Matrix.Translation((-0.45, 0.0, 1.02)) @ Matrix.Rotation(math.radians(14), 4, "Y"))
        bm_add_box(bms["Armor"], (0.18, 0.20, 0.16), m_lla @ Matrix.Translation((0.41, -0.05, 0.72)))

        bm_add_box(bms["DarkSteel"], (0.44, 0.20, 0.48), m_ut @ Matrix.Translation((0.0, 0.22, 0.92)))
        bm_add_cyl(bms["Armor"], 0.21, 0.16, 0.44, 14, m_ut @ Matrix.Translation((0.0, 0.28, 1.05)))
        for rz in (0.94, 1.06, 1.18):
            bm_add_cyl(bms["NeonAccent"], 0.20, 0.20, 0.035, 14, m_ut @ Matrix.Translation((0.0, 0.28, rz)))

        build_class_weapon_in_bmesh("Trapper", bms, m_rh)

    elif role == "Medic":
        bm_add_box(bms["Armor"], (0.37, 0.38, 0.38), m_head @ Matrix.Translation((0.0, 0.0, 1.30)))
        bm_add_box(bms["DarkSteel"], (0.39, 0.18, 0.14), m_head @ Matrix.Translation((0.0, -0.03, 1.24)))
        bm_add_box(bms["VisorGlass"], (0.33, 0.06, 0.12), m_head @ Matrix.Translation((0.0, -0.18, 1.32)))
        bm_add_box(bms["NeonAccent"], (0.16, 0.03, 0.035), m_head @ Matrix.Translation((0.0, -0.19, 1.43)))
        bm_add_box(bms["NeonAccent"], (0.035, 0.03, 0.10), m_head @ Matrix.Translation((0.0, -0.19, 1.43)))

        bm_add_box(bms["Armor"], (0.59, 0.35, 0.38), m_ut @ Matrix.Translation((0.0, 0.0, 0.91)))
        bm_add_box(bms["NeonAccent"], (0.12, 0.04, 0.035), m_ut @ Matrix.Translation((0.0, -0.18, 0.95)))
        bm_add_box(bms["NeonAccent"], (0.035, 0.04, 0.12), m_ut @ Matrix.Translation((0.0, -0.18, 0.95)))
        for sx, m_ua in [(-1.0, m_rua), (1.0, m_lua)]:
            bm_add_box(bms["Armor"], (0.28, 0.31, 0.14), m_ua @ Matrix.Translation((sx * 0.45, 0.0, 1.02)))
        bm_add_box(bms["DarkSteel"], (0.33, 0.33, 0.16), m_lla @ Matrix.Translation((0.41, 0.0, 0.72)))
        bm_add_box(bms["NeonAccent"], (0.04, 0.13, 0.10), m_lla @ Matrix.Translation((0.57, -0.05, 0.72)))

        bm_add_box(bms["DarkSteel"], (0.48, 0.18, 0.44), m_ut @ Matrix.Translation((0.0, 0.21, 0.90)))
        for tx in (-0.14, 0.14):
            bm_add_cyl(bms["Armor"], 0.10, 0.10, 0.56, 12, m_ut @ Matrix.Translation((tx, 0.29, 0.94)))
            bm_add_cyl(bms["NeonAccent"], 0.085, 0.085, 0.28, 12, m_ut @ Matrix.Translation((tx, 0.29, 0.94)))
            bm_add_cyl(bms["DarkSteel"], 0.11, 0.11, 0.08, 12, m_ut @ Matrix.Translation((tx, 0.29, 1.22)))

        build_class_weapon_in_bmesh("Medic", bms, m_rh)

    else:  # Support
        bm_add_box(bms["Armor"], (0.39, 0.40, 0.39), m_head @ Matrix.Translation((0.0, 0.01, 1.30)))
        bm_add_box(bms["DarkSteel"], (0.42, 0.26, 0.18), m_head @ Matrix.Translation((0.0, 0.03, 1.40)))
        bm_add_box(bms["VisorGlass"], (0.36, 0.09, 0.11), m_head @ Matrix.Translation((0.0, -0.175, 1.30)))
        bm_add_box(bms["NeonAccent"], (0.32, 0.02, 0.028), m_head @ Matrix.Translation((0.0, -0.215, 1.30)))
        for side in (-1.0, 1.0):
            bm_add_box(bms["Armor"], (0.04, 0.14, 0.34), m_head @ Matrix.Translation((side * 0.21, 0.06, 1.44)))

        bm_add_box(bms["Armor"], (0.62, 0.38, 0.42), m_ut @ Matrix.Translation((0.0, 0.0, 0.90)))
        bm_add_box(bms["DarkSteel"], (0.56, 0.42, 0.14), m_ut @ Matrix.Translation((0.0, 0.02, 1.12)))
        bm_add_box(bms["NeonAccent"], (0.28, 0.04, 0.06), m_ut @ Matrix.Translation((0.0, -0.20, 0.96)))
        for sx, m_ua, sz in [(-1.0, m_rua, 0.22), (1.0, m_lua, 0.26)]:
            bm_add_box(bms["Armor"], (0.33, 0.36, sz), m_ua @ Matrix.Translation((sx * 0.47, 0.0, 1.01)))
            bm_add_box(bms["DarkSteel"], (0.35, 0.38, 0.06), m_ua @ Matrix.Translation((sx * 0.47, 0.0, 1.11)))
        for sx, m_la in [(-1.0, m_rla), (1.0, m_lla)]:
            bm_add_box(bms["DarkSteel"], (0.32, 0.32, 0.18), m_la @ Matrix.Translation((sx * 0.41, 0.0, 0.72)))

        bm_add_box(bms["DarkSteel"], (0.58, 0.22, 0.48), m_ut @ Matrix.Translation((0.0, 0.22, 0.92)))
        for px in (-0.21, 0.21):
            bm_add_box(bms["Armor"], (0.18, 0.22, 0.76), m_ut @ Matrix.Translation((px, 0.30, 1.08)))
            bm_add_box(bms["NeonAccent"], (0.08, 0.24, 0.52), m_ut @ Matrix.Translation((px, 0.30, 1.10)))
            bm_add_box(bms["DarkSteel"], (0.20, 0.25, 0.07), m_ut @ Matrix.Translation((px, 0.30, 1.46)))

        build_class_weapon_in_bmesh("Support", bms, m_rh)


def build_classes_and_bases_pack(
    palette: Dict[str, bpy.types.Material],
    pedestal_meshes: Dict[str, bpy.types.Mesh],
) -> Tuple[bpy.types.Collection, List[bpy.types.Object]]:
    col = ensure_collection("Pack3_ClassBasesAndHunters")
    objs: List[bpy.types.Object] = []

    ROLE_ACCENTS = {
        "Assault": palette["NeonIvory"],
        "Trapper": palette["NeonAmber"],
        "Medic": palette["NeonGreen"],
        "Support": palette["NeonCyan"],
    }
    ROLE_MATS = {
        "Trapper": (palette["TrapperCloth"], palette["TrapperArmor"]),
        "Medic": (palette["MedicCloth"], palette["MedicArmor"]),
        "Support": (palette["SupportCloth"], palette["SupportArmor"]),
    }

    base_limb_names = [
        "Head", "Head_FaceAndHair", "Head_NeckPlug",
        "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftHand_FingerlessGlove",
        "RightUpperArm", "RightLowerArm", "RightHand", "RightHand_FingerlessGlove",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftFoot_BootUpper",
        "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightFoot_BootUpper",
    ]
    with bpy.data.libraries.load(str(SRC_ASSAULT_BLEND), link=False) as (data_from, data_to):
        data_to.objects = ["Assault_R15_Rig"] + base_limb_names

    loaded_rig_objs = [o for o in data_to.objects if o is not None]
    arm = next(o for o in loaded_rig_objs if o.type == "ARMATURE")
    temp_col = ensure_collection("TEMP_Hunter_Eval")
    for o in loaded_rig_objs:
        temp_col.objects.link(o)

    limb_objs = [o for o in loaded_rig_objs if o.type == "MESH"]
    ped_h = 0.75
    ped_diam = 7.4

    for spec in CLASS_PLACEMENTS:
        role = spec["role"]
        cx, cy = spec["bx"], spec["by"]
        to_spawn = (SPAWN_TARGET_BLENDER - Vector((cx, cy, 0.0))).normalized()
        yaw_rad = math.atan2(to_spawn.x, -to_spawn.y)
        accent_mat = ROLE_ACCENTS[role]

        objs.extend(
            build_pedestal_instance(
                prefix=f"ClassBase_{role}",
                center_xy=(cx, cy),
                base_z=0.0,
                yaw_rad=yaw_rad,
                diameter_studs=ped_diam,
                height_studs=ped_h,
                pedestal_meshes=pedestal_meshes,
                palette=palette,
                col=col,
                accent_mat=accent_mat,
            )
        )
        objs.extend(build_class_plaque(role, (cx, cy), yaw_rad, accent_mat, palette, col))

        s = STUDS_PER_METER * HUNTER_SCALE
        place_xf = (
            Matrix.Translation((cx, cy, ped_h))
            @ Matrix.Rotation(yaw_rad, 4, "Z")
            @ Matrix.Diagonal((s, s, s, 1.0))
        )

        if role == "Assault":
            pose_r15_rig(arm, "Assault")
            bpy.context.view_layer.update()
            pb = arm.pose.bones["RightHand"]
            m_rh = place_xf @ arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted()
            w_bms = {"WeaponSteel": bmesh.new(), "WeaponNeon": bmesh.new()}
            build_class_weapon_in_bmesh("Assault", w_bms, m_rh)
            objs.append(create_mesh_object_from_bmesh("Hunter3D_Assault_WeaponSteel", w_bms["WeaponSteel"], palette["DarkSteel"], col))
            objs.append(create_mesh_object_from_bmesh("Hunter3D_Assault_WeaponNeon", w_bms["WeaponNeon"], palette["NeonCyan"], col))
        else:
            pose_r15_rig(arm, role)
            bpy.context.view_layer.update()
            deps = bpy.context.evaluated_depsgraph_get()

            cloth_mat, armor_mat = ROLE_MATS[role]
            bms: Dict[str, bmesh.types.BMesh] = {
                "Skin": bmesh.new(),
                "Hair": bmesh.new(),
                "Cloth": bmesh.new(),
                "Armor": bmesh.new(),
                "DarkSteel": bmesh.new(),
                "VisorGlass": bmesh.new(),
                "NeonAccent": bmesh.new(),
                "WeaponSteel": bmesh.new(),
                "WeaponNeon": bmesh.new(),
            }

            for l_obj in limb_objs:
                ev = l_obj.evaluated_get(deps)
                tmp_mesh = ev.to_mesh()
                xf = place_xf @ ev.matrix_world
                src_m = l_obj.data.materials[0].name if l_obj.data.materials else ""
                if l_obj.name == "Head_FaceAndHair":
                    bucket = "Hair"
                elif "Skin" in src_m:
                    bucket = "Skin"
                elif "Boot" in l_obj.name or "Glove" in l_obj.name or l_obj.name.endswith("Foot"):
                    bucket = "DarkSteel"
                else:
                    bucket = "Cloth"

                bm_dst = bms[bucket]
                for poly in tmp_mesh.polygons:
                    v_ids = list(poly.vertices)
                    if len(v_ids) < 3:
                        continue
                    v0 = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[0]].co)
                    for i in range(1, len(v_ids) - 1):
                        va = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[i]].co)
                        vb = bm_dst.verts.new(xf @ tmp_mesh.vertices[v_ids[i + 1]].co)
                        try:
                            bm_dst.faces.new((v0, va, vb))
                        except ValueError:
                            pass
                ev.to_mesh_clear()

            append_custom_class_gear(role, arm, bms, place_xf)

            # Auto-ground so the lowest boot vertex across all buckets rests flush on top of pedestal (Z = ped_h)
            z_mins = [v.co.z for bm_k in bms.values() for v in bm_k.verts]
            if z_mins:
                lift_z = ped_h - min(z_mins)
                if abs(lift_z) > 1e-4:
                    for bm_k in bms.values():
                        for v in bm_k.verts:
                            v.co.z += lift_z

            bucket_specs = [
                ("Skin", f"Hunter3D_{role}_Skin", palette["Skin"]),
                ("Hair", f"Hunter3D_{role}_Hair", palette["Hair"]),
                ("Cloth", f"Hunter3D_{role}_Cloth", cloth_mat),
                ("Armor", f"Hunter3D_{role}_Armor", armor_mat),
                ("DarkSteel", f"Hunter3D_{role}_DarkSteel", palette["DarkSteel"]),
                ("VisorGlass", f"Hunter3D_{role}_VisorGlass", palette["Glass"]),
                ("NeonAccent", f"Hunter3D_{role}_NeonAccent", accent_mat),
                ("WeaponSteel", f"Hunter3D_{role}_WeaponSteel", palette["DarkSteel"]),
                ("WeaponNeon", f"Hunter3D_{role}_WeaponNeon", accent_mat),
            ]
            for bk, oname, omat in bucket_specs:
                if len(bms[bk].faces) == 0:
                    bms[bk].free()
                    continue
                objs.append(create_mesh_object_from_bmesh(oname, bms[bk], omat, col, recenter=True))

    bpy.context.scene.collection.children.unlink(temp_col)
    bpy.data.collections.remove(temp_col)
    for o in loaded_rig_objs:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)

    return col, objs


# ---------------------------------------------------------------------------
# Export Helper & Audit + Verification Renders
# ---------------------------------------------------------------------------

def export_collection_as_glb(col: bpy.types.Collection, marker_mat: bpy.types.Material, glb_path: Path, marker_name: str) -> Dict:
    marker = add_origin_marker(col, marker_mat, marker_name)
    mesh_objs = [o for o in col.all_objects if o.type == "MESH"]

    bpy.ops.object.select_all(action="DESELECT")
    total_tris = 0
    max_tris = 0
    max_name = ""
    details = []
    for o in mesh_objs:
        o.select_set(True)
        t = sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
        total_tris += t
        if t > max_tris:
            max_tris = t
            max_name = o.name
        assert t > 0, f"Empty mesh detected: {o.name}"
        assert t < 18000, f"Mesh {o.name} exceeds safe 18k tris limit: {t}"
        assert o.scale.x > 0 and o.scale.y > 0 and o.scale.z > 0, f"Negative/zero scale on {o.name}"
        details.append({"name": o.name, "tris": t, "loc_studs": [round(v, 3) for v in o.location]})

    bpy.context.view_layer.objects.active = marker
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_image_format="NONE",
    )
    bpy.data.objects.remove(marker, do_unlink=True)

    return {
        "glbPath": str(glb_path),
        "meshCount": len(mesh_objs),
        "totalTriangles": total_tris,
        "heaviestMesh": max_name,
        "heaviestTriangles": max_tris,
        "meshes": details,
    }


def render_verification_views() -> List[str]:
    col = ensure_collection("Verification_Lighting_Cameras")

    world = bpy.data.worlds.new("Lobby3D_VerifyWorld_v2")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.04, 0.06, 0.10, 1.0)
        bg.inputs["Strength"].default_value = 0.7

    def add_light(name: str, ltype: str, pos: Tuple[float, float, float], color: Tuple[float, float, float], energy: float, size: float = 8.0) -> None:
        ld = bpy.data.lights.new(name=name, type=ltype)
        ld.color = color
        ld.energy = energy
        if hasattr(ld, "size"):
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(pos)
        col.objects.link(lo)

    add_light("Key_Center", "POINT", (0.0, -18.0, 22.0), (1.0, 0.68, 0.35), 55000.0)
    add_light("Key_MonsterRim", "POINT", (0.0, 14.0, 20.0), (1.0, 0.45, 0.15), 40000.0)
    add_light("Key_LeftClasses", "POINT", (-20.0, -24.0, 14.0), (0.65, 0.90, 1.0), 28000.0)
    add_light("Key_RightClasses", "POINT", (20.0, -24.0, 14.0), (0.65, 1.0, 0.85), 28000.0)
    add_light("Ceiling_Fill", "AREA", (0.0, 0.0, 30.0), (0.75, 0.88, 1.0), 38000.0, size=24.0)

    cam_specs = [
        ("VerifyCam_v2_1_SpawnOverview", Vector((0.0, -42.0, 11.5)), Vector((0.0, 0.0, 9.5)), str(PREVIEW_1)),
        ("VerifyCam_v2_2_CloseLineup", Vector((12.0, -34.0, 9.0)), Vector((-6.0, -6.0, 7.5)), str(PREVIEW_2)),
    ]
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"

    rendered: List[str] = []
    for cname, pos, target, out_path in cam_specs:
        cd = bpy.data.cameras.new(cname)
        cd.lens = 21.0
        cd.clip_end = 500.0
        co = bpy.data.objects.new(cname, cd)
        co.location = pos
        co.rotation_euler = (target - pos).normalized().to_track_quat("-Z", "Y").to_euler()
        col.objects.link(co)
        scene.camera = co
        scene.render.filepath = out_path
        bpy.ops.render.render(write_still=True)
        rendered.append(out_path)
    return rendered


def main() -> None:
    assert_no_overwrites()
    reset_scene()
    palette = create_palette()
    pedestal_meshes = load_stage_pedestal_meshes()

    col_hangar, _ = build_hangar_pack(palette)
    col_monster, _ = build_monster_centerpiece_pack(palette, pedestal_meshes)
    col_classes, _ = build_classes_and_bases_pack(palette, pedestal_meshes)

    for m in list(pedestal_meshes.values()):
        m.use_fake_user = False
        if m.name in bpy.data.meshes and m.users == 0:
            bpy.data.meshes.remove(m)

    hangar_audit = export_collection_as_glb(col_hangar, palette["DarkSteel"], HANGAR_GLB, "ORIGIN_MARKER")
    monster_audit = export_collection_as_glb(col_monster, palette["DarkSteel"], MONSTER_GLB, "ORIGIN_MARKER")
    classes_audit = export_collection_as_glb(col_classes, palette["DarkSteel"], CLASSES_GLB, "ORIGIN_MARKER")

    previews = render_verification_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSEMBLY_BLEND))

    manifest = {
        "project": "PRIMAL HUNT",
        "version": "v2",
        "studsPerMeter": STUDS_PER_METER,
        "lobbyOrigin": [0, 600, 0],
        "classPlacementsRoblox": CLASS_PLACEMENTS,
        "packs": {
            "hangar": hangar_audit,
            "monster": monster_audit,
            "classes": classes_audit,
        },
        "assemblyBlend": str(ASSEMBLY_BLEND),
        "previews": previews,
    }
    MANIFEST_JSON.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("LOBBY_3D_ROBLOX_PACK_V2_OK")
    print(
        json.dumps(
            {
                "hangar": {k: hangar_audit[k] for k in ("meshCount", "totalTriangles", "heaviestMesh", "heaviestTriangles")},
                "monster": {k: monster_audit[k] for k in ("meshCount", "totalTriangles", "heaviestMesh", "heaviestTriangles")},
                "classes": {k: classes_audit[k] for k in ("meshCount", "totalTriangles", "heaviestMesh", "heaviestTriangles")},
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
