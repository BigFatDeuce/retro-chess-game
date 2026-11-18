"""Bakes the boards (environments) from the local library: square textures, ground, decor objects.

Reads game/data/boards.json. For each board writes game/assets/gen/boards{set}/<board>/ :
  light_<i>.png / dark_<i>.png   square textures (diamond ground tiles of the library unwarped to squares,
                                 tinted so the two colours of the chessboard read at a glance)
  ground.png                     the ground around the board (a painted ground, or a diamond tile unwarped)
  border.png                     the band framing the squares
  o_<sym>.png + decor.json       standing objects (trees, rocks...) with their foot point
Sets: "" = 4K (density 1.5), "_1x" = 2560x1440 (density 1.0), as the pieces.

Usage: python tools/build_boards.py [board ...]
"""
from __future__ import annotations

import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import tiles as T  # noqa: E402

DATA = ROOT / "game" / "data"
GEN = ROOT / "game" / "assets" / "gen"
DENSITIES = {1.5: "", 1.0: "_1x"}
SQUARE = 210.0  # front-row square width, layout px (BoardView.SQUARE)
CHAR_SCALE = 2.4  # objects are drawn at the creatures' scale in their world (54 px cell = 2.4 x 22.5)


def square_texture(sym, px, tint=None, inset=0.035):
    arr, _ = T.render_tile(sym, 6.0)
    sq = T.unwarp_diamond(arr, int(px / (1 - 2 * inset)) + 2)
    m = int(sq.width * inset)
    sq = sq.crop((m, m, sq.width - m, sq.height - m)).resize((px, px), Image.LANCZOS).convert("RGBA")
    if tint:
        sq = adjust(sq, tint)
    return sq


def adjust(img, t):
    """t = {"bright": 1.0, "sat": 1.0, "mul": [r, g, b]}"""
    rgb = img.convert("RGB")
    if "bright" in t:
        rgb = ImageEnhance.Brightness(rgb).enhance(t["bright"])
    if "sat" in t:
        rgb = ImageEnhance.Color(rgb).enhance(t["sat"])
    if "contrast" in t:
        rgb = ImageEnhance.Contrast(rgb).enhance(t["contrast"])
    a = np.asarray(rgb).astype(np.float32)
    if "mul" in t:
        a *= np.array(t["mul"], np.float32)[None, None, :]
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def pot(n):
    p = 1
    while p * 2 <= n * 1.5:
        p *= 2
    return p


def make_seamless(img: Image.Image, edge=0.22) -> Image.Image:
    """Removes the junction of a painting that does not quite wrap: blends it with a copy shifted by half its
    size (whose borders are the painting's continuous middle), the original in the centre, the shifted copy at
    the borders. No symmetry, unlike mirroring."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    rolled = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)

    def ramp(n):
        t = np.minimum(np.arange(n), np.arange(n)[::-1]) / (n * edge)
        t = np.clip(t, 0.0, 1.0)
        return t * t * (3 - 2 * t)
    m = (ramp(h)[:, None] * ramp(w)[None, :])[:, :, None]
    out = a * m + rolled * (1 - m)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), img.mode)


def ground_texture(sym, px, mirror=False):
    stem, sid = sym.split("_", 1)
    arr, _ = T.render_tile(sym, 3.0)
    a = arr[:, :, 3]
    # a painted ground is a rectangle (opaque corners); a diamond tile has transparent corners
    if (a > 200).mean() > 0.97:  # a painting fills its whole rectangle; a diamond leaves its corners empty
        img = Image.fromarray(arr).convert("RGBA")
        # the library's painted grounds are made to repeat: tiled as they are. Mirroring 2x2 (for a painting
        # that does not tile) shows symmetrical blocks, kept only on request
        img = img.crop((2, 2, img.width - 2, img.height - 2))
        if not mirror:
            img = make_seamless(img)
            # a power-of-two square: every mipmap level still wraps exactly (a 1024x671 texture's reduced
            # levels no longer did, which drew straight seams in the distance); the shader maps it to a square
            return img.resize((pot(px), pot(px)), Image.LANCZOS)
        # mirror 2x2 so any painting tiles seamlessly
        w, h = img.size
        big = Image.new("RGBA", (w * 2, h * 2))
        big.paste(img, (0, 0))
        big.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
        big.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
        big.paste(img.transpose(Image.ROTATE_180), (w, h))
        return big.resize((px, int(px * big.height / big.width)), Image.LANCZOS)
    return T.unwarp_diamond(arr, px).convert("RGBA")


# zones around the board, board coordinates (u across, v depth); the board with its frame is [-0.5, 8.5]
ZONES = {
    "back": (-7.0, 15.0, 9.3, 19.0),
    "left": (-7.5, -1.0, -1.6, 9.5),
    "right": (9.6, 16.0, -1.0, 9.5),
    "near_left": (-1.6, -0.75, -0.6, 9.0),
    "near_right": (8.75, 9.6, -0.6, 9.0),
    "front": (-7.0, 15.0, -1.6, -0.75),
}


def scatter(b):
    """Decor scattered by rules: {"syms": [...], "count": n, "zones": [...], "scale": [min, max], "gap": d,
    "flat": bool}. Positions are drawn once (seeded) at build time, kept apart, never on the board."""
    import random
    rng = random.Random(b.get("seed", 7))
    placed = [(float(d["u"]), float(d["v"]), 1.2) for d in b.get("decor", [])]
    flats = []  # things lying on the ground: no standing object over them either (it would hide them by half)
    out = []
    for rule in b.get("scatter", []):
        gap = float(rule.get("gap", 1.0))
        for _ in range(int(rule["count"])):
            for _try in range(60):
                z = ZONES[rng.choice(rule["zones"])]
                u = rng.uniform(z[0], z[1])
                v = rng.uniform(z[2], z[3])
                near = placed if rule.get("flat") else placed + flats
                if all((u - pu) ** 2 + (v - pv) ** 2 >= max(gap, pg) ** 2 for pu, pv, pg in near):
                    break
            else:
                continue
            lo, hi = rule.get("scale", [1.0, 1.0])
            sc = round(rng.uniform(lo, hi) * 10) / 10
            d = {"sym": rng.choice(rule["syms"]), "u": round(u, 2), "v": round(v, 2), "scale": sc,
                 "flip": rng.random() < 0.5}
            if rule.get("flat"):
                d["flat"] = True
                flats.append((u, v, gap))
            else:
                placed.append((u, v, gap))
            out.append(d)
    return out


def average_colours(out, meta):
    """Mean colour of the squares, frame and ground (hex): the game draws soft lines in them along the board's
    slanted edges where the graphics have no edge smoothing (browser)."""
    def avg(files):
        px = [Image.open(out / f).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0)) for f in files]
        return "%02x%02x%02x" % tuple(sum(c[i] for c in px) // len(px) for i in range(3))
    return {"light": avg(meta["light"]), "dark": avg(meta["dark"]), "border": avg([meta["border"]]),
            "ground": avg([meta["ground"]])}


def job(args):
    key, b, density = args
    out = GEN / ("boards" + DENSITIES[density]) / key
    out.mkdir(parents=True, exist_ok=True)
    px = int(SQUARE * density * 1.0)
    meta = {"density": density, "light": [], "dark": [], "decor": []}
    painted = float(b.get("square_repeat", 0.0))
    meta["square_repeat"] = painted
    for colour in ("light", "dark"):
        for i, sym in enumerate(b[colour]):
            if painted > 0:
                # a painted ground of the library, tiled seamlessly over `painted` squares
                img = ground_texture(sym, int(px * painted), b.get("square_mirror", False))
                if b.get(colour + "_tint"):
                    img = adjust(img, b[colour + "_tint"])
            else:
                img = square_texture(sym, px, b.get(colour + "_tint"))
            fn = f"{colour}_{i}.png"
            img.save(out / fn)
            meta[colour].append(fn)
    g = ground_texture(b["ground"], int(1024 * density), b.get("ground_mirror", False))
    if b.get("ground_tint"):
        g = adjust(g, b["ground_tint"])
    g.save(out / "ground.png")
    meta["ground"] = "ground.png"
    meta["ground_repeat"] = float(b.get("ground_repeat", 3.0))  # squares per texture repeat
    meta["ground_variation"] = float(b.get("ground_variation", 1.0))
    bd = ground_texture(b["border"], px) if b.get("border_painted") else square_texture(b["border"], px)
    if b.get("border_tint"):
        bd = adjust(bd, b["border_tint"])
    bd.save(out / "border.png")
    meta["border"] = "border.png"
    seen = {}
    for d in list(b.get("decor", [])) + scatter(b):
        sym = d["sym"]
        sc = float(d.get("scale", 1.0))
        k = f"{sym}@{sc}"
        if k not in seen:
            arr, org = T.render_tile(sym, CHAR_SCALE * density * sc * float(b.get("decor_scale", 1.0)))
            if arr is None:
                print("  objet vide", sym)
                continue
            fn = f"o_{sym}_{sc}.png"
            Image.fromarray(arr).save(out / fn)
            seen[k] = {"file": fn, "o": [round(float(org[0]), 1), round(float(org[1]), 1)]}
        meta["decor"].append(dict(d, **seen[k]))
    meta["avg"] = average_colours(out, meta)
    (out / "board.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    return f"{key}{DENSITIES[density]} : {len(meta['light'])}+{len(meta['dark'])} cases, {len(seen)} objets"


def main():
    boards = json.loads((DATA / "boards.json").read_text(encoding="utf-8"))["boards"]
    only = sys.argv[1:]
    jobs = [(k, b, d) for k, b in boards.items() if not only or k in only for d in DENSITIES]
    with ProcessPoolExecutor(4) as ex:
        for r in ex.map(job, jobs):
            print(r, flush=True)


if __name__ == "__main__":
    main()
