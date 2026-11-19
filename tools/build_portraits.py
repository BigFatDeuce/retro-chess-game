"""HD portraits of the creatures used as avatars (profiles, opponents): the first idle frame of each creature,
rendered straight from the library's vector drawings at the size the menus show it (never cut out of the
game atlases, which are baked for the board and look soft once enlarged).

Writes game/assets/gen/portraits/<id>.png (512 x 512, creature centred, transparent background).
Ids: "<side>_<role>" (game/data/pieces.json) and the ambient creatures (game/data/critters.json).

With --art, renders instead the creature's large illustration (clips/artworks/big/<gfx>.swf, a drawn pose made
for illustrations) to game/assets/gen/art/<id>.png, ART px on its larger side: the opponents' cards and the end
of game screens show it. Creatures recoloured by a palette (the kings) keep their portrait: the illustration
does not carry the palette.
With --npc, renders the profiles' portraits: the characters of game/data/avatars.json (non player characters of
the library, from their illustration), framed as a bust (head, shoulders, upper body: a tall full-length drawing is
cut around the waist, a wide one around the head) to game/assets/gen/portraits/npc_<gfx>.png, SIZE px square, and
their whole figure to game/assets/gen/art/npc_<gfx>.png (NPC_ART px on its larger side) for the large pictures.
Usage: python build_portraits.py [--art | --npc] [id ...]
"""
import json
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

import build_pieces as B

SIZE = 512
FILL = 0.9  # the creature's larger side, as a share of the portrait
ART = 1200  # larger side of an illustration
NPC_ART = 900  # larger side of a profile character's full figure (shown at most ~470 layout px tall)


def defs():
    out = {}
    d = B.jload(B.DATA / "pieces.json")
    for side, roles in d["sides"].items():
        for role, p in roles.items():
            out[f"{side}_{role}"] = p
    for k, p in B.jload(B.DATA / "critters.json")["critters"].items():
        out[k] = p
    return out


def bbox(frame):
    a = frame[:, :, 3]
    rows, cols = np.where(a.max(axis=1) > 8)[0], np.where(a.max(axis=0) > 8)[0]
    if not len(rows):
        return None
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def job(args):
    key, p = args
    lib = B.library(B.CLIPS / "sprites" / f"{p['gfx']}.swf")
    exports = lib.swfs[0].exports
    sym = B.resolve(exports, "static", "R") or B.resolve(exports, "walk", "R")
    if not sym:
        return f"{key}: pas d'animation de repos"
    app = B.appearance(p, lib)
    # measure at a small scale, then render at the scale that fills the portrait
    probe = B.render_anim(lib, sym, app, 2.0, max_frames=1, supersample=1)
    bb = bbox(probe.frames[0])
    if bb is None:
        return f"{key}: dessin vide"
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    scale = 2.0 * SIZE * FILL / max(w, h)
    ra = B.render_anim(lib, sym, app, scale, max_frames=1, supersample=4)
    f = ra.frames[0]
    bb = bbox(f)
    img = Image.fromarray(f).crop(bb)
    k = SIZE * FILL / max(img.size)
    if abs(k - 1.0) > 0.02:
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, ((SIZE - img.width) // 2, (SIZE - img.height) // 2), img)
    dst = B.GEN / "portraits" / f"{key}.png"
    out.save(dst)
    return f"{key}: {img.width}x{img.height} (échelle {scale:.1f})"


def job_art(args):
    key, p = args
    if p.get("colors") or p.get("accessories"):
        return f"{key}: recolorée ou habillée, garde son portrait"
    src = B.CLIPS / "artworks" / "big" / f"{p['gfx']}.swf"
    if not src.exists():
        return f"{key}: pas d'illustration"
    lib = B.library(src)
    root = (lib.swfs[0], 0)
    # the illustration's extent at scale 1, then a canvas fitted to it at the final scale (small drawings get
    # scaled a lot: a growing canvas would not catch up)
    probe = B.R.render_symbol(lib, root, None, scale=1.0, canvas_size=(1600, 1600), origin=(800, 800), max_frames=1)
    bb = bbox(probe.frames[0])
    if bb is None:
        return f"{key}: illustration vide"
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    scale = ART / max(w, h)
    pad = 24
    ra = B.R.render_symbol(lib, root, None, scale=scale, max_frames=1, supersample=3,
                           canvas_size=(int(w * scale) + 2 * pad, int(h * scale) + 2 * pad),
                           origin=(int((800 - bb[0]) * scale) + pad, int((800 - bb[1]) * scale) + pad))
    f = ra.frames[0]
    img = Image.fromarray(f).crop(bbox(f))
    k = ART / max(img.size)
    if abs(k - 1.0) > 0.01:
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    dst = B.GEN / "art" / f"{key}.png"
    img.save(dst, optimize=True)
    return f"{key}: {img.width}x{img.height}"


def render_art(gfx, longest):
    """The illustration clips/artworks/big/<gfx>.swf, `longest` px on its larger side, cropped to the drawing."""
    lib = B.library(B.CLIPS / "artworks" / "big" / f"{gfx}.swf")
    root = (lib.swfs[0], 0)
    probe = B.R.render_symbol(lib, root, None, scale=1.0, canvas_size=(1600, 1600), origin=(800, 800), max_frames=1)
    bb = bbox(probe.frames[0])
    if bb is None:
        return None
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    scale = longest / max(w, h)
    pad = 24
    ra = B.R.render_symbol(lib, root, None, scale=scale, max_frames=1, supersample=3,
                           canvas_size=(int(w * scale) + 2 * pad, int(h * scale) + 2 * pad),
                           origin=(int((800 - bb[0]) * scale) + pad, int((800 - bb[1]) * scale) + pad))
    f = ra.frames[0]
    return Image.fromarray(f).crop(bbox(f))


def job_npc(gfx):
    img = render_art(gfx, 1500)
    if img is None:
        return f"npc_{gfx}: illustration vide"
    w, h = img.size
    # a square from the top of the drawing: the whole width, or the top 62 % of a tall drawing, never more than
    # the drawing's height (a wide drawing is cut around the head)
    side = min(max(w * 1.08, h * 0.7), h * 1.08)
    side = max(side, min(w, h))
    side = int(min(side, max(w, h)))
    a = np.asarray(img)[:, :, 3].astype(np.float64)
    band = a[: max(1, int(side * 0.5))]
    cols = band.sum(axis=0)
    cx = float((cols * np.arange(w)).sum() / max(cols.sum(), 1.0))
    top = -int(side * 0.06)
    left = int(round(cx - side / 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, (-left, -top), img)
    canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    canvas.save(B.GEN / "portraits" / f"npc_{gfx}.png", optimize=True)
    # the whole figure too, head to feet, for the large pictures (end of an online game): the bust is for medallions
    k = NPC_ART / max(w, h)
    full = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS) if k < 1 else img
    clean = Image.new("RGBA", full.size)
    clean.paste(full)
    # drawn as a bust (a straight cut across the bottom): the cut fades out, so it never reads as a cropped picture
    arr = np.asarray(clean).copy()
    fh = arr.shape[0]
    if (arr[fh - 3:, :, 3] > 128).mean(axis=1).max() > 0.2:
        n = int(fh * 0.16)
        t = np.linspace(1.0, 0.0, n)
        ramp = t * t * (3 - 2 * t)
        arr[fh - n:, :, 3] = (arr[fh - n:, :, 3].astype(np.float64) * ramp[:, None]).astype(np.uint8)
        clean = Image.fromarray(arr, "RGBA")
    (B.GEN / "art").mkdir(parents=True, exist_ok=True)
    clean.save(B.GEN / "art" / f"npc_{gfx}.png", optimize=True)
    return f"npc_{gfx}: {w}x{h} -> buste {side}, en pied {full.size[0]}x{full.size[1]}"


def main():
    args = sys.argv[1:]
    art = "--art" in args
    only = [a for a in args if not a.startswith("--")]
    if "--npc" in args:
        (B.GEN / "portraits").mkdir(parents=True, exist_ok=True)
        ids = [int(g) for g in B.jload(B.DATA / "avatars.json")["avatars"] if not only or f"npc_{g}" in only]
        with ProcessPoolExecutor(4) as ex:
            for r in ex.map(job_npc, ids):
                print(r, flush=True)
        return
    (B.GEN / ("art" if art else "portraits")).mkdir(parents=True, exist_ok=True)
    jobs = [(k, p) for k, p in defs().items() if not only or k in only]
    with ProcessPoolExecutor(5) as ex:
        for r in ex.map(job_art if art else job, jobs):
            print(r, flush=True)


if __name__ == "__main__":
    main()
