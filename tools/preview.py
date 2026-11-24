"""Renders local-library creatures at a common scale for side-by-side comparison.

Usage:
  python tools/preview.py sheet <out.png> <spec> [<spec> ...]      static contact sheet
  python tools/preview.py gif <out_dir> <spec> [<spec> ...]        animated previews (static + attack)
A spec is  gfx[:c1,c2,c3][@anim][=label]  e.g. 1340:6070879,-1,-1@anim2=Dragoss_blanc
Colours come from the creature data (-1 keeps the sprite default).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "swf"))
import swf as S  # noqa: E402
import render as R  # noqa: E402

LIB_DIR = Path(os.environ.get("GAME_ASSETS_DIR",
                              os.path.expandvars(r"%LOCALAPPDATA%/Ankama/Retro/resources/app/retroclient")))
SPRITES = LIB_DIR / "clips" / "sprites"
SCALE = 2.0
CANVAS = (900, 900)
ORIGIN = (450, 680)
BG = (52, 56, 64, 255)


def parse(spec):
    label = None
    if "=" in spec:
        spec, label = spec.split("=", 1)
    anim = None
    if "@" in spec:
        spec, anim = spec.split("@", 1)
    colors = {}
    if ":" in spec:
        spec, cs = spec.split(":", 1)
        for i, v in enumerate(cs.split(",")):
            if v and int(v) >= 0:
                colors[i + 1] = int(v)
    return int(spec), colors, anim, label or spec


def library(gfx):
    lib = R.Library()
    lib.add(S.SWF(str(SPRITES / f"{gfx}.swf")))
    return lib


def render(gfx, colors, symbol, max_frames=1, scale=SCALE):
    lib = library(gfx)
    exports = lib.swfs[0].exports
    if symbol not in exports:
        alt = [s for s in exports if s.startswith(symbol.rstrip("RL")) and s.endswith(symbol[-1])]
        if not alt:
            return None
        symbol = alt[0]
    ra = R.render_symbol(lib, symbol, R.Appearance(colors=colors), scale=scale, canvas_size=CANVAS,
                         origin=ORIGIN, max_frames=max_frames, supersample=2)
    return ra


def font(sz):
    for f in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        if Path(f).exists():
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def sheet(out, specs, cell=(220, 300)):
    cols = min(8, len(specs))
    rows = (len(specs) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell[0], rows * cell[1]), BG)
    d = ImageDraw.Draw(img)
    f = font(14)
    for i, spec in enumerate(specs):
        gfx, colors, anim, label = parse(spec)
        ra = render(gfx, colors, "staticR")
        x, y = (i % cols) * cell[0], (i // cols) * cell[1]
        d.rectangle([x + 4, y + 4, x + cell[0] - 4, y + cell[1] - 4], outline=(80, 86, 96, 255))
        # ground line at the same height for every creature: sizes are comparable
        gy = y + cell[1] - 46
        d.line([x + 10, gy, x + cell[0] - 10, gy], fill=(90, 96, 106, 255))
        if ra is not None and ra.frames:
            frames, (ox, oy), _ = R.crop_frames(ra.frames[:1], ra.origin)
            fr = Image.fromarray(frames[0])
            # same scale for everyone; the sprite origin (feet) sits on the ground line
            fit = min(1.0, (cell[0] - 12) / fr.width, (gy - y - 8) / max(1, oy))
            if fit < 1.0:
                fr = fr.resize((max(1, int(fr.width * fit)), max(1, int(fr.height * fit))), Image.LANCZOS)
                ox, oy = ox * fit, oy * fit
            px = int(x + cell[0] / 2 - ox)
            py = int(gy - oy)
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            layer.paste(fr, (px, py))
            img.alpha_composite(layer)
        d.text((x + 10, y + cell[1] - 40), label.replace("_", " ")[:28], fill=(235, 225, 200, 255), font=f)
        d.text((x + 10, y + cell[1] - 22), f"gfx {gfx}", fill=(150, 156, 166, 255), font=font(12))
    img.save(out)
    print("saved", out)


def crop_union(frames, pad=4):
    x0 = y0 = 10 ** 9
    x1 = y1 = 0
    for f in frames:
        a = f[:, :, 3]
        rr, cc = np.where(a.max(axis=1) > 0)[0], np.where(a.max(axis=0) > 0)[0]
        if len(rr):
            y0, y1 = min(y0, rr[0]), max(y1, rr[-1])
            x0, x1 = min(x0, cc[0]), max(x1, cc[-1])
    if x1 < x0:
        return frames
    return [f[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad] for f in frames]


def gif(out_dir, specs):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for spec in specs:
        gfx, colors, anim, label = parse(spec)
        seq = []
        for sym, n in (("staticR", 60), ((anim or "anim0") + "R", 240), ("hitR", 60), ("dieR", 120)):
            ra = render(gfx, colors, sym, max_frames=n, scale=1.2)
            if ra is None:
                continue
            fr = ra.frames[::2]  # 60 fps source -> 30 fps preview
            seq += fr
        if not seq:
            print("nothing for", spec)
            continue
        seq = crop_union(seq)
        h = max(f.shape[0] for f in seq)
        w = max(f.shape[1] for f in seq)
        ims = []
        for f in seq:
            im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            im.alpha_composite(Image.fromarray(f), ((w - f.shape[1]) // 2, h - f.shape[0]))
            ims.append(im)
        p = out_dir / f"{label}.webp"
        ims[0].save(p, save_all=True, append_images=ims[1:], duration=33, loop=0, lossless=False, quality=80)
        print("saved", p, len(ims), "frames")


if __name__ == "__main__":
    mode, out, *specs = sys.argv[1:]
    (sheet if mode == "sheet" else gif)(out, specs)
