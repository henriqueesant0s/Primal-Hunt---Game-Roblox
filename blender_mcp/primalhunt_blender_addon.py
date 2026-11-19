bl_info = {
    "name": "Primal Hunt Blender MCP Bridge",
    "author": "Project Primal Hunt",
    "version": (1, 0, 0),
    "blender": (5, 0, 0),
    "location": "View3D > Sidebar > PrimalHunt MCP",
    "description": "Local TCP bridge on 127.0.0.1:9876 for live MCP inspection and execution.",
    "category": "Development",
}

import contextlib
import io
import json
import queue
import socket
import threading
import bpy

_HOST = "127.0.0.1"
_PORT = 9876
_server_thread = None
_stop_event = threading.Event()
_task_queue: "queue.Queue[tuple[dict, queue.Queue]]" = queue.Queue()


def _execute_on_main_thread(req: dict) -> dict:
    cmd = req.get("command")
    params = req.get("params") or {}
    if cmd == "get_scene_info":
        objs = []
        for o in bpy.data.objects:
            tris = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
            objs.append(
                {
                    "name": o.name,
                    "type": o.type,
                    "location": list(o.location),
                    "dimensions": list(o.dimensions),
                    "triangles": tris,
                }
            )
        return {"ok": True, "scene": bpy.context.scene.name, "objects": objs}

    if cmd == "execute_python":
        buf = io.StringIO()
        ns = {"bpy": bpy}
        with contextlib.redirect_stdout(buf):
            exec(params.get("code", ""), ns)
        return {"ok": True, "stdout": buf.getvalue()}

    if cmd == "export_glb":
        bpy.ops.export_scene.gltf(
            filepath=params["output_path"],
            export_format="GLB",
            use_selection=bool(params.get("selected_only", False)),
            export_apply=True,
            export_yup=True,
        )
        return {"ok": True, "exported": params["output_path"]}

    return {"ok": False, "error": f"Unknown command: {cmd}"}


def _pump_queue():
    while not _task_queue.empty():
        req, reply_q = _task_queue.get_nowait()
        try:
            res = _execute_on_main_thread(req)
        except Exception as exc:
            res = {"ok": False, "error": str(exc)}
        reply_q.put(res)
    return 0.1 if not _stop_event.is_set() else None


def _serve():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((_HOST, _PORT))
        srv.listen(4)
        srv.settimeout(0.5)
        while not _stop_event.is_set():
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            with conn:
                data = conn.recv(1048576).decode("utf-8").strip()
                if not data:
                    continue
                req = json.loads(data)
                reply_q: "queue.Queue[dict]" = queue.Queue()
                _task_queue.put((req, reply_q))
                res = reply_q.get(timeout=20.0)
                conn.sendall((json.dumps(res) + "\n").encode("utf-8"))
    finally:
        srv.close()


def start_bridge():
    global _server_thread
    if _server_thread and _server_thread.is_alive():
        return False
    _stop_event.clear()
    _server_thread = threading.Thread(target=_serve, daemon=True)
    _server_thread.start()
    bpy.app.timers.register(_pump_queue, first_interval=0.1)
    return True


def stop_bridge():
    global _server_thread
    _stop_event.set()
    _server_thread = None


class PRIMALHUNT_OT_ToggleBridge(bpy.types.Operator):
    bl_idname = "primalhunt.toggle_mcp_bridge"
    bl_label = "Toggle MCP Socket Bridge"

    def execute(self, context):
        if _server_thread and _server_thread.is_alive():
            stop_bridge()
            self.report({"INFO"}, "Primal Hunt MCP Bridge stopped")
        else:
            start_bridge()
            self.report({"INFO"}, f"Primal Hunt MCP Bridge listening on {_HOST}:{_PORT}")
        return {"FINISHED"}


class PRIMALHUNT_PT_Panel(bpy.types.Panel):
    bl_label = "Primal Hunt MCP"
    bl_idname = "PRIMALHUNT_PT_Panel"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "PrimalHunt"

    def draw(self, context):
        layout = self.layout
        active = bool(_server_thread and _server_thread.is_alive())
        layout.label(text="Status: Active (9876)" if active else "Status: Stopped")
        layout.operator("primalhunt.toggle_mcp_bridge")


def register():
    bpy.utils.register_class(PRIMALHUNT_OT_ToggleBridge)
    bpy.utils.register_class(PRIMALHUNT_PT_Panel)


def unregister():
    _stop_event.set()
    bpy.utils.unregister_class(PRIMALHUNT_PT_Panel)
    bpy.utils.unregister_class(PRIMALHUNT_OT_ToggleBridge)
