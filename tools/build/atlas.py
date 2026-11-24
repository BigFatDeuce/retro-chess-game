"""Pack rendered animation frames into atlas pages + JSON metadata for Godot.

Format (one JSON per sprite set):
{
  "scale": 2.4, "fps": 24,
  "pages": ["name_0.png", ...],
  "anims": {
    "<anim>": {"frames": [{"p": page, "r": [x, y, w, h], "o": [ox, oy]}, ...],
               "events": {"<frame>": ["sound:jet_903", "impact", "end"]},
               "loop": bool}
  }
}
"o" is the symbol origin (feet / impact point) relative to the frame rect's top-left.
Identical frames are stored once.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

MAX_W = 4096
MAX_H = 4096
PAD = 2


def trim(arr: np.ndarray, origin):
    a = arr[:, :, 3]
    rows = np.where(a.max(axis=1) > 2)[0]
    cols = np.where(a.max(axis=0) > 2)[0]
    if len(rows) == 0:
        return arr[:1, :1] * 0, (origin[0], origin[1])
    y0, y1 = rows[0], rows[-1] + 1
    x0, x1 = cols[0], cols[-1] + 1
    return arr[y0:y1, x0:x1], (float(origin[0] - x0), float(origin[1] - y0))


class AtlasBuilder:
    def __init__(self, name: str, out_dir: Path, scale: float, fps: float = 24.0, density: float = 1.5):
        self.name = name
        self.out = out_dir
        self.scale = scale
        self.fps = fps
        self.density = density
        self.frames = []  # (hash, img)
        self.hash_index = {}
        self.anims = {}

    def add_anim(self, key, frames, origin, events=None, loop=False):
        refs = []
        for f in frames:
            img, o = f if isinstance(f, tuple) else trim(f, origin)  # tuple = already trimmed (img, origin)
            h = hashlib.sha1(img.tobytes() + bytes(str(img.shape), "ascii")).hexdigest()
            if h not in self.hash_index:
                self.hash_index[h] = len(self.frames)
                self.frames.append(img)
            refs.append((self.hash_index[h], o))
        ev = {}
        for fi, kind, data in events or []:
            fi = min(fi, len(frames) - 1)
            tag = kind if data in (None, "") or kind in ("end",) else f"{kind}:{data}"
            ev.setdefault(str(fi), []).append(tag)
        self.anims[key] = {"refs": refs, "events": ev, "loop": loop}

    def save(self):
        self.out.mkdir(parents=True, exist_ok=True)
        order = sorted(range(len(self.frames)), key=lambda i: -self.frames[i].shape[0])
        pages = []
        placements = {}
        cur = None
        x = y = shelf_h = 0
        for i in order:
            h, w = self.frames[i].shape[:2]
            if cur is None or x + w + PAD > MAX_W:
                x = 0
                y += shelf_h + PAD
                shelf_h = 0
            if cur is None or y + h > MAX_H:
                cur = []
                pages.append(cur)
                x = y = shelf_h = 0
            cur.append((i, x, y))
            placements[i] = (len(pages) - 1, x, y, w, h)
            x += w + PAD
            shelf_h = max(shelf_h, h)
        page_files = []
        for pi, items in enumerate(pages):
            W = max(x0 + self.frames[i].shape[1] for i, x0, _ in items)
            H = max(y0 + self.frames[i].shape[0] for i, _, y0 in items)
            W = _pow2ish(W)
            H = _pow2ish(H)
            page = np.zeros((H, W, 4), np.uint8)
            for i, x0, y0 in items:
                f = self.frames[i]
                page[y0:y0 + f.shape[0], x0:x0 + f.shape[1]] = f
            fn = f"{self.name}_{pi}.png"
            Image.fromarray(page, "RGBA").save(self.out / fn, optimize=True)
            page_files.append(fn)
        anims = {}
        for key, a in self.anims.items():
            fl = []
            for fi, o in a["refs"]:
                p, x0, y0, w, h = placements[fi]
                fl.append({"p": p, "r": [x0, y0, w, h], "o": [round(o[0], 1), round(o[1], 1)]})
            anims[key] = {"frames": fl, "events": a["events"], "loop": a["loop"]}
        meta = {"scale": self.scale, "density": self.density, "fps": self.fps, "pages": page_files, "anims": anims}
        (self.out / f"{self.name}.json").write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
                                                    encoding="utf-8")
        return meta


def _pow2ish(v):
    # round up to a multiple of 4 (keeps textures compressible without wasting memory)
    return (v + 3) // 4 * 4
