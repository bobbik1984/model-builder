"""Validate and summarize a Model Builder context packet.

Usage:
    python tools/check_packet.py                 # newest export (sessions/latest.json pointer)
    python tools/check_packet.py path/to/pk_....json

Checks:
  * JSON Schema (protocol/schemas/context_packet.schema.json), if `jsonschema` is installed
  * normals are unit length, pins have entity paths ending in the hit entity
  * the viewport image exists and its pixel size equals camera.viewport_px
Prints a pin table and pairwise distances (meters) so a human or an agent can
sanity-check the numbers. Exit code 0 = no problems, 1 = problems found.
"""

from __future__ import annotations

import itertools
import json
import math
import os
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCHEMA = REPO / "protocol" / "schemas" / "context_packet.schema.json"


def sessions_root() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "ModelBuilder" / "sessions"


def find_packet(arg: str | None) -> Path:
    if arg:
        return Path(arg)
    pointer = sessions_root() / "latest.json"
    if not pointer.exists():
        sys.exit(f"No packet given and no pointer at {pointer}. Export from SketchUp first.")
    return Path(json.loads(pointer.read_text(encoding="utf-8"))["packet_path"])


def png_size(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as f:
        head = f.read(24)
    if head[1:4] != b"PNG":
        return None
    return struct.unpack(">II", head[16:24])


def session_dir_for(packet_path: Path) -> Path:
    # packets live in <session>/packets/ ; latest.json lives in <session>/
    return packet_path.parent.parent if packet_path.parent.name == "packets" else packet_path.parent


def main() -> int:
    # Notes/warnings contain non-ASCII (中文, °); Windows consoles default to a code page.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    path = find_packet(sys.argv[1] if len(sys.argv) > 1 else None)
    packet = json.loads(path.read_text(encoding="utf-8"))
    problems: list[str] = []
    print(f"Packet: {path}")

    try:
        import jsonschema

        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        validator = jsonschema.Draft202012Validator(schema)
        errors = sorted(validator.iter_errors(packet), key=lambda e: list(e.path))
        for e in errors:
            problems.append(f"schema: {'/'.join(map(str, e.path)) or '<root>'}: {e.message}")
        print(f"Schema: {'OK' if not errors else f'{len(errors)} error(s)'}")
    except ImportError:
        print("Schema: skipped (pip install jsonschema)")

    cam = packet.get("camera", {})
    vp = cam.get("viewport_px")
    print(
        f"Host: {packet['host']['app']} {packet['host']['version']}  model units: {packet['host'].get('model_units')}"
        f"  model: {packet.get('model', {}).get('name') or '(untitled)'}"
    )
    print(
        f"Camera: eye {cam.get('eye')} target {cam.get('target')} "
        f"{'perspective fov ' + str(cam.get('fov_deg')) + ' ' + str(cam.get('fov_axis', '')) if cam.get('perspective') else 'parallel h=' + str(cam.get('ortho_height_m'))}"
        f"  viewport {vp}"
    )

    sdir = session_dir_for(path)
    for v in packet.get("views", []):
        img = sdir / v["path"]
        if not img.exists():
            problems.append(f"view image missing: {img}")
            continue
        size = png_size(img)
        status = "OK" if size and vp and list(size) == list(vp) else "MISMATCH"
        if status != "OK":
            problems.append(f"image {img.name} is {size}, viewport_px is {vp}")
        print(f"View: {v['kind']} {img}  {size}  {status}")

    pins = packet.get("pins", [])
    print(f"\nPins: {len(pins)}")
    for p in pins:
        n = p.get("normal")
        if n is not None and abs(math.hypot(*n) - 1) > 1e-4:
            problems.append(f"{p['id']}: normal not unit length {n}")
        ent = p.get("entity") or {}
        detail = p.get("path_detail") or []
        if ent.get("path") and ent["path"][-1] != ent.get("ref"):
            problems.append(f"{p['id']}: entity.path does not end with entity.ref")
        if [d["ref"] for d in detail] != ent.get("path", []):
            problems.append(f"{p['id']}: path_detail refs differ from entity.path")
        names = " > ".join(
            f"{d['kind']}:{d.get('name') or d.get('definition') or d['ref']}" for d in detail
        )
        fmt = lambda v: "[" + ", ".join(f"{c:.4f}" for c in v) + "]" if v else "-"  # noqa: E731
        print(
            f"  {p['id']:>3}  point {fmt(p['point'])}  normal {fmt(n)}  snap {p.get('snap')}"
            f"  front {p.get('front_facing')}  px {p.get('screen_px')} in_frame {p.get('in_frame')}"
            f"  visible {p.get('visible')}"
        )
        print(f"       {names}")
        c = (p.get("instance") or {}).get("contents")
        if c:
            tags = ", ".join(f"{t['name']} x{t['count']}" for t in c.get("tags", []))
            print(f"       contains {c['faces']} faces, {c['instances']} instances{'; tags ' + tags if tags else ''}")

    for p in pins:
        if p.get("note"):
            print(f"  {p['id']} note: {p['note']}")

    strokes = packet.get("strokes", [])
    if strokes:
        print(f"\nOutlines: {len(strokes)}")
    for s in strokes:
        m = s.get("metrics", {})
        if len(s.get("world", [])) != len(s.get("screen_px", [])):
            problems.append(f"{s['id']}: world/screen_px length mismatch")
        size = f"area {m.get('area_m2')} m2, " if "area_m2" in m else ""
        print(f"  {s['id']:>3}  {s['kind']}  {len(s.get('world', []))} pts  {size}length {m.get('length_m')} m"
              f"  centroid {m.get('centroid')}  snaps {s.get('point_snaps')}")
        for n in s.get("hit_names", []):
            print(f"       touches {n}")
        if s.get("note"):
            print(f"       note: {s['note']}")

    refs = packet.get("references", [])
    if refs:
        print(f"\nReferences: {len(refs)}")
    for r in refs:
        if "file" not in r:
            print(f"  {r['id']} {r['kind']}: in the model {r.get('model_ref')} {r.get('name', '')}  note: {r.get('note', '')}")
            continue
        f = sdir / r["file"]
        ok = f.exists()
        if not ok:
            problems.append(f"reference file missing: {f}")
        print(f"  {r['id']} {r['kind']} {r.get('size_px', '')}: {f} {'OK' if ok else 'MISSING'}  note: {r.get('note', '')}")
        if r.get("preview"):
            pv = sdir / r["preview"]
            if not pv.exists():
                problems.append(f"reference preview missing: {pv}")
            print(f"     preview: {pv} {png_size(pv) if pv.exists() else 'MISSING'}")

    if packet.get("project_notes"):
        print(f"\nProject notes: {packet['project_notes']}")
    for c in packet.get("cad_imports", []):
        print(f"CAD import: {c['name']} rotation {c.get('rotation_z_deg')} deg, registration: {c['registration']}")
    if packet.get("warnings"):
        print("\nExport warnings (from the plugin; information, not packet errors):")
        for w in packet["warnings"]:
            print(f"  ! {w}")

    if packet.get("message"):
        print(f"\nTask: {packet['message']}  (lod {packet.get('lod')})")

    if len(pins) > 1:
        print("\nDistances (m):")
        for a, b in itertools.combinations(pins, 2):
            print(f"  {a['id']}-{b['id']}: {math.dist(a['point'], b['point']):.4f}")

    print()
    if problems:
        print("PROBLEMS:")
        for pr in problems:
            print(f"  - {pr}")
        return 1
    print("No problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
