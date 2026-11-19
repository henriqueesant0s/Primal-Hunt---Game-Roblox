"""Accurate chronological extractor for PRIMAL HUNT Luau scripts into ./roblox_scripts/.

Fixes parallel tool response indexing (`steps[idx + 1 + tc_pos]`) and assembles
sliced inspect payloads (MonsterAnimClient animClient + animTail, etc.), then replays
every successful multi_edit sequentially.
"""

from __future__ import annotations

import json
import os
import re
from typing import Dict

TRANSCRIPT = r"C:\Users\Usuario\.gemini\antigravity\brain\ab208d61-aaf3-4da6-93fd-78e81f4ae04f\.system_generated\logs\transcript_full.jsonl"
OUT_ROOT = r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt\roblox_scripts"


def normalize_path(raw: str) -> str:
    p = raw.strip()
    if p.startswith("game."):
        p = p[5:]
    # Unify ServerScriptService.Modules.DamageService if same or keep clear folder
    return p


def strip_line_numbers(text: str) -> str:
    lines = text.splitlines()
    while lines and (lines[0].startswith("Created At:") or lines[0].startswith("Completed At:")):
        lines.pop(0)
    out = []
    pat = re.compile(r"^\s*\d+→(.*)$")
    pat_colon = re.compile(r"^\s*\d+: (.*)$")
    for ln in lines:
        m = pat.match(ln)
        if m:
            out.append(m.group(1))
        else:
            mc = pat_colon.match(ln)
            out.append(mc.group(1) if mc else ln)
    return "\n".join(out) + ("\n" if out else "")


def load_step_payload(resp_text: str) -> str:
    m = re.search(r"file:///([^\s\]]+output\.txt)", resp_text)
    if m:
        fpath = m.group(1).replace("/", "\\")
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as fh:
                return fh.read()
    return resp_text


def main() -> None:
    with open(TRANSCRIPT, "r", encoding="utf-8") as fh:
        steps = [json.loads(ln) for ln in fh]

    scripts: Dict[str, str] = {}
    class_hints: Dict[str, str] = {}
    edits_replayed = 0
    misses = 0

    for idx, step in enumerate(steps):
        tcs = step.get("tool_calls") or []
        for tc_pos, tc in enumerate(tcs):
            if tc.get("name") != "call_mcp_tool":
                continue
            args = tc.get("args") or {}
            tname = args.get("ToolName")
            targs = args.get("Arguments") or {}

            resp_idx = idx + 1 + tc_pos
            if resp_idx >= len(steps):
                continue
            cand = steps[resp_idx]
            resp_content = cand.get("content") or ""
            resp_status = cand.get("status") or ""
            if "Error" in resp_status or resp_content.startswith("Encountered error") or "error:" in resp_content[:40].lower():
                continue

            if tname == "script_read" and targs.get("should_read_entire_file", True):
                tf = targs.get("target_file")
                if not tf:
                    continue
                np = normalize_path(tf)
                payload = load_step_payload(resp_content)
                if "→" in payload[:160]:
                    scripts[np] = strip_line_numbers(payload)

            elif tname == "multi_edit":
                fp = targs.get("file_path")
                if not fp:
                    continue
                np = normalize_path(fp)
                cn = targs.get("className")
                if cn:
                    class_hints[np] = cn
                if not ("Modified " in resp_content[:200] or "Created " in resp_content[:200]):
                    continue
                edits = targs.get("edits") or []
                cur = scripts.get(np, "")
                ok = True
                for ed in edits:
                    old_s = ed.get("old_string", "")
                    new_s = ed.get("new_string", "")
                    if old_s == "":
                        cur = new_s
                    else:
                        if old_s not in cur:
                            print(f"WARN edit miss on {np} step {idx}: {old_s[:50]!r}")
                            misses += 1
                            ok = False
                            break
                        if ed.get("replace_all"):
                            cur = cur.replace(old_s, new_s)
                        else:
                            cur = cur.replace(old_s, new_s, 1)
                if ok:
                    scripts[np] = cur
                    edits_replayed += 1

            elif tname == "execute_luau" and targs.get("datamodel_type") in ("Edit", None):
                payload = load_step_payload(resp_content)
                # Strip Created At / Completed At lines if offloaded JSON
                plines = [ln for ln in payload.splitlines() if not (ln.startswith("Created At:") or ln.startswith("Completed At:"))]
                clean_p = "\n".join(plines).strip()
                if clean_p.startswith("{"):
                    try:
                        parsed = json.loads(clean_p)
                        if isinstance(parsed, dict) and "faunaAnim" in parsed and "animClient" in parsed:
                            scripts["StarterPlayer.StarterPlayerScripts.FaunaAnimClient"] = strip_line_numbers(parsed["faunaAnim"])
                            class_hints["StarterPlayer.StarterPlayerScripts.FaunaAnimClient"] = "LocalScript"
                            scripts["StarterPlayer.StarterCharacterScripts.MonsterAnimClient"] = strip_line_numbers(parsed["animClient"])
                            class_hints["StarterPlayer.StarterCharacterScripts.MonsterAnimClient"] = "LocalScript"
                        if isinstance(parsed, dict) and "animTail" in parsed:
                            cur_anim = scripts.get("StarterPlayer.StarterCharacterScripts.MonsterAnimClient", "")
                            tail = strip_line_numbers(parsed["animTail"])
                            if cur_anim and "ShoulderUpLMotor = rot(18, -armFwd" not in cur_anim:
                                scripts["StarterPlayer.StarterCharacterScripts.MonsterAnimClient"] = cur_anim.rstrip("\n") + "\n" + tail
                    except Exception:
                        pass

    os.makedirs(OUT_ROOT, exist_ok=True)
    written = 0
    for np, src in sorted(scripts.items()):
        if not src.strip():
            continue
        parts = np.split(".")
        tail_lines = "\n".join(src.splitlines()[-10:])
        if np in class_hints:
            ch = class_hints[np]
            ext = ".server.luau" if ch == "Script" else ".client.luau" if ch == "LocalScript" else ".luau"
        elif "ReplicatedStorage" in parts[0] or "DamageService" in parts[-1] or "PreyManager" in parts[-1] or re.search(r"^\s*return\s+[A-Za-z_]\w*\s*$", tail_lines, re.MULTILINE):
            ext = ".luau"
        elif "StarterPlayerScripts" in parts or "StarterCharacterScripts" in parts or "Client" in parts[-1] or "HUD" in parts[-1] or "HorrorAtmosphere" in parts[-1] or "LobbyRoleSelector" in parts[-1] or "Controller" in parts[-1]:
            ext = ".client.luau"
        else:
            ext = ".server.luau"

        rel_dir = os.path.join(OUT_ROOT, *parts[:-1])
        os.makedirs(rel_dir, exist_ok=True)
        out_path = os.path.join(rel_dir, parts[-1] + ext)
        if os.path.exists(out_path):
            raise RuntimeError(f"Refusing to overwrite {out_path}")
        with open(out_path, "w", encoding="utf-8", newline="\n") as out_f:
            out_f.write(src)
        written += 1
        print(f"WROTE {np}{ext} ({len(src.splitlines())} lines)")

    print(f"DONE: {written} scripts written, {edits_replayed} edit batches replayed, {misses} misses.")


if __name__ == "__main__":
    main()
