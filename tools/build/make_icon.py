"""Application icons from the title screen's logo, the same way as Retro Defenders and Retro Survivors (same palette,
proportions and sizes: the games sit side by side on a desktop or a phone).

    python tools/build/make_icon.py            # writes the icons in game/assets/brand/
    python tools/build/make_icon.py --sheet    # also a preview sheet (1920 x 1080) next to this script's output: build/icons/

Source: brand/logo_source.png (the original, 5056 px) when present, else game/assets/brand/logo.png.
Outputs, in game/assets/brand/:
  icon.png       512  rounded tile (corners 22 %): deep teal radial gradient, a warm glow the shape of the logo behind
                      it, the logo 94 % of the width (window, favicon and Apple icon of the browser build: config/icon)
  icon_192.png   192  the same tile, Android's classic icon
  icon_fg.png    432  Android adaptive foreground: transparent, no frame (the phone cuts the shape); the whole logo inside
                      the circle of radius 33 % (the 72 dp of 108 every launcher shows)
  icon_bg.png    432  Android adaptive background, a layer of its own: the gradient and the logo's glow
  icon_mono.png  432  Android 13 themed icon: white, alpha only; the logo's light areas kept, so its dark outlines draw
                      the shapes
  icon.ico            16 20 24 32 40 48 64 96 128 256, each size reduced on its own; under 48 px the text cannot be read:
                      the Bouftou's head (the logo's character, above the letters) fills the tile
  icon.icns           macOS (16 to 1024)
Every reduction is done in premultiplied alpha (no dark fringes); sizes of 64 px and less get a light sharpening.
No repeated pattern anywhere: the gradients are smooth, dithered with seeded noise against banding.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "game" / "assets" / "brand"
SOURCES = [ROOT / "brand" / "logo_source.png", BRAND / "logo.png"]
PREVIEW = ROOT / "build" / "icons" / "preview.png"
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
SMALL = 48            # under this size, the head alone
MASTER = 1024         # tiles are drawn at this size, then reduced
LOGO_PX = 1536        # the logo is worked at this width
SAFE_R = 0.33         # Android: radius of the circle the whole logo fits (72/108 dp)

BG_IN = np.array([34, 96, 96], np.float32)      # gradient centre: a deep teal, apart from the leaves' yellow-greens
BG_OUT = np.array([6, 22, 30], np.float32)      # corners
BG_IN_HEAD = np.array([22, 62, 66], np.float32)  # the small tiles' centre: darker, the head stands out
GLOW = (255, 196, 90)                           # the warm light behind the logo (its orange letters)
TILE_R = 0.22         # corner radius of the tiles (fraction of the side)
LOGO_W = 0.94         # the logo's width on the big tile
HEAD_W = 0.90         # the head's size on the small tile
HEAD_BOX = (0.335, 0.0, 0.695, 0.385)  # the Bouftou's head and horns in the logo (fractions), above "RETRO"


def load_logo() -> Image.Image:
    im = Image.open(next(p for p in SOURCES if p.exists())).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox())
    return down(im, (LOGO_PX, round(im.height * LOGO_PX / im.width)), sharpen=False)


def down(im: Image.Image, size, sharpen: bool | None = None) -> Image.Image:
    """Reduced in premultiplied alpha (LANCZOS); a light sharpening at 64 px and less."""
    size = (size, size) if isinstance(size, int) else size
    small = im.convert("RGBa").resize(size, Image.LANCZOS)
    if sharpen is None:
        sharpen = max(size) <= 64
    if sharpen:
        a = np.asarray(small, np.float32)
        f = ImageFilter.UnsharpMask(radius=0.7, percent=55, threshold=0)
        rgb = np.asarray(Image.fromarray(np.clip(a[..., :3], 0, 255).astype(np.uint8), "RGB").filter(f), np.float32)
        al = np.asarray(Image.fromarray(np.clip(a[..., 3], 0, 255).astype(np.uint8), "L").filter(f), np.float32)
        rgb = np.minimum(rgb, al[..., None])  # premultiplied: no colour above its alpha
        small = Image.fromarray(np.dstack([rgb, al]).astype(np.uint8), "RGBa")
    return small.convert("RGBA")


def background(n: int, c0=BG_IN, cy=0.42, seed=7) -> np.ndarray:
    """Radial teal gradient as float RGB (n, n, 3), dithered against banding, never tiled."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / (n - 1)
    d = np.clip(np.hypot(xx - 0.5, (yy - cy) * 1.05) / 0.72, 0, 1)[..., None] ** 1.3
    rgb = c0 * (1 - d) + BG_OUT * d
    rgb += (np.random.default_rng(seed).random((n, n, 1)).astype(np.float32) - 0.5) * 2.0
    return np.clip(rgb, 0, 255)


def glow(art: Image.Image, n: int, at, strength=0.85, blur=0.06) -> Image.Image:
    """A soft warm light the shape of the art, behind it."""
    a = Image.new("L", (n, n))
    a.paste(art.getchannel("A"), at)
    a = a.filter(ImageFilter.GaussianBlur(n * blur))
    g = Image.new("RGBA", (n, n), GLOW + (0,))
    g.putalpha(a.point(lambda v: int(min(255, v * strength))))
    return g


def rounded_mask(n: int, radius: float, ss: int = 4) -> np.ndarray:
    m = Image.new("L", (n * ss, n * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, n * ss - 1, n * ss - 1), radius=radius * ss, fill=255)
    return np.asarray(m.resize((n, n), Image.BOX), np.float32) / 255.0


def tile(n: int, art: Image.Image, frac: float, art_cy=0.5, c0=BG_IN, bg_cy=0.42, glow_k=0.85, glow_blur=0.06):
    """A rounded square tile: gradient, the art's glow, the art `frac` of the side (width, or height if taller)."""
    k = min(frac * n / art.width, frac * n / art.height)
    w, h = max(1, round(art.width * k)), max(1, round(art.height * k))
    a = down(art, (w, h), sharpen=False)
    at = ((n - w) // 2, round(n * art_cy - h / 2))
    img = Image.fromarray(np.dstack([background(n, c0, bg_cy), np.full((n, n), 255.0)]).astype(np.uint8), "RGBA")
    img.alpha_composite(glow(a, n, at, glow_k, glow_blur))
    img.alpha_composite(a, at)
    out = np.asarray(img, np.float32)
    out[..., 3] = rounded_mask(n, n * TILE_R) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def head_of(logo: Image.Image) -> Image.Image:
    """The Bouftou's head, cut just above the letters; its lower edge fades so it does not end on a straight line."""
    x0, y0, x1, y1 = HEAD_BOX
    h = logo.crop((round(x0 * logo.width), round(y0 * logo.height), round(x1 * logo.width), round(y1 * logo.height)))
    a = np.asarray(h, np.float32).copy()
    fade = np.clip((h.height - np.arange(h.height)) / (h.height * 0.10), 0, 1) ** 0.8
    a[..., 3] *= fade[:, None]
    h = Image.fromarray(a.astype(np.uint8), "RGBA")
    return h.crop(h.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox())


def adaptive(logo: Image.Image, n: int = 432, ss: int = 4):
    """Android adaptive layers: foreground (the whole logo inside the safe circle, transparent), background (gradient
    and glow), monochrome."""
    al = np.asarray(logo.getchannel("A")) > 64
    ys, xs = np.nonzero(al)
    c = np.array([(xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2], np.float32)
    r = float(np.sqrt((xs - c[0]) ** 2 + (ys - c[1]) ** 2).max())
    big = n * ss
    k = SAFE_R * big / r
    w, h = round(logo.width * k), round(logo.height * k)
    a = logo.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    at = (round(big / 2 - c[0] * k), round(big / 2 - c[1] * k))
    fg = Image.new("RGBA", (big, big))
    fg.alpha_composite(a, at)
    fg_n = down(fg, n, sharpen=False)
    bg_big = Image.fromarray(np.dstack([background(big, cy=0.5), np.full((big, big), 255.0)]).astype(np.uint8), "RGBA")
    bg_big.alpha_composite(glow(a, big, at, 0.8))
    bg_n = down(bg_big, n, sharpen=False).convert("RGB").convert("RGBA")
    px = np.asarray(fg_n, np.float32)
    lum = (px[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)) / 255.0
    s = np.clip((lum - 0.24) / (0.52 - 0.24), 0, 1)
    s = s * s * (3 - 2 * s)
    mono = Image.fromarray(np.dstack([np.full((n, n, 3), 255.0), px[..., 3] * s]).astype(np.uint8), "RGBA")
    return fg_n, bg_n, mono


def preview(big, tiles, fg, bg, mono, path: Path) -> None:
    """One sheet, 1920 x 1080: the launcher masks, the themed icon, phone size, then every size on dark and light."""
    from PIL import ImageFont

    def mask_shape(n, shape):
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
        u, v = (xx - n / 2) / (n / 2), (yy - n / 2) / (n / 2)
        if shape == "rounded":
            return rounded_mask(n, n * 0.2)
        d = np.hypot(u, v) if shape == "circle" else (np.abs(u) ** 4 + np.abs(v) ** 4) ** 0.25
        return np.clip((1.0 - d) * n / 2 + 0.5, 0, 1)

    def launcher(img, n, shape):
        crop = round(img.width * (18 / 108) * 0.7)
        im = down(img.crop((crop, crop, img.width - crop, img.height - crop)), n)
        a = np.asarray(im, np.float32).copy()
        a[..., 3] *= mask_shape(n, shape)
        return Image.fromarray(a.astype(np.uint8), "RGBA")

    full = bg.copy()
    full.alpha_composite(fg)
    m = np.asarray(mono, np.float32)[..., 3:] / 255.0
    themed = Image.fromarray((np.array([40, 56, 82.0]) * (1 - m) + np.array([207, 225, 255.0]) * m).astype(np.uint8))
    W, H = 1920, 1080
    sheet = Image.new("RGBA", (W, H), (44, 38, 58, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(str(ROOT / "game" / "assets" / "fonts" / "Nunito-SemiBold.ttf"), 22)
    except OSError:
        font = ImageFont.load_default()
    x = 40
    for shape, name in (("circle", "cercle"), ("squircle", "squircle"), ("rounded", "carré arrondi")):
        sheet.alpha_composite(launcher(full, 240, shape), (x, 36))
        d.text((x, 286), name, fill=(236, 232, 240), font=font)
        x += 280
    sheet.alpha_composite(launcher(themed.convert("RGBA"), 240, "circle"), (x, 36))
    d.text((x, 286), "thème Android 13", fill=(236, 232, 240), font=font)
    x += 290
    for shape in ("circle", "squircle"):
        sheet.alpha_composite(launcher(full, 140, shape), (x, 86))
        x += 160
    d.text((x - 320, 286), "taille téléphone (140 px)", fill=(236, 232, 240), font=font)
    y = 340
    sheet.alpha_composite(down(big, 300, sharpen=False), (40, y))
    d.text((40, y + 306), "icon.png", fill=(236, 232, 240), font=font)
    sheet.alpha_composite(tiles[192], (380, y + 54))
    d.text((380, y + 306), "Android 192", fill=(236, 232, 240), font=font)
    x = 620
    for s in sorted(ICO_SIZES, reverse=True):
        sheet.alpha_composite(tiles[s], (x, y + 300 - s))
        d.text((x, y + 306), str(s), fill=(236, 232, 240), font=font)
        x += s + (26 if s > 40 else 20)
    y = 720
    d.rectangle((0, y, W, H), fill=(234, 234, 240, 255))
    x = 40
    for s in sorted(ICO_SIZES, reverse=True):
        sheet.alpha_composite(tiles[s], (x, y + 290 - s))
        d.text((x, y + 300), str(s), fill=(60, 56, 70), font=font)
        x += s + (26 if s > 40 else 20)
    x += 30
    for s in (32, 24, 16):
        sheet.alpha_composite(tiles[s].resize((s * 4, s * 4), Image.NEAREST), (x, y + 290 - s * 4))
        d.text((x, y + 300), f"{s} x4", fill=(60, 56, 70), font=font)
        x += s * 4 + 24
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true", help="also write the preview sheet (build/icons/preview.png)")
    args = ap.parse_args()
    logo = load_logo()
    big = tile(MASTER, logo, LOGO_W)
    small = tile(MASTER, head_of(logo), HEAD_W, art_cy=0.53, c0=BG_IN_HEAD, bg_cy=0.5, glow_k=1.0, glow_blur=0.04)
    sizes = sorted(set(ICO_SIZES + ICNS_SIZES + [192, 512]))
    tiles = {s: (big if s == MASTER else down(small if s < SMALL else big, s)) for s in sizes}
    tiles[512].save(BRAND / "icon.png", optimize=True)
    tiles[192].save(BRAND / "icon_192.png", optimize=True)
    # .ico: every size given as its own image (Pillow then writes them as they are)
    tiles[256].save(BRAND / "icon.ico", format="ICO", sizes=[(s, s) for s in ICO_SIZES],
                    append_images=[tiles[s] for s in ICO_SIZES if s != 256])
    with Image.open(BRAND / "icon.ico") as ico:
        for s in ICO_SIZES:
            ico.size = (s, s)
            got = np.asarray(ico.convert("RGBA"), np.int16)
            assert np.abs(got - np.asarray(tiles[s], np.int16)).max() <= 1, f"ICO {s}: not the image given"
    tiles[1024].save(BRAND / "icon.icns", format="ICNS", append_images=[tiles[s] for s in ICNS_SIZES if s != 1024])
    fg, bg, mono = adaptive(logo)
    fg.save(BRAND / "icon_fg.png", optimize=True)
    bg.save(BRAND / "icon_bg.png", optimize=True)
    mono.save(BRAND / "icon_mono.png", optimize=True)
    if args.sheet:
        preview(big, tiles, fg, bg, mono, PREVIEW)
        print("planche :", PREVIEW)
    print("icônes écrites dans", BRAND)


if __name__ == "__main__":
    main()
