"""Download real 1K CC0 PBR maps (Diffuse, Rough, nor_gl) from Poly Haven for the Abyss Monster.

Includes deterministic procedural PNG fallback generation if offline or if any file fails.
Records exact URLs and CC0 license metadata in textures/monster/cc0_sources.json.
"""

from __future__ import annotations

import json
import math
import struct
import urllib.request
import zlib
from pathlib import Path
from typing import Any, Dict, List, Tuple

OUT_DIR = Path(r"C:\Users\Usuario\.gemini\antigravity\scratch\project_primalhunt\textures\monster")
OUT_DIR.mkdir(parents=True, exist_ok=True)
HEADERS = {"User-Agent": "PrimalHuntBlenderPipeline/1.0"}

ASSETS: List[Tuple[str, str]] = [
    ("cliff_side", "Obsidian-Basalt Carapace"),
    ("brown_leather", "Abyssal Leathery Hide"),
]
MAPS = [
    ("Diffuse", "diff"),
    ("Rough", "rough"),
    ("nor_gl", "nor_gl"),
]


def _write_png_rgb(path: Path, width: int, height: int, rows_bytes: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", crc)

    raw = b"".join(b"\x00" + rows_bytes[y * width * 3 : (y + 1) * width * 3] for y in range(height))
    ihdr = struct.pack("!IIBBBBB", width, height, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw, level=6)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    path.write_bytes(png)


def _generate_procedural_fallback(asset_id: str, map_suffix: str, dst: Path) -> Path:
    """Deterministic 256x256 PNG fallback if Poly Haven is unreachable."""
    png_path = dst.with_suffix(".png")
    w = h = 256
    buf = bytearray(w * h * 3)
    for y in range(h):
        for x in range(w):
            u, v = x / w, y / h
            n1 = math.sin(u * 2 * math.pi * 6.0) * math.cos(v * 2 * math.pi * 6.0)
            n2 = math.sin((u * 14.0 + v * 9.0) * math.pi) * math.cos((v * 17.0 - u * 5.0) * math.pi)
            h_val = 0.5 + 0.3 * n1 + 0.2 * n2
            idx = (y * w + x) * 3
            if map_suffix == "diff":
                if asset_id == "cliff_side":
                    c = int(max(18, min(140, 65 + 40 * h_val)))
                    buf[idx : idx + 3] = bytes((c, int(c * 0.96), int(c * 1.04)))
                else:
                    c = int(max(15, min(120, 55 + 35 * h_val)))
                    buf[idx : idx + 3] = bytes((int(c * 1.05), int(c * 0.92), c))
            elif map_suffix == "rough":
                val = int(max(40, min(230, (145 if asset_id == "cliff_side" else 130) + 55 * (h_val - 0.5))))
                buf[idx : idx + 3] = bytes((val, val, val))
            else:
                gx = math.cos(u * 2 * math.pi * 6.0) * 0.25 + math.cos((u * 14.0 + v * 9.0) * math.pi) * 0.15
                gy = math.sin(v * 2 * math.pi * 6.0) * 0.25 + math.sin((v * 17.0 - u * 5.0) * math.pi) * 0.15
                nx = int(max(0, min(255, 128 + gx * 90)))
                ny = int(max(0, min(255, 128 + gy * 90)))
                buf[idx : idx + 3] = bytes((nx, ny, 235))
    _write_png_rgb(png_path, w, h, bytes(buf))
    return png_path


def _pick_1k_entry(map_block: Dict[str, Any]) -> Tuple[str, str]:
    res_block = map_block.get("1k") or map_block.get("2k") or {}
    for fmt in ("jpg", "png"):
        if fmt in res_block and isinstance(res_block[fmt], dict) and "url" in res_block[fmt]:
            return res_block[fmt]["url"], fmt
    raise ValueError("No jpg or png URL found in 1k/2k block")


def main() -> None:
    sources_record: Dict[str, Any] = {
        "license": "CC0 1.0 Universal (Poly Haven)",
        "assets": {},
    }

    for asset_id, usage in ASSETS:
        api_url = f"https://api.polyhaven.com/files/{asset_id}"
        asset_rec: Dict[str, Any] = {
            "usage": usage,
            "apiUrl": api_url,
            "polyhavenPage": f"https://polyhaven.com/a/{asset_id}",
            "license": "CC0",
            "maps": {},
        }
        try:
            req = urllib.request.Request(api_url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=12) as resp:
                files_json = json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            files_json = None
            asset_rec["apiError"] = str(exc)

        for ph_key, suffix in MAPS:
            fallback_flag = False
            url_used = None
            out_file = OUT_DIR / f"{asset_id}_{suffix}_1k.jpg"
            try:
                if files_json is None or ph_key not in files_json:
                    raise ValueError(f"Missing {ph_key} in Poly Haven response for {asset_id}")
                dl_url, fmt = _pick_1k_entry(files_json[ph_key])
                url_used = dl_url
                out_file = OUT_DIR / f"{asset_id}_{suffix}_1k.{fmt}"
                dl_req = urllib.request.Request(dl_url, headers=HEADERS)
                with urllib.request.urlopen(dl_req, timeout=20) as dl_resp:
                    data = dl_resp.read()
                if len(data) < 1024:
                    raise ValueError(f"Downloaded file too small ({len(data)} bytes)")
                out_file.write_bytes(data)
            except Exception as exc:
                fallback_flag = True
                out_file = _generate_procedural_fallback(asset_id, suffix, out_file)
                url_used = f"fallback:{exc}"

            asset_rec["maps"][ph_key] = {
                "file": str(out_file),
                "url": url_used,
                "fallback": fallback_flag,
                "bytes": out_file.stat().st_size,
            }

        sources_record["assets"][asset_id] = asset_rec

    manifest_path = OUT_DIR / "cc0_sources.json"
    manifest_path.write_text(json.dumps(sources_record, indent=2), encoding="utf-8")
    print(json.dumps(sources_record, indent=2))


if __name__ == "__main__":
    main()
