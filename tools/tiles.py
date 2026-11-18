"""Ground tiles and decor objects of the local library (clips/gfx/g1.swf = grounds, o*.swf = objects),
rendered for the board. Diamond ground tiles (the library's isometric cells, 53x27 at scale 1) are unwarped
into square textures; painted grounds (large seamless bitmaps) are used as they are.

  python tools/tiles.py sheet <out.png> <sym> [<sym> ...]     unwarped previews, sym = g1_222, o1_57 ...
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "swf"))
import swf as S  # noqa: E402
import render as R  # noqa: E402

LIB_DIR = Path(os.environ.get("GAME_ASSETS_DIR",
                              os.path.expandvars(r"%LOCALAPPDATA%/Ankama/Retro/resources/app/retroclient")))
GFX = LIB_DIR / "clips" / "gfx"
_libs = {}


def library(stem):
    if stem not in _libs:
        lib = R.Library()
        lib.add(S.SWF(str(GFX / f"{stem}.swf")))
        _libs[stem] = lib
    return _libs[stem]


def render_tile(sym: str, scale: float, frame: int = 0, supersample: int = 3):
    """Returns (rgba array cropped to the drawing, origin (x, y) inside it)."""
    stem, sid = sym.split("_", 1)
    lib = library(stem)
    size = int(1400 * scale / 2.4) + 400
    ra = R.render_symbol(lib, sid, R.Appearance(colors={}), scale=scale, canvas_size=(size, size),
                         origin=(size // 2, size // 2), max_frames=frame + 1, supersample=supersample)
    if not ra.frames:
        return None, None
    fr, org, _ = R.crop_frames([ra.frames[min(frame, len(ra.frames) - 1)]], ra.origin, pad=0)
    return fr[0], org


def unwarp_diamond(img: np.ndarray, out_px: int = 256) -> Image.Image:
    """An isometric diamond (corners at mid-edges of its bounding box) -> a square seen from above."""
    a = img[:, :, 3]
    rows, cols = np.where(a.max(axis=1) > 128)[0], np.where(a.max(axis=0) > 128)[0]
    h, w = rows[-1] - rows[0] + 1, cols[-1] - cols[0] + 1
    x0, y0 = cols[0], rows[0]
    src = Image.fromarray(img)
    # square (u, v) in [0,1]: u along the top-left -> top-right... map the square corners to the diamond:
    # (0,0)->left corner, (1,0)->top corner, (1,1)->right corner, (0,1)->bottom corner
    # affine inverse: x = x0 + w/2*(u + v), y = y0 + h/2*(1 - u + v)
    s = out_px
    coeffs = (w / 2 / s, w / 2 / s, x0, -h / 2 / s, h / 2 / s, y0 + h / 2)
    sq = src.transform((s, s), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    return sq


def sheet(out, syms, cell=200):
    cols = min(8, len(syms))
    rows = (len(syms) + cols - 1) // cols
    img = Image.new("RGB", (cols * cell, rows * (cell + 24)), (40, 44, 52))
    d = ImageDraw.Draw(img)
    for i, sym in enumerate(syms):
        arr, _ = render_tile(sym, 2.4)
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        if arr is not None and arr.shape[0] > 4:
            sq = unwarp_diamond(arr, cell - 10)
            img.paste(sq.convert("RGB"), (x + 5, y + 5), sq)
        d.text((x + 6, y + cell + 4), sym, fill=(230, 220, 200))
    img.save(out)
    print("saved", out)


if __name__ == "__main__":
    if sys.argv[1] == "sheet":
        sheet(sys.argv[2], sys.argv[3:])
