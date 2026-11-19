"""Bakes the 12 chess pieces and their spell effects into animation atlases for Godot.

Reads game/data/pieces.json (composition) and the vector sprites of the local library
(assets de la bibliothèque locale, read only). Writes game/assets/gen/pieces/ and game/assets/gen/fx/.

Usage:  python tools/build_pieces.py [--workers N] [--density 1.5] [only ...]
  only = side_role keys (white_king ...) or fx ids (fx2008 ...)

Conventions (same atlas format as tools/build/atlas.py):
  - layout reference 2560x1440; a piece's "scale" is its on-screen scale on the front row of the board
  - textures are baked at scale x density (density 1.5 = sharp up to 4K)
  - 60 fps; events carry sound cues ("sound:<name>") and the clip's own "impact"/"end" markers
  - when the left view of a sprite is the exact mirror of its right view, only the right view is baked
    and the atlas says "mirror": the game flips it (measured: not the case for these sprites, both are baked)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "swf"))
sys.path.insert(0, str(ROOT / "tools" / "build"))
import swf as S  # noqa: E402
import render as R  # noqa: E402
from avm1 import ASObject  # noqa: E402
from atlas import AtlasBuilder, trim  # noqa: E402

LIB_DIR = Path(os.environ.get("GAME_ASSETS_DIR",
                              os.path.expandvars(r"%LOCALAPPDATA%/Ankama/Retro/resources/app/retroclient")))
CLIPS = LIB_DIR / "clips"
DATA = ROOT / "game" / "data"
GEN = ROOT / "game" / "assets" / "gen"
FPS = 60.0
SUPERSAMPLE = 4
MAX_FRAMES = 240


def library(path):
    lib = R.Library()
    lib.add(S.SWF(str(path)))
    return lib


def appearance(p, lib):
    """The creature's look: its palette ("colors": zone -> colour) and what it wears ("accessories": slot -> item
    symbol "<type>_<gfx>", slot 1 the hat, 2 the cape), loaded from clips/items into `lib`. Most items export no
    symbol: the whole file is then the drawing (render.py centres it on the anchor)."""
    acc = {}
    for slot, sym in (p.get("accessories") or {}).items():
        t, g = sym.split("_")
        sw = lib.add(S.SWF(str(CLIPS / "items" / t / f"{g}.swf")))
        lib.exports.setdefault(sym, (sw, 0))
        acc[int(slot)] = sym
    return R.Appearance(colors={int(k): v for k, v in (p.get("colors") or {}).items()}, accessories=acc)


def render_anim(lib, symbol, app, scale, max_frames=MAX_FRAMES, params=None, canvas=(900, 900), origin=(450, 640),
                supersample=SUPERSAMPLE, attach=None):
    """Two passes: measure where the animation draws (growing the canvas when it touches an edge), then render
    only that area with supersampling (analytic AA alone leaves dark seams between adjacent shapes)."""
    orig = R.Player.__init__
    if params:
        def init(self, *a, **k):
            orig(self, *a, **k)
            self.root_params = params
        R.Player.__init__ = init
    try:
        for _ in range(4):
            probe = R.render_symbol(lib, symbol, app, scale=scale, canvas_size=canvas, origin=origin,
                                    max_frames=max_frames, supersample=1, attach=attach)
            x0, y0, x1, y1 = canvas[0], canvas[1], 0, 0
            for f in probe.frames:
                a = f[:, :, 3]
                rows, cols = np.where(a.max(axis=1) > 0)[0], np.where(a.max(axis=0) > 0)[0]
                if len(rows):
                    y0, y1 = min(y0, rows[0]), max(y1, rows[-1])
                    x0, x1 = min(x0, cols[0]), max(x1, cols[-1])
            if x1 < x0:
                return probe
            if x0 > 0 and y0 > 0 and x1 < canvas[0] - 1 and y1 < canvas[1] - 1:
                break
            gx = canvas[0] // 2 if (x0 == 0 or x1 >= canvas[0] - 1) else 0
            gy = canvas[1] // 2 if (y0 == 0 or y1 >= canvas[1] - 1) else 0
            canvas = (canvas[0] + 2 * gx, canvas[1] + 2 * gy)
            origin = (origin[0] + gx, origin[1] + gy)
        if supersample <= 1:
            return probe
        pad = 6
        x0, y0 = int(max(0, x0 - pad)), int(max(0, y0 - pad))
        x1, y1 = int(min(canvas[0], x1 + pad + 1)), int(min(canvas[1], y1 + pad + 1))
        ra = R.render_symbol(lib, symbol, app, scale=scale, canvas_size=(x1 - x0, y1 - y0),
                             origin=(origin[0] - x0, origin[1] - y0), max_frames=len(probe.frames),
                             supersample=supersample, attach=attach)
        if len(ra.frames) != len(probe.frames):
            return probe
        return ra
    finally:
        R.Player.__init__ = orig


def jload(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def piece_anims(p):
    """Animations the board asks of a piece, with the drawings it needs: the back view ("L") only where a piece
    can be seen from behind (walking away, attacking a piece further back); idle, hit, death, run and highlight
    are always shown facing the viewer (mirrored toward the side)."""
    if p.get("_critter"):  # ambient creatures: they wander every way, flee, and play their idle emote
        return {"static": ("R", "L"), "walk": ("R", "L"), "run": ("R", "L"), "bonus": ("R",)}
    out = {"static": ("R",), "walk": ("R", "L"), "run": ("R",), "hit": ("R",), "die": ("R",)}
    if p.get("highlight"):
        out.setdefault(p["highlight"], ("R",))
    for a in p.get("attacks", {}).values():
        out[a["anim"]] = ("R", "L")
    return out


DIE_MAX_S = 1.6  # the board fades a fallen piece out after this: later frames are never seen


def resolve(exports, anim, d):
    sym = anim + d
    if sym in exports:
        return sym
    alt = [s for s in exports if s.startswith(anim) and s.endswith(d)]
    return alt[0] if alt else None


def is_mirror(lib, exports, app, scale):
    """Left view == mirrored right view, on a few frames of the idle and of every other common animation."""
    for anim in ("static", "anim0", "hit"):
        r, l = resolve(exports, anim, "R"), resolve(exports, anim, "L")
        if not r or not l:
            continue
        canvas, origin = (700, 700), (350, 500)
        ra = R.render_symbol(lib, r, app, scale=scale, canvas_size=canvas, origin=origin, max_frames=30)
        la = R.render_symbol(lib, l, app, scale=scale, canvas_size=canvas, origin=origin, max_frames=30)
        if len(ra.frames) != len(la.frames):
            return False
        for i in range(0, len(ra.frames), 7):
            a = ra.frames[i][:, :, 3] > 40
            b = la.frames[i][:, :, 3] > 40
            # mirror b about the origin column 350: column x -> 700 - x
            fb = np.zeros_like(b)
            fb[:, 1:] = b[:, :0:-1]
            u = (a | fb).sum()
            if u and (a & fb).sum() / u < 0.97:
                return False
    return True


def set_suffix(density):
    """Two sets (as Retro Defenders, D105): "" = 4K (density 1.5), "_1x" = one texel per pixel at 2560x1440.
    Showing the 4K set shrunk 1.5x at 1440p and below blurs and shimmers; the game picks the set at launch."""
    return "" if density >= 1.5 else "_1x"


def job_piece(args):
    key, p, density = args
    out = GEN / (("critters" if p.get("_critter") else "pieces") + set_suffix(density))
    gfx = p["gfx"]
    lib = library(CLIPS / "sprites" / f"{gfx}.swf")
    exports = lib.swfs[0].exports
    app = appearance(p, lib)
    scale = float(p["scale"]) * density
    mirror = False  # measured: the left views of these sprites are drawn apart (IoU 0.4-0.7 against the mirrored right view)
    fps = float(lib.swfs[0].frame_rate) or FPS  # one rendered frame per frame of the clip
    ab = AtlasBuilder(key, out, scale, fps, density=density)
    canvas = (max(360, int(190 * scale)), max(360, int(170 * scale)))  # grows when a drawing touches an edge
    origin = (canvas[0] // 2, int(canvas[1] * 0.714))
    report = []
    for anim, dirs in piece_anims(p).items():
        for d in dirs:
            sym = resolve(exports, anim, d)
            if not sym:
                continue
            ra = render_anim(lib, sym, app, scale, canvas=canvas, origin=origin)
            n = len(ra.frames)
            while n > 1 and ra.frames[n - 1][:, :, 3].max() == 0:
                n -= 1
            if anim == "die":
                n = min(n, int(DIE_MAX_S * fps))
            ev = [e for e in ra.events if e[0] < n]
            ab.add_anim(f"{anim}_{d}", ra.frames[:n], ra.origin, ev, anim in ("static", "walk", "run"))
            if d == "R":
                report.append(f"{anim}:{n}" + ("*" if any(e[1] == "sound" for e in ev) else ""))
    meta = ab.save()
    meta["mirror"] = mirror
    meta["gfx"] = gfx
    (out / f"{key}.json").write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
                                                encoding="utf-8")
    return f"{key} gfx {gfx} miroir={mirror} pages={len(meta['pages'])} " + " ".join(report)


# --- spell effects -------------------------------------------------------------------------------------------------
# Each effect is the spell's own clip from the local library, baked the way the clip shows itself:
#   at_target  the clip is drawn around the target (it reads cellTo and falls / bursts there): origin = target
#   beam       the clip stretches from the caster to cellTo: baked for a reference distance along +x, the game
#              rotates it and scales its length
#   arc        projectile_arc: the "move" part is the projectile the client carries, an impact part bursts where
#              it lands
FX_REF_DIST = 300.0  # layout px at density 1 for beams


def job_fx(args):
    fx_id, spec, density = args
    s = S.SWF(str(CLIPS / "spells" / f"{fx_id}.swf"))
    lib = R.Library()
    lib.add(s)
    scale = float(spec["scale"]) * density
    mode = spec["mode"]
    out = GEN / ("fx" + set_suffix(density))
    ab = AtlasBuilder(f"fx{fx_id}", out, scale, float(s.frame_rate) or FPS, density=density)

    def prm(dx):
        return {"cellFrom": ASObject(x=0.0, y=0.0), "cellTo": ASObject(x=float(dx) / scale, y=0.0),
                "angle": 0.0, "level": 5.0}

    info = {"mode": mode}
    if mode in ("at_target", "beam"):
        dist = FX_REF_DIST * density
        canvas, origin = (int(dist + 1400), 1400), (600, 900)
        ra = render_anim(lib, (s, 0), None, scale, max_frames=150, params=prm(dist), canvas=canvas, origin=origin,
                         supersample=2)
        n = len(ra.frames)
        while n > 1 and ra.frames[n - 1][:, :, 3].max() == 0:
            n -= 1
        o = ra.origin if mode == "beam" else (ra.origin[0] + dist, ra.origin[1])
        ev = [e for e in ra.events if e[0] < n]
        ab.add_anim("play", ra.frames[:n], o, ev, False)
        info["impact"] = next((e[0] for e in ev if e[1] == "impact"), None)
        if mode == "beam":
            # the clip does not stop exactly at cellTo: measure how far it really reaches (widest frame, from the
            # caster) so the game can fit that reach to the distance of the target
            reach = 0.0
            for f in ra.frames[:n]:
                cols = np.where(f[:, :, 3].max(axis=0) > 40)[0]
                if len(cols):
                    reach = max(reach, float(cols[-1]) - ra.origin[0])
            info["ref_dist"] = round(reach / density, 1) if reach > 0 else FX_REF_DIST
            info["asked_dist"] = FX_REF_DIST
    elif mode == "arc":
        for part, key, loop in ((spec["flight"], "flight", True), (spec["impact"], "impact", False)):
            ra = render_anim(lib, (s, 0), R.Appearance(colors={}), scale, max_frames=150, params=prm(0),
                             canvas=(900, 900), origin=(450, 450), supersample=2, attach=part)
            n = len(ra.frames)
            while n > 1 and ra.frames[n - 1][:, :, 3].max() == 0:
                n -= 1
            ab.add_anim(key, ra.frames[:n], ra.origin, [e for e in ra.events if e[0] < n], loop)
    meta = ab.save()
    meta["fx"] = info
    (out / f"fx{fx_id}.json").write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
                                                encoding="utf-8")
    return f"fx{fx_id} {mode} " + " ".join(f"{k}:{len(v['frames'])}" for k, v in meta["anims"].items()) + f" {info}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=5)  # each worker holds a whole animation in memory
    ap.add_argument("--density", type=float, nargs="+", default=[1.5, 1.0])
    ap.add_argument("only", nargs="*")
    a = ap.parse_args()
    d = jload(DATA / "pieces.json")
    jobs = []
    for side, roles in d["sides"].items():
        for role, p in roles.items():
            key = f"{side}_{role}"
            if not a.only or key in a.only:
                jobs += [(key, p, dn) for dn in a.density]
    cr = jload(DATA / "critters.json")["critters"]
    for key, p in cr.items():
        if not a.only or key in a.only:
            jobs += [(key, dict(p, _critter=True), dn) for dn in a.density]
    fx_jobs = []
    for fx_id, spec in d.get("fx", {}).items():
        if fx_id.startswith("_"):
            continue
        if not a.only or f"fx{fx_id}" in a.only:
            fx_jobs += [(fx_id, spec, dn) for dn in a.density]
    for dn in a.density:
        (GEN / ("pieces" + set_suffix(dn))).mkdir(parents=True, exist_ok=True)
        (GEN / ("fx" + set_suffix(dn))).mkdir(parents=True, exist_ok=True)
        (GEN / ("critters" + set_suffix(dn))).mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(a.workers) as ex:
        futs = [ex.submit(job_fx, j) for j in fx_jobs] + [ex.submit(job_piece, j) for j in jobs]
        for f in futs:
            print(f.result(), flush=True)


if __name__ == "__main__":
    main()
