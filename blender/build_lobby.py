"""Orbital Dropship Hangar — Procedural High-Detail Sci-Fi/Industrial Lobby for Roblox Studio.

Built for Blender 5.3 (bpy & bmesh), generating separate watertight modules under
root Collection 'Lobby' -> '01_Floor_And_Substructure' .. '07_Roblox_Anchors',
auditing mesh integrity (< 8,000 tris/object, no negative scale, non-empty meshes),
exporting OrbitalDropshipLobby.blend + OrbitalDropshipLobby.fbx, and rendering Eevee previews.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
BLEND_PATH = ROOT_DIR / "OrbitalDropshipLobby.blend"
FBX_PATH = ROOT_DIR / "OrbitalDropshipLobby.fbx"
PREVIEWS_DIR = ROOT_DIR / "previews"
AUDIT_PATH = ROOT_DIR / "lobby_audit.json"

PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Scene Reset & Collection Helpers
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Materials (Language-independent node lookup for PT-BR / EN Blender 5.3)
# ---------------------------------------------------------------------------

def _hex_to_linear(hex_str: str) -> Tuple[float, float, float]:
    h = hex_str.lstrip("#")
    srgb = [int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [
        c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        for c in srgb
    ]
    return (lin[0], lin[1], lin[2])


def create_materials() -> Dict[str, bpy.types.Material]:
    def make_mat(
        name: str,
        color: Tuple[float, float, float],
        roughness: float,
        metallic: float = 0.0,
        alpha: float = 1.0,
        emission: Tuple[float, float, float] | None = None,
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
        bsdf.inputs["Alpha"].default_value = alpha
        if emission is not None and emission_strength > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        if alpha < 0.99:
            bsdf.inputs["IOR"].default_value = 1.45
            if hasattr(mat, "blend_method"):
                mat.blend_method = "BLEND"
        return mat

    cyan = _hex_to_linear("#00D8FF")
    amber = _hex_to_linear("#FF6A00")

    return {
        "DarkSteel": make_mat("Mat_Hull_DarkSteel", (0.075, 0.088, 0.105), roughness=0.45, metallic=0.82),
        "ArmorGrey": make_mat("Mat_Wall_ArmorGrey", (0.20, 0.225, 0.255), roughness=0.55, metallic=0.42),
        "FloorGrating": make_mat("Mat_Floor_Grating", (0.045, 0.052, 0.062), roughness=0.60, metallic=0.72),
        "HazardYellow": make_mat("Mat_Trim_HazardYellow", (0.76, 0.48, 0.03), roughness=0.48, metallic=0.15),
        "Glass": make_mat("Mat_Glass_Observation", (0.18, 0.58, 0.78), roughness=0.10, metallic=0.0, alpha=0.30),
        "NeonCyan": make_mat("Mat_Neon_Cyan", cyan, roughness=0.15, emission=cyan, emission_strength=5.2),
        "NeonAmber": make_mat("Mat_Neon_AmberAlert", amber, roughness=0.15, emission=amber, emission_strength=4.8),
    }


# ---------------------------------------------------------------------------
# Reusable Procedural BMesh Builders (Hard-Surface Sci-Fi Primitives)
# ---------------------------------------------------------------------------

def _box_uv(bm: bmesh.types.BMesh, scale: float = 0.5) -> None:
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


def finalize_mesh_object(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    location: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    rotation_euler: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel_width: float = 0.025,
    bevel_segments: int = 1,
) -> bpy.types.Object:
    """Creates a clean Roblox-compatible Mesh Object with applied transforms, bevel, and outward normals."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _box_uv(bm)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = Vector(location)
    obj.rotation_euler = Euler(rotation_euler, "XYZ")
    obj.data.materials.append(mat)
    collection.objects.link(obj)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    # Apply rotation & scale first so bevel & normals stay uniform
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    if bevel_width > 0.0 and bevel_segments > 0 and len(obj.data.polygons) > 0:
        bev = obj.modifiers.new(name="AutoBevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = bevel_segments
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(30.0)
        bev.use_clamp_overlap = True
        bpy.ops.object.modifier_apply(modifier=bev.name)

    # Final outward normal recalc after bevel + clean non-zero check
    bm_check = bmesh.new()
    bm_check.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm_check, faces=bm_check.faces)
    bm_check.to_mesh(obj.data)
    bm_check.free()
    obj.data.update()
    return obj


def _bm_add_box(bm: bmesh.types.BMesh, size: Tuple[float, float, float], xf: Matrix = Matrix.Identity(4)) -> List[bmesh.types.BMFace]:
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    mat = xf @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    for v in verts:
        v.co = mat @ v.co
    vert_set = set(verts)
    return [f for f in bm.faces if all(v in vert_set for v in f.verts)]


def _bm_add_cylinder(
    bm: bmesh.types.BMesh,
    radius: float,
    depth: float,
    segments: int = 16,
    xf: Matrix = Matrix.Identity(4),
) -> List[bmesh.types.BMFace]:
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    verts = res["verts"]
    for v in verts:
        v.co = xf @ v.co
    vert_set = set(verts)
    return [f for f in bm.faces if all(v in vert_set for v in f.verts)]


def _bm_add_octagon_prism(
    bm: bmesh.types.BMesh,
    radius: float,
    height: float,
    xf: Matrix = Matrix.Identity(4),
) -> None:
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=8,
        radius1=radius,
        radius2=radius * 0.96,
        depth=height,
    )
    rot_oct = Matrix.Rotation(math.pi / 8.0, 4, "Z")
    for v in res["verts"]:
        v.co = xf @ (rot_oct @ v.co)


def _bm_add_octagon_ring(
    bm: bmesh.types.BMesh,
    outer_r: float,
    inner_r: float,
    z_bottom: float,
    z_top: float,
    cx: float = 0.0,
    cy: float = 0.0,
) -> None:
    """Creates a clean flush-mitered 8-sided ring frame (zero corner overlap)."""
    bot_out, bot_in, top_out, top_in = [], [], [], []
    for i in range(8):
        ang = (i * math.pi / 4.0) + math.pi / 8.0
        ca, sa = math.cos(ang), math.sin(ang)
        bot_out.append(bm.verts.new(Vector((cx + ca * outer_r, cy + sa * outer_r, z_bottom))))
        bot_in.append(bm.verts.new(Vector((cx + ca * inner_r, cy + sa * inner_r, z_bottom))))
        top_out.append(bm.verts.new(Vector((cx + ca * outer_r, cy + sa * outer_r, z_top))))
        top_in.append(bm.verts.new(Vector((cx + ca * inner_r, cy + sa * inner_r, z_top))))
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((top_in[i], top_out[i], top_out[j], top_in[j]))
        bm.faces.new((bot_out[i], bot_in[i], bot_in[j], bot_out[j]))
        bm.faces.new((bot_out[i], top_out[i], top_out[j], bot_out[j]))
        bm.faces.new((top_in[i], bot_in[i], bot_in[j], top_in[j]))


def make_recessed_panel(
    name: str,
    size: Tuple[float, float, float],
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    location: Tuple[float, float, float],
    rotation_euler: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    recess_faces: str = "Z+",
    inset_thickness: float = 0.14,
    inset_depth: float = 0.06,
    ribs: int = 1,
) -> bpy.types.Object:
    """Creates a chamfered structural armor plate with recessed inner panels and stiffening ribs."""
    bm = bmesh.new()
    sx, sy, sz = size
    # Base slab
    faces = _bm_add_box(bm, (sx, sy, sz))

    # Select target face(s) for panel inset & recess extrusion
    targets: List[bmesh.types.BMFace] = []
    for f in faces:
        n = f.normal
        if recess_faces == "Z+" and n.z > 0.8:
            targets.append(f)
        elif recess_faces == "X+" and n.x > 0.8:
            targets.append(f)
        elif recess_faces == "X-" and n.x < -0.8:
            targets.append(f)
        elif recess_faces == "Y+" and n.y > 0.8:
            targets.append(f)
        elif recess_faces == "Y-" and n.y < -0.8:
            targets.append(f)

    if targets:
        inset = bmesh.ops.inset_individual(bm, faces=targets, thickness=inset_thickness, depth=-inset_depth)
        # Re-bevel border slightly with a secondary shallow lip
        if inset["faces"]:
            bmesh.ops.inset_individual(bm, faces=inset["faces"], thickness=inset_thickness * 0.35, depth=0.012)

    # Optional external structural stiffening ribs
    if ribs > 0 and recess_faces in ("X+", "X-", "Y+", "Y-"):
        for r_i in range(ribs):
            frac = ((r_i + 1) / (ribs + 1)) - 0.5
            if recess_faces in ("X+", "X-"):
                sign = 1.0 if recess_faces == "X+" else -1.0
                _bm_add_box(bm, (0.08, 0.14, sz * 0.88), Matrix.Translation((sign * sx * 0.5, frac * sy, 0.0)))
            else:
                sign = 1.0 if recess_faces == "Y+" else -1.0
                _bm_add_box(bm, (0.14, 0.08, sz * 0.88), Matrix.Translation((frac * sx, sign * sy * 0.5, 0.0)))

    return finalize_mesh_object(name, bm, mat, col, location=location, rotation_euler=rotation_euler, bevel_width=0.025, bevel_segments=1)


def make_h_beam(
    name: str,
    length: float,
    height: float,
    width: float,
    flange_t: float,
    web_t: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    location: Tuple[float, float, float],
    rotation_euler: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    stiffeners: int = 3,
) -> bpy.types.Object:
    """Creates a realistic structural steel H/I-beam oriented along local X axis."""
    bm = bmesh.new()
    # Top and bottom flanges + central web
    _bm_add_box(bm, (length, width, flange_t), Matrix.Translation((0.0, 0.0, height * 0.5 - flange_t * 0.5)))
    _bm_add_box(bm, (length, width, flange_t), Matrix.Translation((0.0, 0.0, -height * 0.5 + flange_t * 0.5)))
    _bm_add_box(bm, (length, web_t, height - flange_t * 1.9), Matrix.Identity(4))
    # Vertical web stiffener gussets
    for i in range(stiffeners):
        x_pos = -length * 0.42 + (i / max(1, stiffeners - 1)) * (length * 0.84) if stiffeners > 1 else 0.0
        _bm_add_box(bm, (0.08, width * 0.92, height - flange_t * 1.8), Matrix.Translation((x_pos, 0.0, 0.0)))
    return finalize_mesh_object(name, bm, mat, col, location=location, rotation_euler=rotation_euler, bevel_width=0.015, bevel_segments=1)


def make_slotted_grate(
    name: str,
    width_x: float,
    length_y: float,
    thickness: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    location: Tuple[float, float, float],
) -> bpy.types.Object:
    """Creates an open industrial floor grate revealing pipes and amber underfloor lights below."""
    bm = bmesh.new()
    rim = 0.12
    # Outer frame rails
    _bm_add_box(bm, (rim, length_y, thickness), Matrix.Translation((-width_x * 0.5 + rim * 0.5, 0.0, 0.0)))
    _bm_add_box(bm, (rim, length_y, thickness), Matrix.Translation((width_x * 0.5 - rim * 0.5, 0.0, 0.0)))
    _bm_add_box(bm, (width_x - rim * 2.0, rim, thickness), Matrix.Translation((0.0, -length_y * 0.5 + rim * 0.5, 0.0)))
    _bm_add_box(bm, (width_x - rim * 2.0, rim, thickness), Matrix.Translation((0.0, length_y * 0.5 - rim * 0.5, 0.0)))

    # Longitudinal stringers + transverse load bars with real gaps
    for sx in (-width_x * 0.18, width_x * 0.18):
        _bm_add_box(bm, (0.05, length_y - rim * 2.0, thickness * 0.72), Matrix.Translation((sx, 0.0, -thickness * 0.10)))
    bar_count = max(4, int(length_y / 0.34))
    for i in range(1, bar_count):
        y_pos = -length_y * 0.5 + (i / bar_count) * length_y
        _bm_add_box(bm, (width_x - rim * 1.8, 0.055, thickness * 0.85), Matrix.Translation((0.0, y_pos, 0.0)))

    return finalize_mesh_object(name, bm, mat, col, location=location, bevel_width=0.006, bevel_segments=1)


def make_flanged_pipe(
    name: str,
    points: Sequence[Vector],
    radius: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    segments: int = 12,
    flange_every: int = 1,
) -> bpy.types.Object:
    """Creates a watertight industrial conduit run with bolted octagonal/circular flanges at joints."""
    bm = bmesh.new()
    for i in range(len(points) - 1):
        p0, p1 = points[i], points[i + 1]
        vec = p1 - p0
        dist = vec.length
        if dist < 1e-4:
            continue
        mid = (p0 + p1) * 0.5
        quat = vec.normalized().to_track_quat("Z", "Y")
        xf = Matrix.Translation(mid) @ quat.to_matrix().to_4x4()
        _bm_add_cylinder(bm, radius, dist + radius * 0.25, segments=segments, xf=xf)
        if flange_every > 0 and i % flange_every == 0:
            xf_f0 = Matrix.Translation(p0.lerp(p1, 0.06)) @ quat.to_matrix().to_4x4()
            _bm_add_cylinder(bm, radius * 1.38, 0.11, segments=8, xf=xf_f0)
            xf_fm = Matrix.Translation(mid) @ quat.to_matrix().to_4x4()
            _bm_add_cylinder(bm, radius * 1.38, 0.11, segments=8, xf=xf_fm)
    return finalize_mesh_object(name, bm, mat, col, bevel_width=0.012, bevel_segments=1)


def make_hydraulic_strut(
    name: str,
    p_start: Vector,
    p_end: Vector,
    outer_radius: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
) -> bpy.types.Object:
    """Creates a telescopic hydraulic actuator strut between two structural anchor points."""
    bm = bmesh.new()
    vec = p_end - p_start
    dist = vec.length
    quat = vec.normalized().to_track_quat("Z", "Y")
    rot_m = quat.to_matrix().to_4x4()

    # Outer sleeve (lower 58%), collar ring, inner piston rod (upper 52%), end clevis blocks
    p_sleeve = p_start.lerp(p_end, 0.29)
    _bm_add_cylinder(bm, outer_radius, dist * 0.58, segments=10, xf=Matrix.Translation(p_sleeve) @ rot_m)
    p_collar = p_start.lerp(p_end, 0.58)
    _bm_add_cylinder(bm, outer_radius * 1.28, 0.12, segments=10, xf=Matrix.Translation(p_collar) @ rot_m)
    p_rod = p_start.lerp(p_end, 0.74)
    _bm_add_cylinder(bm, outer_radius * 0.58, dist * 0.52, segments=10, xf=Matrix.Translation(p_rod) @ rot_m)
    _bm_add_box(bm, (outer_radius * 2.4, outer_radius * 2.4, 0.18), Matrix.Translation(p_start) @ rot_m)
    _bm_add_box(bm, (outer_radius * 2.2, outer_radius * 2.2, 0.16), Matrix.Translation(p_end) @ rot_m)
    return finalize_mesh_object(name, bm, mat, col, bevel_width=0.01, bevel_segments=1)


# ---------------------------------------------------------------------------
# 2.1) 01_Floor_And_Substructure
# ---------------------------------------------------------------------------

def build_floor_and_substructure(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("01_Floor_And_Substructure", root_col)

    # Outer lateral main deck plates (X = -15..-10.2 and +10.2..+15) leaving cable trench at X = +-9.0
    for sx_label, cx in [("W", -12.6), ("E", 12.6)]:
        for idx, cy in enumerate([-11.3, 0.0, 11.3]):
            make_recessed_panel(
                f"Floor_SideDeck_{sx_label}_{idx+1}",
                (4.8, 11.2, 0.45),
                mats["ArmorGrey"],
                col,
                location=(cx, cy, -0.225),
                inset_thickness=0.22,
                inset_depth=0.03,
            )

    # Central main walkway deck tiles around trench (X = -7.8..+7.8, Y = -17..+17)
    for row_i, cy in enumerate([-13.5, -7.8, 7.8, 13.5]):
        for col_i, cx in enumerate([-4.0, 4.0]):
            make_recessed_panel(
                f"Floor_MainTile_{row_i+1}_{col_i+1}",
                (7.6, 5.5, 0.45),
                mats["ArmorGrey"],
                col,
                location=(cx, cy, -0.225),
                inset_thickness=0.20,
                inset_depth=0.03,
            )
    # Flanking floor tiles beside octagonal dais (Y = -5..+5, X = +-6.8)
    for sx_label, cx in [("W", -6.5), ("E", 6.5)]:
        make_recessed_panel(
            f"Floor_FlankMid_{sx_label}",
            (2.8, 10.0, 0.45),
            mats["ArmorGrey"],
            col,
            location=(cx, 0.0, -0.225),
            inset_thickness=0.16,
            inset_depth=0.03,
        )

    # Recessed Subfloor Cable Trenches (X = +-9.0m, Y = -16..+16m, bottom at Z = -0.65m)
    for sx_label, tx in [("W", -9.0), ("E", 9.0)]:
        bm_t = bmesh.new()
        _bm_add_box(bm_t, (2.4, 33.2, 0.25), Matrix.Translation((tx, 0.0, -0.78)))
        _bm_add_box(bm_t, (0.18, 33.2, 0.65), Matrix.Translation((tx - 1.12, 0.0, -0.35)))
        _bm_add_box(bm_t, (0.18, 33.2, 0.65), Matrix.Translation((tx + 1.12, 0.0, -0.35)))
        finalize_mesh_object(f"Floor_TrenchChannel_{sx_label}", bm_t, mats["DarkSteel"], col, bevel_width=0.015)

        # Subfloor thick flanged conduit pipes inside trench
        make_flanged_pipe(
            f"Subfloor_Pipe_{sx_label}",
            [Vector((tx - 0.35, -15.5, -0.42)), Vector((tx - 0.35, 0.0, -0.42)), Vector((tx - 0.35, 15.5, -0.42))],
            radius=0.14,
            mat=mats["ArmorGrey"],
            col=col,
            segments=10,
            flange_every=1,
        )

        # Separate glowing amber strips inside trench underneath the open grates
        bm_glow = bmesh.new()
        _bm_add_box(bm_glow, (0.18, 31.0, 0.14), Matrix.Translation((tx + 0.42, 0.0, -0.52)))
        finalize_mesh_object(f"Subfloor_AmberGlow_{sx_label}", bm_glow, mats["NeonAmber"], col, bevel_width=0.0)

        # Modular slotted open metal floor grates at Z = 0
        for g_i, gy in enumerate([-12.0, -4.0, 4.0, 12.0]):
            make_slotted_grate(
                f"Floor_Grate_{sx_label}_{g_i+1}",
                width_x=2.15,
                length_y=7.9,
                thickness=0.12,
                mat=mats["FloorGrating"],
                col=col,
                location=(tx, gy, -0.06),
            )

    # Under-octagon continuous floor sub-deck closing any gap around diagonal octagon corners
    make_recessed_panel(
        "Floor_CenterUnderDeck",
        (15.6, 15.6, 0.45),
        mats["ArmorGrey"],
        col,
        location=(0.0, 0.0, -0.225),
        inset_thickness=0.35,
        inset_depth=0.025,
    )

    # Central Elevated Octagonal Platform (0, 0, 0) height = 0.45m, radius = 5.5m
    bm_oct = bmesh.new()
    _bm_add_octagon_prism(bm_oct, radius=5.5, height=0.45, xf=Matrix.Translation((0.0, 0.0, 0.225)))
    _bm_add_octagon_prism(bm_oct, radius=4.6, height=0.05, xf=Matrix.Translation((0.0, 0.0, 0.46)))
    finalize_mesh_object("Floor_CenterOctagonDais", bm_oct, mats["DarkSteel"], col, bevel_width=0.025, bevel_segments=2)

    # Flush-mitered Hazard Yellow rim ring around Octagonal Platform edge
    bm_trim = bmesh.new()
    _bm_add_octagon_ring(bm_trim, outer_r=5.46, inner_r=5.12, z_bottom=0.42, z_top=0.475)
    finalize_mesh_object("Floor_OctagonHazardTrim", bm_trim, mats["HazardYellow"], col, bevel_width=0.008)

    # 4 Short Access Ramps (N, S, E, W) aligned flush with octagon flat face (5.08m) -> main floor (7.28m)
    ramp_dirs = [
        ("N", (0.0, -6.12, 0.225), 0.0),
        ("S", (0.0, 6.12, 0.225), math.pi),
        ("W", (-6.12, 0.0, 0.225), math.pi * 0.5),
        ("E", (6.12, 0.0, 0.225), -math.pi * 0.5),
    ]
    for r_label, r_pos, r_yaw in ramp_dirs:
        bm_r = bmesh.new()
        slope = math.atan2(0.45, 2.2)
        _bm_add_box(bm_r, (2.8, 2.32, 0.16), Matrix.Rotation(slope, 4, "X"))
        for sx in (-1.45, 1.45):
            _bm_add_box(bm_r, (0.18, 2.36, 0.28), Matrix.Translation((sx, 0.0, 0.06)) @ Matrix.Rotation(slope, 4, "X"))
        finalize_mesh_object(f"Floor_OctagonRamp_{r_label}", bm_r, mats["DarkSteel"], col, location=r_pos, rotation_euler=(0.0, 0.0, r_yaw), bevel_width=0.015)

        bm_rh = bmesh.new()
        _bm_add_box(bm_rh, (2.56, 0.22, 0.05), Matrix.Translation((0.0, -0.92, -0.11)) @ Matrix.Rotation(slope, 4, "X"))
        _bm_add_box(bm_rh, (2.56, 0.22, 0.05), Matrix.Translation((0.0, 0.92, 0.27)) @ Matrix.Rotation(slope, 4, "X"))
        finalize_mesh_object(f"Floor_RampHazard_{r_label}", bm_rh, mats["HazardYellow"], col, location=r_pos, rotation_euler=(0.0, 0.0, r_yaw), bevel_width=0.006)


# ---------------------------------------------------------------------------
# 2.2) 02_Walls_Pillars_And_Ceiling
# ---------------------------------------------------------------------------

def build_walls_pillars_ceiling(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("02_Walls_Pillars_And_Ceiling", root_col)

    # Sci-Fi Dropship side wall hull sections (X = +-15.0m, Z = 0..9.5m) with 45-deg lower plinth & 45-deg upper cant
    y_bays = [-13.5, -7.8, 0.0, 7.8, 13.5]
    for side_label, sx, sign in [("West", -15.0, 1.0), ("East", 15.0, -1.0)]:
        face_dir = "X+" if sign > 0 else "X-"
        for b_i, cy in enumerate(y_bays):
            bay_len = 5.4 if abs(cy) > 10.0 else 7.4
            make_recessed_panel(
                f"Wall_HullMid_{side_label}_{b_i+1}",
                (0.75, bay_len, 5.8),
                mats["ArmorGrey"],
                col,
                location=(sx, cy, 4.7),
                recess_faces=face_dir,
                inset_thickness=0.22,
                inset_depth=0.09,
                ribs=2,
            )
        # Continuous angled 45-deg lower plinth skirt & upper chamfered bulkhead along entire 34m length
        bm_skirt = bmesh.new()
        _bm_add_box(
            bm_skirt,
            (1.1, 34.4, 2.1),
            Matrix.Translation((sx + sign * 0.45, 0.0, 0.85)) @ Matrix.Rotation(sign * math.radians(45.0), 4, "Y"),
        )
        _bm_add_box(
            bm_skirt,
            (1.2, 34.4, 2.6),
            Matrix.Translation((sx + sign * 0.55, 0.0, 8.55)) @ Matrix.Rotation(-sign * math.radians(45.0), 4, "Y"),
        )
        finalize_mesh_object(f"Wall_CantedBulkheads_{side_label}", bm_skirt, mats["DarkSteel"], col, bevel_width=0.025)

    # 8 Heavy Structural Side Columns (4 West, 4 East) cleanly framing Loadout Bays & Monster Pod without overlap
    col_y_coords = [-14.2, -7.1, 7.1, 14.2]
    for side_label, sx, sign in [("West", -14.2, 1.0), ("East", 14.2, -1.0)]:
        for c_i, cy in enumerate(col_y_coords):
            bm_col = bmesh.new()
            # Main tapered heavy steel column + base anchor shoe + upper haunch gusset
            _bm_add_box(bm_col, (1.15, 1.35, 9.4), Matrix.Translation((0.0, 0.0, 4.7)))
            _bm_add_box(bm_col, (1.65, 1.80, 0.85), Matrix.Translation((sign * 0.20, 0.0, 0.425)))
            _bm_add_box(bm_col, (2.20, 1.45, 1.40), Matrix.Translation((sign * 0.45, 0.0, 8.75)))
            # Junction electrical cabinet on column side
            _bm_add_box(bm_col, (0.38, 0.65, 1.05), Matrix.Translation((sign * 0.65, 0.55, 2.2)))
            finalize_mesh_object(f"Pillar_{side_label}_{c_i+1}", bm_col, mats["DarkSteel"], col, location=(sx, cy, 0.0), bevel_width=0.03)

            # Hydraulic piston strut bracing column base to upper flange
            make_hydraulic_strut(
                f"Pillar_Hydraulic_{side_label}_{c_i+1}",
                p_start=Vector((sx + sign * 0.72, cy - 0.35, 1.2)),
                p_end=Vector((sx + sign * 0.25, cy - 0.35, 5.2)),
                outer_radius=0.14,
                mat=mats["ArmorGrey"],
                col=col,
            )

            # Separate vertical Neon Cyan strip mounted on inner face of column
            bm_neon = bmesh.new()
            _bm_add_box(bm_neon, (0.10, 0.16, 4.4), Matrix.Translation((sx + sign * 0.62, cy, 4.9)))
            finalize_mesh_object(f"Pillar_LightBar_{side_label}_{c_i+1}", bm_neon, mats["NeonCyan"], col, bevel_width=0.0)

    # Overhead Longitudinal Wall Pipe Runs connecting bays (conduits + flanges)
    for side_label, px in [("West", -13.9), ("East", 13.9)]:
        make_flanged_pipe(
            f"Wall_OverheadConduit_{side_label}",
            [Vector((px, -16.0, 7.6)), Vector((px, -5.0, 7.6)), Vector((px, 5.0, 7.6)), Vector((px, 15.5, 7.6))],
            radius=0.18,
            mat=mats["ArmorGrey"],
            col=col,
            segments=10,
            flange_every=1,
        )

    # Ceiling Structural Deck (Z = 9.5m) + Transverse H-Beam Trusses + Overhead Gantry Crane + Ventilation Ducts + Cold Lights
    for t_i, ty in enumerate([-13.5, -5.0, 5.0, 13.5]):
        make_recessed_panel(
            f"Ceiling_ArmorDeck_{t_i+1}",
            (29.0, 8.2, 0.55),
            mats["DarkSteel"],
            col,
            location=(0.0, ty, 9.78),
            recess_faces="Z-",
            inset_thickness=0.35,
            inset_depth=0.08,
        )

    for b_i, cy in enumerate(col_y_coords):
        make_h_beam(
            f"Ceiling_HBeamTruss_{b_i+1}",
            length=28.4,
            height=0.95,
            width=0.62,
            flange_t=0.12,
            web_t=0.14,
            mat=mats["DarkSteel"],
            col=col,
            location=(0.0, cy, 9.05),
            stiffeners=5,
        )

    # Overhead Gantry Crane rails (X = +-6.8m) + movable cross bridge at Y = -2.0m + hoist trolley
    for side_label, rx in [("W", -6.8), ("E", 6.8)]:
        make_h_beam(
            f"Ceiling_CraneRail_{side_label}",
            length=30.0,
            height=0.45,
            width=0.34,
            flange_t=0.08,
            web_t=0.09,
            mat=mats["ArmorGrey"],
            col=col,
            location=(rx, 0.0, 8.30),
            rotation_euler=(0.0, 0.0, math.pi * 0.5),
            stiffeners=6,
        )
    make_h_beam(
        "Ceiling_GantryCraneBridge",
        length=14.4,
        height=0.65,
        width=0.48,
        flange_t=0.09,
        web_t=0.10,
        mat=mats["HazardYellow"],
        col=col,
        location=(0.0, -2.0, 7.85),
        stiffeners=4,
    )
    bm_hoist = bmesh.new()
    _bm_add_box(bm_hoist, (1.45, 1.35, 0.72), Matrix.Translation((0.0, -2.0, 7.35)))
    _bm_add_cylinder(bm_hoist, 0.34, 0.85, segments=12, xf=Matrix.Translation((0.0, -2.0, 7.35)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y"))
    _bm_add_box(bm_hoist, (0.28, 0.28, 0.95), Matrix.Translation((0.0, -2.0, 6.55)))
    finalize_mesh_object("Ceiling_GantryHoist", bm_hoist, mats["DarkSteel"], col, bevel_width=0.02)

    # Rectangular Ventilation Ducts with louvers on ceiling sides (X = +-10.5m)
    for side_label, dx in [("W", -10.5), ("E", 10.5)]:
        bm_duct = bmesh.new()
        _bm_add_box(bm_duct, (1.65, 29.0, 0.85), Matrix.Translation((dx, 0.0, 8.75)))
        for ly in range(-12, 13, 6):
            _bm_add_box(bm_duct, (1.82, 0.22, 0.96), Matrix.Translation((dx, float(ly), 8.75)))
        finalize_mesh_object(f"Ceiling_VentDuct_{side_label}", bm_duct, mats["ArmorGrey"], col, bevel_width=0.02)

    # Embedded Ceiling Cold-Light Panels (separate frames + cyan emissive inserts)
    for l_i, ly in enumerate([-8.0, 0.0, 8.0]):
        bm_frame = bmesh.new()
        _bm_add_box(bm_frame, (5.2, 1.6, 0.24), Matrix.Translation((0.0, ly, 9.40)))
        finalize_mesh_object(f"Ceiling_LightFrame_{l_i+1}", bm_frame, mats["DarkSteel"], col, bevel_width=0.015)

        bm_emit = bmesh.new()
        _bm_add_box(bm_emit, (4.6, 1.05, 0.08), Matrix.Translation((0.0, ly, 9.26)))
        finalize_mesh_object(f"Ceiling_LightPanel_{l_i+1}", bm_emit, mats["NeonCyan"], col, bevel_width=0.0)


# ---------------------------------------------------------------------------
# 2.3) 03_Panoramic_Observation_Bay (South Wall Y = +17m)
# ---------------------------------------------------------------------------

def build_panoramic_observation_bay(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("03_Panoramic_Observation_Bay", root_col)
    wy = 17.0
    tilt = math.radians(-14.0)  # Tilted outward at top so players look out & down onto planet/arena

    # Side corner armor piers flanking the 24m window (X = +-13.5m)
    for s_label, sx in [("W", -13.6), ("E", 13.6)]:
        make_recessed_panel(
            f"Obs_CornerPier_{s_label}",
            (3.2, 1.2, 9.5),
            mats["DarkSteel"],
            col,
            location=(sx, wy - 0.2, 4.75),
            recess_faces="Y-",
            inset_thickness=0.22,
            inset_depth=0.08,
        )

    # Heavy window frame sills (lower parapet header Z = 1.65m, upper lintel Z = 8.4m) & diagonal mullions
    bm_mullions = bmesh.new()
    _bm_add_box(bm_mullions, (24.6, 1.35, 1.65), Matrix.Translation((0.0, wy - 0.35, 0.825)))
    _bm_add_box(bm_mullions, (25.2, 1.50, 1.45), Matrix.Translation((0.0, wy + 0.85, 8.75)))

    # 7 Slanted armored mullions dividing the 24m x 6.5m window into 6 crisp bays
    mullion_xs = [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]
    for mx in mullion_xs:
        xf = Matrix.Translation((mx, wy + 0.25, 4.95)) @ Matrix.Rotation(tilt, 4, "X")
        _bm_add_box(bm_mullions, (0.42, 0.85, 7.1), xf)
    # Horizontal mid transom beam
    _bm_add_box(bm_mullions, (24.4, 0.55, 0.38), Matrix.Translation((0.0, wy + 0.45, 5.8)) @ Matrix.Rotation(tilt, 4, "X"))
    finalize_mesh_object("Obs_ArmoredMullionsAndFrame", bm_mullions, mats["DarkSteel"], col, bevel_width=0.025)

    # Separate Glass Panes fitted cleanly inside each window bay (NEVER merged with frame!)
    for p_i in range(len(mullion_xs) - 1):
        cx = (mullion_xs[p_i] + mullion_xs[p_i + 1]) * 0.5
        bm_g = bmesh.new()
        _bm_add_box(bm_g, (3.68, 0.14, 6.65), Matrix.Translation((cx, wy + 0.22, 4.95)) @ Matrix.Rotation(tilt, 4, "X"))
        finalize_mesh_object(f"Obs_GlassPane_{p_i+1}", bm_g, mats["Glass"], col, bevel_width=0.0)

    # Tactical observation console rail & metal guardrail at Y = +15.0..+16.2m
    bm_rail = bmesh.new()
    _bm_add_box(bm_rail, (18.0, 0.72, 0.92), Matrix.Translation((0.0, wy - 1.35, 0.46)))
    # Metal tubular safety railing across full width
    _bm_add_cylinder(bm_rail, 0.045, 22.0, segments=8, xf=Matrix.Translation((0.0, wy - 1.95, 1.08)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y"))
    _bm_add_cylinder(bm_rail, 0.032, 22.0, segments=8, xf=Matrix.Translation((0.0, wy - 1.95, 0.62)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y"))
    for px in range(-10, 11, 2):
        _bm_add_cylinder(bm_rail, 0.045, 1.08, segments=8, xf=Matrix.Translation((float(px), wy - 1.95, 0.54)))
    finalize_mesh_object("Obs_ParapetAndGuardrail", bm_rail, mats["ArmorGrey"], col, bevel_width=0.015)

    # Separate cyan tactical screens along observation console
    bm_scr = bmesh.new()
    for sx in (-6.0, -2.0, 2.0, 6.0):
        _bm_add_box(bm_scr, (1.9, 0.52, 0.08), Matrix.Translation((sx, wy - 1.35, 0.96)) @ Matrix.Rotation(math.radians(-28), 4, "X"))
    finalize_mesh_object("Obs_ConsoleScreens", bm_scr, mats["NeonCyan"], col, bevel_width=0.0)


# ---------------------------------------------------------------------------
# 2.4) 04_Central_Briefing_HoloTable (0, 0, 0.45m)
# ---------------------------------------------------------------------------

def build_central_holotable(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("04_Central_Briefing_HoloTable", root_col)
    base_z = 0.45  # Top surface of Octagonal Platform

    # Mechanical circular command table pedestal + 8 outward buttress consoles (radius = 2.2m)
    bm_tbl = bmesh.new()
    _bm_add_cylinder(bm_tbl, 1.55, 0.42, segments=16, xf=Matrix.Translation((0.0, 0.0, base_z + 0.21)))
    _bm_add_cylinder(bm_tbl, 1.15, 0.45, segments=16, xf=Matrix.Translation((0.0, 0.0, base_z + 0.55)))
    _bm_add_cylinder(bm_tbl, 2.20, 0.24, segments=16, xf=Matrix.Translation((0.0, 0.0, base_z + 0.85)))
    # Recessed inner projector well
    _bm_add_cylinder(bm_tbl, 1.38, 0.14, segments=16, xf=Matrix.Translation((0.0, 0.0, base_z + 0.94)))
    # 8 angled perimeter console stations
    for i in range(8):
        ang = i * (math.pi / 4.0)
        xf = Matrix.Translation((math.cos(ang) * 2.02, math.sin(ang) * 2.02, base_z + 0.98)) @ Matrix.Rotation(ang, 4, "Z") @ Matrix.Rotation(math.radians(22), 4, "Y")
        _bm_add_box(bm_tbl, (0.62, 0.95, 0.18), xf)
        # Support leg strut
        xf_leg = Matrix.Translation((math.cos(ang) * 1.65, math.sin(ang) * 1.65, base_z + 0.42)) @ Matrix.Rotation(ang, 4, "Z")
        _bm_add_box(bm_tbl, (0.48, 0.28, 0.72), xf_leg)
    finalize_mesh_object("HoloTable_MechanicalPedestal", bm_tbl, mats["DarkSteel"], col, bevel_width=0.02)

    # Separate tilted holographic screens around perimeter
    bm_screens = bmesh.new()
    for i in range(8):
        ang = i * (math.pi / 4.0)
        xf = Matrix.Translation((math.cos(ang) * 2.04, math.sin(ang) * 2.04, base_z + 1.07)) @ Matrix.Rotation(ang, 4, "Z") @ Matrix.Rotation(math.radians(22), 4, "Y")
        _bm_add_box(bm_screens, (0.48, 0.78, 0.04), xf)
    finalize_mesh_object("HoloTable_PerimeterScreens", bm_screens, mats["NeonCyan"], col, bevel_width=0.0)

    # Floating Holographic Topographic Arena Scan & Orbital Scanning Rings
    bm_holo = bmesh.new()
    # Mini stepped topographic terrain relief & central spire representing hunt caldera
    _bm_add_cylinder(bm_holo, 1.10, 0.06, segments=16, xf=Matrix.Translation((0.0, 0.0, base_z + 1.48)))
    for px, py, r_m, h_m in [(-0.42, 0.35, 0.28, 0.32), (0.45, 0.28, 0.24, 0.28), (-0.25, -0.45, 0.22, 0.26), (0.0, 0.0, 0.16, 0.20), (0.0, -0.72, 0.18, 0.38)]:
        _bm_add_cylinder(bm_holo, r_m, h_m, segments=8, xf=Matrix.Translation((px, py, base_z + 1.52 + h_m * 0.5)))

    # 2 Tilted Orbital Scanning Rings around hologram
    for r_ring, tilt_ang in [(1.45, math.radians(14)), (1.28, math.radians(-18))]:
        seg_n = 24
        for s_i in range(seg_n):
            a0 = (2.0 * math.pi * s_i) / seg_n
            a1 = (2.0 * math.pi * (s_i + 1)) / seg_n
            a_mid = (a0 + a1) * 0.5
            seg_len = 2.0 * r_ring * math.sin(math.pi / seg_n) * 1.02
            xf_r = (
                Matrix.Translation((0.0, 0.0, base_z + 1.85))
                @ Matrix.Rotation(tilt_ang, 4, "X")
                @ Matrix.Rotation(a_mid, 4, "Z")
                @ Matrix.Translation((r_ring, 0.0, 0.0))
            )
            _bm_add_box(bm_holo, (0.045, seg_len, 0.045), xf_r)
    finalize_mesh_object("HoloTable_ProjectionAndRings", bm_holo, mats["NeonCyan"], col, bevel_width=0.0)


# ---------------------------------------------------------------------------
# 2.5) 05_Hunter_Loadout_Bays (West Wall X = -14m, 4 Alcoves)
# ---------------------------------------------------------------------------

def build_hunter_loadout_bays(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("05_Hunter_Loadout_Bays", root_col)
    classes = ["Assault", "Medic", "Trapper", "Support"]
    bay_ys = [-10.5, -3.5, 3.5, 10.5]
    bx = -13.8

    for idx, (cls_name, by) in enumerate(zip(classes, bay_ys), start=1):
        # 1. Tactical beveled alcove cabinet & raised work deck
        bm_cab = bmesh.new()
        _bm_add_box(bm_cab, (1.85, 5.2, 0.35), Matrix.Translation((0.25, 0.0, 0.175)))
        _bm_add_box(bm_cab, (0.65, 4.9, 4.4), Matrix.Translation((-0.45, 0.0, 2.35)))
        # Side divider fins & angled canopy hood
        for sy in (-2.45, 2.45):
            _bm_add_box(bm_cab, (1.65, 0.28, 4.6), Matrix.Translation((0.15, sy, 2.45)))
        _bm_add_box(bm_cab, (1.95, 5.3, 0.55), Matrix.Translation((0.28, 0.0, 4.85)) @ Matrix.Rotation(math.radians(-12), 4, "Y"))
        # Equipment bench
        _bm_add_box(bm_cab, (0.85, 1.9, 0.92), Matrix.Translation((0.22, -1.35, 0.81)))
        finalize_mesh_object(f"Bay_{idx}_{cls_name}_Cabinet", bm_cab, mats["ArmorGrey"], col, location=(bx, by, 0.0), bevel_width=0.025)

        # 2. Mechanical Jetpack Docking Rig (twin cylindrical thrusters + spinal frame + clamps)
        bm_jp = bmesh.new()
        jp_x = bx + 0.12
        jp_y = by + 1.05
        _bm_add_box(bm_jp, (0.35, 0.85, 1.35), Matrix.Translation((jp_x, jp_y, 2.15)))
        for dy in (-0.32, 0.32):
            _bm_add_cylinder(bm_jp, 0.16, 1.15, segments=10, xf=Matrix.Translation((jp_x + 0.24, jp_y + dy, 2.15)))
            _bm_add_cylinder(bm_jp, 0.20, 0.26, segments=10, xf=Matrix.Translation((jp_x + 0.24, jp_y + dy, 1.48)))
        # Docking arms gripping jetpack from cabinet
        _bm_add_box(bm_jp, (0.55, 1.15, 0.16), Matrix.Translation((jp_x - 0.10, jp_y, 2.55)))
        finalize_mesh_object(f"Bay_{idx}_{cls_name}_JetpackRig", bm_jp, mats["DarkSteel"], col, bevel_width=0.015)

        # 3. Stylized Sci-Fi Weapon Rack + Class-Distinct Gear Silhouette
        bm_wp = bmesh.new()
        wx = bx + 0.05
        wy = by - 0.15
        # Angled rack frame + 2 stylized weapons mounted horizontally
        _bm_add_box(bm_wp, (0.28, 1.35, 1.85), Matrix.Translation((wx, wy, 2.35)))
        for wz in (1.95, 2.75):
            # Receiver + barrel + scope/stock
            _bm_add_box(bm_wp, (0.14, 1.05, 0.22), Matrix.Translation((wx + 0.22, wy, wz)))
            _bm_add_cylinder(bm_wp, 0.045, 0.72, segments=8, xf=Matrix.Translation((wx + 0.22, wy + 0.65, wz + 0.04)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
            _bm_add_box(bm_wp, (0.10, 0.34, 0.11), Matrix.Translation((wx + 0.22, wy - 0.12, wz + 0.16)))
        # Class-distinct bench equipment (Assault armor plates, Medic cryo tank, Trapper dome reel, Support capacitor)
        if cls_name == "Assault":
            for pz in (1.34, 1.48):
                _bm_add_box(bm_wp, (0.52, 0.68, 0.11), Matrix.Translation((bx + 0.24, by - 1.35, pz)))
        elif cls_name == "Medic":
            _bm_add_cylinder(bm_wp, 0.22, 0.75, segments=12, xf=Matrix.Translation((bx + 0.24, by - 1.35, 1.65)))
        elif cls_name == "Trapper":
            _bm_add_cylinder(bm_wp, 0.34, 0.45, segments=12, xf=Matrix.Translation((bx + 0.24, by - 1.35, 1.55)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y"))
        else:
            for cx_o in (-0.16, 0.16):
                _bm_add_box(bm_wp, (0.26, 0.42, 0.65), Matrix.Translation((bx + 0.24 + cx_o, by - 1.35, 1.60)))
        finalize_mesh_object(f"Bay_{idx}_{cls_name}_WeaponAndGear", bm_wp, mats["DarkSteel"], col, bevel_width=0.012)

        # 4. Illuminated Header Sign & Status Strip (Neon Cyan)
        bm_hdr = bmesh.new()
        _bm_add_box(bm_hdr, (0.14, 3.6, 0.46), Matrix.Translation((bx + 1.10, by, 4.78)) @ Matrix.Rotation(math.radians(-12), 4, "Y"))
        _bm_add_box(bm_hdr, (0.08, 0.22, 2.2), Matrix.Translation((bx + 0.02, by + 1.05, 2.25)))
        finalize_mesh_object(f"Bay_{idx}_{cls_name}_SignPanel", bm_hdr, mats["NeonCyan"], col, bevel_width=0.0)


# ---------------------------------------------------------------------------
# 2.6) 06_Dropship_Airlock_And_Monster_Pod (North Wall Y = -17m & East Wall X = +14m)
# ---------------------------------------------------------------------------

def build_airlock_and_monster_pod(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("06_Dropship_Airlock_And_Monster_Pod", root_col)
    ny = -17.0

    # --- North Wall: Dropship Double Blast Door (8m wide x 6.5m tall) ---
    for s_label, sx in [("W", -9.5), ("E", 9.5)]:
        make_recessed_panel(
            f"NorthWall_Bulkhead_{s_label}",
            (11.0, 1.1, 9.5),
            mats["ArmorGrey"],
            col,
            location=(sx, ny, 4.75),
            recess_faces="Y+",
            inset_thickness=0.25,
            inset_depth=0.09,
            ribs=2,
        )
    # Upper lintel above blast door (Z = 6.5..9.5m) + overhead heavy sliding rail
    make_recessed_panel(
        "NorthWall_UpperLintel",
        (8.4, 1.25, 3.0),
        mats["DarkSteel"],
        col,
        location=(0.0, ny, 8.0),
        recess_faces="Y+",
        inset_thickness=0.20,
        inset_depth=0.08,
    )
    make_h_beam(
        "Airlock_OverheadRail",
        length=12.4,
        height=0.55,
        width=0.65,
        flange_t=0.10,
        web_t=0.12,
        mat=mats["DarkSteel"],
        col=col,
        location=(0.0, ny + 0.55, 6.75),
        stiffeners=4,
    )

    # Left & Right Interlocking Blast Door Leaves with mechanical trapezoidal teeth
    for side_label, sign in [("Left", -1.0), ("Right", 1.0)]:
        bm_d = bmesh.new()
        # Door leaf body (4.0m wide x 6.4m tall)
        _bm_add_box(bm_d, (3.85, 0.58, 6.35), Matrix.Translation((sign * 2.02, ny + 0.15, 3.20)))
        # Interlocking heavy mechanical teeth at center seam (X ~ 0)
        for tz in (1.1, 3.2, 5.3):
            tooth_x = sign * 0.08 if (sign < 0) else sign * 0.08
            _bm_add_box(bm_d, (0.45, 0.68, 0.85), Matrix.Translation((tooth_x, ny + 0.18, tz + (0.45 if sign > 0 else -0.45))))
        # External armor rib bars
        for rz in (1.5, 4.8):
            _bm_add_box(bm_d, (3.4, 0.72, 0.42), Matrix.Translation((sign * 2.02, ny + 0.22, rz)))
        finalize_mesh_object(f"Airlock_BlastDoor_{side_label}", bm_d, mats["DarkSteel"], col, bevel_width=0.025)

    # Hydraulic clamping actuators flanking the blast door
    for s_label, sign in [("W", -1.0), ("E", 1.0)]:
        make_hydraulic_strut(
            f"Airlock_Hydraulic_{s_label}",
            p_start=Vector((sign * 5.2, ny + 0.72, 1.0)),
            p_end=Vector((sign * 4.25, ny + 0.65, 5.4)),
            outer_radius=0.18,
            mat=mats["ArmorGrey"],
            col=col,
        )

    # Airlock Amber Emergency Beacons + Floor Hazard Safety Threshold Strip
    bm_amb = bmesh.new()
    for sx in (-4.4, 4.4):
        _bm_add_box(bm_amb, (0.36, 0.36, 0.95), Matrix.Translation((sx, ny + 0.78, 5.6)))
    _bm_add_box(bm_amb, (3.6, 0.25, 0.32), Matrix.Translation((0.0, ny + 0.78, 6.95)))
    finalize_mesh_object("Airlock_AmberAlertLights", bm_amb, mats["NeonAmber"], col, bevel_width=0.0)

    bm_haz = bmesh.new()
    _bm_add_box(bm_haz, (8.6, 0.85, 0.06), Matrix.Translation((0.0, ny + 1.25, 0.03)))
    finalize_mesh_object("Airlock_FloorSafetyStrip", bm_haz, mats["HazardYellow"], col, bevel_width=0.01)

    # --- East Wall (X = +14m): Bio-Containment / Monster Trophy Display Podium ---
    px = 12.2
    bm_pod = bmesh.new()
    _bm_add_octagon_prism(bm_pod, radius=2.65, height=0.40, xf=Matrix.Translation((px, 0.0, 0.20)))
    _bm_add_octagon_prism(bm_pod, radius=2.15, height=0.12, xf=Matrix.Translation((px, 0.0, 0.42)))
    finalize_mesh_object("MonsterPod_DisplayPlatform", bm_pod, mats["DarkSteel"], col, bevel_width=0.025, bevel_segments=2)

    bm_pod_h = bmesh.new()
    _bm_add_octagon_ring(bm_pod_h, outer_r=2.62, inner_r=2.30, z_bottom=0.38, z_top=0.43, cx=px, cy=0.0)
    finalize_mesh_object("MonsterPod_HazardRing", bm_pod_h, mats["HazardYellow"], col, bevel_width=0.008)

    # 3 Heavy Containment Arches arching over the Monster Display Podium with chamfered knee gussets
    bm_arches = bmesh.new()
    for ay in (-1.9, 0.0, 1.9):
        _bm_add_box(bm_arches, (0.48, 0.48, 5.2), Matrix.Translation((px - 2.35, ay, 2.60)))
        _bm_add_box(bm_arches, (0.48, 0.48, 5.6), Matrix.Translation((px + 2.15, ay, 2.80)))
        _bm_add_box(bm_arches, (5.2, 0.52, 0.55), Matrix.Translation((px - 0.1, ay, 5.65)))
        # Corner diagonal gusset braces linking legs to top header
        _bm_add_box(bm_arches, (0.95, 0.42, 0.36), Matrix.Translation((px - 1.95, ay, 5.15)) @ Matrix.Rotation(math.radians(-42), 4, "Y"))
        _bm_add_box(bm_arches, (0.95, 0.42, 0.36), Matrix.Translation((px + 1.75, ay, 5.15)) @ Matrix.Rotation(math.radians(42), 4, "Y"))
    # Spotlight hood fixtures aimed down at podium center
    for sy in (-1.4, 1.4):
        _bm_add_cylinder(bm_arches, 0.26, 0.62, segments=10, xf=Matrix.Translation((px - 1.2, sy, 5.25)) @ Matrix.Rotation(math.radians(24), 4, "Y"))
    finalize_mesh_object("MonsterPod_ContainmentArches", bm_arches, mats["ArmorGrey"], col, bevel_width=0.02)

    # Lateral Cylindrical Bio-Stasis Generators + Floor Flanged Power Cables
    for s_label, gy in [("N", -3.4), ("S", 3.4)]:
        bm_gen = bmesh.new()
        _bm_add_box(bm_gen, (1.6, 1.6, 0.38), Matrix.Translation((px + 0.6, gy, 0.19)))
        _bm_add_cylinder(bm_gen, 0.68, 3.6, segments=14, xf=Matrix.Translation((px + 0.6, gy, 2.18)))
        for fz in (1.1, 2.2, 3.3):
            _bm_add_cylinder(bm_gen, 0.84, 0.16, segments=14, xf=Matrix.Translation((px + 0.6, gy, fz)))
        finalize_mesh_object(f"MonsterPod_Generator_{s_label}", bm_gen, mats["DarkSteel"], col, bevel_width=0.018)

        make_flanged_pipe(
            f"MonsterPod_PowerCable_{s_label}",
            [
                Vector((px + 0.6, gy, 0.42)),
                Vector((px - 1.6, gy * 0.72, 0.16)),
                Vector((px - 2.4, gy * 0.42, 0.16)),
            ],
            radius=0.14,
            mat=mats["FloorGrating"],
            col=col,
            segments=10,
            flange_every=1,
        )

    # Containment Arch Emergency Neon Amber Emitters
    bm_pem = bmesh.new()
    for ay in (-1.9, 0.0, 1.9):
        _bm_add_box(bm_pem, (0.14, 0.26, 2.8), Matrix.Translation((px - 2.08, ay, 2.8)))
    for gy in (-3.4, 3.4):
        _bm_add_cylinder(bm_pem, 0.70, 0.24, segments=12, xf=Matrix.Translation((px + 0.6, gy, 4.05)))
    finalize_mesh_object("MonsterPod_ContainmentLights", bm_pem, mats["NeonAmber"], col, bevel_width=0.0)


# ---------------------------------------------------------------------------
# 2.7) 07_Roblox_Anchors (Exact Reference Guide Cubes at Floor Level)
# ---------------------------------------------------------------------------

def build_roblox_anchors(root_col: bpy.types.Collection, mats: Dict[str, bpy.types.Material]) -> None:
    col = ensure_collection("07_Roblox_Anchors", root_col)
    anchors = [
        ("ANCHOR_LobbySpawn", (0.0, -10.5, 0.05)),
        ("ANCHOR_HoloCenter", (0.0, 0.0, 0.50)),
        ("ANCHOR_WindowView", (0.0, 13.8, 0.05)),
        ("ANCHOR_ClassBay_1", (-11.2, -10.5, 0.05)),
        ("ANCHOR_ClassBay_2", (-11.2, -3.5, 0.05)),
        ("ANCHOR_ClassBay_3", (-11.2, 3.5, 0.05)),
        ("ANCHOR_ClassBay_4", (-11.2, 10.5, 0.05)),
        ("ANCHOR_MonsterPodium", (12.2, 0.0, 0.53)),
    ]
    for a_name, pos in anchors:
        bm = bmesh.new()
        _bm_add_box(bm, (0.5, 0.5, 0.1))
        finalize_mesh_object(a_name, bm, mats["NeonCyan"], col, location=pos, bevel_width=0.0)


# ---------------------------------------------------------------------------
# Lighting, World Atmosphere & Preview Cameras (Non-MESH, filtered out of FBX)
# ---------------------------------------------------------------------------

def setup_lighting_and_cameras() -> List[bpy.types.Object]:
    col = ensure_collection("Lobby_Lighting_And_Cameras")

    # Orbital dark space/volcanic horizon outside the panoramic glass
    world = bpy.data.worlds.new("OrbitalHangar_World")
    bpy.context.scene.world = world
    if not world.use_nodes:
        world.use_nodes = True
    nt = world.node_tree
    bg = next((n for n in nt.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.05, 0.09, 0.14, 1.0)
        bg.inputs["Strength"].default_value = 0.85

    def add_light(name: str, ltype: str, pos: Tuple[float, float, float], color: Tuple[float, float, float], energy: float, rot: Tuple[float, float, float] = (0, 0, 0), size: float = 2.0) -> None:
        ld = bpy.data.lights.new(name=name, type=ltype)
        ld.color = color
        ld.energy = energy
        if hasattr(ld, "size"):
            ld.size = size
        elif hasattr(ld, "shadow_soft_size"):
            ld.shadow_soft_size = size * 0.3
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(pos)
        lo.rotation_euler = Euler(rot, "XYZ")
        col.objects.link(lo)

    # Overhead industrial cold-cyan ceiling banks
    for ly in (-8.0, 0.0, 8.0):
        add_light(f"KeyCeilingLight_{ly}", "AREA", (0.0, ly, 8.95), (0.72, 0.90, 1.0), 1600.0, size=4.0)

    # Central Hologram bounce light
    add_light("HoloCenterBounce", "POINT", (0.0, 0.0, 2.8), (0.0, 0.86, 1.0), 650.0, size=1.0)

    # 4 West Hunter Bay accent spots
    for idx, by in enumerate([-10.5, -3.5, 3.5, 10.5], start=1):
        add_light(f"BaySpot_{idx}", "POINT", (-11.5, by, 4.4), (0.65, 0.88, 1.0), 420.0, size=0.8)

    # East Monster Containment dramatic warm amber spotlight + North Airlock alert glow
    add_light("MonsterPodiumKey", "SPOT", (10.5, 0.0, 5.8), (1.0, 0.45, 0.12), 1800.0, rot=(0.0, math.radians(-22), 0.0), size=1.2)
    add_light("AirlockAmberFill", "POINT", (0.0, -14.2, 5.4), (1.0, 0.42, 0.05), 550.0, size=1.2)
    add_light("ObsSkyFill", "AREA", (0.0, 21.0, 6.0), (0.42, 0.68, 0.95), 2400.0, rot=(math.radians(95), 0.0, 0.0), size=12.0)

    cam_specs = [
        ("Cam_1_Overview", Vector((-11.0, -13.5, 6.2)), Vector((2.5, 4.0, 2.2))),
        ("Cam_2_HoloToWindow", Vector((0.0, -10.5, 2.1)), Vector((0.0, 16.0, 2.8))),
        ("Cam_3_LoadoutBays", Vector((-4.5, -11.0, 2.4)), Vector((-13.8, 2.0, 2.3))),
        ("Cam_4_AirlockAndPodium", Vector((-5.5, 7.5, 2.8)), Vector((8.5, -9.0, 2.8))),
    ]
    cams: List[bpy.types.Object] = []
    for cname, pos, target in cam_specs:
        cd = bpy.data.cameras.new(cname)
        cd.lens = 21.0
        cd.clip_end = 500.0
        co = bpy.data.objects.new(cname, cd)
        co.location = pos
        co.rotation_euler = (target - pos).normalized().to_track_quat("-Z", "Y").to_euler()
        col.objects.link(co)
        cams.append(co)
    bpy.context.scene.camera = cams[0]
    return cams


# ---------------------------------------------------------------------------
# Audit, Export (.blend + .fbx), & Preview Rendering
# ---------------------------------------------------------------------------

def run_audit() -> dict:
    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    total_tris = 0
    heaviest_name = ""
    heaviest_tris = 0
    neg_scales: List[str] = []
    empty_meshes: List[str] = []
    over_budget: List[str] = []

    for o in mesh_objs:
        v_count = len(o.data.vertices)
        if v_count == 0 or len(o.data.polygons) == 0:
            empty_meshes.append(o.name)
        if o.scale.x < 0 or o.scale.y < 0 or o.scale.z < 0:
            neg_scales.append(o.name)
        tris = sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
        total_tris += tris
        if tris > heaviest_tris:
            heaviest_tris = tris
            heaviest_name = o.name
        if tris > 8000:
            over_budget.append(f"{o.name} ({tris})")

    report = {
        "totalMeshObjects": len(mesh_objs),
        "totalTriangles": total_tris,
        "heaviestObject": heaviest_name,
        "heaviestTriangles": heaviest_tris,
        "negativeScaleObjects": neg_scales,
        "emptyMeshes": empty_meshes,
        "over8000Budget": over_budget,
    }
    print("=== AUDIT ORBITAL DROPSHIP HANGAR ===")
    print(json.dumps(report, indent=2))
    assert not empty_meshes, f"Empty meshes detected: {empty_meshes}"
    assert not neg_scales, f"Negative scale objects detected: {neg_scales}"
    assert not over_budget, f"Objects over 8000 tris budget: {over_budget}"
    return report


def render_previews(cams: List[bpy.types.Object]) -> List[str]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    paths: List[str] = []
    for idx, cam in enumerate(cams, start=1):
        scene.camera = cam
        out = str(PREVIEWS_DIR / f"lobby_view_{idx}.png")
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        paths.append(out)
    scene.camera = cams[0]
    return paths


def main() -> None:
    reset_scene()
    mats = create_materials()
    lobby_col = ensure_collection("Lobby")

    build_floor_and_substructure(lobby_col, mats)
    build_walls_pillars_ceiling(lobby_col, mats)
    build_panoramic_observation_bay(lobby_col, mats)
    build_central_holotable(lobby_col, mats)
    build_hunter_loadout_bays(lobby_col, mats)
    build_airlock_and_monster_pod(lobby_col, mats)
    build_roblox_anchors(lobby_col, mats)
    cams = setup_lighting_and_cameras()

    audit = run_audit()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    bpy.ops.export_scene.fbx(
        filepath=str(FBX_PATH),
        use_selection=False,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        mesh_smooth_type="FACE",
        path_mode="AUTO",
    )

    previews = render_previews(cams)
    audit["blendPath"] = str(BLEND_PATH)
    audit["fbxPath"] = str(FBX_PATH)
    audit["previews"] = previews
    AUDIT_PATH.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print("ORBITAL_DROPSHIP_LOBBY_BUILT_OK")


if __name__ == "__main__":
    main()
