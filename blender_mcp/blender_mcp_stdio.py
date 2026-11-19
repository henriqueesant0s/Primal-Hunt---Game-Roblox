#!/usr/bin/env python3
"""Stdio MCP Server bridging Antigravity with Blender 5.3 (live socket or background CLI)."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

BLENDER_EXE = os.environ.get(
    "BLENDER_EXE",
    r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe",
)
ADDON_HOST = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
ADDON_PORT = int(os.environ.get("BLENDER_MCP_PORT", "9876"))


def _try_live_blender(command: str, params: dict[str, Any], timeout: float = 15.0) -> dict[str, Any] | None:
    try:
        with socket.create_connection((ADDON_HOST, ADDON_PORT), timeout=timeout) as sock:
            payload = json.dumps({"command": command, "params": params}) + "\n"
            sock.sendall(payload.encode("utf-8"))
            chunks: list[bytes] = []
            while True:
                data = sock.recv(65536)
                if not data:
                    break
                chunks.append(data)
                if b"\n" in data:
                    break
            raw = b"".join(chunks).decode("utf-8").strip()
            if raw:
                return json.loads(raw)
    except OSError:
        return None
    return None


def _run_blender_background(python_code: str, blend_path: str | None = None, timeout: float = 120.0) -> dict[str, Any]:
    if not Path(BLENDER_EXE).exists():
        return {"ok": False, "error": f"Blender executable not found at {BLENDER_EXE}"}

    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as tmp:
        tmp.write(python_code)
        tmp_path = tmp.name

    try:
        cmd = [BLENDER_EXE, "--background"]
        if blend_path:
            cmd.append(blend_path)
        cmd.extend(["--python", tmp_path])
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        return {
            "ok": proc.returncode == 0,
            "returncode": proc.returncode,
            "stdout": proc.stdout[-12000:],
            "stderr": proc.stderr[-4000:],
        }
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


def _handle_tool_call(name: str, arguments: dict[str, Any]) -> str:
    if name == "get_blender_info":
        live = _try_live_blender("get_scene_info", {})
        proc = subprocess.run([BLENDER_EXE, "--version"], capture_output=True, text=True, timeout=10)
        return json.dumps(
            {
                "blender_exe": BLENDER_EXE,
                "version": proc.stdout.strip(),
                "live_bridge_connected": live is not None,
                "live_scene": live,
            },
            indent=2,
        )

    if name == "inspect_blender_scene":
        blend_path = arguments.get("blend_path")
        live = _try_live_blender("get_scene_info", {}) if not blend_path else None
        if live is not None:
            return json.dumps(live, indent=2)

        script = (
            "import bpy, json\n"
            "objs = []\n"
            "for o in bpy.data.objects:\n"
            "    tris = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == 'MESH' else 0\n"
            "    objs.append({'name': o.name, 'type': o.type, 'location': list(o.location), "
            "'dimensions': list(o.dimensions), 'triangles': tris})\n"
            "print('MCP_JSON:' + json.dumps({'scene': bpy.context.scene.name, 'objects': objs}))\n"
        )
        res = _run_blender_background(script, blend_path=blend_path)
        return json.dumps(res, indent=2)

    if name == "execute_blender_python":
        code = str(arguments.get("code", ""))
        blend_path = arguments.get("blend_path")
        if not blend_path:
            live = _try_live_blender("execute_python", {"code": code})
            if live is not None:
                return json.dumps(live, indent=2)
        res = _run_blender_background(code, blend_path=blend_path)
        return json.dumps(res, indent=2)

    if name == "export_glb":
        blend_path = arguments.get("blend_path")
        output_path = str(arguments["output_path"])
        selected_only = bool(arguments.get("selected_only", False))
        if not blend_path:
            live = _try_live_blender(
                "export_glb",
                {"output_path": output_path, "selected_only": selected_only},
            )
            if live is not None:
                return json.dumps(live, indent=2)

        code = (
            "import bpy\n"
            f"bpy.ops.export_scene.gltf(filepath={output_path!r}, export_format='GLB', "
            f"use_selection={selected_only!r}, export_apply=True, export_yup=True)\n"
            "print('EXPORTED_GLB_OK')\n"
        )
        res = _run_blender_background(code, blend_path=blend_path)
        return json.dumps(res, indent=2)

    raise ValueError(f"Unknown tool: {name}")


TOOLS = [
    {
        "name": "get_blender_info",
        "description": "Check installed Blender 5.3 version and whether the live viewport socket bridge is active.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "inspect_blender_scene",
        "description": "List objects, dimensions, and triangle counts in the live Blender session or a .blend file.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "blend_path": {"type": "string", "description": "Optional .blend file path."}
            },
        },
    },
    {
        "name": "execute_blender_python",
        "description": "Run Python (bpy) code inside Blender (live session if addon enabled, or background Blender 5.3 CLI).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Python bpy script to execute."},
                "blend_path": {"type": "string", "description": "Optional .blend file to open before running."},
            },
            "required": ["code"],
        },
    },
    {
        "name": "export_glb",
        "description": "Export scene or selected meshes from Blender to a .glb file ready for Roblox Studio import.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "output_path": {"type": "string", "description": "Absolute .glb output file path."},
                "blend_path": {"type": "string", "description": "Optional .blend file path."},
                "selected_only": {"type": "boolean", "description": "Export only selected objects."},
            },
            "required": ["output_path"],
        },
    },
]


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        req_id: Any = None
        try:
            msg = json.loads(line)
            req_id = msg.get("id")
            method = msg.get("method")
            params = msg.get("params") or {}

            if method == "initialize":
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "primalhunt-blender-mcp", "version": "1.0.0"},
                    },
                }
            elif method == "notifications/initialized":
                continue
            elif method == "tools/list":
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}
            elif method == "tools/call":
                tool_name = params.get("name", "")
                tool_args = params.get("arguments") or {}
                text = _handle_tool_call(tool_name, tool_args)
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": text}]},
                }
            else:
                if req_id is None:
                    continue
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                }
        except Exception as exc:  # noqa: BLE001
            if req_id is None:
                continue
            resp = {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32000, "message": str(exc)},
            }

        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
