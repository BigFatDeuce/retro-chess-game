"""Bakes the still-picture chess sets (Settings "piece_set"): "classic", Bonta against Brâkmar, and "staunton",
plain ivory and ebony Staunton pieces. For "classic": White is Bonta (angels: ivory,
sky blue, gold, feathered wings), black is Brâkmar (demons: charcoal, crimson, bat wings, horns).

    python tools/build_classic.py [--set classic|staunton|all] [--preview out.png]
        (with the python that has skia, like loading_runners.py)
    -> game/assets/gen/<set>/<side>_<role>.json + .png      (density 1.5, sharp up to 4K)
       game/assets/gen/<set>_1x/<side>_<role>.json + .png   (density 1.0)

The pictures come from one painted sheet, tools/art/classic_set.webp (transparent background, white row on top,
black row below, king queen rook bishop knight pawn from left to right). Touched up here:
    - the emblems on the banners: Bonta's pair of white wings, Brâkmar's pair of horns (city of the angels, of
      the demons) instead of the sheet's own marks;
    - Brâkmar's king and queen wear gold crowns, like Bonta's;
    - Brâkmar's queen has a demon's horns, so she does not look like her king.

"staunton" comes from tools/art/staunton_set.webp, same layout on a plain green background (keyed out here), used
as it is: its proportions are already a real set's, scaled so its king stands as tall as the classic one.

The pieces are still pictures: their animations (breathing, hop, lunge, hit, fall, cheer) are transforms of that
one picture, written into the atlas frames ("t": [degrees, scale x, scale y, dx, dy] around the feet, see
src/render/flash_sprite.gd). Same atlas format as the creatures otherwise (src/render/atlas.gd).
"""
from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path

import numpy as np
import skia
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "game" / "assets" / "gen"
SHEET = ROOT / "tools" / "art" / "classic_set.webp"
FPS = 60.0
SIDES = ("white", "black")
ROLES = ("king", "queen", "rook", "bishop", "knight", "pawn")
LAYOUT = 0.5      # layout px per sheet px ("classic"; "staunton" is matched to its king): the king stands ~205 layout px tall, like the creatures' tallest
# like a real set: the king the biggest (taller and broader), the queen next (taller); (width, height) factors
ROLE_SCALE = {"king": (1.2, 1.14), "queen": (1.04, 1.12)}
FOOT_K = 0.3      # the base's bottom ellipse: its half height over its half width, on the sheet's own view
SETS = {
    "classic": {"sheet": "classic_set.webp", "foot_k": 0.3},
    "staunton": {"sheet": "staunton_set.webp", "foot_k": 0.22, "key_green": True, "role_scale": {}},
}
OUTLINE = (24, 16, 20)
GOLD = [(0.0, (70, 46, 14)), (0.25, (148, 86, 18)), (0.5, (211, 141, 39)), (0.75, (238, 176, 53)),
        (1.0, (255, 230, 140))]


# --- the sheet ------------------------------------------------------------------------------------------------------

def _runs(v):
    out, start = [], None
    for i, x in enumerate(v):
        if x and start is None:
            start = i
        elif not x and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(v)))
    return out


def _boxes(alpha: np.ndarray) -> dict:
    """(side, role) -> (x0, y0, x1, y1) of every piece on the sheet."""
    on = alpha > 8
    out = {}
    rows = [r for r in _runs(on.any(1)) if r[1] - r[0] > 12]  # specks of the background ignored
    assert len(rows) == 2, rows
    for side, (y0, y1) in zip(SIDES, rows):
        cols = [c for c in _runs(on[y0:y1].any(0)) if c[1] - c[0] > 12]
        assert len(cols) == 6, cols
        for role, (x0, x1) in zip(ROLES, cols):
            ys = np.nonzero(on[y0:y1, x0:x1].any(1))[0]
            out[(side, role)] = (x0, y0 + ys[0], x1, y0 + ys[-1] + 1)
    return out


def _label(mask: np.ndarray):
    """The connected parts of `mask` (4-neighbours), as (ys, xs) arrays."""
    seen = np.zeros_like(mask, bool)
    H, W = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        ys, xs = [], []
        while q:
            y, x = q.popleft()
            ys.append(y)
            xs.append(x)
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        yield np.array(ys), np.array(xs)


def _grow(m: np.ndarray, n: int) -> np.ndarray:
    for _ in range(n):
        g = m.copy()
        g[1:] |= m[:-1]
        g[:-1] |= m[1:]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        m = g
    return m


def _lum(a):
    return 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]


# --- the emblems ----------------------------------------------------------------------------------------------------

def _p(points, close=True):
    p = skia.Path()
    p.moveTo(*points[0])
    for q in points[1:]:
        if len(q) == 4:
            p.quadTo(*q)
        else:
            p.lineTo(*q)
    if close:
        p.close()
    return p


def _wings(cv):
    """Bonta: a pair of white wings, in a 100 x 100 box."""
    for flip in (-1, 1):
        cv.save()
        cv.translate(50, 0)
        cv.scale(flip, 1)
        # the wing sweeps up and out from the middle, three feathers along its lower edge
        w = _p([(4, 62), (10, 30, 44, 14), (50, 30, 46, 42), (46, 50, 38, 52), (40, 62, 30, 62), (30, 72, 18, 70),
                (12, 76, 4, 62)])
        cv.drawPath(w, skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE), Style=skia.Paint.kStroke_Style,
                                  StrokeWidth=9, StrokeJoin=skia.Paint.kRound_Join))
        cv.drawPath(w, skia.Paint(AntiAlias=True, Color=skia.Color(250, 248, 238)))
        cv.drawPath(_p([(12, 52), (24, 36, 40, 26)], False),
                    skia.Paint(AntiAlias=True, Color=skia.Color(176, 196, 226), Style=skia.Paint.kStroke_Style,
                               StrokeWidth=4, StrokeCap=skia.Paint.kRound_Cap))
        cv.restore()


def _horns(cv):
    """Brâkmar: a demon's head, horned, with glowing eyes, in a 100 x 100 box."""
    line = skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE), Style=skia.Paint.kStroke_Style, StrokeWidth=9,
                      StrokeJoin=skia.Paint.kRound_Join)
    dark = skia.Paint(AntiAlias=True, Color=skia.Color(48, 40, 50))
    for flip in (-1, 1):
        cv.save()
        cv.translate(50, 0)
        cv.scale(flip, 1)
        h = _p([(10, 46), (30, 40, 34, 6), (40, 30, 26, 56)])
        cv.drawPath(h, line)
        cv.drawPath(h, skia.Paint(AntiAlias=True, Color=skia.Color(214, 204, 200)))
        cv.restore()
    head = _p([(50, 92), (22, 90, 22, 62), (24, 40, 50, 40), (76, 40, 78, 62), (78, 90, 50, 92)])
    cv.drawPath(head, line)
    cv.drawPath(head, dark)
    eye = skia.Paint(AntiAlias=True, Color=skia.Color(255, 214, 70))
    for flip in (-1, 1):
        cv.drawPath(_p([(50 + flip * 6, 66), (50 + flip * 18, 54), (50 + flip * 17, 64, 50 + flip * 6, 66)]), eye)


def _gold_paint(y0, y1):
    """A vertical gold gradient between y0 and y1 (the emblem box's units)."""
    return skia.Paint(AntiAlias=True, Shader=skia.GradientShader.MakeLinear(
        [(0, y0), (0, y1)], [skia.Color(255, 226, 120), skia.Color(238, 176, 53), skia.Color(170, 104, 22)]))


def _crown_wings(cv):
    """The kings: a gold crown between two gold wings, in a 100 x 100 box (both cities)."""
    line = skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE), Style=skia.Paint.kStroke_Style, StrokeWidth=8,
                      StrokeJoin=skia.Paint.kRound_Join)
    shine = skia.Paint(AntiAlias=True, Color=skia.Color(255, 244, 196), Style=skia.Paint.kStroke_Style,
                       StrokeWidth=3, StrokeCap=skia.Paint.kRound_Cap)
    for flip in (-1, 1):
        cv.save()
        cv.translate(50, 0)
        cv.scale(flip, 1)
        # a wing swept up and out behind the crown, three feathers along its lower edge
        w = _p([(16, 70), (22, 36, 48, 20), (52, 36, 47, 46), (47, 54, 40, 56), (41, 64, 33, 64), (33, 72, 25, 72),
                (20, 78, 16, 70)])
        cv.drawPath(w, line)
        cv.drawPath(w, _gold_paint(20, 78))
        cv.drawPath(_p([(22, 58), (30, 42, 42, 32)], False), shine)
        cv.restore()
    crown = _p([(30, 78), (27, 46), (39, 60), (50, 38), (61, 60), (73, 46), (70, 78)])
    cv.drawPath(crown, line)
    cv.drawPath(crown, _gold_paint(38, 80))
    cv.drawPath(_p([(33, 72), (67, 72)], False), shine)
    gem = skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE))
    for x, y, r in ((27, 45, 4.5), (50, 37, 5), (73, 45, 4.5)):
        cv.drawCircle(x, y, r + 2.5, gem)
        cv.drawCircle(x, y, r, _gold_paint(y - r, y + r))


MARGIN = 0.8  ## the emblem drawn at 80 % of its box


def _stamp(draw, size: int) -> np.ndarray:
    """RGBA array of an emblem drawn at `size` px (4x supersampled)."""
    ss = 4
    s = skia.Surface(size * ss, size * ss)
    cv = s.getCanvas()
    cv.clear(0)
    cv.scale(size * ss / 100.0, size * ss / 100.0)
    # a margin all round: the wings reach the box's sides, their outline must not be cut off
    cv.translate(50, 50)
    cv.scale(MARGIN, MARGIN)
    cv.translate(-50, -50)
    draw(cv)
    a = s.makeImageSnapshot().toarray(colorType=skia.kRGBA_8888_ColorType, alphaType=skia.kUnpremul_AlphaType)
    return np.array(Image.fromarray(a, "RGBA").resize((size, size), Image.LANCZOS))


def _over(dst: np.ndarray, src: np.ndarray, x: int, y: int):
    """Paints `src` (RGBA) over `dst` (float RGBA) at (x, y)."""
    h, w = src.shape[:2]
    d = dst[y:y + h, x:x + w]
    sa = src[..., 3:4] / 255.0
    d[..., :3] = d[..., :3] * (1 - sa) + src[..., :3] * sa
    d[..., 3:4] = np.maximum(d[..., 3:4], src[..., 3:4])


def _emblems(a: np.ndarray, boxes: dict):
    """Swaps the marks on the banners (holes in the blue / red cloth) for the cities' emblems; the kings get a gold
    crown between gold wings, to be told from the queens at a glance."""
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    H = a.shape[0]
    cloth = {
        "white": (b > r + 40) & (b > 90) & (al > 200),
        "black": (r > 120) & (r > g + 70) & (r > b + 50) & (al > 200),
    }
    done = 0
    for side, m in cloth.items():
        half = slice(0, H // 2) if side == "white" else slice(H // 2, H)
        mm = np.zeros_like(m)
        mm[half] = m[half]
        for ys, xs in _label(~mm):
            if ys.min() == 0 or xs.min() == 0 or ys.max() == H - 1 or xs.max() == a.shape[1] - 1:
                continue  # the outside
            if len(xs) < 150:
                continue  # folds and specks
            hole = np.zeros_like(m)
            hole[ys, xs] = True
            hole = _grow(hole, 2)
            known = mm & ~hole
            # fill the hole with the cloth around it (diffusion from its edge inwards)
            todo = hole.copy()
            while todo.any():
                acc = np.zeros(a.shape[:2] + (3,))
                n = np.zeros(a.shape[:2])
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    k = np.roll(np.roll(known, dy, 0), dx, 1)
                    c = np.roll(np.roll(a[..., :3], dy, 0), dx, 1)
                    acc += c * k[..., None]
                    n += k
                front = todo & (n > 0)
                if not front.any():
                    break
                a[front, :3] = acc[front] / n[front][:, None]
                a[front, 3] = 255
                known = known | front
                todo &= ~front
            # the emblem, as wide as the old mark
            w = xs.max() - xs.min() + 1
            hgt = ys.max() - ys.min() + 1
            size = int(max(w, hgt) * 1.15 / MARGIN)
            cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
            kx0, ky0, kx1, ky1 = boxes[(side, "king")]
            king = kx0 <= cx < kx1 and ky0 <= cy < ky1
            if king:
                size = int(size * 1.6)
            st = _stamp(_crown_wings if king else (_wings if side == "white" else _horns), size)
            _over(a, st, int(round(cx - size / 2)), int(round(cy - size / 2)))
            done += 1
    assert done == 12, done


def _gold(a: np.ndarray, box, rows: tuple[float, float], cols: tuple[float, float], lower=None):
    """Brâkmar's crowns: their charcoal turned to gold. The crown is the part of the box between `rows` (fractions of
    the piece's height) and `cols` (of its width); `lower` = (row, cols) widens it down to the crown's band."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    m = np.zeros(a.shape[:2], bool)
    m[y0 + int(rows[0] * H):y0 + int(rows[1] * H), x0 + int(cols[0] * W):x0 + int(cols[1] * W)] = True
    if lower:
        row, c = lower
        m[y0 + int(rows[1] * H):y0 + int(row * H), x0 + int(c[0] * W):x0 + int(c[1] * W)] = True
    px = a[m]
    red = (px[:, 0] > px[:, 1] + 60) & (px[:, 0] > px[:, 2] + 40)
    t = np.clip((_lum(px) - 26) / 64.0, 0, 1)
    out = np.zeros((len(px), 3))
    for (t0, c0), (t1, c1) in zip(GOLD, GOLD[1:]):
        k = (t >= t0) & (t <= t1)
        f = ((t[k] - t0) / (t1 - t0))[:, None]
        out[k] = np.array(c0) * (1 - f) + np.array(c1) * f
    # the outline stays dark, eased into the gold through its soft edge
    edge = np.clip((_lum(px) - 14) / 14.0, 0, 1)[:, None]
    out = px[:, :3] * (1 - edge) + out * edge
    keep = red | (px[:, 3] < 8)
    px[~keep, :3] = out[~keep]
    a[m] = px


def _queen_horns(a: np.ndarray, box):
    """Brâkmar's queen: two curved horns rising from behind her crown."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    pad = 60
    layer = skia.Surface(W + 2 * pad, H + 2 * pad)
    cv = layer.getCanvas()
    cv.clear(0)
    cv.translate(pad + W / 2, pad)
    line = skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE), Style=skia.Paint.kStroke_Style, StrokeWidth=7,
                      StrokeJoin=skia.Paint.kRound_Join)
    for flip in (-1, 1):
        cv.save()
        cv.scale(flip, 1)
        # the root hidden behind the crown's side, the horn curling out then up, tip in
        horn = _p([(30, 72), (76, 68, 74, 26), (72, 2, 52, -12), (60, 12, 55, 32), (50, 50, 28, 50)])
        cv.drawPath(horn, line)
        cv.drawPath(horn, skia.Paint(AntiAlias=True, Color=skia.Color(142, 130, 138)))  # the shaded outer side
        cv.save()
        cv.clipPath(horn, skia.ClipOp.kIntersect, True)
        cv.translate(-6, 3)
        cv.drawPath(horn, skia.Paint(AntiAlias=True, Color=skia.Color(214, 206, 204)))  # the lit inner side
        cv.restore()
        cv.drawPath(horn, line)
        for y, ra, rb in ((48, 46, 70), (30, 54, 72)):  # ridges
            cv.drawLine(ra, y + 4, rb, y - 2, skia.Paint(AntiAlias=True, Color=skia.Color(*OUTLINE), StrokeWidth=3,
                                                         StrokeCap=skia.Paint.kRound_Cap))
        cv.drawCircle(58, 14, 3.5, skia.Paint(AntiAlias=True, Color=skia.Color(248, 244, 238)))  # glint
        cv.restore()
    hl = layer.makeImageSnapshot().toarray(colorType=skia.kRGBA_8888_ColorType, alphaType=skia.kUnpremul_AlphaType)
    # behind the queen: the horns first, the piece over them
    region = a[y0 - pad:y1 + pad, x0 - pad:x1 + pad].copy()
    under = hl.astype(float)
    pa = region[..., 3:4] / 255.0
    ha = under[..., 3:4] / 255.0
    ua = pa + ha * (1 - pa)
    rgb = under[..., :3] * ha * (1 - pa) + region[..., :3] * pa
    region[..., :3] = np.where(ua > 0, rgb / np.maximum(ua, 1e-6), 0)
    region[..., 3:4] = ua * 255.0
    a[y0 - pad:y1 + pad, x0 - pad:x1 + pad] = region


def _key_green(a: np.ndarray):
    """A plain green background made transparent; the soft edges lose their green (unmixed from it)."""
    rgb = a[..., :3]
    green = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    border = np.concatenate([green[:4].ravel(), green[-4:].ravel(), green[:, :4].ravel(), green[:, -4:].ravel()])
    g0 = float(np.median(border))
    edge = np.concatenate([rgb[:4].reshape(-1, 3), rgb[-4:].reshape(-1, 3)])
    bg = np.median(edge, 0)
    al = np.clip(1 - (green - 4) / (g0 - 10), 0, 1)
    al[al < 0.04] = 0
    al[al > 0.96] = 1
    with np.errstate(divide="ignore", invalid="ignore"):
        un = (rgb - (1 - al[..., None]) * bg) / al[..., None]
    a[..., :3] = np.where(al[..., None] > 0, np.clip(un, 0, 255), 0)
    a[..., 3] = al * 255


def load_sheet():
    """The touched-up sheet (float RGBA) and every piece's box on it."""
    a = np.array(Image.open(SHEET).convert("RGBA")).astype(float)
    if CFG.get("key_green"):
        _key_green(a)
        return a, _boxes(a[..., 3])
    a[..., 3] = np.where(a[..., 3] >= 250, 255, a[..., 3])
    boxes = _boxes(a[..., 3])
    _emblems(a, boxes)
    _gold(a, boxes[("black", "king")], (0.0, 0.225), (0.19, 0.81), (0.275, (0.31, 0.69)))
    _gold(a, boxes[("black", "queen")], (0.0, 0.20), (0.24, 0.76), (0.27, (0.28, 0.72)))
    _queen_horns(a, boxes[("black", "queen")])
    boxes = _boxes(a[..., 3])  # the horns widened the queen
    return a, boxes


def render(sheet, boxes, side: str, role: str, density: float):
    """The piece at `density` texels per layout px; returns (image, feet origin inside it, foot radius in layout px)."""
    x0, y0, x1, y1 = boxes[(side, role)]
    pad = 3
    crop = sheet[y0 - pad:y1 + pad, x0 - pad:x1 + pad]
    al = crop[..., 3]
    # premultiplied for the resize (no dark fringes), then back
    pm = crop.copy()
    pm[..., :3] *= al[..., None] / 255.0
    sx, sy = CFG.get("role_scale", ROLE_SCALE).get(role, (1.0, 1.0))
    kx, ky = LAYOUT * density * sx, LAYOUT * density * sy
    w, h = round(pm.shape[1] * kx), round(pm.shape[0] * ky)
    chans = [np.array(Image.fromarray(pm[..., c].astype(np.float32), "F").resize((w, h), Image.LANCZOS))
             for c in range(4)]
    out = np.stack(chans, -1)
    out[..., 3] = np.clip(out[..., 3], 0, 255)
    rgb = np.where(out[..., 3:4] > 0.5, out[..., :3] * 255.0 / np.maximum(out[..., 3:4], 1e-6), 0)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), out[..., 3]]).astype(np.uint8), "RGBA")
    # the feet: the middle of the base's bottom ellipse (its half width from the lowest tenth of the piece)
    on = al > 128
    rows = np.nonzero(on.any(1))[0]
    low = on[rows[-1] - int(0.1 * (y1 - y0)):rows[-1]]
    xs = np.nonzero(low.any(0))[0]
    rx = (xs[-1] - xs[0]) / 2
    fx = (xs[0] + xs[-1]) / 2
    fy = rows[-1] - CFG.get("foot_k", FOOT_K) * rx
    return img, (fx * kx, fy * ky), rx * LAYOUT * sx




# --- animations (transforms of the still picture) -------------------------------------------------------------------

def ease(t):
    return t * t * (3 - 2 * t)


def pivot(rot_deg, px, py):
    """Translation that makes a rotation about the feet turn about (px, py) instead (layout px)."""
    a = math.radians(rot_deg)
    rx = px * math.cos(a) - py * math.sin(a)
    ry = px * math.sin(a) + py * math.cos(a)
    return px - rx, py - ry


def anims(role: str, height: float, base_r: float) -> dict:
    """key -> (frames: [(deg, sx, sy, dx, dy)], events {frame: [tags]}, loop)."""
    # idle: breathing, a slow rise and fall with a hint of sway (the piece starts it at a random frame)
    n = 210
    idle = []
    for i in range(n):
        t = i / n
        br = math.sin(2 * math.pi * t)
        idle.append((0.7 * math.sin(2 * math.pi * t + 1.2), 1 - 0.008 * br, 1 + 0.018 * br, 0, 0))
    out = {"static_R": (idle, {}, True)}
    # walk: little hops, squashing as it lands (with a soft knock)
    n = 22
    hop = []
    for i in range(n):
        t = i / n
        y = -math.sin(math.pi * t) * 13.0
        sq = 0.0
        if t < 0.14:
            sq = 1 - t / 0.14
        elif t > 0.9:
            sq = (t - 0.9) / 0.1
        hop.append((math.sin(2 * math.pi * t) * 2.5, 1 + 0.07 * sq, 1 - 0.09 * sq + 0.04 * math.sin(math.pi * t), 0, y))
    out["walk_R"] = (hop, {"0": ["sound:blop_step"]}, True)
    # attack: lean back, then a fast lunge forward that strikes, then settle
    f = []
    n = 44
    for i in range(n):
        t = i / (n - 1)
        if t < 0.35:
            k = ease(t / 0.35)
            rot, dx = -12 * k, -6 * k
        elif t < 0.5:
            k = (t - 0.35) / 0.15
            rot, dx = -12 + 36 * k * k, -6 + 40 * k * k
        else:
            k = ease((t - 0.5) / 0.5)
            rot, dx = 24 * (1 - k) + math.sin(k * math.pi * 2) * 3 * (1 - k), 34 * (1 - k)
        f.append((rot, 1, 1, dx, 0))
    out["anim0_R"] = (f, {"10": ["sound:rapid_swish"], "22": ["impact"], str(n - 1): ["end"]}, False)
    # hit: knocked back, wobbling
    f = []
    n = 28
    for i in range(n):
        t = i / (n - 1)
        rot = -16 * math.exp(-4 * t) * math.cos(t * 9)
        dx, dy = pivot(rot, -base_r * 0.7, 0)
        f.append((rot, 1, 1, dx - 10 * math.exp(-5 * t), dy))
    out["hit_R"] = (f, {str(n - 1): ["end"]}, False)
    # death: topples over backward and bounces on its side
    f = []
    n = 50
    for i in range(n):
        t = i / (n - 1)
        if t < 0.6:
            k = (t / 0.6) ** 2
            rot = -92 * k
        else:
            k = (t - 0.6) / 0.4
            rot = -92 + 10 * math.sin(k * math.pi) * (1 - k)
        dx, dy = pivot(rot, -base_r * 0.9, 0)
        f.append((rot, 1, 1, dx, dy))
    out["die_R"] = (f, {"30": ["sound:krak_step"], str(n - 1): ["end"]}, False)
    # cheer (check, mate, promotion): a jump with a turn on itself, then a happy bounce
    f = []
    n = 60
    for i in range(n):
        t = i / (n - 1)
        if t < 0.15:
            k = t / 0.15
            f.append((0, 1 + 0.08 * k, 1 - 0.12 * k, 0, 0))
        elif t < 0.65:
            k = (t - 0.15) / 0.5
            f.append((0, math.cos(k * 2 * math.pi), 1.06, 0, -math.sin(k * math.pi) * 34))
        elif t < 0.75:
            k = (t - 0.65) / 0.1
            f.append((0, 1 + 0.1 * math.sin(k * math.pi), 1 - 0.12 * math.sin(k * math.pi), 0, 0))
        else:
            k = (t - 0.75) / 0.25
            f.append((0, 1, 1, 0, -math.sin(k * math.pi) * 9))
    out["anim1_R"] = (f, {"5": ["sound:saut"], "39": ["sound:blop_step"], str(n - 1): ["end"]}, False)
    return out



def bake(sheet, boxes, density: float, folder: str, preview: list | None = None):
    out = GEN / folder
    out.mkdir(parents=True, exist_ok=True)
    for side in SIDES:
        for role in ROLES:
            img, (ox, oy), base_r = render(sheet, boxes, side, role, density)
            key = f"{side}_{role}"
            img.save(out / f"{key}_0.png", optimize=True)
            if preview is not None:
                preview.append((key, img, oy))
            fr = {"p": 0, "r": [0, 0, img.width, img.height], "o": [round(ox, 2), round(oy, 2)]}
            data = {"density": density, "fps": FPS, "pages": [f"{key}_0.png"], "classic": True, "set": SET,
                    "anims": {}}
            for name, (frames, events, loop) in anims(role, oy / density, base_r).items():
                data["anims"][name] = {
                    "frames": [dict(fr, t=[round(v, 4) for v in t]) if t != (0, 1, 1, 0, 0) else fr for t in frames],
                    "events": events, "loop": loop}
            (out / f"{key}.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    print(f"{folder}: 12 pièces (densité {density})")


def use_set(name: str):
    """Points the module at one set: its sheet, its options, and its scale (the king as tall as the classic one)."""
    global SET, CFG, SHEET, LAYOUT
    SET, CFG = name, SETS[name]
    SHEET = ROOT / "tools" / "art" / CFG["sheet"]
    LAYOUT = 0.5
    if name != "classic":
        ref = np.array(Image.open(ROOT / "tools" / "art" / SETS["classic"]["sheet"]).convert("RGBA"))[..., 3]
        k0 = _boxes(ref.astype(float))[("white", "king")]
        target = (k0[3] - k0[1]) * 0.5 * ROLE_SCALE["king"][1]
        sheet = np.array(Image.open(SHEET).convert("RGBA")).astype(float)
        _key_green(sheet)
        k1 = _boxes(sheet[..., 3])[("white", "king")]
        LAYOUT = target / (k1[3] - k1[1])


SET, CFG = "classic", SETS["classic"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="all", choices=["all", *SETS])
    ap.add_argument("--preview", help="sheet of the 12 pieces (PNG) for a quick look")
    a = ap.parse_args()
    for name in (SETS if a.set == "all" else [a.set]):
        use_set(name)
        sheet, boxes = load_sheet()
        shots: list = []
        bake(sheet, boxes, 1.5, name, shots if a.preview else None)
        bake(sheet, boxes, 1.0, name + "_1x")
        if a.preview:
            _preview(shots, a.preview if a.set != "all" else a.preview.replace(".png", f"_{name}.png"))


def _preview(shots, path):
    if True:
        W = sum(i.width for _, i, _ in shots[:6]) + 40 * 7
        H = 2 * max(i.height for _, i, _ in shots) + 60
        sheet_img = Image.new("RGBA", (W, H), (96, 128, 72, 255))
        y_row = [max(oy for _, _, oy in shots[:6]) + 20, 0]
        y_row[1] = y_row[0] + max(i.height for _, i, _ in shots) + 20
        for row in range(2):
            x = 40
            for key, img, oy in shots[row * 6:(row + 1) * 6]:
                sheet_img.alpha_composite(img, (x, int(y_row[row] - oy)))
                x += img.width + 40
        sheet_img.save(path)
        print("aperçu :", path)


if __name__ == "__main__":
    main()
