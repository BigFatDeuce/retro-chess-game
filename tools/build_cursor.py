"""Curseur de Retro Chess : un gant de dessin animé (blanc crème, contour brun foncé de l'interface).

    python tools/build_cursor.py [--preview out.png]

Écrit game/assets/gen/cursor/<forme>_<taille>.png et cursor.json (point chaud de chaque forme, en fraction de
la taille). Formes :
    point          index levé (le curseur ordinaire)
    press          index enfoncé (bouton tenu)
    open           main ouverte (au-dessus d'une pièce qu'on peut prendre)
    grab1, grab2   la main qui se referme (animation de la prise)
    fist           poing fermé (pièce tenue, vue qu'on fait glisser ou qu'on incline)
Chaque forme est dessinée en coordonnées 0..100, puis rendue à plusieurs tailles (le jeu prend la plus proche
de la hauteur de sa fenêtre).
"""
import json
import sys
from pathlib import Path

import skia

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "gen" / "cursor"
SIZES = (24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160)

FILL = skia.Color(0xFF, 0xFA, 0xEE)
LINE = skia.Color(0x2B, 0x17, 0x0C)
CREASE = skia.Color(0xC9, 0xBC, 0xA8)
SHADE = skia.Color(0xEC, 0xE1, 0xCF)
FIT = 0.86   # the drawing in its square: room for the outline of the fingertips
SHIFT = (0.06, 0.1)

W = 13.0   # finger width
O = 4.6    # outer outline
S = 2.4    # line between fingers

# fingers: (base x, base y, tip x, tip y), drawn back to front: pinky, ring, middle, index; thumb apart
OPEN = {
    "palm": (29, 46, 79, 95),
    "fingers": [(72, 62, 80, 30), (63, 56, 66, 13), (52, 55, 52, 7), (40, 57, 37, 14)],
    "thumb": (36, 74, 14, 56),
}
FIST = {
    "palm": (29, 48, 79, 95),
    "fingers": [(72, 60, 73, 48), (63, 58, 63, 43), (52, 57, 52, 41), (41, 58, 41, 45)],
    "thumb": (36, 74, 25, 61),
}
POINT = {
    "palm": (29, 48, 79, 95),
    "fingers": [(72, 60, 73, 49), (63, 58, 64, 43), (52, 57, 53, 41), (40, 58, 36, 6)],
    "thumb": (36, 74, 15, 60),
}
PRESS = {
    "palm": (29, 51, 79, 96),
    "fingers": [(72, 62, 73, 52), (63, 60, 64, 46), (52, 59, 53, 44), (40, 60, 37, 19)],
    "thumb": (36, 76, 17, 64),
}


def mix(a, b, t):
    def lerp(x, y):
        return tuple(p + (q - p) * t for p, q in zip(x, y))
    return {
        "palm": lerp(a["palm"], b["palm"]),
        "fingers": [lerp(f, g) for f, g in zip(a["fingers"], b["fingers"])],
        "thumb": lerp(a["thumb"], b["thumb"]),
    }


SHAPES = {
    "point": (POINT, (36 / 100.0, 1.5 / 100.0)),
    "press": (PRESS, (37 / 100.0, 14.5 / 100.0)),
    "open": (OPEN, (0.53, 0.45)),
    "grab1": (mix(OPEN, FIST, 0.4), (0.53, 0.47)),
    "grab2": (mix(OPEN, FIST, 0.75), (0.53, 0.5)),
    "fist": (FIST, (0.53, 0.52)),
}


def _line(c, a, b, width, color):
    p = skia.Paint(AntiAlias=True, Color=color, StrokeWidth=width, Style=skia.Paint.kStroke_Style,
                   StrokeCap=skia.Paint.kRound_Cap)
    c.drawLine(a[0], a[1], b[0], b[1], p)


def _palm(r, grow=0.0):
    x0, y0, x1, y1 = r
    rect = skia.Rect.MakeLTRB(x0 - grow, y0 - grow, x1 + grow, y1 + grow)
    return skia.RRect.MakeRectXY(rect, 22 + grow, 24 + grow)


def draw(c, shape):
    fill = skia.Paint(AntiAlias=True, Color=FILL)
    line = skia.Paint(AntiAlias=True, Color=LINE)
    fingers = shape["fingers"]
    thumb = shape["thumb"]
    # 1. the silhouette: every part grown by the outline
    c.drawRRect(_palm(shape["palm"], O), line)
    for f in fingers + [thumb]:
        _line(c, f[:2], f[2:], W + 2 * O, LINE)
    # 2. the thumb and the fingers back to front, each with its own thinner line (the gaps between fingers)
    for f in [thumb] + fingers:
        _line(c, f[:2], f[2:], W + 2 * S, LINE)
        _line(c, f[:2], f[2:], W, FILL)
    # 3. the back of the hand over the fingers' bases, a soft shade at the bottom, the three creases
    c.drawRRect(_palm(shape["palm"]), fill)
    x0, y0, x1, y1 = shape["palm"]
    shade = skia.Paint(AntiAlias=True, Color=SHADE)
    c.save()
    c.clipRRect(_palm(shape["palm"]), skia.ClipOp.kIntersect, True)
    c.drawOval(skia.Rect.MakeLTRB(x0 - 10, y1 - 9, x1 + 10, y1 + 30), shade)
    c.restore()
    cx = (x0 + x1) / 2
    for dx in (-9, 0, 9):
        _line(c, (cx + dx, y0 + 16), (cx + dx * 0.9, y0 + 34), 3.6, CREASE)


def render(shape, size):
    surf = skia.Surface(size, size)
    c = surf.getCanvas()
    c.clear(skia.ColorTRANSPARENT)
    c.translate(SHIFT[0] * size, SHIFT[1] * size)
    c.scale(size * FIT / 100.0, size * FIT / 100.0)
    draw(c, shape)
    return surf.makeImageSnapshot()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {"sizes": list(SIZES), "hotspot": {}}
    for name, (shape, hot) in SHAPES.items():
        hot = (SHIFT[0] + hot[0] * FIT, SHIFT[1] + hot[1] * FIT)
        meta["hotspot"][name] = [round(hot[0], 4), round(hot[1], 4)]
        for s in SIZES:
            render(shape, s).save(str(OUT / f"{name}_{s}.png"), skia.kPNG)
    (OUT / "cursor.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        big = 240
        surf = skia.Surface(big * len(SHAPES), big + 120)
        c = surf.getCanvas()
        c.clear(skia.Color(0x6A, 0x8F, 0x3A))
        for i, (name, (shape, hot)) in enumerate(SHAPES.items()):
            hot = (SHIFT[0] + hot[0] * FIT, SHIFT[1] + hot[1] * FIT)
            c.drawImage(render(shape, big), i * big, 0)
            c.drawImage(render(shape, 48), i * big + 20, big + 30)
            c.drawCircle(i * big + hot[0] * big, hot[1] * big, 4, skia.Paint(AntiAlias=True, Color=skia.ColorRED))
        surf.makeImageSnapshot().save(out, skia.kPNG)
    print("cursor:", len(SHAPES), "formes x", len(SIZES), "tailles ->", OUT)


if __name__ == "__main__":
    main()
