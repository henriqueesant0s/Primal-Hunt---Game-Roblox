"""Arauto do Eclipse Abissal — 3-Stage Evolving Animated 3D Monster for PRIMAL HUNT / PROJECT ABYSS.

Features:
- Faithful 3D adaptation of the approved Solar-Eclipse cosmic-horror predator:
  * Stage 1 ("Predador Alfa do Eclipse", 1.0x = ~6.2m tall — already dwarfing 2.4m Alpha Fauna & 1.54m Hunter)
  * Stage 2 ("Arauto Desperto", 1.3x = ~8.1m tall)
  * Stage 3 ("Deus do Eclipse Abissal", 1.65x = ~10.2m tall)
- Continuous Voxel-Remeshed Core Body (< 16k tris) + exposed curved bone ribcage over internal solar furnace
- 63-bone Skeletal Armature (Spine, Eclipse Head + 8 radial 2-bone Crown Chains, 4 Clawed/Shackled Arms, 6 5-bone Spiral Tentacles)
- 8 Full Biomechanical Skeletal Animations (24fps Blender 5.3 Slotted Actions & NLA):
  Monster_Intro_Roar, Monster_Idle, Monster_Walk, Monster_Run, Monster_Attack, Monster_Jump, Monster_SpitAndSlam, Monster_Evolve
- 4 Eevee Renders (incl. 5-figure 3D Lineup) + 288-frame (12s) H.264 MP4 Animation Reel + GLB / FBX / Per-Stage GLBs + .blend
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector, kdtree, noise

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
TEX_DIR = ROOT_DIR / "textures" / "monster"
PREVIEWS_DIR = ROOT_DIR / "previews"

BLEND_PATH = ROOT_DIR / "AbyssMonster.blend"
SHOWCASE_BLEND_PATH = ROOT_DIR / "ArautoDoEclipse_3Estagios.blend"
FBX_PATH = ROOT_DIR / "AbyssMonster.fbx"
GLB_PATH = ROOT_DIR / "AbyssMonster.glb"
STAGE1_GLB = ROOT_DIR / "AbyssMonster_Stage1.glb"
STAGE2_GLB = ROOT_DIR / "AbyssMonster_Stage2.glb"
STAGE3_GLB = ROOT_DIR / "AbyssMonster_Stage3.glb"
VIDEO_PATH = PREVIEWS_DIR / "AbyssMonster_AnimationPreview.mp4"
AUDIT_PATH = ROOT_DIR / "monster_audit.json"

PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Scene Reset & Language-Independent Shader / Action Helpers (Blender 5.3)
# ---------------------------------------------------------------------------

def clear_scene_keep_ui() -> None:
    bpy.ops.wm.read_factory_settings()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for cam in list(bpy.data.cameras):
        bpy.data.cameras.remove(cam)
    for lt in list(bpy.data.lights):
        bpy.data.lights.remove(lt)
    for im in list(bpy.data.images):
        bpy.data.images.remove(im)

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


def _get_socket(sockets: Sequence[bpy.types.NodeSocket], identifier: str) -> bpy.types.NodeSocket:
    for s in sockets:
        if getattr(s, "identifier", None) == identifier:
            return s
    for s in sockets:
        if s.name == identifier:
            return s
    raise KeyError(f"Socket '{identifier}' not found among {[s.identifier for s in sockets]}")


def _load_packed_image(stem: str, colorspace: str) -> Optional[bpy.types.Image]:
    for ext in (".jpg", ".png", ".jpeg"):
        p = TEX_DIR / f"{stem}{ext}"
        if p.exists():
            img = bpy.data.images.load(str(p), check_existing=True)
            img.colorspace_settings.name = colorspace
            img.pack()
            return img
    return None


def _build_pbr_chitin_material(
    name: str,
    tex_prefix: str,
    tint_linear: Tuple[float, float, float],
    rough_min: float,
    rough_max: float,
    metallic: float,
    normal_strength: float,
    uv_scale: float,
    voronoi_scale: float,
    bump_strength: float,
    ao_darken: float,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")

    _get_socket(bsdf.inputs, "Base Color").default_value = (*tint_linear, 1.0)
    _get_socket(bsdf.inputs, "Metallic").default_value = metallic
    _get_socket(bsdf.inputs, "Roughness").default_value = (rough_min + rough_max) * 0.5

    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    _get_socket(mp.inputs, "Scale").default_value = (uv_scale, uv_scale, uv_scale)
    nt.links.new(_get_socket(tc.outputs, "UV"), _get_socket(mp.inputs, "Vector"))

    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "F1"
    _get_socket(vor.inputs, "Scale").default_value = voronoi_scale
    nt.links.new(_get_socket(tc.outputs, "Object"), _get_socket(vor.inputs, "Vector"))

    vr = nt.nodes.new("ShaderNodeMapRange")
    _get_socket(vr.inputs, "From Min").default_value = 0.0
    _get_socket(vr.inputs, "From Max").default_value = 0.85
    _get_socket(vr.inputs, "To Min").default_value = 1.15
    _get_socket(vr.inputs, "To Max").default_value = 0.72
    nt.links.new(_get_socket(vor.outputs, "Distance"), _get_socket(vr.inputs, "Value"))

    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    _get_socket(ao.inputs, "Distance").default_value = 0.85
    ar = nt.nodes.new("ShaderNodeMapRange")
    _get_socket(ar.inputs, "To Min").default_value = ao_darken
    _get_socket(ar.inputs, "To Max").default_value = 1.0
    nt.links.new(_get_socket(ao.outputs, "AO"), _get_socket(ar.inputs, "Value"))

    mul_t = nt.nodes.new("ShaderNodeMath")
    mul_t.operation = "MULTIPLY"
    nt.links.new(_get_socket(vr.outputs, "Result"), mul_t.inputs[0])
    nt.links.new(_get_socket(ar.outputs, "Result"), mul_t.inputs[1])

    diff_img = _load_packed_image(f"{tex_prefix}_diff_1k", "sRGB")
    if diff_img is not None:
        td = nt.nodes.new("ShaderNodeTexImage")
        td.image = diff_img
        nt.links.new(_get_socket(mp.outputs, "Vector"), _get_socket(td.inputs, "Vector"))
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        nt.links.new(_get_socket(td.outputs, "Color"), _get_socket(bw.inputs, "Color"))
        br = nt.nodes.new("ShaderNodeMapRange")
        _get_socket(br.inputs, "From Min").default_value = 0.05
        _get_socket(br.inputs, "From Max").default_value = 0.80
        _get_socket(br.inputs, "To Min").default_value = 0.55
        _get_socket(br.inputs, "To Max").default_value = 1.32
        nt.links.new(_get_socket(bw.outputs, "Val"), _get_socket(br.inputs, "Value"))
        ma = nt.nodes.new("ShaderNodeMath")
        ma.operation = "MULTIPLY"
        nt.links.new(_get_socket(mul_t.outputs, "Value"), ma.inputs[0])
        nt.links.new(_get_socket(br.outputs, "Result"), ma.inputs[1])
        tone_out = _get_socket(ma.outputs, "Value")
    else:
        tone_out = _get_socket(mul_t.outputs, "Value")

    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.clamp_result = True
    rin = [s for s in mix.inputs if s.type == "RGBA"]
    rout = [s for s in mix.outputs if s.type == "RGBA"][0]
    _get_socket(mix.inputs, "Factor").default_value = 1.0
    rin[0].default_value = (*tint_linear, 1.0)
    nt.links.new(tone_out, rin[1])
    nt.links.new(rout, _get_socket(bsdf.inputs, "Base Color"))

    r_img = _load_packed_image(f"{tex_prefix}_rough_1k", "Non-Color")
    if r_img is not None:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = r_img
        nt.links.new(_get_socket(mp.outputs, "Vector"), _get_socket(tr.inputs, "Vector"))
        mr = nt.nodes.new("ShaderNodeMapRange")
        _get_socket(mr.inputs, "From Min").default_value = 0.1
        _get_socket(mr.inputs, "From Max").default_value = 0.9
        _get_socket(mr.inputs, "To Min").default_value = rough_min
        _get_socket(mr.inputs, "To Max").default_value = rough_max
        nt.links.new(_get_socket(tr.outputs, "Color"), _get_socket(mr.inputs, "Value"))
        nt.links.new(_get_socket(mr.outputs, "Result"), _get_socket(bsdf.inputs, "Roughness"))

    bmp = nt.nodes.new("ShaderNodeBump")
    _get_socket(bmp.inputs, "Strength").default_value = bump_strength
    _get_socket(bmp.inputs, "Distance").default_value = 0.04
    nt.links.new(_get_socket(vor.outputs, "Distance"), _get_socket(bmp.inputs, "Height"))
    nt.links.new(_get_socket(bmp.outputs, "Normal"), _get_socket(bsdf.inputs, "Normal"))

    n_img = _load_packed_image(f"{tex_prefix}_nor_gl_1k", "Non-Color")
    if n_img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = n_img
        nt.links.new(_get_socket(mp.outputs, "Vector"), _get_socket(tn.inputs, "Vector"))
        nm = nt.nodes.new("ShaderNodeNormalMap")
        _get_socket(nm.inputs, "Strength").default_value = normal_strength
        nt.links.new(_get_socket(tn.outputs, "Color"), _get_socket(nm.inputs, "Color"))
        nt.links.new(_get_socket(nm.outputs, "Normal"), _get_socket(bmp.inputs, "Normal"))

    return mat


def create_materials() -> Dict[str, bpy.types.Material]:
    def simple_mat(
        name: str,
        color: Tuple[float, float, float],
        roughness: float,
        metallic: float = 0.0,
        emission: Tuple[float, float, float] | None = None,
        emission_strength: float = 0.0,
        alpha: float = 1.0,
        specular: float = 0.5,
    ) -> bpy.types.Material:
        mat = bpy.data.materials.new(name=name)
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        _get_socket(bsdf.inputs, "Base Color").default_value = (*color, 1.0)
        _get_socket(bsdf.inputs, "Roughness").default_value = roughness
        _get_socket(bsdf.inputs, "Metallic").default_value = metallic
        _get_socket(bsdf.inputs, "Alpha").default_value = alpha
        for cand in ("Specular IOR Level", "Specular"):
            if any(getattr(s, "identifier", s.name) == cand for s in bsdf.inputs):
                _get_socket(bsdf.inputs, cand).default_value = specular
                break
        if emission is not None and emission_strength > 0.0:
            _get_socket(bsdf.inputs, "Emission Color").default_value = (*emission, 1.0)
            _get_socket(bsdf.inputs, "Emission Strength").default_value = emission_strength
        if alpha < 0.99 and hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        return mat

    return {
        "Hide": _build_pbr_chitin_material(
            "Mat_Monster_AbyssalHide",
            "brown_leather",
            tint_linear=(0.044, 0.040, 0.045),
            rough_min=0.28,
            rough_max=0.62,
            metallic=0.05,
            normal_strength=1.25,
            uv_scale=2.2,
            voronoi_scale=42.0,
            bump_strength=0.38,
            ao_darken=0.20,
        ),
        "Carapace": _build_pbr_chitin_material(
            "Mat_Monster_ObsidianCarapace",
            "cliff_side",
            tint_linear=(0.110, 0.100, 0.112),
            rough_min=0.22,
            rough_max=0.48,
            metallic=0.36,
            normal_strength=1.55,
            uv_scale=2.0,
            voronoi_scale=24.0,
            bump_strength=0.32,
            ao_darken=0.18,
        ),
        "Bronze": simple_mat("Mat_Eclipse_BronzeShackle", (0.36, 0.23, 0.09), roughness=0.34, metallic=0.85),
        "Bone": simple_mat("Mat_Monster_BoneClaws", (0.28, 0.22, 0.17), roughness=0.28, metallic=0.12),
        "DarkRibChitin": simple_mat("Mat_Eclipse_DarkRibChitin", (0.026, 0.022, 0.024), roughness=0.30, metallic=0.38),
        "VoidBlack": simple_mat("Mat_Eclipse_VoidBlack", (0.0, 0.0, 0.0), roughness=1.0, metallic=0.0, specular=0.0),
        # Pure self-emissive Chest Solar Furnace (zero diffuse key-light washout under AgX!)
        "FurnaceOuter": simple_mat("Mat_Furnace_OuterEmber", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.04, 0.001), emission_strength=3.8),
        "FurnaceHeart": simple_mat("Mat_Furnace_MoltenHeart", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.28, 0.01), emission_strength=8.0),
        # Pure self-emissive Dual-Layer Solar Eclipse Coronas: Blood Red (S1) -> Burning Amber (S2) -> White-Gold (S3)
        "BloodCorona_S1": simple_mat("Mat_Eclipse_BloodCorona_S1", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.025, 0.001), emission_strength=3.2),
        "BloodRim_S1": simple_mat("Mat_Eclipse_BloodRim_S1", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.18, 0.01), emission_strength=7.5),
        "GoldCorona_S2": simple_mat("Mat_Eclipse_GoldCorona_S2", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.18, 0.005), emission_strength=4.2),
        "GoldRim_S2": simple_mat("Mat_Eclipse_GoldRim_S2", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.45, 0.04), emission_strength=9.5),
        "SolarCorona_S3": simple_mat("Mat_Eclipse_SolarCorona_S3", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.42, 0.05), emission_strength=5.8),
        "SolarRim_S3": simple_mat("Mat_Eclipse_SolarRim_S3", (0.0, 0.0, 0.0), roughness=1.0, specular=0.0, emission=(1.0, 0.78, 0.32), emission_strength=14.0),
        "SpitPlasma": simple_mat("Mat_Spit_SolarAcid", (0.62, 1.0, 0.08), roughness=0.15, emission=(0.62, 1.0, 0.08), emission_strength=14.0, alpha=0.82),
        # Stage materials
        "StageBasalt": simple_mat("Mat_Stage_Basalt", (0.035, 0.040, 0.048), roughness=0.72, metallic=0.10),
        "StageAmber": simple_mat("Mat_Stage_AmberTrim", (1.0, 0.25, 0.02), roughness=0.20, emission=(1.0, 0.25, 0.02), emission_strength=3.5),
        "HunterArmor": simple_mat("Mat_Stage_HunterArmor", (0.16, 0.19, 0.24), roughness=0.45, metallic=0.38),
        "HunterVisor": simple_mat("Mat_Stage_HunterVisor", (0.0, 0.85, 1.0), roughness=0.12, emission=(0.0, 0.85, 1.0), emission_strength=6.0),
        "FaunaHide": simple_mat("Mat_Stage_FaunaHide", (0.065, 0.058, 0.055), roughness=0.58, metallic=0.08),
        "FaunaCarapace": simple_mat("Mat_Stage_FaunaArmor", (0.13, 0.115, 0.11), roughness=0.34, metallic=0.30),
        "FaunaMagma": simple_mat("Mat_Stage_FaunaMagma", (1.0, 0.08, 0.004), roughness=0.20, emission=(1.0, 0.08, 0.004), emission_strength=6.5),
    }


# ---------------------------------------------------------------------------
# Skeleton Definition & Builder (63 Bones, Base Scale = Stage 1 ~6.2m)
# ---------------------------------------------------------------------------

CROWN_ANGLES_DEG = [22.0, 56.0, 92.0, 126.0]  # Mirrored +X (L) and -X (R) = 8 chains x 2 bones = 16 bones
TENT_ANGLES_DEG = [28.0, -28.0, 88.0, -88.0, 148.0, -148.0]  # 6 radial pillar->spiral tentacles x 5 bones = 30 bones


def _eval_catmull_rom(pts: Sequence[Vector], t_global: float) -> Vector:
    n = len(pts)
    if n < 2:
        return pts[0].copy()
    s = max(0.0, min(1.0, t_global)) * (n - 1)
    i = min(n - 2, int(s))
    u = s - i
    p0 = pts[i - 1] if i > 0 else (pts[0] * 2.0 - pts[1])
    p1 = pts[i]
    p2 = pts[i + 1]
    p3 = pts[i + 2] if (i + 2) < n else (pts[-1] * 2.0 - pts[-2])
    u2 = u * u
    u3 = u2 * u
    return 0.5 * (
        (2.0 * p1)
        + (-p0 + p2) * u
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3
    )


def tentacle_curve_points(angle_deg: float) -> List[Vector]:
    """Six iconic coiled constrictor tentacles: sleek descending pillar -> floor sweep -> grand upward inward spiral."""
    rad = math.radians(angle_deg)
    # Direction outward from pelvis center (-Y = forward)
    dir_xy = Vector((math.sin(rad), -math.cos(rad), 0.0))
    perp_xy = Vector((math.cos(rad), math.sin(rad), 0.0))
    c_sign = 1.0 if angle_deg >= 0.0 else -1.0

    p0 = dir_xy * 0.36 + Vector((0.0, 0.0, 2.42))
    p1 = dir_xy * 0.54 + Vector((0.0, 0.0, 1.54))
    p2 = dir_xy * 0.88 + perp_xy * (0.12 * c_sign) + Vector((0.0, 0.0, 0.54))
    p3 = dir_xy * 1.50 + perp_xy * (0.34 * c_sign) + Vector((0.0, 0.0, 0.24))
    p4 = dir_xy * 2.08 + perp_xy * (0.28 * c_sign) + Vector((0.0, 0.0, 1.02))
    p5 = dir_xy * 1.68 + perp_xy * (0.08 * c_sign) + Vector((0.0, 0.0, 1.48))
    return [p0, p1, p2, p3, p4, p5]


def create_master_armature(root_col: bpy.types.Collection) -> Tuple[bpy.types.Object, Dict[str, List[str]]]:
    arm_data = bpy.data.armatures.new("Monster_Armature")
    arm_obj = bpy.data.objects.new("Monster_Armature", arm_data)
    root_col.objects.link(arm_obj)

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_bone(name: str, head: Vector, tail: Vector, parent_name: Optional[str] = None, connect: bool = False) -> bpy.types.EditBone:
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.roll = 0.0
        if parent_name:
            b.parent = eb[parent_name]
            b.use_connect = connect
        return b

    # Root & Spine
    add_bone("root", Vector((0, 0, 0)), Vector((0, 0, 0.50)))
    add_bone("pelvis", Vector((0, 0, 2.35)), Vector((0, 0, 2.75)), "root", connect=False)
    add_bone("spine_1", Vector((0, 0, 2.75)), Vector((0, -0.04, 3.30)), "pelvis", connect=True)
    add_bone("spine_2", Vector((0, -0.04, 3.30)), Vector((0, -0.08, 3.90)), "spine_1", connect=True)
    add_bone("spine_3", Vector((0, -0.08, 3.90)), Vector((0, -0.12, 4.50)), "spine_2", connect=True)
    add_bone("neck", Vector((0, -0.12, 4.50)), Vector((0, -0.16, 4.85)), "spine_3", connect=True)
    add_bone("head", Vector((0, -0.16, 4.85)), Vector((0, -0.20, 5.48)), "neck", connect=True)

    eclipse_center = Vector((0.0, -0.22, 5.14))

    # 8 Radial 2-Bone Crown Chains (16 bones)
    crown_chains: List[Tuple[str, Vector, Vector, Vector]] = []
    idx_c = 0
    for sgn in (1.0, -1.0):
        for ang_deg in CROWN_ANGLES_DEG:
            rad = math.radians(ang_deg)
            dir_v = Vector((sgn * math.sin(rad), 0.14, math.cos(rad) * 0.85)).normalized()
            p0 = eclipse_center + dir_v * 0.45
            p1 = eclipse_center + dir_v * 1.18 + Vector((0, 0.08, 0.06))
            p2 = eclipse_center + dir_v * 2.15 + Vector((0, 0.22, -0.06))
            b1 = f"crown_{idx_c}_1"
            b2 = f"crown_{idx_c}_2"
            add_bone(b1, p0, p1, "head", connect=False)
            add_bone(b2, p1, p2, b1, connect=True)
            crown_chains.append((b1, p0, p1, p2))
            idx_c += 1

    # 4 Muscular Clawed Arms
    for side, sgn in (("l", 1.0), ("r", -1.0)):
        # Upper Arm Pair (parented to spine_3)
        p_sh = Vector((sgn * 0.35, -0.10, 4.32))
        p_up = Vector((sgn * 0.90, -0.06, 4.38))
        p_el = Vector((sgn * 1.62, -0.12, 4.10))
        p_wr = Vector((sgn * 2.34, -0.26, 3.80))
        p_hd = Vector((sgn * 2.78, -0.36, 3.60))
        add_bone(f"arm_up_sh_{side}", p_sh, p_up, "spine_3", connect=False)
        add_bone(f"arm_up_up_{side}", p_up, p_el, f"arm_up_sh_{side}", connect=True)
        add_bone(f"arm_up_lo_{side}", p_el, p_wr, f"arm_up_up_{side}", connect=True)
        add_bone(f"arm_up_hd_{side}", p_wr, p_hd, f"arm_up_lo_{side}", connect=True)

        # Lower Arm Pair (parented to spine_2)
        lp_sh = Vector((sgn * 0.40, -0.08, 3.62))
        lp_el = Vector((sgn * 0.96, -0.20, 3.10))
        lp_wr = Vector((sgn * 1.38, -0.44, 2.55))
        lp_hd = Vector((sgn * 1.62, -0.60, 2.16))
        add_bone(f"arm_lo_up_{side}", lp_sh, lp_el, "spine_2", connect=False)
        add_bone(f"arm_lo_lo_{side}", lp_el, lp_wr, f"arm_lo_up_{side}", connect=True)
        add_bone(f"arm_lo_hd_{side}", lp_wr, lp_hd, f"arm_lo_lo_{side}", connect=True)

    # 6 Coiling Constrictor Tentacles (5 bones each = 30 bones)
    region_bones: Dict[str, List[str]] = {
        "torso": ["pelvis", "spine_1", "spine_2", "spine_3", "neck"],
        "arm_up_l": ["arm_up_sh_l", "arm_up_up_l", "arm_up_lo_l", "arm_up_hd_l"],
        "arm_up_r": ["arm_up_sh_r", "arm_up_up_r", "arm_up_lo_r", "arm_up_hd_r"],
        "arm_lo_l": ["arm_lo_up_l", "arm_lo_lo_l", "arm_lo_hd_l"],
        "arm_lo_r": ["arm_lo_up_r", "arm_lo_lo_r", "arm_lo_hd_r"],
    }

    for tid, ang_deg in enumerate(TENT_ANGLES_DEG):
        pts = tentacle_curve_points(ang_deg)
        t_names: List[str] = []
        parent_n = "pelvis"
        for k in range(5):
            bn = f"tent_{tid}_{k + 1}"
            add_bone(bn, pts[k], pts[k + 1], parent_n, connect=(k > 0))
            t_names.append(bn)
            parent_n = bn
        region_bones[f"tent_{tid}"] = t_names

    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"

    return arm_obj, region_bones


# ---------------------------------------------------------------------------
# Procedural Lofting Primitives (Watertight Organics, Spiral Tentacles, Ribs, Claws)
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
    radial_segs: int = 12,
    mat_idx: int = 0,
    dform_lay: Optional[bmesh.types.BMLayerItem] = None,
    weights_per_station: Optional[Sequence[Dict[int, float]]] = None,
    kd_samples: Optional[List[Tuple[Vector, str]]] = None,
    kd_region: Optional[str] = None,
    dorsal_pinch: float = 0.0,
) -> None:
    pts = [s[0] for s in stations]
    frames = _parallel_frames(pts)
    if kd_samples is not None and kd_region is not None:
        for p in pts:
            kd_samples.append((p.copy(), kd_region))

    rings: List[List[bmesh.types.BMVert]] = []
    for idx, ((c, rx, rz), (t, rv, uv)) in enumerate(zip(stations, frames)):
        w_dict = weights_per_station[idx] if weights_per_station is not None else None
        ring: List[bmesh.types.BMVert] = []
        for s in range(radial_segs):
            th = (2.0 * math.pi * s) / radial_segs
            ct, st = math.cos(th), math.sin(th)
            ridge = dorsal_pinch * max(0.0, st) ** 2
            pos = c + rv * (ct * rx) + uv * ((st + ridge) * rz)
            v = bm.verts.new(pos)
            if dform_lay is not None and w_dict is not None:
                for gi, wv in w_dict.items():
                    v[dform_lay][gi] = wv
            ring.append(v)
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(radial_segs):
            jn = (j + 1) % radial_segs
            f = bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
            f.material_index = mat_idx

    v0 = bm.verts.new(pts[0] - frames[0][0] * min(stations[0][1], stations[0][2]) * 0.28)
    v1 = bm.verts.new(pts[-1] + frames[-1][0] * max(0.015, min(stations[-1][1], stations[-1][2]) * 0.65))
    if dform_lay is not None and weights_per_station is not None:
        for gi, wv in weights_per_station[0].items():
            v0[dform_lay][gi] = wv
        for gi, wv in weights_per_station[-1].items():
            v1[dform_lay][gi] = wv

    for j in range(radial_segs):
        jn = (j + 1) % radial_segs
        f0 = bm.faces.new((v0, rings[0][jn], rings[0][j]))
        f0.material_index = mat_idx
        f1 = bm.faces.new((v1, rings[-1][j], rings[-1][jn]))
        f1.material_index = mat_idx


# ---------------------------------------------------------------------------
# 1. Core Continuous Voxel-Remeshed Body + Surgical KDTree Bone Skinning
# ---------------------------------------------------------------------------

def _seg_distance(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    denom = ab.dot(ab)
    if denom < 1e-8:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    proj = a + ab * t
    return (p - proj).length


def build_core_body(
    arm_obj: bpy.types.Object,
    region_bones: Dict[str, List[str]],
    root_col: bpy.types.Collection,
    mats: Dict[str, bpy.types.Material],
) -> Tuple[bpy.types.Object, int]:
    bm = bmesh.new()
    kd_samples: List[Tuple[Vector, str]] = []

    # Sculpted muscular V-tapered torso: wide predator chest -> sunken sternum furnace pocket -> wasp-waist -> hip root
    add_closed_loft(
        bm,
        [
            (Vector((0.0, 0.02, 2.05)), 0.42, 0.32),  # Hip root neatly tucked inside Gothic pelvic skirt
            (Vector((0.0, 0.01, 2.42)), 0.46, 0.34),  # Pelvis core
            (Vector((0.0, 0.00, 2.78)), 0.29, 0.24),  # Narrow wasp-waist
            (Vector((0.0, 0.08, 3.38)), 0.40, 0.22),  # Mid thoracic core (recessed front behind dark ribs)
            (Vector((0.0, 0.06, 3.92)), 0.52, 0.24),  # Upper sternum core
            (Vector((0.0, 0.04, 4.38)), 0.84, 0.30),  # Broad predator V-taper lats/shoulders
            (Vector((0.0, 0.02, 4.72)), 0.30, 0.20),  # Neck tucked cleanly behind Solar Tear & Eclipse Ring
            (Vector((0.0, -0.02, 4.96)), 0.24, 0.18), # Head socket collar behind Singularity Sphere
        ],
        radial_segs=18,
        kd_samples=kd_samples,
        kd_region="torso",
    )

    # Thick pectoral & deltoid/trapezius shoulder swells flanking the recessed central sternum furnace pocket
    for sgn in (1.0, -1.0):
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.48, -0.08, 3.94)), 0.23, 0.22),
                (Vector((sgn * 0.62, -0.10, 4.28)), 0.34, 0.29),
                (Vector((sgn * 0.86, -0.08, 4.38)), 0.34, 0.31),
            ],
            radial_segs=12,
            kd_samples=kd_samples,
            kd_region="torso",
        )

    # 4 Thick Muscular Clawed Arms with well-spaced clearance for clean Voxel Remesh
    for side, sgn in (("l", 1.0), ("r", -1.0)):
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.72, -0.08, 4.36)), 0.34, 0.31),
                (Vector((sgn * 1.24, -0.09, 4.24)), 0.27, 0.25),
                (Vector((sgn * 1.62, -0.12, 4.10)), 0.21, 0.20),
                (Vector((sgn * 1.98, -0.19, 3.95)), 0.24, 0.22),
                (Vector((sgn * 2.34, -0.26, 3.80)), 0.16, 0.14),
                (Vector((sgn * 2.66, -0.34, 3.65)), 0.17, 0.12),
                (Vector((sgn * 2.86, -0.38, 3.56)), 0.11, 0.08),
            ],
            radial_segs=12,
            kd_samples=kd_samples,
            kd_region=f"arm_up_{side}",
        )
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.46, -0.08, 3.62)), 0.24, 0.22),
                (Vector((sgn * 0.74, -0.14, 3.34)), 0.21, 0.19),
                (Vector((sgn * 0.96, -0.20, 3.10)), 0.17, 0.16),
                (Vector((sgn * 1.18, -0.33, 2.82)), 0.19, 0.17),
                (Vector((sgn * 1.38, -0.44, 2.55)), 0.135, 0.12),
                (Vector((sgn * 1.58, -0.58, 2.20)), 0.14, 0.10),
            ],
            radial_segs=10,
            kd_samples=kd_samples,
            kd_region=f"arm_lo_{side}",
        )

    body_mesh = bpy.data.meshes.new("Monster_CoreBody_Skinned")
    bm.to_mesh(body_mesh)
    bm.free()

    body_obj = bpy.data.objects.new("Monster_CoreBody_Skinned", body_mesh)
    root_col.objects.link(body_obj)
    body_obj.parent = arm_obj

    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    bpy.context.view_layer.objects.active = body_obj

    # Voxel Remesh fuses torso, deltoid muscles, neck & all 4 arms into 1 watertight sculpted upper anatomy!
    rem = body_obj.modifiers.new("VoxelRemesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = 0.038
    rem.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=rem.name)

    sm = body_obj.modifiers.new("SmoothSkin", "SMOOTH")
    sm.factor = 0.50
    sm.iterations = 3
    bpy.ops.object.modifier_apply(modifier=sm.name)

    # 3D Anatomical Muscle Striations & Chitin Relief on Upper Body
    bm_s = bmesh.new()
    bm_s.from_mesh(body_obj.data)
    bm_s.normal_update()
    for v in bm_s.verts:
        p = v.co
        n = v.normal
        muscle_rib = noise.noise(Vector((p.x * 1.5, p.y * 1.5, p.z * 2.4))) * 0.028
        chitin_grit = noise.noise(p * 4.5) * 0.012
        v.co = p + n * (muscle_rib + chitin_grit)
    bmesh.ops.recalc_face_normals(bm_s, faces=bm_s.faces)
    bm_s.to_mesh(body_obj.data)
    bm_s.free()

    # Decimate remeshed upper body <= 9,200 tris so total with 6 sleek tentacles stays ~12.7k (< 20k limit)
    cur_tris = sum(max(1, len(p.vertices) - 2) for p in body_obj.data.polygons)
    if cur_tris > 9200:
        dec = body_obj.modifiers.new("BudgetDecimate", "DECIMATE")
        dec.ratio = max(0.10, 9000.0 / float(cur_tris))
        bpy.ops.object.modifier_apply(modifier=dec.name)

    # Assign UVs, Materials & KDTree Skinning to remeshed upper body, then append 6 sleek post-remesh spiral tentacles!
    bmap = {b.name: i for i, b in enumerate(arm_obj.data.bones)}
    bone_segs: Dict[str, Tuple[Vector, Vector]] = {
        b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm_obj.data.bones
    }

    kd = kdtree.KDTree(len(kd_samples))
    for i, (pt, _) in enumerate(kd_samples):
        kd.insert(pt, i)
    kd.balance()

    bm_fin = bmesh.new()
    bm_fin.from_mesh(body_obj.data)
    bmesh.ops.recalc_face_normals(bm_fin, faces=bm_fin.faces)
    dform = bm_fin.verts.layers.deform.verify()
    uv_lay = bm_fin.loops.layers.uv.verify()
    uv_s = 0.28

    # Skin remeshed upper-body vertices cleanly without cross-limb bleed
    for v in bm_fin.verts:
        p = v.co
        hits = kd.find_n(p, 4)
        allowed_regs = {kd_samples[idx][1] for _, idx, _ in hits}
        cand_bones: List[str] = []
        for reg in allowed_regs:
            cand_bones.extend(region_bones[reg])
        scored: List[Tuple[int, float]] = []
        for bn in cand_bones:
            bh, bt = bone_segs[bn]
            d = _seg_distance(p, bh, bt)
            w = 1.0 / ((d + 0.07) ** 3.2)
            scored.append((bmap[bn], w))
        scored.sort(key=lambda it: it[1], reverse=True)
        top4 = scored[:4]
        tot = sum(w for _, w in top4) or 1.0
        for gi, w in top4:
            v[dform][gi] = w / tot

    # Triplanar UVs on remeshed upper body (material indices assigned AFTER materials.append on final Mesh!)
    for face in bm_fin.faces:
        fn = face.normal

        ax, ay, az = abs(fn.x), abs(fn.y), abs(fn.z)
        for lp in face.loops:
            co = lp.vert.co
            if az >= ax and az >= ay:
                lp[uv_lay].uv = (co.x * uv_s, co.y * uv_s)
            elif ax >= ay and ax >= az:
                lp[uv_lay].uv = (co.y * uv_s, co.z * uv_s)
            else:
                lp[uv_lay].uv = (co.x * uv_s, co.z * uv_s)

    # Append 6 Post-Remesh 24-Station Sleek Fluted Spiral Constrictor Tentacles (never melted together!)
    g_pelvis = bmap["pelvis"]
    tent_radii_ctrl = [0.29, 0.24, 0.19, 0.14, 0.09, 0.045, 0.016]
    num_st = 24
    radial_segs = 12

    for tid, ang_deg in enumerate(TENT_ANGLES_DEG):
        cpts = tentacle_curve_points(ang_deg)
        rad = math.radians(ang_deg)
        dir_xy = Vector((math.sin(rad), -math.cos(rad), 0.0))
        perp_xy = Vector((math.cos(rad), math.sin(rad), 0.0))
        c_sign = 1.0 if ang_deg >= 0.0 else -1.0
        p6 = dir_xy * 1.44 + perp_xy * (-0.04 * c_sign) + Vector((0.0, 0.0, 1.12))
        ctrl = cpts + [p6]

        pts_t: List[Vector] = []
        rads_t: List[float] = []
        ws_t: List[Dict[int, float]] = []
        for idx in range(num_st):
            u = idx / float(num_st - 1)
            pts_t.append(_eval_catmull_rom(ctrl, u))
            s_c = u * (len(tent_radii_ctrl) - 1)
            kr = min(len(tent_radii_ctrl) - 2, int(s_c))
            fr = s_c - kr
            rads_t.append(tent_radii_ctrl[kr] * (1.0 - fr) + tent_radii_ctrl[kr + 1] * fr)

            s_b = u * 6.0
            w_d: Dict[int, float] = {}
            if s_b >= 4.95:
                w_d[bmap[f"tent_{tid}_5"]] = 1.0
            else:
                if s_b < 0.55:
                    pw = max(0.0, (1.0 - s_b / 0.55) ** 1.3) * 0.68
                    if pw > 0.01:
                        w_d[g_pelvis] = pw
                raw_b: List[Tuple[int, float]] = []
                for k in range(5):
                    dist = abs(s_b - (k + 0.5))
                    val = max(0.0, 1.0 - dist * 0.85) ** 1.5
                    if val > 0.01:
                        raw_b.append((bmap[f"tent_{tid}_{k + 1}"], val))
                if not raw_b:
                    raw_b = [(bmap[f"tent_{tid}_{min(5, max(1, int(s_b) + 1))}"], 1.0)]
                rem_w = max(0.05, 1.0 - sum(w_d.values()))
                sum_raw = sum(v for _, v in raw_b) or 1.0
                for gi, val in raw_b:
                    w_d[gi] = (val / sum_raw) * rem_w
            ws_t.append(w_d)

        frames_t = _parallel_frames(pts_t)
        rings_t: List[List[bmesh.types.BMVert]] = []
        for idx in range(num_st):
            u = idx / float(num_st - 1)
            c_pt = pts_t[idx]
            r_b = rads_t[idx]
            _, rv, uv_ax = frames_t[idx]
            w_d = ws_t[idx]
            ring: List[bmesh.types.BMVert] = []
            for s in range(radial_segs):
                th = (2.0 * math.pi * s) / radial_segs
                # Longitudinal muscle fluting + transverse chitinous constrictor rings
                flute = 1.0 + 0.06 * math.cos(th * 6.0) + 0.055 * math.sin(u * 30.0 * math.pi) * (1.0 - 0.45 * u)
                pos = c_pt + (rv * math.cos(th) + uv_ax * math.sin(th)) * (r_b * flute)
                v = bm_fin.verts.new(pos)
                for gi, wv in w_d.items():
                    v[dform][gi] = wv
                ring.append(v)
            rings_t.append(ring)

        tent_faces: List[bmesh.types.BMFace] = []
        for i in range(num_st - 1):
            r0, r1 = rings_t[i], rings_t[i + 1]
            u0, u1 = i / float(num_st - 1), (i + 1) / float(num_st - 1)
            for j in range(radial_segs):
                jn = (j + 1) % radial_segs
                f = bm_fin.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
                f.material_index = 0
                f.loops[0][uv_lay].uv = (j / radial_segs, u0 * 3.0)
                f.loops[1][uv_lay].uv = ((j + 1) / radial_segs, u0 * 3.0)
                f.loops[2][uv_lay].uv = ((j + 1) / radial_segs, u1 * 3.0)
                f.loops[3][uv_lay].uv = (j / radial_segs, u1 * 3.0)
                tent_faces.append(f)

        v0 = bm_fin.verts.new(pts_t[0] - frames_t[0][0] * 0.08)
        v1 = bm_fin.verts.new(pts_t[-1] + frames_t[-1][0] * 0.03)
        for gi, wv in ws_t[0].items():
            v0[dform][gi] = wv
        for gi, wv in ws_t[-1].items():
            v1[dform][gi] = wv
        for j in range(radial_segs):
            jn = (j + 1) % radial_segs
            f0 = bm_fin.faces.new((v0, rings_t[0][jn], rings_t[0][j]))
            f0.material_index = 0
            f1 = bm_fin.faces.new((v1, rings_t[-1][j], rings_t[-1][jn]))
            f1.material_index = 0

    bmesh.ops.recalc_face_normals(bm_fin, faces=bm_fin.faces)
    bm_fin.to_mesh(body_obj.data)
    bm_fin.free()

    body_obj.data.materials.clear()
    body_obj.data.materials.append(mats["Hide"])          # 0
    body_obj.data.materials.append(mats["Carapace"])      # 1
    body_obj.data.materials.append(mats["FurnaceOuter"])  # 2 (deep volcanic red-orange chest core)
    body_obj.data.materials.append(mats["FurnaceHeart"])  # 3 (blazing molten amber heart)

    for poly in body_obj.data.polygons:
        c = poly.center
        fn = poly.normal
        if abs(c.x) < 0.18 and c.y < -0.05 and 3.06 < c.z < 4.42 and fn.y < -0.10:
            poly.material_index = 3  # FurnaceHeart
        elif abs(c.x) < 0.38 and c.y < -0.04 and 2.98 < c.z < 4.48 and fn.y < -0.10:
            poly.material_index = 2  # FurnaceOuter
        elif (c.z > 4.22 and abs(c.x) < 0.98) or (c.y > 0.20 and 2.65 < c.z < 4.65):
            poly.material_index = 1  # Carapace
        else:
            poly.material_index = 0  # Hide

    if len(body_obj.data.polygons) > 0:
        body_obj.data.polygons.foreach_set("use_smooth", [True] * len(body_obj.data.polygons))

    for b in arm_obj.data.bones:
        body_obj.vertex_groups.new(name=b.name)

    arm_mod = body_obj.modifiers.new("Armature", "ARMATURE")
    arm_mod.object = arm_obj
    arm_mod.use_vertex_groups = True
    bpy.ops.object.select_all(action="DESELECT")

    final_tris = sum(max(1, len(p.vertices) - 2) for p in body_obj.data.polygons)
    return body_obj, final_tris


# ---------------------------------------------------------------------------
# 2. Exposed Ribcage, Bronze Shackles, Eclipse Head Core & 3 Stage Overlays
# ---------------------------------------------------------------------------

def _new_skinned_mesh(
    name: str,
    bm: bmesh.types.BMesh,
    mats_list: Sequence[bpy.types.Material],
    arm_obj: bpy.types.Object,
    root_col: bpy.types.Collection,
    smooth: bool = True,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv_lay = bm.loops.layers.uv.verify()
    uv_s = 0.35
    for f in bm.faces:
        fn = f.normal
        ax, ay, az = abs(fn.x), abs(fn.y), abs(fn.z)
        for lp in f.loops:
            co = lp.vert.co
            lp[uv_lay].uv = (co.x * uv_s, co.y * uv_s) if az >= ax and az >= ay else ((co.y * uv_s, co.z * uv_s) if ax >= ay and ax >= az else (co.x * uv_s, co.z * uv_s))

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats_list:
        mesh.materials.append(m)
    if smooth and len(mesh.polygons) > 0:
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))

    obj = bpy.data.objects.new(name, mesh)
    root_col.objects.link(obj)
    obj.parent = arm_obj
    for b in arm_obj.data.bones:
        obj.vertex_groups.new(name=b.name)
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mod.use_vertex_groups = True
    return obj


def _add_weighted_box(bm: bmesh.types.BMesh, dform: bmesh.types.BMLayerItem, g_idx: int, xf: Matrix, size: Vector, mat_idx: int) -> None:
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=xf @ Matrix.Diagonal((size.x, size.y, size.z, 1.0)))
    for v in ret["verts"]:
        v[dform][g_idx] = 1.0
        for f in v.link_faces:
            f.material_index = mat_idx


def _add_weighted_torus(
    bm: bmesh.types.BMesh,
    dform: bmesh.types.BMLayerItem,
    g_idx: int,
    center: Vector,
    normal_axis: Vector,
    major_r: float,
    minor_r: float,
    mat_idx: int,
    segs_u: int = 32,
    segs_v: int = 12,
    irregular_flare: float = 0.0,
) -> None:
    ax = normal_axis.normalized()
    ref = Vector((1.0, 0.0, 0.0)) if abs(ax.x) < 0.85 else Vector((0.0, 0.0, 1.0))
    u = ax.cross(ref).normalized()
    v = ax.cross(u).normalized()

    rings: List[List[bmesh.types.BMVert]] = []
    for i in range(segs_u):
        th = (2.0 * math.pi * i) / segs_u
        rad_dir = u * math.cos(th) + v * math.sin(th)
        flare = 1.0 + irregular_flare * (0.5 + 0.5 * math.sin(th * 7.0) * math.cos(th * 3.0))
        rc_pt = center + rad_dir * (major_r * flare)
        ring = []
        for j in range(segs_v):
            ph = (2.0 * math.pi * j) / segs_v
            pt = rc_pt + rad_dir * (math.cos(ph) * minor_r * flare) + ax * (math.sin(ph) * minor_r)
            vert = bm.verts.new(pt)
            vert[dform][g_idx] = 1.0
            ring.append(vert)
        rings.append(ring)

    for i in range(segs_u):
        inext = (i + 1) % segs_u
        for j in range(segs_v):
            jnext = (j + 1) % segs_v
            f = bm.faces.new((rings[i][j], rings[inext][j], rings[inext][jnext], rings[i][jnext]))
            f.material_index = mat_idx


def _add_shackle_and_chain(
    bm: bmesh.types.BMesh,
    dform: bmesh.types.BMLayerItem,
    g_idx: int,
    wrist_pos: Vector,
    arm_dir: Vector,
    radius: float,
    num_links: int,
    mat_bronze: int,
    minor_r: float = 0.038,
) -> None:
    _add_weighted_torus(bm, dform, g_idx, wrist_pos, arm_dir, major_r=radius, minor_r=minor_r, mat_idx=mat_bronze, segs_u=18, segs_v=8)
    for k in range(num_links):
        l_pos = wrist_pos + Vector((0.0, 0.0, -0.08 - k * 0.075))
        rot_axis = Vector((1.0, 0.0, 0.0)) if k % 2 == 0 else Vector((0.0, 1.0, 0.0))
        _add_weighted_torus(bm, dform, g_idx, l_pos, rot_axis, major_r=0.046, minor_r=0.013, mat_idx=mat_bronze, segs_u=12, segs_v=6)


def _add_finger_claw(
    bm: bmesh.types.BMesh,
    dform: bmesh.types.BMLayerItem,
    g_idx: int,
    base: Vector,
    fwd: Vector,
    curl_down: Vector,
    length: float,
    r0: float,
    mat_root: int,
    mat_tip: int,
) -> None:
    # Dark obsidian-chitin knuckle/finger base tapering seamlessly into an ivory-bone scythe talon
    pts_root = [
        (base, r0, r0 * 1.15),
        (base + fwd * (length * 0.38) + curl_down * (length * 0.14), r0 * 0.68, r0 * 0.80),
    ]
    pts_tip = [
        (base + fwd * (length * 0.36) + curl_down * (length * 0.13), r0 * 0.66, r0 * 0.78),
        (base + fwd * (length * 0.72) + curl_down * (length * 0.44), r0 * 0.34, r0 * 0.42),
        (base + fwd * (length * 0.94) + curl_down * (length * 0.84), 0.010, 0.012),
    ]
    add_closed_loft(bm, pts_root, radial_segs=7, mat_idx=mat_root, dform_lay=dform, weights_per_station=[{g_idx: 1.0}] * 2, dorsal_pinch=0.22)
    add_closed_loft(bm, pts_tip, radial_segs=7, mat_idx=mat_tip, dform_lay=dform, weights_per_station=[{g_idx: 1.0}] * 3, dorsal_pinch=0.28)


def build_ribcage_and_shackles(
    arm_obj: bpy.types.Object,
    root_col: bpy.types.Collection,
    mats: Dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Shared Core Anatomy Overlay: Void Singularity Sphere + Notched Sternum + 7 Rib Pairs + Gothic V-Skirt + Snug Bronze Shackles."""
    bm = bmesh.new()
    dform = bm.verts.layers.deform.verify()
    bmap = {b.name: i for i, b in enumerate(arm_obj.data.bones)}

    # 1. Enlarged Pitch-Black Eclipse Singularity Sphere + Dark Sculpted Obsidian Outer Collar ('head')
    g_hd = bmap["head"]
    ec = Vector((0.0, -0.22, 5.14))
    ret_sp = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.48, matrix=Matrix.Translation(ec))
    for v in ret_sp["verts"]:
        v[dform][g_hd] = 1.0
        for f in v.link_faces:
            f.material_index = 3  # VoidBlack
    _add_weighted_torus(bm, dform, g_hd, ec + Vector((0.0, 0.08, 0.0)), Vector((0.0, 1.0, 0.0)), 0.56, 0.095, mat_idx=0, segs_u=32, segs_v=10)

    # 2. High-Contrast Central Notched Sternum Bar + 7 Pairs of Arched Dark Obsidian-Bone Ribs Over the Fire!
    sternum_pts = [
        (Vector((0.0, -0.36, 3.04)), 0.036, 0.032),
        (Vector((0.0, -0.42, 3.40)), 0.048, 0.038),
        (Vector((0.0, -0.47, 3.76)), 0.056, 0.042),
        (Vector((0.0, -0.50, 4.10)), 0.064, 0.046),
        (Vector((0.0, -0.44, 4.42)), 0.072, 0.046),
    ]
    sternum_ws = [
        {bmap["spine_1"]: 1.0},
        {bmap["spine_2"]: 1.0},
        {bmap["spine_2"]: 0.7, bmap["spine_3"]: 0.3},
        {bmap["spine_3"]: 1.0},
        {bmap["spine_3"]: 1.0},
    ]
    add_closed_loft(bm, sternum_pts, radial_segs=8, mat_idx=4, dform_lay=dform, weights_per_station=sternum_ws, dorsal_pinch=0.32)

    rib_specs = [
        (4.36, 0.44, 0.48, "spine_3"),
        (4.16, 0.45, 0.52, "spine_3"),
        (3.96, 0.42, 0.51, "spine_3"),
        (3.76, 0.37, 0.49, "spine_2"),
        (3.56, 0.31, 0.46, "spine_2"),
        (3.36, 0.25, 0.43, "spine_2"),
        (3.14, 0.19, 0.39, "spine_1"),
    ]
    for z_rib, hw, fwd_y, bname in rib_specs:
        gi = bmap[bname]
        for sgn in (1.0, -1.0):
            rib_pts = [
                (Vector((sgn * hw * 0.96, 0.04, z_rib + 0.14)), 0.046, 0.038),
                (Vector((sgn * hw * 0.88, -fwd_y * 0.56, z_rib + 0.04)), 0.042, 0.034),
                (Vector((sgn * hw * 0.46, -fwd_y * 0.98, z_rib - 0.04)), 0.038, 0.030),
                (Vector((sgn * 0.04, -fwd_y * 0.96, z_rib - 0.08)), 0.036, 0.028),
            ]
            add_closed_loft(bm, rib_pts, radial_segs=7, mat_idx=4, dform_lay=dform, weights_per_station=[{gi: 1.0}] * 4, dorsal_pinch=0.25)

    # Segmented Ossified Dorsal Spine Scutes down neck -> pelvis
    for z_sc, bname in ((4.75, "neck"), (4.42, "spine_3"), (4.05, "spine_3"), (3.65, "spine_2"), (3.20, "spine_1"), (2.68, "pelvis")):
        gi = bmap[bname]
        _add_closed_horn(
            bm, dform, gi,
            base=Vector((0.0, 0.26, z_sc)),
            points=[Vector((0.0, 0.40, z_sc + 0.08)), Vector((0.0, 0.54, z_sc + 0.22))],
            radii=[0.10, 0.068, 0.014],
            mat_idx=4,
        )

    # 3. Sharp Gothic V-Pointed Segmented Chitin Pelvic Skirt ('pelvis')
    g_pv = bmap["pelvis"]
    # Central front downward V-tasset (Z = 2.68 -> 1.72)
    add_closed_loft(
        bm,
        [
            (Vector((0.0, -0.34, 2.68)), 0.24, 0.08),
            (Vector((0.0, -0.44, 2.38)), 0.22, 0.075),
            (Vector((0.0, -0.48, 2.04)), 0.12, 0.055),
            (Vector((0.0, -0.52, 1.72)), 0.018, 0.024),
        ],
        radial_segs=6, mat_idx=4, dform_lay=dform, weights_per_station=[{g_pv: 1.0}] * 4, dorsal_pinch=0.55,
    )
    # Rear tail chitin plate (Z = 2.68 -> 1.76)
    add_closed_loft(
        bm,
        [
            (Vector((0.0, 0.34, 2.68)), 0.22, 0.08),
            (Vector((0.0, 0.44, 2.25)), 0.16, 0.065),
            (Vector((0.0, 0.52, 1.76)), 0.02, 0.025),
        ],
        radial_segs=6, mat_idx=0, dform_lay=dform, weights_per_station=[{g_pv: 1.0}] * 3, dorsal_pinch=0.50,
    )
    # 3 pairs of overlapping serrated lateral hip armor plates (Z = 2.70 -> 1.95)
    for sgn in (1.0, -1.0):
        for ang_h, z_top, z_tip, rad_out in ((40.0, 2.70, 1.95, 0.62), (76.0, 2.66, 1.98, 0.68), (116.0, 2.62, 2.02, 0.62)):
            rh = math.radians(ang_h)
            dxy = Vector((sgn * math.sin(rh), -math.cos(rh), 0.0))
            add_closed_loft(
                bm,
                [
                    (dxy * 0.34 + Vector((0.0, 0.0, z_top)), 0.16, 0.065),
                    (dxy * 0.50 + Vector((0.0, 0.0, (z_top + z_tip) * 0.5)), 0.14, 0.055),
                    (dxy * rad_out + Vector((0.0, 0.0, z_tip)), 0.02, 0.025),
                ],
                radial_segs=6, mat_idx=4, dform_lay=dform, weights_per_station=[{g_pv: 1.0}] * 3, dorsal_pinch=0.45,
            )

    # 4. Snug Tarnished Bronze Containment Shackles & Fine Hanging Chains on all 4 Wrists
    for side, sgn in (("l", 1.0), ("r", -1.0)):
        _add_shackle_and_chain(bm, dform, bmap[f"arm_up_lo_{side}"], Vector((sgn * 2.24, -0.24, 3.84)), Vector((sgn, -0.2, -0.3)), 0.175, 5, mat_bronze=2, minor_r=0.038)
        _add_shackle_and_chain(bm, dform, bmap[f"arm_lo_lo_{side}"], Vector((sgn * 1.32, -0.40, 2.64)), Vector((sgn * 0.5, -0.3, -0.8)), 0.145, 4, mat_bronze=2, minor_r=0.034)

    return _new_skinned_mesh(
        "Monster_RibcageAndShackles_Skinned",
        bm,
        [mats["Carapace"], mats["Bone"], mats["Bronze"], mats["VoidBlack"], mats["DarkRibChitin"]],
        arm_obj,
        root_col,
    )


def _add_closed_horn(
    bm: bmesh.types.BMesh,
    dform: bmesh.types.BMLayerItem,
    weights: Dict[int, float] | int,
    base: Vector,
    points: Sequence[Vector],
    radii: Sequence[float],
    mat_idx: int,
    radial_segs: int = 7,
) -> None:
    all_pts = [base] + list(points)
    ws = [{weights: 1.0} if isinstance(weights, int) else weights] * len(all_pts)
    stations = [(p, r, r * 1.12) for p, r in zip(all_pts, radii)]
    add_closed_loft(bm, stations, radial_segs=radial_segs, mat_idx=mat_idx, dform_lay=dform, weights_per_station=ws, dorsal_pinch=0.25)


def build_stage_overlays(
    arm_obj: bpy.types.Object,
    root_col: bpy.types.Collection,
    mats: Dict[str, bpy.types.Material],
) -> Dict[str, bpy.types.Object]:
    """Build Stage 1 ('Predador Alfa'), Stage 2 ('Arauto Desperto'), and Stage 3 ('Deus do Eclipse Abissal') overlays."""
    bmap = {b.name: i for i, b in enumerate(arm_obj.data.bones)}
    ec = Vector((0.0, -0.22, 5.14))

    def build_crown_halo(
        stage_tag: str,
        stage_mode: str,
        corona_mat: bpy.types.Material,
        rim_mat: bpy.types.Material,
        corona_r: float,
        corona_minor: float,
        flare_val: float,
        claw_len_mul: float,
        skirt_blades: int,
        chain_links_extra: int,
    ) -> bpy.types.Object:
        bm = bmesh.new()
        dform = bm.verts.layers.deform.verify()
        g_hd = bmap["head"]

        # 1. Dual-Layer Solar Eclipse Corona (sleek circular outer corona + razor incandescent inner rim + throat flame tear)
        _add_weighted_torus(
            bm, dform, g_hd,
            center=ec, normal_axis=Vector((0.0, 1.0, 0.0)),
            major_r=corona_r, minor_r=corona_minor, mat_idx=2, segs_u=48, segs_v=12, irregular_flare=flare_val,
        )
        _add_weighted_torus(
            bm, dform, g_hd,
            center=ec - Vector((0.0, 0.022, 0.0)), normal_axis=Vector((0.0, 1.0, 0.0)),
            major_r=0.495, minor_r=0.024, mat_idx=3, segs_u=48, segs_v=10, irregular_flare=flare_val * 0.35,
        )
        # Downward-dripping Solar Flame Tear blazing down throat into sternum (Z = 4.68 -> 4.32)
        tear_pts = [
            (Vector((0.0, -0.25, 4.68)), 0.072, 0.055),
            (Vector((0.0, -0.28, 4.55)), 0.054, 0.044),
            (Vector((0.0, -0.32, 4.44)), 0.034, 0.028),
            (Vector((0.0, -0.34, 4.32)), 0.010, 0.010),
        ]
        add_closed_loft(bm, tear_pts, radial_segs=8, mat_idx=3, dform_lay=dform, weights_per_station=[{g_hd: 1.0}] * 4, dorsal_pinch=0.3)

        # 2. 14-18 Station Curved Spline Crown:
        #    Stage 1 -> 12 thick ribbed crescent horns + 2 inward lower mandible tusks
        #    Stage 2 -> 16 medium sinuous S-wave tendrils
        #    Stage 3 -> 24 colossal multi-wave S-curved whip-tendrils
        if stage_mode == "S1":
            pairs_count = 7  # 6 pairs curved crescent horns + 1 pair lower inward mandible tusks
            num_st = 14
        elif stage_mode == "S2":
            pairs_count = 8
            num_st = 16
        else:
            pairs_count = 12
            num_st = 18

        for pair_idx in range(pairs_count):
            for sgn in (1.0, -1.0):
                frac_ang = pair_idx / max(1, pairs_count - 1) if pairs_count > 1 else 0.0
                if stage_mode == "S1":
                    is_mandible = pair_idx == (pairs_count - 1)
                    ang_deg = 142.0 if is_mandible else (28.0 + 84.0 * (pair_idx / max(1, pairs_count - 2)))
                elif stage_mode == "S2":
                    is_mandible = False
                    ang_deg = 14.0 + 118.0 * frac_ang
                else:
                    is_mandible = False
                    ang_deg = 10.0 + 136.0 * frac_ang

                rad = math.radians(ang_deg)
                crown_side_offset = 0 if sgn > 0 else 4
                best_sub = min(3, int(frac_ang * 3.99))
                g_c1 = bmap[f"crown_{crown_side_offset + best_sub}_1"]
                g_c2 = bmap[f"crown_{crown_side_offset + best_sub}_2"]

                y_wobble = 0.08 if (pair_idx % 2 == 0) else 0.18
                dir_v = Vector((sgn * math.sin(rad), y_wobble, math.cos(rad) * 0.94)).normalized()
                tangent_v = Vector((0.0, -1.0, 0.0)).cross(dir_v).normalized()

                stations: List[Tuple[Vector, float, float]] = []
                ws: List[Dict[int, float]] = []
                p_start = ec + dir_v * (corona_r + 0.01)

                if stage_mode == "S1":
                    L = 0.72 if is_mandible else (1.18 + 0.36 * math.sin((pair_idx / 5.0) * math.pi))
                    r0 = 0.085 if is_mandible else 0.125
                    out_vec = Vector((sgn * (0.68 + 0.32 * math.sin(rad)), 0.14, math.cos(rad) * 0.42)).normalized()
                    for si in range(num_st):
                        t = si / float(num_st - 1)
                        if is_mandible:
                            pos = p_start + dir_v * (L * t * 0.72) + Vector((-sgn * 0.28 * (t ** 1.7), -0.06 * math.sin(t * math.pi), -0.32 * (t ** 1.3)))
                        else:
                            # Bold Demon/Beetle Crescent Horns sweeping out sideways first, then curving steeply UP and inward!
                            arch = Vector((sgn * 0.56 * math.sin(t * math.pi * 0.72), 0.18 * (t ** 1.4), (t ** 1.80) * 1.16 - t * 0.14))
                            inward = Vector((-sgn * 0.44 * (t ** 2.6), 0.0, 0.0))
                            pos = p_start + out_vec * (L * t * 0.65) + arch + inward
                        rib_bump = 1.0 + 0.08 * math.sin(t * 26.0)
                        r_st = max(0.012, r0 * (1.0 - 0.88 * (t ** 1.15)) * rib_bump)
                        stations.append((pos, r_st, r_st * 1.12))
                else:
                    is_s3 = stage_mode == "S3"
                    L = (2.65 + 0.45 * math.sin(frac_ang * math.pi)) if is_s3 else (1.75 + 0.32 * math.sin(frac_ang * math.pi))
                    r0 = 0.082 if is_s3 else 0.092
                    wave_cycles = 2.4 if is_s3 else 1.9
                    wave_amp = 0.38 if is_s3 else 0.28
                    phase = pair_idx * 0.85
                    for si in range(num_st):
                        t = si / float(num_st - 1)
                        s_wave = math.sin(t * wave_cycles * math.pi + phase) * wave_amp * (t ** 0.7)
                        depth_arc = 0.22 * math.sin(t * math.pi * 1.3 + phase * 0.5) * (t ** 0.8)
                        lift_outer = (0.28 if ang_deg < 85.0 else -0.22) * (t ** 1.6)
                        pos = p_start + dir_v * (L * t) + tangent_v * s_wave + Vector((0.0, depth_arc, lift_outer))
                        r_st = max(0.010, r0 * (1.0 - 0.86 * (t ** 1.10)))
                        stations.append((pos, r_st, r_st * 1.12))

                for si in range(num_st):
                    t = si / float(num_st - 1)
                    if t <= 0.25:
                        k = t / 0.25
                        ws.append({g_hd: 1.0 - k * 0.75, g_c1: k * 0.75})
                    elif t <= 0.72:
                        k = (t - 0.25) / 0.47
                        ws.append({g_c1: 1.0 - k * 0.85, g_c2: k * 0.85})
                    else:
                        ws.append({g_c2: 1.0})

                mat_crown = 5 if (pair_idx % 2 == 0 or stage_mode == "S1") else 0
                add_closed_loft(bm, stations, radial_segs=7, mat_idx=mat_crown, dform_lay=dform, weights_per_station=ws, dorsal_pinch=0.28)

        # 3. Curved Carapace Shoulder Pauldrons (Armored Shells — NO vertical picket-fence spikes!) + 5-Claw Predatory Hands
        for side, sgn in (("l", 1.0), ("r", -1.0)):
            sh_g = bmap[f"arm_up_sh_{side}"]
            if stage_mode == "S1":
                # Low swept-back obsidian deltoid armor ridge hugging the massive shoulders
                p_pts = [
                    (Vector((sgn * 0.54, -0.02, 4.56)), 0.16, 0.10),
                    (Vector((sgn * 0.86, 0.02, 4.62)), 0.18, 0.11),
                    (Vector((sgn * 1.16, 0.14, 4.44)), 0.09, 0.06),
                    (Vector((sgn * 1.28, 0.22, 4.30)), 0.02, 0.02),
                ]
                add_closed_loft(bm, p_pts, radial_segs=8, mat_idx=0, dform_lay=dform, weights_per_station=[{sh_g: 1.0}] * 4, dorsal_pinch=0.45)
            elif stage_mode == "S2":
                # Broad layered outward-and-downward curving beetle/knight carapace shoulder plates
                for layer_z, rx_w, out_x in ((0.0, 0.24, 1.38), (-0.12, 0.20, 1.52)):
                    p_pts = [
                        (Vector((sgn * 0.46, -0.04, 4.62 + layer_z)), rx_w * 0.85, 0.10),
                        (Vector((sgn * 0.92, -0.02, 4.72 + layer_z)), rx_w * 1.15, 0.11),
                        (Vector((sgn * out_x, 0.08, 4.48 + layer_z)), rx_w * 0.72, 0.075),
                        (Vector((sgn * (out_x + 0.16), 0.18, 4.24 + layer_z)), 0.025, 0.025),
                    ]
                    add_closed_loft(bm, p_pts, radial_segs=8, mat_idx=0, dform_lay=dform, weights_per_station=[{sh_g: 1.0}] * 4, dorsal_pinch=0.50)
            else:
                # Stage 3: Broad swept regal winged carapace pauldrons + high trapezius collar blades
                p_main = [
                    (Vector((sgn * 0.48, -0.04, 4.64)), 0.26, 0.11),
                    (Vector((sgn * 0.98, 0.00, 4.76)), 0.30, 0.12),
                    (Vector((sgn * 1.48, 0.10, 4.86)), 0.18, 0.08),
                    (Vector((sgn * 1.72, 0.22, 4.68)), 0.03, 0.03),
                ]
                add_closed_loft(bm, p_main, radial_segs=8, mat_idx=0, dform_lay=dform, weights_per_station=[{sh_g: 1.0}] * 4, dorsal_pinch=0.52)
                p_sub = [
                    (Vector((sgn * 0.72, -0.02, 4.48)), 0.22, 0.09),
                    (Vector((sgn * 1.18, 0.06, 4.44)), 0.18, 0.08),
                    (Vector((sgn * 1.56, 0.18, 4.20)), 0.025, 0.025),
                ]
                add_closed_loft(bm, p_sub, radial_segs=8, mat_idx=5, dform_lay=dform, weights_per_station=[{sh_g: 1.0}] * 3, dorsal_pinch=0.45)

            # 5-Claw Predatory Upper Hand (4 curved finger scythes + 1 inner opposable thumb)
            uh_g = bmap[f"arm_up_hd_{side}"]
            uh_base = Vector((sgn * 2.74, -0.36, 3.60))
            uh_fwd = Vector((sgn * 0.92, -0.22, -0.32)).normalized()
            uh_curl = Vector((-sgn * 0.15, -0.25, -0.95)).normalized()
            for y_f, z_f, c_len in ((-0.11, 0.05, 0.56), (-0.04, 0.03, 0.78), (0.04, 0.01, 0.72), (0.11, -0.02, 0.52)):
                _add_finger_claw(
                    bm, dform, uh_g,
                    base=uh_base + Vector((0, y_f, z_f)),
                    fwd=uh_fwd, curl_down=uh_curl,
                    length=c_len * claw_len_mul, r0=0.045, mat_root=5, mat_tip=1,
                )
            # Opposable thumb claw
            _add_finger_claw(
                bm, dform, uh_g,
                base=uh_base + Vector((-sgn * 0.08, -0.11, -0.08)),
                fwd=Vector((sgn * 0.45, -0.45, -0.78)).normalized(),
                curl_down=Vector((-sgn * 0.60, 0.10, -0.75)).normalized(),
                length=0.46 * claw_len_mul, r0=0.042, mat_root=5, mat_tip=1,
            )

            # 5-Claw Predatory Lower Hand (4 curved finger scythes + 1 inner thumb)
            lh_g = bmap[f"arm_lo_hd_{side}"]
            lh_base = Vector((sgn * 1.56, -0.58, 2.20))
            lh_fwd = Vector((sgn * 0.42, -0.52, -0.74)).normalized()
            lh_curl = Vector((-sgn * 0.35, 0.45, -0.72)).normalized()
            for x_f, y_f, c_len in ((-0.08, -0.06, 0.42), (-0.02, -0.02, 0.60), (0.04, 0.02, 0.56), (0.09, 0.06, 0.40)):
                _add_finger_claw(
                    bm, dform, lh_g,
                    base=lh_base + Vector((x_f, y_f, 0.0)),
                    fwd=lh_fwd, curl_down=lh_curl,
                    length=c_len * claw_len_mul, r0=0.038, mat_root=5, mat_tip=1,
                )
            _add_finger_claw(
                bm, dform, lh_g,
                base=lh_base + Vector((-sgn * 0.09, -0.06, 0.06)),
                fwd=Vector((-sgn * 0.30, -0.55, -0.75)).normalized(),
                curl_down=Vector((sgn * 0.25, 0.45, -0.82)).normalized(),
                length=0.38 * claw_len_mul, r0=0.036, mat_root=5, mat_tip=1,
            )

            if chain_links_extra > 0:
                _add_shackle_and_chain(bm, dform, bmap[f"arm_up_lo_{side}"], Vector((sgn * 2.24, -0.24, 3.84)), Vector((sgn, -0.2, -0.3)), 0.178, chain_links_extra, mat_bronze=4, minor_r=0.036)

        # 4. Extra Stage 2/3 Serrated Skirt Blades flaring downward around Pelvis
        if skirt_blades > 0:
            pv_g = bmap["pelvis"]
            for i in range(skirt_blades):
                ang = (2.0 * math.pi * i) / skirt_blades
                dir_xy = Vector((math.sin(ang), -math.cos(ang), 0.0))
                b_pt = dir_xy * 0.52 + Vector((0.0, 0.0, 2.48))
                _add_closed_horn(
                    bm, dform, pv_g,
                    base=b_pt,
                    points=[dir_xy * 0.68 + Vector((0, 0, 2.04)), dir_xy * 0.78 + Vector((0, 0, 1.56))],
                    radii=[0.095, 0.055, 0.012],
                    mat_idx=5,
                )

        return _new_skinned_mesh(
            f"Monster_{stage_tag}_Skinned",
            bm,
            [mats["Carapace"], mats["Bone"], corona_mat, rim_mat, mats["Bronze"], mats["DarkRibChitin"]],
            arm_obj,
            root_col,
        )

    stage_objs = {
        "Stage1": build_crown_halo(
            "Stage1_Apex", "S1", mats["BloodCorona_S1"], mats["BloodRim_S1"],
            corona_r=0.53, corona_minor=0.052, flare_val=0.020,
            claw_len_mul=1.0, skirt_blades=0, chain_links_extra=0,
        ),
        "Stage2": build_crown_halo(
            "Stage2_Tyrant", "S2", mats["GoldCorona_S2"], mats["GoldRim_S2"],
            corona_r=0.56, corona_minor=0.066, flare_val=0.025,
            claw_len_mul=1.35, skirt_blades=6, chain_links_extra=7,
        ),
        "Stage3": build_crown_halo(
            "Stage3_EclipseGod", "S3", mats["SolarCorona_S3"], mats["SolarRim_S3"],
            corona_r=0.60, corona_minor=0.082, flare_val=0.035,
            claw_len_mul=1.75, skirt_blades=10, chain_links_extra=10,
        ),
    }
    return stage_objs


# ---------------------------------------------------------------------------
# 3. Synthesize All 8 Requested Animations (Blender 5.3 Slotted Actions)
# ---------------------------------------------------------------------------

def _new_action_slot(arm_obj: bpy.types.Object, name: str) -> bpy.types.Action:
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    for tr in list(arm_obj.animation_data.nla_tracks):
        arm_obj.animation_data.nla_tracks.remove(tr)
    act = bpy.data.actions.new(name=name)
    act.use_fake_user = True
    arm_obj.animation_data.action = act
    if hasattr(act, "slots"):
        slot = act.slots.new(id_type="OBJECT", name=arm_obj.name)
        arm_obj.animation_data.action_slot = slot
    return act


def _set_bone_world_rot(
    arm_obj: bpy.types.Object,
    rest_mats: Dict[str, Matrix],
    bone_name: str,
    rx_deg: float = 0.0,
    ry_deg: float = 0.0,
    rz_deg: float = 0.0,
) -> None:
    """Apply clean anatomical world-axis Euler delta rotated cleanly into Bone's own rest frame."""
    pb = arm_obj.pose.bones.get(bone_name)
    if pb is None:
        return
    r_world = Euler((math.radians(rx_deg), math.radians(ry_deg), math.radians(rz_deg)), "XYZ").to_matrix()
    m_rest = rest_mats[bone_name]
    r_local = m_rest.inverted() @ r_world @ m_rest
    pb.rotation_quaternion = r_local.to_quaternion()


def _reset_pose(arm_obj: bpy.types.Object) -> None:
    for pb in arm_obj.pose.bones:
        pb.location = Vector((0.0, 0.0, 0.0))
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.scale = Vector((1.0, 1.0, 1.0))


def _key_all(arm_obj: bpy.types.Object, frame: int) -> None:
    for pb in arm_obj.pose.bones:
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if pb.name == "pelvis":
            pb.keyframe_insert(data_path="location", frame=frame)
            pb.keyframe_insert(data_path="scale", frame=frame)


def build_all_8_animations(arm_obj: bpy.types.Object) -> List[bpy.types.Action]:
    rest_mats: Dict[str, Matrix] = {b.name: b.matrix_local.to_3x3().copy() for b in arm_obj.data.bones}
    actions: List[bpy.types.Action] = []

    def pose_tentacles(
        f_phase: float,
        stride_amp: float = 16.0,
        curl_lift: float = 0.0,
        lean_back: float = 0.0,
        spread_splay: float = 0.0,
    ) -> None:
        for tid, ang_deg in enumerate(TENT_ANGLES_DEG):
            ph = f_phase + tid * (math.pi / 3.0)
            rad = math.radians(ang_deg)
            dir_xy_x, dir_xy_y = math.sin(rad), -math.cos(rad)
            # Horizontal axis k = dir_xy x +Z = (dir_xy_y, -dir_xy_x, 0) lifts ANY radial tentacle strictly toward +Z!
            kx, ky = dir_xy_y, -dir_xy_x
            for seg in range(1, 6):
                bn = f"tent_{tid}_{seg}"
                w1 = math.sin(ph - seg * 0.65) * stride_amp * (0.40 + 0.12 * seg)
                w2 = math.cos(ph - seg * 0.55) * stride_amp * 0.48
                # Clamped positive lift factor keeps coiled tips above the floor unless airborne!
                lift = (curl_lift + spread_splay * 0.6) * (0.25 * seg) + abs(w1) * 0.25
                rx = kx * (w1 + lift) + lean_back * 0.6
                ry = ky * (w1 + lift)
                rz = w2
                _set_bone_world_rot(arm_obj, rest_mats, bn, rx_deg=rx, ry_deg=ry, rz_deg=rz)

    def pose_crown(f_phase: float, flare: float = 6.0, whip_amp: float = 10.0) -> None:
        for cid in range(8):
            sgn = 1.0 if cid < 4 else -1.0
            ph = f_phase + cid * 0.55
            for seg in (1, 2):
                bn = f"crown_{cid}_{seg}"
                w = math.sin(ph - seg * 0.8) * whip_amp * (0.6 + 0.4 * seg)
                _set_bone_world_rot(arm_obj, rest_mats, bn, rx_deg=-flare + w, ry_deg=sgn * (flare * 0.45 + w * 0.3), rz_deg=w * 0.4)

    def bake_clip(name: str, total_frames: int, step: int, eval_fn) -> bpy.types.Action:
        act = _new_action_slot(arm_obj, name)
        for fr in range(0, total_frames + 1, step):
            _reset_pose(arm_obj)
            eval_fn(fr / float(total_frames), fr)
            _key_all(arm_obj, fr)
        actions.append(act)
        return act

    # 1. Monster_Intro_Roar (84f): Dormant coil -> Tremor -> Explosive Cruciform Ascension + Screaming Eclipse Burst
    def anim_intro(u: float, _fr: int) -> None:
        if u < 0.28:
            k = u / 0.28
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, -0.55 + 0.12 * math.sin(u * 40.0)))
            for bn, deg in (("spine_1", 20), ("spine_2", 26), ("spine_3", 28), ("head", 32)):
                _set_bone_world_rot(arm_obj, rest_mats, bn, rx_deg=deg)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", rx_deg=10, ry_deg=sgn * 48, rz_deg=-sgn * 58)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rx_deg=20, ry_deg=sgn * 15, rz_deg=-sgn * 55)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rx_deg=25, ry_deg=sgn * 25, rz_deg=-sgn * 38)
            pose_tentacles(u * 6.0, stride_amp=6.0, curl_lift=10.0)
            pose_crown(u * 12.0, flare=-18.0, whip_amp=6.0)
        elif u < 0.72:
            # Explosive Cruciform Ascension! Chest proud, head forward-facing toward viewer!
            ease = math.sin(((u - 0.28) / 0.44) * math.pi * 0.5)
            vib = math.sin(u * 68.0) * 3.0
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, -0.45 + 1.05 * ease))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_1", rx_deg=-4 * ease)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-6 * ease)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=-8 * ease + vib * 0.3)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=8 * ease + vib * 0.4)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                # Arms flung WIDE OPEN cruciform upward!
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_sh_{side}", ry_deg=-sgn * 18 * ease, rz_deg=sgn * 22 * ease)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", rx_deg=-12 * ease, ry_deg=-sgn * 14 * ease, rz_deg=sgn * 18 * ease)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rx_deg=-10 * ease, rz_deg=-sgn * 12 * ease)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 10, rz_deg=sgn * 34 * ease)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_lo_{side}", rx_deg=-18 * ease, rz_deg=-sgn * 24 * ease)
            pose_tentacles(u * 10.0, stride_amp=12.0, curl_lift=8.0, spread_splay=12.0 * ease)
            pose_crown(u * 20.0, flare=28.0 * ease, whip_amp=18.0)
        else:
            # Settle into terrifying stalking hover
            settle = 1.0 - ((u - 0.72) / 0.28)
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, 0.60 * settle))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_1", rx_deg=-4 * settle)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-6 * settle + 4 * (1 - settle))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=-8 * settle + 5 * (1 - settle))
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=8 * settle - 4 * (1 - settle))
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 12 * (1 - settle), rz_deg=sgn * 18 * settle - sgn * 16 * (1 - settle))
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=-sgn * 22 * (1 - settle))
            pose_tentacles(u * 8.0, stride_amp=10.0, spread_splay=10.0 * settle)
            pose_crown(u * 10.0, flare=16.0 * settle + 6.0, whip_amp=10.0)

    bake_clip("Monster_Intro_Roar", 84, 4, anim_intro)

    # 2. Monster_Idle (60f): Heavy floating levitation + rib breathing + sinuous tentacle coil
    def anim_idle(u: float, _fr: int) -> None:
        th = u * 2.0 * math.pi
        arm_obj.pose.bones["pelvis"].location = Vector((0.0, 0.0, 0.14 * math.sin(th)))
        _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=4.0 + 3.0 * math.sin(th))
        _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=5.0 + 3.5 * math.sin(th - 0.5))
        _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-4.0 + 4.0 * math.cos(th), rz_deg=5.0 * math.sin(th * 0.5))
        for side, sgn in (("l", 1.0), ("r", -1.0)):
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * (14.0 + 5.0 * math.sin(th)), rz_deg=-sgn * (14.0 + 4.0 * math.cos(th)))
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rx_deg=12.0, rz_deg=-sgn * 26.0)
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 12.0, rz_deg=-sgn * (22.0 + 6.0 * math.sin(th)))
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_lo_{side}", rx_deg=10.0, rz_deg=-sgn * 24.0)
        pose_tentacles(th, stride_amp=12.0, curl_lift=1.0)
        pose_crown(th, flare=6.0, whip_amp=11.0)

    bake_clip("Monster_Idle", 60, 4, anim_idle)

    # 3. Monster_Walk (48f): Stalking forward stride + coordinated alternating tentacle push
    def anim_walk(u: float, _fr: int) -> None:
        th = u * 2.0 * math.pi
        arm_obj.pose.bones["pelvis"].location = Vector((0.08 * math.sin(th), 0.0, 0.22 + 0.14 * abs(math.cos(th))))
        _set_bone_world_rot(arm_obj, rest_mats, "pelvis", rx_deg=10.0, rz_deg=7.0 * math.sin(th))
        _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=8.0, rz_deg=-6.0 * math.sin(th))
        _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=6.0, rz_deg=8.0 * math.sin(th))
        _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-16.0, rz_deg=-5.0 * math.sin(th))
        for side, sgn in (("l", 1.0), ("r", -1.0)):
            sw = 18.0 * math.sin(th) * sgn
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 18.0, rz_deg=-sgn * 16.0 + sw)
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rz_deg=-sgn * 32.0 + sw * 0.5)
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 14.0, rz_deg=-sgn * 24.0 - sw * 0.7)
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_lo_{side}", rz_deg=-sgn * 28.0)
        pose_tentacles(th * 2.0, stride_amp=22.0, curl_lift=8.0, lean_back=12.0)
        pose_crown(th * 2.0, flare=8.0, whip_amp=14.0)

    bake_clip("Monster_Walk", 48, 3, anim_walk)

    # 4. Monster_Run (36f): High-speed aggressive pursuit jet-surge (steep forward torso pitch + streaming tentacles & arms)
    def anim_run(u: float, _fr: int) -> None:
        th = u * 2.0 * math.pi
        arm_obj.pose.bones["pelvis"].location = Vector((0.0, -0.25, 0.45 + 0.18 * math.sin(th)))
        _set_bone_world_rot(arm_obj, rest_mats, "pelvis", rx_deg=26.0, rz_deg=9.0 * math.sin(th))
        _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=14.0)
        _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=10.0)
        _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-34.0)  # Locks gaze sharply onto prey!
        for side, sgn in (("l", 1.0), ("r", -1.0)):
            pump = 14.0 * math.sin(th + (0 if sgn > 0 else math.pi))
            # Swept back streamlined claws ready to strike!
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 16.0, rz_deg=sgn * (28.0 + pump))
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rx_deg=14.0, rz_deg=-sgn * 22.0)
            _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=sgn * (14.0 - pump * 0.6))
        pose_tentacles(th * 2.0, stride_amp=20.0, curl_lift=14.0, lean_back=26.0)
        pose_crown(th * 2.0, flare=18.0, whip_amp=16.0)

    bake_clip("Monster_Run", 36, 3, anim_run)

    # 5. Monster_Attack (44f): Brutal 4-Arm X-Cross Slash Combo + Front Tentacle Lash
    def anim_attack(u: float, _fr: int) -> None:
        if u < 0.30:
            w = math.sin((u / 0.30) * math.pi * 0.5)
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0.25 * w, 0.20 * w))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rz_deg=-24 * w, rx_deg=-10 * w)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rz_deg=-22 * w)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_up_r", ry_deg=24 * w, rz_deg=-40 * w)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_lo_up_r", rz_deg=-35 * w)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_up_l", rz_deg=26 * w)
            pose_tentacles(u * 8.0, stride_amp=16.0, curl_lift=8.0)
        elif u < 0.62:
            # Right Double-Arm Diagonal Cleave + Left Cross Windup
            k = (u - 0.30) / 0.32
            s = math.sin(k * math.pi * 0.5)
            arm_obj.pose.bones["pelvis"].location = Vector((0, -0.55 * s, 0.15))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=22 * s, rz_deg=38 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rz_deg=32 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-18 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_up_r", ry_deg=-20 * s, rz_deg=72 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_lo_r", rz_deg=36 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_lo_up_r", ry_deg=-18 * s, rz_deg=64 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_up_l", ry_deg=18 * s, rz_deg=34 * s)
            pose_tentacles(u * 12.0, stride_amp=26.0, spread_splay=12.0)
        else:
            # Left Double-Arm Cross Tear + Recovery
            k = min(1.0, (u - 0.62) / 0.25)
            rec = max(0.0, (u - 0.87) / 0.13)
            s = math.sin(k * math.pi * 0.5) * (1.0 - rec)
            arm_obj.pose.bones["pelvis"].location = Vector((0, -0.42 * s, 0.10 * s))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=18 * s, rz_deg=-36 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rz_deg=-28 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_up_up_l", ry_deg=22 * s, rz_deg=-76 * s)
            _set_bone_world_rot(arm_obj, rest_mats, "arm_lo_up_l", rz_deg=-68 * s)
            pose_tentacles(u * 12.0, stride_amp=18.0)
        pose_crown(u * 14.0, flare=14.0, whip_amp=16.0)

    bake_clip("Monster_Attack", 44, 3, anim_attack)

    # 6. Monster_Jump (60f): Deep spring coil -> Skybound leap (+3.4m) -> Crushing 4-Arm & Radial Tentacle Slam
    def anim_jump(u: float, _fr: int) -> None:
        if u < 0.24:
            k = math.sin((u / 0.24) * math.pi * 0.5)
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, -1.05 * k))
            for bn, dg in (("spine_1", 16), ("spine_2", 22), ("spine_3", 20), ("head", -18)):
                _set_bone_world_rot(arm_obj, rest_mats, bn, rx_deg=dg * k)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 34 * k, rz_deg=-sgn * 32 * k)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 25 * k, rz_deg=-sgn * 28 * k)
            pose_tentacles(u * 8.0, stride_amp=6.0, curl_lift=22.0 * k, spread_splay=24.0 * k)
        elif u < 0.68:
            t_air = (u - 0.24) / 0.44
            arc = math.sin(t_air * math.pi)
            arm_obj.pose.bones["pelvis"].location = Vector((0, -0.35 * arc, 3.35 * arc))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-12 * arc)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=-14 * arc)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=12 * (1.0 - t_air))
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=-sgn * 28 * arc, rz_deg=sgn * 14 * arc)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=-sgn * 20 * arc)
            pose_tentacles(u * 12.0, stride_amp=14.0, curl_lift=-24.0 * arc, lean_back=18.0 * arc)
        else:
            t_land = (u - 0.68) / 0.32
            imp = math.sin(min(1.0, t_land * 2.2) * math.pi * 0.5) * (1.0 - max(0.0, (t_land - 0.45) / 0.55))
            arm_obj.pose.bones["pelvis"].location = Vector((0, -0.25 * imp, -0.85 * imp))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=28 * imp)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=24 * imp)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-28 * imp)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 42 * imp, rz_deg=-sgn * 46 * imp)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 30 * imp, rz_deg=-sgn * 38 * imp)
            pose_tentacles(u * 8.0, stride_amp=10.0, curl_lift=20.0 * imp, spread_splay=28.0 * imp)
        pose_crown(u * 14.0, flare=16.0, whip_amp=16.0)

    bake_clip("Monster_Jump", 60, 4, anim_jump)

    # 7. Monster_SpitAndSlam (72f): Channel Solar Energy at Eclipse/Ribs -> Violent Forward Acid Spit -> Lunging Overhead 4-Arm Smash!
    def anim_spit_and_slam(u: float, _fr: int) -> None:
        if u < 0.25:
            k = math.sin((u / 0.25) * math.pi * 0.5)
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0.35 * k, 0.25 * k))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-22 * k)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=-24 * k)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-28 * k)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                # Gather/channel hands up toward glowing Eclipse Ring!
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=-sgn * 26 * k, rz_deg=-sgn * 46 * k)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_lo_{side}", rz_deg=-sgn * 40 * k)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=-sgn * 32 * k)
            pose_tentacles(u * 10.0, stride_amp=12.0, curl_lift=8.0)
            pose_crown(u * 18.0, flare=-24.0 * k, whip_amp=14.0)
        elif u < 0.55:
            # Violent Spit Burst! Snaps head & chest forward firing Plasma/Acid torrent while bracing arms wide
            k = min(1.0, (u - 0.25) / 0.14)
            vib = math.sin(u * 80.0) * 3.0
            arm_obj.pose.bones["pelvis"].location = Vector((0, -0.35 * k, 0.10))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=26 * k + vib * 0.4)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=24 * k)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=12 * k + vib)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=-sgn * 10, rz_deg=sgn * 26 * k)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=sgn * 18 * k)
            pose_tentacles(u * 16.0, stride_amp=18.0, spread_splay=16.0)
            pose_crown(u * 24.0, flare=32.0 * k, whip_amp=22.0)
        else:
            # Immediate Brutal Overhead 4-Arm Slam Execution!
            k = (u - 0.55) / 0.45
            if k < 0.45:
                # Raise all 4 arms overhead
                up = math.sin((k / 0.45) * math.pi * 0.5)
                arm_obj.pose.bones["pelvis"].location = Vector((0, 0.15 * up, 0.55 * up))
                _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-18 * up)
                _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-12 * up)
                for side, sgn in (("l", 1.0), ("r", -1.0)):
                    _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=-sgn * 48 * up, rz_deg=-sgn * 18 * up)
                    _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=-sgn * 34 * up, rz_deg=-sgn * 26 * up)
            else:
                sm = math.sin(min(1.0, (k - 0.45) / 0.35) * math.pi * 0.5) * (1.0 - max(0.0, (k - 0.80) / 0.20))
                arm_obj.pose.bones["pelvis"].location = Vector((0, -0.55 * sm, -0.75 * sm))
                _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=34 * sm)
                _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=26 * sm)
                _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=-24 * sm)
                for side, sgn in (("l", 1.0), ("r", -1.0)):
                    _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 44 * sm, rz_deg=-sgn * 54 * sm)
                    _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", ry_deg=sgn * 36 * sm, rz_deg=-sgn * 48 * sm)
            pose_tentacles(u * 12.0, stride_amp=16.0, curl_lift=14.0)
            pose_crown(u * 16.0, flare=14.0, whip_amp=16.0)

    bake_clip("Monster_SpitAndSlam", 72, 4, anim_spit_and_slam)

    # 8. Monster_Evolve (84f): Solar Cocoon Compression -> Violent Tremor -> Blazing Growth Surge
    def anim_evolve(u: float, _fr: int) -> None:
        if u < 0.55:
            k = math.sin((u / 0.55) * math.pi * 0.5)
            vib = math.sin(u * 90.0) * 4.5 * k
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, -0.70 * k))
            arm_obj.pose.bones["pelvis"].scale = Vector((1.0 - 0.08 * k, 1.0 - 0.08 * k, 1.0 - 0.08 * k))
            for bn in ("spine_1", "spine_2", "spine_3", "head"):
                _set_bone_world_rot(arm_obj, rest_mats, bn, rx_deg=18 * k + vib * 0.4)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=sgn * 25 * k, rz_deg=-sgn * 62 * k)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=-sgn * 48 * k)
            pose_tentacles(u * 10.0, stride_amp=6.0, curl_lift=22.0 * k)
            pose_crown(u * 16.0, flare=-26.0 * k, whip_amp=10.0)
        else:
            b = math.sin(min(1.0, (u - 0.55) / 0.30) * math.pi * 0.5) * (1.0 - max(0.0, (u - 0.85) / 0.15))
            arm_obj.pose.bones["pelvis"].location = Vector((0, 0, 1.15 * b))
            arm_obj.pose.bones["pelvis"].scale = Vector((1.0 + 0.15 * b, 1.0 + 0.15 * b, 1.0 + 0.15 * b))
            _set_bone_world_rot(arm_obj, rest_mats, "spine_1", rx_deg=-4 * b)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_2", rx_deg=-8 * b)
            _set_bone_world_rot(arm_obj, rest_mats, "spine_3", rx_deg=-8 * b)
            _set_bone_world_rot(arm_obj, rest_mats, "head", rx_deg=10 * b)
            for side, sgn in (("l", 1.0), ("r", -1.0)):
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_up_up_{side}", ry_deg=-sgn * 22 * b, rz_deg=sgn * 20 * b)
                _set_bone_world_rot(arm_obj, rest_mats, f"arm_lo_up_{side}", rz_deg=sgn * 24 * b)
            pose_tentacles(u * 14.0, stride_amp=18.0, spread_splay=24.0 * b)
            pose_crown(u * 22.0, flare=32.0 * b, whip_amp=22.0)

    bake_clip("Monster_Evolve", 84, 4, anim_evolve)

    _reset_pose(arm_obj)
    return actions


# ---------------------------------------------------------------------------
# 4. Volcanic Alpha Fauna (2.4m) + Cyan-Visor Hunter (1.54m) + Showcase Stage + VFX
# ---------------------------------------------------------------------------

def build_hunter_dummy(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material], loc: Vector) -> bpy.types.Object:
    """Armored sci-fi Hunter (1.54m) built in local origin space with world location applied to object."""
    bm = bmesh.new()
    # Boots & legs (0 -> 0.78m)
    for ox in (-0.11, 0.11):
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((ox, 0.0, 0.12)) @ Matrix.Diagonal((0.17, 0.24, 0.24, 1.0)))
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((ox, 0.0, 0.48)) @ Matrix.Diagonal((0.15, 0.17, 0.56, 1.0)))
    # Armored torso & chest rig (0.76 -> 1.28m)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.0, 0.0, 1.02)) @ Matrix.Diagonal((0.40, 0.24, 0.52, 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.0, -0.02, 1.08)) @ Matrix.Diagonal((0.36, 0.28, 0.30, 1.0)))
    # Jetpack / Thruster pack on back
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.0, 0.16, 1.08)) @ Matrix.Diagonal((0.28, 0.12, 0.36, 1.0)))
    # Shoulder pads & arms
    for ox in (-0.28, 0.28):
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((ox, 0.0, 1.22)) @ Matrix.Diagonal((0.18, 0.22, 0.16, 1.0)))
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((ox, -0.04, 0.98)) @ Matrix.Diagonal((0.13, 0.15, 0.44, 1.0)))
    # Helmet dome (top at 1.54m)
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=Matrix.Translation((0.0, -0.01, 1.41)) @ Matrix.Diagonal((0.125, 0.145, 0.13, 1.0)))
    # Sci-fi heavy assault rifle
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-0.14, -0.28, 1.00)) @ Matrix.Diagonal((0.065, 0.66, 0.10, 1.0)))
    for f in bm.faces:
        f.material_index = 0
    # Glowing Cyan tactical visor facing -Y
    ret_v = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.0, -0.14, 1.42)) @ Matrix.Diagonal((0.17, 0.045, 0.06, 1.0)))
    for v in ret_v["verts"]:
        for f in v.link_faces:
            f.material_index = 1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Stage_Hunter_1_54m")
    bm.to_mesh(mesh); bm.free()
    mesh.materials.append(mats["HunterArmor"])
    mesh.materials.append(mats["HunterVisor"])
    obj = bpy.data.objects.new("Stage_Hunter_1_54m", mesh)
    col.objects.link(obj)
    obj.location = loc
    return obj


def build_alpha_fauna(col: bpy.types.Collection, mats: Dict[str, bpy.types.Material], loc: Vector, yaw_deg: float = 15.0) -> bpy.types.Object:
    """Build a ~2.4m fiercely armored faceted volcanic quadruped Alpha Fauna predator (dwarfed by Stage 1!)."""
    bm = bmesh.new()
    # 1. Muscular Quadruped Core Body + Armored Spiked Tail (narrower profile so jagged basalt carapace dominates!)
    add_closed_loft(
        bm,
        [
            (Vector((0, 2.55, 0.92)), 0.04, 0.04),
            (Vector((0, 1.85, 1.10)), 0.22, 0.20),
            (Vector((0, 1.05, 1.48)), 0.54, 0.52),
            (Vector((0, -0.05, 1.60)), 0.68, 0.66),
            (Vector((0, -1.05, 1.72)), 0.74, 0.70),
            (Vector((0, -1.72, 1.60)), 0.48, 0.46),
        ],
        radial_segs=10, mat_idx=0, dorsal_pinch=0.35,
    )
    # 4 Heavily Muscled Clawed Legs grounded at Z = 0
    for ox, oy, rleg in ((0.76, -1.05, 0.28), (-0.76, -1.05, 0.28), (0.66, 1.15, 0.25), (-0.66, 1.15, 0.25)):
        add_closed_loft(
            bm,
            [
                (Vector((ox, oy, 1.38)), rleg * 1.25, rleg * 1.20),
                (Vector((ox * 1.10, oy + 0.14, 0.72)), rleg * 0.98, rleg * 0.98),
                (Vector((ox * 1.04, oy - 0.08, 0.18)), rleg * 1.15, rleg * 1.12),
                (Vector((ox * 1.04, oy - 0.16, 0.04)), rleg * 1.28, 0.14),
            ],
            radial_segs=10, mat_idx=0,
        )
        # Heavy basalt shoulder & hip armor pauldrons on front legs
        if oy < 0:
            add_closed_loft(
                bm,
                [
                    (Vector((ox * 0.85, oy - 0.18, 1.82)), 0.28, 0.22),
                    (Vector((ox * 1.12, oy, 1.56)), 0.34, 0.28),
                    (Vector((ox * 1.16, oy + 0.24, 1.18)), 0.18, 0.14),
                ],
                radial_segs=6, mat_idx=1, dorsal_pinch=0.55,
            )
        # 3 front basalt toes per foot
        for cx in (-0.12, 0.0, 0.12):
            add_closed_loft(
                bm,
                [
                    (Vector((ox * 1.04 + cx, oy - 0.24, 0.10)), 0.055, 0.065),
                    (Vector((ox * 1.04 + cx * 1.15, oy - 0.44, 0.04)), 0.014, 0.016),
                ],
                radial_segs=6, mat_idx=1,
            )

    # 2. 5 Overlapping Jagged Dorsal Basalt Armor Plates + Tall Dorsal Spine Blades (flat-shaded mat_idx=1!)
    plate_specs = [
        (1.25, 1.52, 0.42, 0.65),
        (0.65, 1.78, 0.62, 0.85),
        (-0.05, 1.98, 0.78, 0.98),
        (-0.75, 2.18, 0.84, 1.10),
        (-1.35, 2.12, 0.72, 0.92),
    ]
    for py, pz, hw_p, ridge_z in plate_specs:
        add_closed_loft(
            bm,
            [
                (Vector((0, py + 0.36, pz - 0.10)), hw_p * 0.80, 0.18),
                (Vector((0, py, pz + 0.08)), hw_p, 0.24),
                (Vector((0, py - 0.32, pz + 0.14)), hw_p * 0.90, 0.18),
            ],
            radial_segs=6, mat_idx=1, dorsal_pinch=0.65,
        )
        # Tall jagged basalt dorsal spine blades rising cleanly above shoulders (~2.4m crest height!)
        add_closed_loft(
            bm,
            [
                (Vector((0, py - 0.06, pz + 0.10)), 0.14, 0.18),
                (Vector((0, py + 0.24, pz + 0.42 * (ridge_z / 0.85))), 0.02, 0.025),
            ],
            radial_segs=5, mat_idx=1,
        )

    # 3. Fierce Horned Predator Skull + Open Fanged Lower Jaw + Twin Curved Horns (~2.42m tip height!)
    add_closed_loft(
        bm,
        [
            (Vector((0, -1.68, 1.74)), 0.44, 0.34),
            (Vector((0, -2.06, 1.78)), 0.36, 0.26),
            (Vector((0, -2.42, 1.72)), 0.22, 0.16),
        ],
        radial_segs=7, mat_idx=1, dorsal_pinch=0.45,
    )
    # Open snarling lower jaw with glowing molten maw core
    add_closed_loft(
        bm,
        [
            (Vector((0, -1.78, 1.50)), 0.32, 0.14),
            (Vector((0, -2.30, 1.40)), 0.18, 0.09),
        ],
        radial_segs=6, mat_idx=1,
    )
    ret_maw = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.14, matrix=Matrix.Translation((0.0, -2.14, 1.56)))
    for v in ret_maw["verts"]:
        for f in v.link_faces:
            f.material_index = 2
    for sgn in (1.0, -1.0):
        # Twin large swept curved volcanic horns (rising to ~2.42m!)
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.28, -1.86, 1.88)), 0.12, 0.12),
                (Vector((sgn * 0.48, -2.12, 2.12)), 0.08, 0.08),
                (Vector((sgn * 0.56, -2.28, 2.42)), 0.015, 0.015),
            ],
            radial_segs=6, mat_idx=1,
        )
        # Upper & lower snout fangs
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.14, -2.28, 1.62)), 0.035, 0.035),
                (Vector((sgn * 0.14, -2.30, 1.46)), 0.008, 0.008),
            ],
            radial_segs=5, mat_idx=1,
        )
        # Glowing Magma Shoulder Veins & Fiery Predator Eyes
        add_closed_loft(
            bm,
            [
                (Vector((sgn * 0.72, -1.25, 1.72)), 0.055, 0.045),
                (Vector((sgn * 0.88, -0.65, 1.50)), 0.050, 0.038),
                (Vector((sgn * 0.78, 0.15, 1.38)), 0.035, 0.025),
            ],
            radial_segs=6, mat_idx=2,
        )
        ret_e = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.065, matrix=Matrix.Translation((sgn * 0.28, -2.12, 1.78)))
        for v in ret_e["verts"]:
            for f in v.link_faces:
                f.material_index = 2

    # Flat-shade basalt carapace (mat_idx == 1), smooth muscle/magma (0, 2)
    for f in bm.faces:
        f.smooth = (f.material_index != 1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Stage_AlphaFauna_2_4m")
    bm.to_mesh(mesh); bm.free()
    mesh.materials.append(mats["FaunaHide"])
    mesh.materials.append(mats["FaunaCarapace"])
    mesh.materials.append(mats["FaunaMagma"])

    obj = bpy.data.objects.new("Stage_AlphaFauna_2_4m", mesh)
    col.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    return obj


def build_stage_and_cameras(
    arm_obj: bpy.types.Object,
    col: bpy.types.Collection,
    mats: Dict[str, bpy.types.Material],
) -> Tuple[Dict[str, bpy.types.Object], bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    # Broad volcanic basalt arena disc (radius 36m so 5-figure lineup + 10.2m Colossus fit comfortably)
    bm_fl = bmesh.new()
    bmesh.ops.create_cone(
        bm_fl, cap_ends=True, cap_tris=False, segments=48,
        radius1=36.0, radius2=35.0, depth=0.65,
        matrix=Matrix.Translation((0.0, 0.0, -0.325)),
    )
    fl_mesh = bpy.data.meshes.new("Stage_VolcanicFloor")
    bm_fl.to_mesh(fl_mesh); bm_fl.free()
    fl_obj = bpy.data.objects.new("Stage_VolcanicFloor", fl_mesh)
    col.objects.link(fl_obj)
    fl_obj.data.materials.append(mats["StageBasalt"])

    # Glowing orbital containment perimeter ring (radius 18.5m)
    bm_rg = bmesh.new()
    pts_o, pts_i = [], []
    for i in range(64):
        a = (2.0 * math.pi * i) / 64.0
        ca, sa = math.cos(a), math.sin(a)
        pts_o.append(bm_rg.verts.new(Vector((ca * 18.6, sa * 18.6, 0.008))))
        pts_i.append(bm_rg.verts.new(Vector((ca * 18.3, sa * 18.3, 0.008))))
    for i in range(64):
        jn = (i + 1) % 64
        bm_rg.faces.new((pts_i[i], pts_o[i], pts_o[jn], pts_i[jn]))
    rg_mesh = bpy.data.meshes.new("Stage_ContainmentRing")
    bm_rg.to_mesh(rg_mesh); bm_rg.free()
    rg_obj = bpy.data.objects.new("Stage_ContainmentRing", rg_mesh)
    col.objects.link(rg_obj)
    rg_obj.data.materials.append(mats["StageAmber"])

    hunter_obj = build_hunter_dummy(col, mats, Vector((-4.6, -3.2, 0.0)))
    fauna_obj = build_alpha_fauna(col, mats, Vector((4.2, -2.8, 0.0)), yaw_deg=24.0)

    # Dynamic Spit Plasma Torrent VFX Cone (triggered at frames 242..262 during Monster_SpitAndSlam)
    bm_sp = bmesh.new()
    add_closed_loft(
        bm_sp,
        [
            (Vector((0.0, 0.0, 0.0)), 0.14, 0.14),
            (Vector((0.0, -3.5, -1.6)), 0.48, 0.48),
            (Vector((0.0, -7.2, -3.6)), 0.85, 0.85),
            (Vector((0.0, -9.8, -4.8)), 0.25, 0.25),
        ],
        radial_segs=12, mat_idx=0,
    )
    sp_mesh = bpy.data.meshes.new("Stage_SpitBeamVFX")
    bm_sp.to_mesh(sp_mesh); bm_sp.free()
    sp_mesh.materials.append(mats["SpitPlasma"])
    sp_obj = bpy.data.objects.new("Stage_SpitBeamVFX", sp_mesh)
    col.objects.link(sp_obj)
    cn_sp = sp_obj.constraints.new("COPY_LOCATION")
    cn_sp.target = arm_obj
    cn_sp.subtarget = "head"
    sp_obj.scale = Vector((0.001, 0.001, 0.001))
    sp_obj.hide_render = True

    # World dark atmospheric glow backdrop
    world = bpy.data.worlds.new("EclipseAbyssWorld")
    bpy.context.scene.world = world
    w_nt = world.node_tree
    bg = next((n for n in w_nt.nodes if n.type == "BACKGROUND"), None)
    if bg is None:
        bg = w_nt.nodes.new("ShaderNodeBackground")
    _get_socket(bg.inputs, "Color").default_value = (0.042, 0.052, 0.072, 1.0)
    _get_socket(bg.inputs, "Strength").default_value = 0.85

    def add_area(name: str, loc: Tuple[float, float, float], target: Tuple[float, float, float], power: float, color: Tuple[float, float, float], size: float) -> None:
        ldata = bpy.data.lights.new(name=name, type="AREA")
        ldata.energy = power; ldata.color = color; ldata.size = size
        lo = bpy.data.objects.new(name, ldata)
        lo.location = loc
        lo.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        col.objects.link(lo)

    add_area("Light_KeyFrontLeft", (-12.0, -15.0, 12.5), (0.0, 0.0, 4.5), 5500.0, (1.0, 0.92, 0.85), 8.0)
    add_area("Light_CoolRimBack", (8.0, 13.0, 11.0), (0.0, 0.0, 4.8), 7500.0, (0.45, 0.72, 1.0), 7.5)
    add_area("Light_GoldenEclipseBack", (0.0, 9.5, 6.2), (0.0, 0.0, 4.8), 6500.0, (1.0, 0.48, 0.12), 9.0)
    add_area("Light_FillRight", (14.0, -10.0, 6.5), (0.0, 0.0, 4.2), 2800.0, (0.78, 0.86, 1.0), 8.0)
    add_area("Light_UnderMagma", (0.0, -6.0, 0.8), (0.0, 0.0, 4.5), 1800.0, (1.0, 0.30, 0.05), 5.0)

    # Moving Golden Eclipse Point Light attached directly to Monster_Armature bone 'head'!
    pt_data = bpy.data.lights.new(name="Light_EclipseHeadAura", type="POINT")
    pt_data.energy = 3500.0
    pt_data.color = (1.0, 0.56, 0.14)
    pt_data.shadow_soft_size = 1.2
    pt_obj = bpy.data.objects.new("Light_EclipseHeadAura", pt_data)
    col.objects.link(pt_obj)
    cn = pt_obj.constraints.new("COPY_LOCATION")
    cn.target = arm_obj
    cn.subtarget = "head"
    cn.head_tail = 0.5

    def add_cam(name: str, loc: Tuple[float, float, float], target: Tuple[float, float, float], lens: float) -> bpy.types.Object:
        cd = bpy.data.cameras.new(name)
        cd.lens = lens; cd.clip_end = 500.0
        co = bpy.data.objects.new(name, cd)
        co.location = loc
        co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        col.objects.link(co)
        return co

    cams = {
        "lineup": add_cam("Cam_1_EvolutionLineup", (2.7, -30.5, 5.0), (2.7, 0.0, 4.7), 28.0),
        "stage1": add_cam("Cam_2_Stage1ApexVsFauna", (-5.6, -11.8, 3.5), (0.2, -1.0, 3.1), 30.0),
        "stage2": add_cam("Cam_3_Stage2AttackAction", (10.5, -13.2, 4.8), (0.0, 0.0, 4.2), 30.0),
        "stage3": add_cam("Cam_4_Stage3EclipseGod", (-9.5, -20.5, 5.4), (0.0, 0.0, 5.2), 28.0),
        "turntable": add_cam("Cam_5_AnimationReel", (-14.0, -21.0, 6.2), (0.0, 0.0, 5.0), 28.0),
    }
    return cams, hunter_obj, fauna_obj, sp_obj


# ---------------------------------------------------------------------------
# 5. Render Stills (Incl. 5-Figure Lineup), 12s MP4 Reel, Audit & Export
# ---------------------------------------------------------------------------

def _toggle_stages(stage_objs: Dict[str, bpy.types.Object], active: str) -> None:
    for key, obj in stage_objs.items():
        hide = key != active
        obj.hide_render = hide
        obj.hide_viewport = hide


def _set_single_action(arm_obj: bpy.types.Object, act: bpy.types.Action) -> None:
    ad = arm_obj.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = act
    if hasattr(ad, "action_slot") and len(act.slots) > 0:
        ad.action_slot = act.slots[0]


def render_4_stills(
    arm_obj: bpy.types.Object,
    core_obj: bpy.types.Object,
    ribs_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions_by_name: Dict[str, bpy.types.Action],
    cams: Dict[str, bpy.types.Object],
    hunter_obj: bpy.types.Object,
    fauna_obj: bpy.types.Object,
    stage_col: bpy.types.Collection,
) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.media_type = "IMAGE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"

    # --- SHOT 1: 5-Figure 3D Lineup (Hunter 1.54m -> Alpha Fauna 2.4m -> S1 6.2m -> S2 8.1m -> S3 10.2m) ---
    temp_clones: List[bpy.types.Object] = []
    _set_single_action(arm_obj, actions_by_name["Monster_Idle"])
    scene.frame_set(0)

    h_saved_loc = hunter_obj.location.copy()
    f_saved_loc = fauna_obj.location.copy()
    f_saved_rot = fauna_obj.rotation_euler.copy()

    hunter_obj.location = Vector((-11.2, 0.0, 0.0))
    fauna_obj.location = Vector((-7.8, 0.2, 0.0))
    fauna_obj.rotation_euler = (0.0, 0.0, math.radians(22.0))

    # Position Main Armature temporarily as Stage 1 at X = -2.8
    arm_obj.location = Vector((-2.8, 0.0, 0.0))
    arm_obj.scale = Vector((1.0, 1.0, 1.0))
    _toggle_stages(stage_objs, "Stage1")

    def spawn_lineup_clone(stage_key: str, scale_v: float, pos_x: float) -> None:
        c_arm = arm_obj.copy()
        c_arm.location = Vector((pos_x, 0.0, 0.0))
        c_arm.scale = Vector((scale_v, scale_v, scale_v))
        stage_col.objects.link(c_arm)
        temp_clones.append(c_arm)
        for src in (core_obj, ribs_obj, stage_objs[stage_key]):
            co = src.copy()
            co.parent = c_arm
            co.hide_render = False
            co.hide_viewport = False
            for m in co.modifiers:
                if m.type == "ARMATURE":
                    m.object = c_arm
            stage_col.objects.link(co)
            temp_clones.append(co)

    spawn_lineup_clone("Stage2", 1.30, 3.8)
    spawn_lineup_clone("Stage3", 1.65, 12.4)

    scene.camera = cams["lineup"]
    scene.render.filepath = str(PREVIEWS_DIR / "monster_view_1.png")
    bpy.ops.render.render(write_still=True)

    # Cleanup lineup clones & restore armature origin
    for o in temp_clones:
        bpy.data.objects.remove(o, do_unlink=True)
    arm_obj.location = Vector((0.0, 0.0, 0.0))

    # --- SHOT 2: Stage 1 ("Predador Alfa do Eclipse") Dwarfing Alpha Fauna & Hunter ---
    _toggle_stages(stage_objs, "Stage1")
    arm_obj.scale = Vector((1.0, 1.0, 1.0))
    hunter_obj.location = Vector((-3.4, -2.5, 0.0))
    fauna_obj.location = Vector((2.3, -1.8, 0.0))
    fauna_obj.rotation_euler = (0.0, 0.0, math.radians(-28.0))
    _set_single_action(arm_obj, actions_by_name["Monster_Idle"])
    scene.frame_set(18)
    scene.camera = cams["stage1"]
    scene.render.filepath = str(PREVIEWS_DIR / "monster_view_2.png")
    bpy.ops.render.render(write_still=True)

    # Restore arena hunter/fauna stance for Shots 3 & 4
    hunter_obj.location = h_saved_loc
    fauna_obj.location = f_saved_loc
    fauna_obj.rotation_euler = f_saved_rot

    # --- SHOT 3: Stage 2 ("Arauto Desperto", 1.3x) Mid-Attack Strike ---
    _toggle_stages(stage_objs, "Stage2")
    arm_obj.scale = Vector((1.30, 1.30, 1.30))
    _set_single_action(arm_obj, actions_by_name["Monster_Attack"])
    scene.frame_set(22)
    scene.camera = cams["stage2"]
    scene.render.filepath = str(PREVIEWS_DIR / "monster_view_3.png")
    bpy.ops.render.render(write_still=True)

    # --- SHOT 4: Stage 3 ("Deus do Eclipse Abissal", 1.65x) Colossal Intro Roar ---
    _toggle_stages(stage_objs, "Stage3")
    arm_obj.scale = Vector((1.65, 1.65, 1.65))
    _set_single_action(arm_obj, actions_by_name["Monster_Intro_Roar"])
    scene.frame_set(46)
    scene.camera = cams["stage3"]
    scene.render.filepath = str(PREVIEWS_DIR / "monster_view_4.png")
    bpy.ops.render.render(write_still=True)


def _populate_showcase_tracks(
    arm_target: bpy.types.Object,
    actions_by_name: Dict[str, bpy.types.Action],
) -> Tuple[bpy.types.NlaTrack, bpy.types.NlaTrack]:
    if arm_target.animation_data is None:
        arm_target.animation_data_create()
    ad = arm_target.animation_data
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)

    tr_a = ad.nla_tracks.new()
    tr_a.name = "Showcase_A"
    tr_b = ad.nla_tracks.new()
    tr_b.name = "Showcase_B"

    # Non-colliding dual-track crossfaded showcase: Intro_Roar -> Walk -> Run -> Attack -> Jump -> SpitAndSlam!
    seq = [
        (tr_a, "Monster_Intro_Roar", 1, 68),
        (tr_b, "Monster_Walk", 64, 108),
        (tr_a, "Monster_Run", 104, 140),
        (tr_b, "Monster_Attack", 136, 178),
        (tr_a, "Monster_Jump", 174, 228),
        (tr_b, "Monster_SpitAndSlam", 224, 288),
    ]
    for tr, cname, s_f, e_f in seq:
        act = actions_by_name[cname]
        st = tr.strips.new(cname, s_f, act)
        if hasattr(st, "action_slot") and len(act.slots) > 0:
            st.action_slot = act.slots[0]
        st.action_frame_start = act.frame_range[0]
        st.action_frame_end = act.frame_range[1]
        st.frame_end = e_f
        st.use_auto_blend = True
        st.blend_in = 4.0
        st.blend_out = 4.0
    return tr_a, tr_b


def setup_showcase_nla(
    arm_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions_by_name: Dict[str, bpy.types.Action],
    sp_obj: bpy.types.Object,
) -> None:
    scene = bpy.context.scene
    arm_obj.scale = Vector((1.65, 1.65, 1.65))
    _toggle_stages(stage_objs, "Stage3")
    _populate_showcase_tracks(arm_obj, actions_by_name)

    # Keyframe Plasma Spit Torrent VFX strictly during SpitAndSlam window (242..262)
    sp_obj.hide_render = False
    sp_obj.hide_viewport = False
    for fr, sc in ((1, 0.001), (240, 0.001), (244, 1.15), (256, 1.25), (262, 0.001), (288, 0.001)):
        sp_obj.scale = Vector((sc, sc, sc))
        sp_obj.keyframe_insert(data_path="scale", frame=fr)

    scene.frame_start = 1
    scene.frame_end = 288
    scene.render.fps = 24


def render_showcase_video(
    arm_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions_by_name: Dict[str, bpy.types.Action],
    cams: Dict[str, bpy.types.Object],
    sp_obj: bpy.types.Object,
) -> None:
    scene = bpy.context.scene
    setup_showcase_nla(arm_obj, stage_objs, actions_by_name, sp_obj)

    # Smooth orbital tracking camera
    cam_t = cams["turntable"]
    target = Vector((0.0, 0.0, 4.8))
    for fr, ang_deg, dist, z_cam in (
        (1, -130.0, 23.0, 6.0),
        (72, -98.0, 21.5, 5.5),
        (144, -62.0, 23.0, 6.2),
        (216, -24.0, 24.5, 6.8),
        (288, -108.0, 22.5, 5.8),
    ):
        rad = math.radians(ang_deg)
        cam_t.location = Vector((math.cos(rad) * dist, math.sin(rad) * dist, z_cam))
        cam_t.rotation_euler = (target - cam_t.location).to_track_quat("-Z", "Y").to_euler()
        cam_t.keyframe_insert(data_path="location", frame=fr)
        cam_t.keyframe_insert(data_path="rotation_euler", frame=fr)

    scene.camera = cam_t
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.image_settings.media_type = "VIDEO"
    scene.render.ffmpeg.format = "MPEG4"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.filepath = str(VIDEO_PATH)
    bpy.ops.render.render(animation=True)

    scene.render.image_settings.media_type = "IMAGE"
    scene.render.image_settings.file_format = "PNG"


def export_rigged_models(
    root_col: bpy.types.Collection,
    arm_obj: bpy.types.Object,
    core_obj: bpy.types.Object,
    ribs_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions: Sequence[bpy.types.Action],
) -> None:
    ad = arm_obj.animation_data
    ad.action = None
    show_trs = [tr for tr in ad.nla_tracks if tr.name.startswith("Showcase_")]
    for tr in show_trs:
        tr.mute = True

    export_trs = []
    for act in actions:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(act.frame_range[0]), act)
        if hasattr(st, "action_slot") and len(act.slots) > 0:
            st.action_slot = act.slots[0]
        export_trs.append(tr)

    # Export combined multi-stage GLB & FBX at canonical 1.0x Stage-1 metric base scale
    arm_obj.scale = Vector((1.0, 1.0, 1.0))
    for o in stage_objs.values():
        o.hide_viewport = False
        o.hide_render = False

    bpy.ops.object.select_all(action="DESELECT")
    for o in [arm_obj, core_obj, ribs_obj] + list(stage_objs.values()):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
    )

    bpy.ops.export_scene.fbx(
        filepath=str(FBX_PATH),
        use_selection=True,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        mesh_smooth_type="FACE",
        bake_anim=True,
        bake_anim_use_nla_strips=True,
        bake_anim_use_all_actions=False,
        add_leaf_bones=False,
        path_mode="AUTO",
    )

    # Export per-stage standalone GLBs (Stage 1 = 1.0x, Stage 2 = 1.3x, Stage 3 = 1.65x)
    for skey, s_scale, out_p in (("Stage1", 1.0, STAGE1_GLB), ("Stage2", 1.30, STAGE2_GLB), ("Stage3", 1.65, STAGE3_GLB)):
        bpy.ops.object.select_all(action="DESELECT")
        arm_obj.scale = Vector((s_scale, s_scale, s_scale))
        for o in (arm_obj, core_obj, ribs_obj, stage_objs[skey]):
            o.select_set(True)
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.export_scene.gltf(
            filepath=str(out_p),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=False,
            export_materials="EXPORT",
            export_animations=True,
            export_animation_mode="NLA_TRACKS",
            export_nla_strips=True,
        )

    bpy.ops.object.select_all(action="DESELECT")

    # Restore interactive Stage 3 Showcase NLA state for instant Spacebar playback when opening .blend!
    arm_obj.scale = Vector((1.65, 1.65, 1.65))
    _toggle_stages(stage_objs, "Stage3")
    for tr in export_trs:
        tr.mute = True
    for tr in show_trs:
        tr.mute = False


def audit_and_configure_view(
    root_col: bpy.types.Collection,
    arm_obj: bpy.types.Object,
    core_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions: Sequence[bpy.types.Action],
    cams: Dict[str, bpy.types.Object],
    core_tris: int,
) -> Dict[str, object]:
    scene = bpy.context.scene
    scene.camera = cams["stage3"]
    scene.frame_set(42)

    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.clip_end = 500.0
                        space.shading.type = "MATERIAL"
                        space.shading.use_scene_lights = True
                        space.shading.use_scene_world = True
                        if space.region_3d:
                            space.region_3d.view_perspective = "CAMERA"

    def stage_height_m(s_key: str, s_val: float) -> float:
        arm_obj.data.pose_position = "REST"
        arm_obj.scale = Vector((s_val, s_val, s_val))
        prev_hide = stage_objs[s_key].hide_viewport
        stage_objs[s_key].hide_viewport = False
        bpy.context.view_layer.update()
        mn_z, mx_z = float("inf"), float("-inf")
        for o in (core_obj, stage_objs[s_key]):
            mw = o.matrix_world
            for c in o.bound_box:
                wz = (mw @ Vector(c)).z
                mn_z, mx_z = min(mn_z, wz), max(mx_z, wz)
        stage_objs[s_key].hide_viewport = prev_hide
        return round(mx_z - mn_z, 3)

    h1 = stage_height_m("Stage1", 1.0)
    h2 = stage_height_m("Stage2", 1.30)
    h3 = stage_height_m("Stage3", 1.65)
    arm_obj.data.pose_position = "POSE"
    bpy.context.view_layer.update()

    # Check loose components on CoreBody
    bm = bmesh.new(); bm.from_mesh(core_obj.data)
    vis = set(); comps = 0
    for v in bm.verts:
        if v not in vis:
            comps += 1; st = [v]; vis.add(v)
            while st:
                cur = st.pop()
                for e in cur.link_edges:
                    nb = e.other_vert(cur)
                    if nb not in vis: vis.add(nb); st.append(nb)
    bm.free()

    meshes = [o for o in root_col.objects if o.type == "MESH"]
    tri_map: Dict[str, int] = {}
    over_20k: List[Dict[str, object]] = []
    neg_scale: List[str] = []
    empty_m: List[str] = []
    for o in meshes:
        if min(o.scale) < 0.0:
            neg_scale.append(o.name)
        t = sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
        tri_map[o.name] = t
        if t == 0:
            empty_m.append(o.name)
        if t > 20000:
            over_20k.append({"name": o.name, "triangles": t})

    return {
        "creature": "Arauto do Eclipse Abissal",
        "skeletonBones": len(arm_obj.data.bones),
        "coreBodyLooseComponents": comps,
        "coreBodyTriangles": core_tris,
        "meshTriangleBreakdown": tri_map,
        "totalTrianglesAllStages": sum(tri_map.values()),
        "over20000Budget": over_20k,
        "negativeScaleObjects": neg_scale,
        "emptyMeshes": empty_m,
        "stageHeightsMeters": {"Stage1_1_0x": h1, "Stage2_1_3x": h2, "Stage3_1_65x": h3},
        "animationsCount": len(actions),
        "animationClips": [{"name": a.name, "frames": [round(a.frame_range[0], 1), round(a.frame_range[1], 1)]} for a in actions],
        "blendPath": str(BLEND_PATH),
        "showcaseBlendPath": str(SHOWCASE_BLEND_PATH),
        "glbPath": str(GLB_PATH),
        "fbxPath": str(FBX_PATH),
        "stageGlbs": [str(STAGE1_GLB), str(STAGE2_GLB), str(STAGE3_GLB)],
        "videoPath": str(VIDEO_PATH),
        "previews": [str(PREVIEWS_DIR / f"monster_view_{i}.png") for i in (1, 2, 3, 4)],
    }


def prepare_all_stages_viewport_scene(
    arm_obj: bpy.types.Object,
    core_obj: bpy.types.Object,
    ribs_obj: bpy.types.Object,
    stage_objs: Dict[str, bpy.types.Object],
    actions_by_name: Dict[str, bpy.types.Action],
    cams: Dict[str, bpy.types.Object],
    hunter_obj: bpy.types.Object,
    fauna_obj: bpy.types.Object,
    sp_obj: bpy.types.Object,
    stage_col: bpy.types.Collection,
) -> None:
    """Arrange ALL 3 animated evolution stages + Alpha Fauna + Hunter side-by-side for immediate visibility on Ctrl+O."""
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 288
    scene.render.fps = 24

    # Ensure Showcase_A / Showcase_B are active (not muted) and export tracks are muted on main Stage 3 Armature
    if arm_obj.animation_data is None:
        _populate_showcase_tracks(arm_obj, actions_by_name)
    else:
        ad = arm_obj.animation_data
        ad.action = None
        has_show = any(tr.name.startswith("Showcase_") for tr in ad.nla_tracks)
        if not has_show:
            _populate_showcase_tracks(arm_obj, actions_by_name)
        else:
            for tr in ad.nla_tracks:
                tr.mute = not tr.name.startswith("Showcase_")

    hunter_obj.location = Vector((-11.2, 0.0, 0.0))
    fauna_obj.location = Vector((-7.8, 0.2, 0.0))
    fauna_obj.rotation_euler = (0.0, 0.0, math.radians(22.0))

    # Main rig stands cleanly on the right as Stage 3 (1.65x)
    arm_obj.location = Vector((12.4, 0.0, 0.0))
    arm_obj.scale = Vector((1.65, 1.65, 1.65))
    _toggle_stages(stage_objs, "Stage3")

    # Spawn animated Stage 1 (1.0x @ X=-2.8) and Stage 2 (1.30x @ X=3.8) clones with explicit NLA Showcase tracks!
    for arm_name, stage_key, scale_v, pos_x in (
        ("Estagio1_Armature", "Stage1", 1.0, -2.8),
        ("Estagio2_Armature", "Stage2", 1.30, 3.8),
    ):
        c_arm = arm_obj.copy()
        c_arm.name = arm_name
        c_arm.location = Vector((pos_x, 0.0, 0.0))
        c_arm.scale = Vector((scale_v, scale_v, scale_v))
        stage_col.objects.link(c_arm)
        bpy.context.view_layer.update()
        if c_arm.pose is not None:
            for pb in c_arm.pose.bones:
                pb.rotation_mode = "QUATERNION"
        _populate_showcase_tracks(c_arm, actions_by_name)

        for src in (core_obj, ribs_obj, stage_objs[stage_key]):
            co = src.copy()
            co.name = f"{src.name}_{stage_key}"
            co.parent = c_arm
            co.hide_viewport = False
            co.hide_render = False
            for m in co.modifiers:
                if m.type == "ARMATURE":
                    m.object = c_arm
            stage_col.objects.link(co)

    sp_obj.hide_viewport = False
    scene.camera = cams["lineup"]
    scene.frame_set(42)
    bpy.context.view_layer.update()

    # Configure Material Preview + Camera + centered fallback orbit in all VIEW_3D panes
    orbit_target = Vector((2.7, 0.0, 4.5))
    orbit_cam_pos = Vector((2.7, -30.5, 5.0))
    orbit_quat = (orbit_target - orbit_cam_pos).to_track_quat("-Z", "Y")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.clip_end = 500.0
                        space.shading.type = "MATERIAL"
                        space.shading.use_scene_lights = True
                        space.shading.use_scene_world = True
                        if space.region_3d:
                            space.region_3d.view_perspective = "CAMERA"
                            space.region_3d.view_location = orbit_target
                            space.region_3d.view_distance = 30.5
                            space.region_3d.view_rotation = orbit_quat


def main() -> None:
    fast_blend = "--fast-blend" in sys.argv
    clear_scene_keep_ui()
    mats = create_materials()

    root_col = ensure_collection("Monster_AbyssalEclipse")
    stage_col = ensure_collection("Monster_Studio_Stage")

    arm_obj, region_bones = create_master_armature(root_col)
    core_obj, core_tris = build_core_body(arm_obj, region_bones, root_col, mats)
    ribs_obj = build_ribcage_and_shackles(arm_obj, root_col, mats)
    stage_objs = build_stage_overlays(arm_obj, root_col, mats)

    actions = build_all_8_animations(arm_obj)
    actions_by_name = {a.name: a for a in actions}

    cams, hunter_obj, fauna_obj, sp_obj = build_stage_and_cameras(arm_obj, stage_col, mats)

    if not fast_blend:
        render_4_stills(arm_obj, core_obj, ribs_obj, stage_objs, actions_by_name, cams, hunter_obj, fauna_obj, stage_col)
        render_showcase_video(arm_obj, stage_objs, actions_by_name, cams, sp_obj)
        export_rigged_models(root_col, arm_obj, core_obj, ribs_obj, stage_objs, actions)
    else:
        setup_showcase_nla(arm_obj, stage_objs, actions_by_name, sp_obj)

    audit = audit_and_configure_view(root_col, arm_obj, core_obj, stage_objs, actions, cams, core_tris)
    AUDIT_PATH.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print("=== AUDIT ECLIPSE MONSTER (3 STAGES + 8 ANIMATIONS) ===")
    print(json.dumps(audit, indent=2))

    prepare_all_stages_viewport_scene(
        arm_obj, core_obj, ribs_obj, stage_objs, actions_by_name,
        cams, hunter_obj, fauna_obj, sp_obj, stage_col,
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.wm.save_as_mainfile(filepath=str(SHOWCASE_BLEND_PATH))
    print("ECLIPSE_3STAGE_MONSTER_BUILT_OK")


if __name__ == "__main__":
    main()
