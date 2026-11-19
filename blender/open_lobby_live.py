"""Startup script for interactive Blender 5.3 window showing OrbitalDropshipLobby.blend
with Material Preview active and the live TCP MCP bridge listening on 127.0.0.1:9876.
"""

import sys
import bpy

ADDON_DIR = r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt\blender_mcp"
if ADDON_DIR not in sys.path:
    sys.path.insert(0, ADDON_DIR)

import primalhunt_blender_addon  # noqa: E402


def _setup_live_session():
    try:
        primalhunt_blender_addon.register()
    except Exception:
        pass
    try:
        primalhunt_blender_addon.start_bridge()
    except Exception as exc:
        print("Bridge start warning:", exc)

    scene = bpy.context.scene
    cam = bpy.data.objects.get("Cam_1_Overview")
    if cam:
        scene.camera = cam

    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.clip_end = 1000.0
                        space.shading.type = "MATERIAL"
                        space.shading.use_scene_lights = True
                        space.shading.use_scene_world = True
                        if space.region_3d and cam:
                            space.region_3d.view_perspective = "CAMERA"
    return None


bpy.app.timers.register(_setup_live_session, first_interval=0.5)
