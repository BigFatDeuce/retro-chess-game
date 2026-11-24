"""Écran de chargement de la version navigateur : un Tofu court le long de la barre, poursuivi par un Bwork.

    python tools/build/loading_runners.py    (avec le python du rendu vectoriel, comme build_pieces.py)
    -> game/assets/web/loading_shell.html, utilisé par l'export Web (html/custom_html_shell)

Rend la course (runR) des deux créatures depuis leurs dessins vectoriels (assets de la bibliothèque locale, lus
seulement), en bandes horizontales dont les cases partagent le point d'appui (les pieds restent sur la barre).
Les bandes, le logo et la police sont mis dans la page en data URI (WebP, sans métadonnées), à partir du gabarit
tools/build/web_shell.html. La page doit rester légère : elle arrive avant que la barre puisse bouger.
"""
import base64
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_pieces as B  # noqa: E402

TEMPLATE = Path(__file__).with_name("web_shell.html")
OUT = ROOT / "game" / "assets" / "web" / "loading_shell.html"
# key: (gfx, CSS height of a cell, keep every n-th frame)
RUNNERS = {"TOFU": (1558, 88, 2), "BWORK": (1003, 132, 1)}
RENDER_SCALE = 6.0


def strip(gfx: int, step: int):
    lib = B.library(B.CLIPS / "sprites" / f"{gfx}.swf")
    sym = B.resolve(lib.swfs[0].exports, "run", "R")
    canvas = (int(190 * RENDER_SCALE), int(170 * RENDER_SCALE))
    origin = (canvas[0] // 2, int(canvas[1] * 0.714))
    ra = B.render_anim(lib, sym, B.R.Appearance(colors={}), RENDER_SCALE, canvas=canvas, origin=origin)
    frames = [Image.fromarray(f) for f in ra.frames if f[:, :, 3].max() > 0][::step]
    ox, oy = ra.origin
    box = None
    for f in frames:
        b = f.getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    x0, y0, x1, y1 = box[0] - 2, box[1] - 2, box[2] + 2, max(box[3], int(oy)) + 2
    cw, ch = x1 - x0, y1 - y0
    out = Image.new("RGBA", (cw * len(frames), ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f.crop((x0, y0, x1, y1)), (i * cw, 0))
    fps = (float(lib.swfs[0].frame_rate) or 60.0) / step
    return out, len(frames), ox - x0, oy - y0, fps


def data_uri(img: Image.Image, height: int | None = None) -> str:
    if height and img.height > height:
        img = img.resize((round(img.width * height / img.height), height), Image.LANCZOS)
    clean = Image.new("RGBA", img.size)
    clean.paste(img)
    buf = io.BytesIO()
    clean.save(buf, "WEBP", quality=86, method=6)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def main() -> None:
    html = TEMPLATE.read_text(encoding="utf-8")
    for key, (gfx, css_h, step) in RUNNERS.items():
        img, n, ox, oy, fps = strip(gfx, step)
        k = css_h / img.height
        html = (html.replace(f"__{key}_IMG__", data_uri(img, 2 * css_h))
                .replace(f"__{key}_N__", str(n))
                .replace(f"__{key}_W__", f"{img.width / n * k:.2f}")
                .replace(f"__{key}_H__", str(css_h))
                .replace(f"__{key}_OX__", f"{ox * k:.2f}")
                .replace(f"__{key}_OY__", f"{oy * k:.2f}")
                .replace(f"__{key}_MS__", str(round(n * 1000 / fps))))
        print(f"  {key.lower()} : {n} images, {fps:.0f} i/s")
    logo = Image.open(ROOT / "game" / "assets" / "brand" / "logo.png").convert("RGBA")
    html = html.replace("__LOGO__", data_uri(logo, 400))
    font = (ROOT / "game" / "assets" / "fonts" / "Fredoka-Bold.ttf").read_bytes()
    html = html.replace("__FONT__", "data:font/ttf;base64," + base64.b64encode(font).decode())
    assert "__" not in html.replace("__proto__", ""), "gabarit : marque non remplacée"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html, encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(ROOT)} : {OUT.stat().st_size // 1024} Kio")


if __name__ == "__main__":
    main()
