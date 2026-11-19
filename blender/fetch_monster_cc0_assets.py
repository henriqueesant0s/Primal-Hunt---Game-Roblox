"""Download verified CC0-1.0 Poly Haven PBR textures & Mesh2Motion Kaiju rig + 7 animations.

Records exact URLs, byte counts, and CC0 license metadata in textures/monster/cc0_sources.json.
"""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt")
TEX_DIR = ROOT_DIR / "textures" / "monster"
KAIJU_DIR = ROOT_DIR / "assets" / "cc0_kaiju"
TEX_DIR.mkdir(parents=True, exist_ok=True)
KAIJU_DIR.mkdir(parents=True, exist_ok=True)

HEADERS = {"User-Agent": "PrimalHuntBlenderPipeline/1.0"}

POLYHAVEN_ASSETS: List[Tuple[str, str]] = [
    ("cliff_side", "Obsidian-Basalt Carapace & Dorsal Plates"),
    ("brown_leather", "Abyssal Reptilian Hide Micro-Grain"),
]
POLYHAVEN_MAPS = [
    ("Diffuse", "diff"),
    ("Rough", "rough"),
    ("nor_gl", "nor_gl"),
]

KAIJU_BASE = "https://raw.githubusercontent.com/Mesh2Motion/mesh2motion-app/main/static/assets/kaiju"
KAIJU_FILES: List[Tuple[str, str, str]] = [
    ("model.glb", "model.glb", "Base 58-Bone Kaiju Rigged Mesh (CC0-1.0)"),
    ("animations/idle.glb", "idle.glb", "Monster_Idle Skeletal Animation"),
    ("animations/walk.glb", "walk.glb", "Monster_Walk Skeletal Animation"),
    ("animations/roar.glb", "roar.glb", "Monster_Roar Skeletal Animation"),
    ("animations/attack.glb", "attack.glb", "Monster_Attack Skeletal Animation"),
    ("animations/tail-attack.glb", "tail-attack.glb", "Monster_TailAttack Skeletal Animation"),
    ("animations/hit.glb", "hit.glb", "Monster_Hit Skeletal Animation"),
    ("animations/death.glb", "death.glb", "Monster_Death Skeletal Animation"),
]


def _download_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=25) as resp:
        data = resp.read()
    if len(data) < 512:
        raise ValueError(f"Downloaded payload too small ({len(data)} bytes) from {url}")
    return data


def _pick_1k_entry(map_block: Dict[str, Any]) -> Tuple[str, str]:
    res_block = map_block.get("1k") or map_block.get("2k") or {}
    for fmt in ("jpg", "png"):
        if fmt in res_block and isinstance(res_block[fmt], dict) and "url" in res_block[fmt]:
            return res_block[fmt]["url"], fmt
    raise ValueError("No jpg or png URL found in 1k/2k block")


def main() -> None:
    manifest_path = TEX_DIR / "cc0_sources.json"
    record: Dict[str, Any] = {
        "licenseSummary": "CC0 1.0 Universal (Poly Haven PBR Maps + Mesh2Motion Kaiju Rig & Motion Clips)",
        "polyhaven": {},
        "mesh2motionKaiju": {
            "repo": "https://github.com/Mesh2Motion/mesh2motion-app",
            "assetsRepoLicense": "CC0-1.0 (https://github.com/Mesh2Motion/mesh2motion-assets)",
            "files": {},
        },
    }

    for asset_id, usage in POLYHAVEN_ASSETS:
        api_url = f"https://api.polyhaven.com/files/{asset_id}"
        arec: Dict[str, Any] = {
            "usage": usage,
            "apiUrl": api_url,
            "polyhavenPage": f"https://polyhaven.com/a/{asset_id}",
            "license": "CC0 1.0",
            "maps": {},
        }
        files_json = None
        for _, suffix in POLYHAVEN_MAPS:
            existing = TEX_DIR / f"{asset_id}_{suffix}_1k.jpg"
            if not existing.exists() or existing.stat().st_size < 1024:
                if files_json is None:
                    files_json = json.loads(_download_bytes(api_url).decode("utf-8"))
                ph_key = next(k for k, s in POLYHAVEN_MAPS if s == suffix)
                dl_url, fmt = _pick_1k_entry(files_json[ph_key])
                existing = TEX_DIR / f"{asset_id}_{suffix}_1k.{fmt}"
                existing.write_bytes(_download_bytes(dl_url))
            arec["maps"][suffix] = {
                "file": str(existing),
                "bytes": existing.stat().st_size,
            }
        record["polyhaven"][asset_id] = arec

    for rel_url, local_name, desc in KAIJU_FILES:
        url = f"{KAIJU_BASE}/{rel_url}"
        dst = KAIJU_DIR / local_name
        data = _download_bytes(url)
        dst.write_bytes(data)
        record["mesh2motionKaiju"]["files"][local_name] = {
            "description": desc,
            "url": url,
            "file": str(dst),
            "bytes": len(data),
        }

    manifest_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
