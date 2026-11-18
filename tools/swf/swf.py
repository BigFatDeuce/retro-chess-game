"""Minimal SWF reader for Dofus Retro assets.

Parses the tag stream (including nested DefineSprite timelines), shapes,
bitmaps, sounds, placements and AVM1 action bytecode. Rendering lives in
render.py; this module only decodes.

Coordinates stay in twips (1/20 px) as stored in the file.
"""
from __future__ import annotations

import io
import struct
import zlib
from dataclasses import dataclass, field


# --------------------------------------------------------------------------
# Bit-level reader
# --------------------------------------------------------------------------
class Reader:
    __slots__ = ("data", "pos", "bitbuf", "bitcount")

    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos
        self.bitbuf = 0
        self.bitcount = 0

    def align(self):
        self.bitcount = 0

    def ub(self, n: int) -> int:
        v = 0
        for _ in range(n):
            if self.bitcount == 0:
                self.bitbuf = self.data[self.pos]
                self.pos += 1
                self.bitcount = 8
            self.bitcount -= 1
            v = (v << 1) | ((self.bitbuf >> self.bitcount) & 1)
        return v

    def sb(self, n: int) -> int:
        if n == 0:
            return 0
        v = self.ub(n)
        if v & (1 << (n - 1)):
            v -= 1 << n
        return v

    def fb(self, n: int) -> float:
        return self.sb(n) / 65536.0

    def u8(self) -> int:
        self.align()
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        self.align()
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def s16(self) -> int:
        self.align()
        v = struct.unpack_from("<h", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u32(self) -> int:
        self.align()
        v = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def s32(self) -> int:
        self.align()
        v = struct.unpack_from("<i", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f32(self) -> float:
        self.align()
        v = struct.unpack_from("<f", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f64_avm(self) -> float:
        # AVM1 doubles are stored as two little-endian 32-bit words, high word first.
        self.align()
        hi = self.data[self.pos:self.pos + 4]
        lo = self.data[self.pos + 4:self.pos + 8]
        self.pos += 8
        return struct.unpack("<d", lo + hi)[0]

    def fixed8(self) -> float:
        return self.s16() / 256.0

    def bytes(self, n: int) -> bytes:
        self.align()
        v = self.data[self.pos:self.pos + n]
        self.pos += n
        return v

    def string(self) -> str:
        self.align()
        end = self.data.index(b"\x00", self.pos)
        raw = self.data[self.pos:end]
        self.pos = end + 1
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("latin-1")

    def rect(self):
        self.align()
        n = self.ub(5)
        r = (self.sb(n), self.sb(n), self.sb(n), self.sb(n))  # xmin, xmax, ymin, ymax
        self.align()
        return r

    def matrix(self) -> "Matrix":
        self.align()
        a = d = 1.0
        b = c = 0.0
        if self.ub(1):
            n = self.ub(5)
            a = self.fb(n)
            d = self.fb(n)
        if self.ub(1):
            n = self.ub(5)
            b = self.fb(n)
            c = self.fb(n)
        n = self.ub(5)
        tx = self.sb(n)
        ty = self.sb(n)
        self.align()
        return Matrix(a, b, c, d, tx, ty)

    def cxform(self, alpha: bool) -> "CXForm":
        self.align()
        has_add = self.ub(1)
        has_mult = self.ub(1)
        n = self.ub(4)
        m = [256, 256, 256, 256]
        a = [0, 0, 0, 0]
        k = 4 if alpha else 3
        if has_mult:
            for i in range(k):
                m[i] = self.sb(n)
        if has_add:
            for i in range(k):
                a[i] = self.sb(n)
        self.align()
        return CXForm(m[0] / 256, m[1] / 256, m[2] / 256, m[3] / 256, a[0], a[1], a[2], a[3])

    def rgb(self):
        return (self.u8(), self.u8(), self.u8(), 255)

    def rgba(self):
        return (self.u8(), self.u8(), self.u8(), self.u8())


# --------------------------------------------------------------------------
# Geometry / colour primitives
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class Matrix:
    a: float = 1.0  # scaleX
    b: float = 0.0  # rotateSkew0
    c: float = 0.0  # rotateSkew1
    d: float = 1.0  # scaleY
    tx: float = 0.0
    ty: float = 0.0

    # x' = a*x + c*y + tx ; y' = b*x + d*y + ty
    def __mul__(self, o: "Matrix") -> "Matrix":
        """self * o : apply o first, then self."""
        return Matrix(
            self.a * o.a + self.c * o.b,
            self.b * o.a + self.d * o.b,
            self.a * o.c + self.c * o.d,
            self.b * o.c + self.d * o.d,
            self.a * o.tx + self.c * o.ty + self.tx,
            self.b * o.tx + self.d * o.ty + self.ty,
        )

    def apply(self, x, y):
        return (self.a * x + self.c * y + self.tx, self.b * x + self.d * y + self.ty)

    def to_list(self):
        return [self.a, self.b, self.c, self.d, self.tx, self.ty]


IDENTITY = Matrix()


@dataclass(frozen=True)
class CXForm:
    rm: float = 1.0
    gm: float = 1.0
    bm: float = 1.0
    am: float = 1.0
    ra: float = 0.0
    ga: float = 0.0
    ba: float = 0.0
    aa: float = 0.0

    def __mul__(self, o: "CXForm") -> "CXForm":
        """self * o : apply o first (inner), then self (outer)."""
        return CXForm(
            self.rm * o.rm, self.gm * o.gm, self.bm * o.bm, self.am * o.am,
            self.rm * o.ra + self.ra, self.gm * o.ga + self.ga,
            self.bm * o.ba + self.ba, self.am * o.aa + self.aa,
        )

    def is_identity(self):
        return self == CX_IDENTITY

    def apply(self, rgba):
        r, g, b, a = rgba
        f = lambda v: max(0, min(255, v))
        return (f(r * self.rm + self.ra), f(g * self.gm + self.ga),
                f(b * self.bm + self.ba), f(a * self.am + self.aa))


CX_IDENTITY = CXForm()


# --------------------------------------------------------------------------
# Character definitions
# --------------------------------------------------------------------------
@dataclass
class FillStyle:
    kind: int
    color: tuple = (0, 0, 0, 255)
    matrix: Matrix = IDENTITY
    gradient: list = field(default_factory=list)  # [(ratio 0..255, rgba)]
    spread: int = 0
    interp: int = 0
    focal: float = 0.0
    bitmap_id: int = 0
    # morph end state
    color2: tuple | None = None
    matrix2: Matrix | None = None
    gradient2: list | None = None


@dataclass
class LineStyle:
    width: int
    color: tuple = (0, 0, 0, 255)
    fill: FillStyle | None = None
    start_cap: int = 0
    end_cap: int = 0
    join: int = 0
    miter: float = 3.0
    no_hscale: bool = False
    no_vscale: bool = False
    width2: int | None = None
    color2: tuple | None = None


@dataclass
class Shape:
    id: int
    bounds: tuple
    # list of (FillStyle, [contours]) ; contour = list of segments
    # segment = ('L', x0,y0,x1,y1) | ('Q', x0,y0,cx,cy,x1,y1)
    fills: list
    lines: list  # (LineStyle, [segments in draw order])
    is_morph: bool = False
    fills2: list | None = None  # morph end geometry, parallel to fills
    lines2: list | None = None


@dataclass
class PlaceOp:
    depth: int
    move: bool = False
    char_id: int | None = None
    matrix: Matrix | None = None
    cxform: CXForm | None = None
    ratio: int | None = None
    name: str | None = None
    clip_depth: int | None = None
    blend: int | None = None
    filters: list | None = None
    cache_as_bitmap: bool = False
    visible: int | None = None
    clip_actions: list | None = None  # [(event_flags, action_blob)]


@dataclass
class Frame:
    ops: list = field(default_factory=list)  # PlaceOp | ('remove', depth) | ('sound', id)
    actions: list = field(default_factory=list)  # list of action byte blobs
    label: str | None = None


@dataclass
class Sprite:
    id: int
    frames: list  # [Frame]

    @property
    def frame_count(self):
        return len(self.frames)

    def labels(self):
        return {f.label: i for i, f in enumerate(self.frames) if f.label}


@dataclass
class Bitmap:
    id: int
    kind: str  # 'jpeg', 'lossless'
    data: bytes
    alpha: bytes | None = None
    fmt: int = 0
    width: int = 0
    height: int = 0
    lossless_alpha: bool = False
    _image: object = None


@dataclass
class Sound:
    id: int
    fmt: int
    rate: int
    size16: bool
    stereo: bool
    samples: int
    data: bytes


# --------------------------------------------------------------------------
# SWF file
# --------------------------------------------------------------------------
class SWF:
    def __init__(self, path_or_bytes):
        if isinstance(path_or_bytes, (bytes, bytearray)):
            raw = bytes(path_or_bytes)
            self.path = None
        else:
            self.path = str(path_or_bytes)
            with open(path_or_bytes, "rb") as f:
                raw = f.read()
        sig = raw[:3]
        self.version = raw[3]
        if sig == b"CWS":
            body = zlib.decompress(raw[8:])
        elif sig == b"FWS":
            body = raw[8:]
        elif sig == b"ZWS":
            import lzma
            # LZMA SWF: 4 bytes compressed len, 5 bytes props
            props = raw[12:17]
            dec = lzma.LZMADecompressor(lzma.FORMAT_RAW, filters=[
                lzma._decode_filter_properties(lzma.FILTER_LZMA1, props)])
            body = dec.decompress(raw[17:])
        else:
            raise ValueError(f"not a SWF: {sig!r}")
        r = Reader(body)
        self.frame_rect = r.rect()
        self.frame_rate = r.u16() / 256.0
        self.frame_count_hdr = r.u16()
        self.characters: dict[int, object] = {}
        self.exports: dict[str, int] = {}
        self.imports: list = []  # (url, {name: id})
        self.jpeg_tables: bytes | None = None
        self.bg_color = None
        self.unknown_tags: dict[int, int] = {}
        self.errors: list[str] = []
        self.root = Sprite(0, self._parse_timeline(r, len(body), top=True))

    # ------------------------------------------------------------------
    @property
    def width(self):
        return (self.frame_rect[1] - self.frame_rect[0]) / 20

    @property
    def height(self):
        return (self.frame_rect[3] - self.frame_rect[2]) / 20

    def _parse_timeline(self, r: Reader, end: int, top: bool):
        frames = [Frame()]
        while r.pos < end:
            code_len = r.u16()
            code = code_len >> 6
            length = code_len & 0x3F
            if length == 0x3F:
                length = r.u32()
            start = r.pos
            tend = start + length
            cur = frames[-1]
            if code == 0:
                break
            elif code == 1:  # ShowFrame
                frames.append(Frame())
            elif code == 43:  # FrameLabel
                cur.label = Reader(r.data, start).string()
            elif code in (12,):  # DoAction
                cur.actions.append(r.data[start:tend])
            elif code == 4:  # PlaceObject
                rr = Reader(r.data, start)
                cid = rr.u16()
                depth = rr.u16()
                m = rr.matrix()
                cx = rr.cxform(False) if rr.pos < tend else None
                cur.ops.append(PlaceOp(depth, False, cid, m, cx))
            elif code in (26, 70):
                cur.ops.append(self._place(r.data, start, tend, code == 70))
            elif code == 5:  # RemoveObject
                rr = Reader(r.data, start)
                rr.u16()
                cur.ops.append(("remove", rr.u16()))
            elif code == 28:
                cur.ops.append(("remove", Reader(r.data, start).u16()))
            elif code == 15:  # StartSound
                cur.ops.append(("sound", Reader(r.data, start).u16()))
            elif top or code in (39,):
                self._define(code, r.data, start, tend)
            else:
                self.unknown_tags[code] = self.unknown_tags.get(code, 0) + 1
            r.pos = tend
            r.align()
        if frames and not frames[-1].ops and not frames[-1].actions and len(frames) > 1 and not frames[-1].label:
            frames.pop()
        return frames

    def _place(self, data, start, end, v3):
        r = Reader(data, start)
        flags = r.u8()
        flags2 = r.u8() if v3 else 0
        depth = r.u16()
        op = PlaceOp(depth)
        op.move = bool(flags & 1)
        if v3 and (flags2 & 0x08 or (flags2 & 0x10 and flags & 0x02)):
            r.string()  # class name
        if flags & 0x02:
            op.char_id = r.u16()
        if flags & 0x04:
            op.matrix = r.matrix()
        if flags & 0x08:
            op.cxform = r.cxform(True)
        if flags & 0x10:
            op.ratio = r.u16()
        if flags & 0x20:
            op.name = r.string()
        if flags & 0x40:
            op.clip_depth = r.u16()
        if v3:
            if flags2 & 0x01:
                op.filters = self._filters(r)
            if flags2 & 0x02:
                op.blend = r.u8()
            if flags2 & 0x04:
                op.cache_as_bitmap = bool(r.u8())
            if flags2 & 0x20:
                op.visible = r.u8()
            if flags2 & 0x40:
                r.rgba()  # background colour
        if flags & 0x80:
            op.clip_actions = self._clip_actions(r, end)
        return op

    def _clip_actions(self, r: Reader, end: int):
        wide = self.version >= 6
        r.u16()
        r.u32() if wide else r.u16()
        out = []
        while r.pos < end:
            ef = r.u32() if wide else r.u16()
            if ef == 0:
                break
            size = r.u32()
            start = r.pos
            if wide and ef & 0x00020000:
                r.u8()
            out.append((ef, r.data[r.pos:start + size]))
            r.pos = start + size
        return out

    def _filters(self, r: Reader):
        out = []
        n = r.u8()
        for _ in range(n):
            fid = r.u8()
            if fid == 0:  # drop shadow
                col = r.rgba(); bx = r.s32() / 65536; by = r.s32() / 65536
                ang = r.s32() / 65536; dist = r.s32() / 65536; strength = r.fixed8()
                fl = r.u8()
                out.append(("dropshadow", col, bx, by, ang, dist, strength, fl))
            elif fid == 1:  # blur
                bx = r.s32() / 65536; by = r.s32() / 65536; passes = r.u8() >> 3
                out.append(("blur", bx, by, passes))
            elif fid == 2:  # glow
                col = r.rgba(); bx = r.s32() / 65536; by = r.s32() / 65536
                strength = r.fixed8(); fl = r.u8()
                out.append(("glow", col, bx, by, strength, fl))
            elif fid == 3:  # bevel
                c1 = r.rgba(); c2 = r.rgba(); bx = r.s32() / 65536; by = r.s32() / 65536
                ang = r.s32() / 65536; dist = r.s32() / 65536; st = r.fixed8(); fl = r.u8()
                out.append(("bevel", c1, c2, bx, by, ang, dist, st, fl))
            elif fid in (4, 7):  # gradient glow / gradient bevel
                nc = r.u8()
                cols = [r.rgba() for _ in range(nc)]
                ratios = [r.u8() for _ in range(nc)]
                bx = r.s32() / 65536; by = r.s32() / 65536
                ang = r.s32() / 65536; dist = r.s32() / 65536; st = r.fixed8(); fl = r.u8()
                out.append(("gradglow" if fid == 4 else "gradbevel", cols, ratios, bx, by, ang, dist, st, fl))
            elif fid == 5:  # convolution
                mx = r.u8(); my = r.u8(); r.f32(); r.f32()
                for _ in range(mx * my):
                    r.f32()
                r.rgba(); r.u8()
                out.append(("convolution",))
            elif fid == 6:  # color matrix
                out.append(("colormatrix", [r.f32() for _ in range(20)]))
        return out

    # ------------------------------------------------------------------
    def _define(self, code, data, start, end):
        r = Reader(data, start)
        if code in (2, 22, 32, 83):
            try:
                self._define_shape(r, code, end)
            except (ValueError, IndexError) as e:
                sid = int.from_bytes(data[start:start + 2], "little")
                self.errors.append(f"shape {sid}: {e}")
                self.characters[sid] = Shape(sid, (0, 0, 0, 0), [], [])
        elif code in (46, 84):
            self._define_morph(r, code, end)
        elif code == 39:
            sid = r.u16()
            r.u16()
            self.characters[sid] = Sprite(sid, self._parse_timeline(r, end, top=False))
        elif code == 56:  # ExportAssets
            n = r.u16()
            for _ in range(n):
                cid = r.u16()
                name = r.string()
                self.exports[name] = cid
        elif code in (57, 71):  # ImportAssets(2)
            url = r.string()
            if code == 71:
                r.u8(); r.u8()
            n = r.u16()
            m = {}
            for _ in range(n):
                cid = r.u16()
                m[r.string()] = cid
            self.imports.append((url, m))
        elif code == 8:
            self.jpeg_tables = data[start:end]
        elif code == 6:  # DefineBits (uses JPEGTables)
            cid = r.u16()
            self.characters[cid] = Bitmap(cid, "jpeg_tables", data[start + 2:end])
        elif code == 21:
            cid = r.u16()
            self.characters[cid] = Bitmap(cid, "jpeg", data[start + 2:end])
        elif code in (35, 90):
            cid = r.u16()
            off = r.u32()
            if code == 90:
                r.u16()
            jp = r.bytes(off)
            alpha = data[r.pos:end]
            self.characters[cid] = Bitmap(cid, "jpeg", jp, alpha)
        elif code in (20, 36):
            cid = r.u16()
            fmt = r.u8()
            w = r.u16()
            h = r.u16()
            ctab = None
            if fmt == 3:
                ctab = r.u8()
            b = Bitmap(cid, "lossless", data[r.pos:end], fmt=fmt, width=w, height=h,
                       lossless_alpha=(code == 36))
            b.alpha = bytes([ctab]) if ctab is not None else None
            self.characters[cid] = b
        elif code == 14:  # DefineSound
            cid = r.u16()
            fl = r.u8()
            samples = r.u32()
            self.characters[cid] = Sound(cid, fl >> 4, [5512, 11025, 22050, 44100][(fl >> 2) & 3],
                                         bool(fl & 2), bool(fl & 1), samples, data[r.pos:end])
        elif code == 9:
            self.bg_color = r.rgb()
        elif code in (59,):  # DoInitAction
            cid = r.u16()
            self.characters.setdefault(("init", cid), []).append(data[r.pos:end])
        else:
            self.unknown_tags[code] = self.unknown_tags.get(code, 0) + 1

    # ------------------------------------------------------------------
    def _fill_styles(self, r: Reader, shape_ver: int, morph=False):
        n = r.u8()
        if n == 0xFF and shape_ver >= 2:
            n = r.u16()
        return [self._fill_style(r, shape_ver, morph) for _ in range(n)]

    def _gradient(self, r, shape_ver, morph):
        if morph:
            n = r.u8()
            g1, g2 = [], []
            for _ in range(n):
                g1.append((r.u8(), r.rgba()))
                g2.append((r.u8(), r.rgba()))
            return g1, g2, 0, 0
        b = r.u8()
        spread = b >> 6
        interp = (b >> 4) & 3
        n = b & 0x0F
        g = []
        for _ in range(n):
            ratio = r.u8()
            col = r.rgba() if shape_ver >= 3 else r.rgb()
            g.append((ratio, col))
        return g, None, spread, interp

    def _fill_style(self, r: Reader, shape_ver: int, morph=False) -> FillStyle:
        kind = r.u8()
        fs = FillStyle(kind)
        if kind == 0x00:
            if morph:
                fs.color = r.rgba()
                fs.color2 = r.rgba()
            else:
                fs.color = r.rgba() if shape_ver >= 3 else r.rgb()
        elif kind in (0x10, 0x12, 0x13):
            fs.matrix = r.matrix()
            if morph:
                fs.matrix2 = r.matrix()
            g, g2, sp, ip = self._gradient(r, shape_ver, morph)
            fs.gradient, fs.gradient2, fs.spread, fs.interp = g, g2, sp, ip
            if kind == 0x13:
                fs.focal = r.fixed8()
                if morph:
                    r.fixed8()
        elif kind in (0x40, 0x41, 0x42, 0x43):
            fs.bitmap_id = r.u16()
            fs.matrix = r.matrix()
            if morph:
                fs.matrix2 = r.matrix()
        else:
            raise ValueError(f"bad fill style {kind:#x}")
        return fs

    def _line_styles(self, r: Reader, shape_ver: int, morph=False):
        n = r.u8()
        if n == 0xFF and shape_ver >= 2:
            n = r.u16()
        out = []
        for _ in range(n):
            if shape_ver == 4 or (morph and shape_ver == 2):
                w = r.u16()
                w2 = r.u16() if morph else None
                r.align()
                sc = r.ub(2); join = r.ub(2); has_fill = r.ub(1)
                nh = r.ub(1); nv = r.ub(1); r.ub(1); r.ub(5); r.ub(1); ec = r.ub(2)
                miter = r.fixed8() if join == 2 else 3.0
                ls = LineStyle(w, start_cap=sc, end_cap=ec, join=join, miter=miter,
                               no_hscale=bool(nh), no_vscale=bool(nv), width2=w2)
                if has_fill:
                    ls.fill = self._fill_style(r, 4, morph)
                    ls.color = ls.fill.color
                else:
                    ls.color = r.rgba()
                    if morph:
                        ls.color2 = r.rgba()
            else:
                w = r.u16()
                w2 = r.u16() if morph else None
                col = r.rgba() if (shape_ver >= 3 or morph) else r.rgb()
                col2 = r.rgba() if morph else None
                ls = LineStyle(w, col, width2=w2, color2=col2)
            out.append(ls)
        return out

    def _shape_events(self, r: Reader, shape_ver: int, fills, lines, morph=False):
        """Decode SHAPERECORDs into an event list.
        Events: ('S', fs0, fs1, ls) style change (global 1-based indices, 0 = none),
                ('M', x, y) pen move (breaks line paths), ('E', seg) edge.
        Returns (events, fill_table, line_table)."""
        nfb = r.ub(4)
        nlb = r.ub(4)
        x = y = 0
        fill_tab = list(fills)
        line_tab = list(lines)
        fbase = lbase = 0
        fs0 = fs1 = ls = 0
        ev = []
        while True:
            if not r.ub(1):
                flags = r.ub(5)
                if flags == 0:
                    break
                if flags & 0x01:
                    nb = r.ub(5)
                    x = r.sb(nb)
                    y = r.sb(nb)
                    ev.append(("M", x, y))
                if flags & 0x02:
                    v = r.ub(nfb)
                    fs0 = fbase + v if v else 0
                if flags & 0x04:
                    v = r.ub(nfb)
                    fs1 = fbase + v if v else 0
                if flags & 0x08:
                    v = r.ub(nlb)
                    ls = lbase + v if v else 0
                if flags & 0x10:
                    fbase = len(fill_tab)
                    lbase = len(line_tab)
                    fill_tab += self._fill_styles(r, shape_ver, morph)
                    line_tab += self._line_styles(r, shape_ver, morph)
                    nfb = r.ub(4)
                    nlb = r.ub(4)
                if flags & 0x0E:
                    ev.append(("S", fs0, fs1, ls))
                continue
            if r.ub(1):
                nb = r.ub(4) + 2
                if r.ub(1):
                    dx = r.sb(nb)
                    dy = r.sb(nb)
                else:
                    vert = r.ub(1)
                    dx = 0 if vert else r.sb(nb)
                    dy = r.sb(nb) if vert else 0
                seg = ("L", x, y, x + dx, y + dy)
                x += dx
                y += dy
            else:
                nb = r.ub(4) + 2
                cx = x + r.sb(nb)
                cy = y + r.sb(nb)
                ax = cx + r.sb(nb)
                ay = cy + r.sb(nb)
                seg = ("Q", x, y, cx, cy, ax, ay)
                x, y = ax, ay
            ev.append(("E", seg))
        return ev, fill_tab, line_tab

    def _define_shape(self, r: Reader, code, end):
        ver = {2: 1, 22: 2, 32: 3, 83: 4}[code]
        sid = r.u16()
        bounds = r.rect()
        if ver == 4:
            r.rect()
            r.u8()
        fills = self._fill_styles(r, ver)
        lines = self._line_styles(r, ver)
        ev, ftab, ltab = self._shape_events(r, ver, fills, lines)
        sf, sl = build_geometry(ev, ftab, ltab)
        self.characters[sid] = Shape(sid, bounds, sf, sl)

    def _define_morph(self, r: Reader, code, end):
        ver = 2 if code == 84 else 1
        sid = r.u16()
        bounds = r.rect()
        r.rect()
        if ver == 2:
            r.rect(); r.rect(); r.u8()
        offset = r.u32()
        end_pos = r.pos + offset
        fills = self._fill_styles(r, 3, morph=True)
        lines = self._line_styles(r, ver, morph=True)
        ev1, ftab, ltab = self._shape_events(r, 3, fills, lines, morph=True)
        ev2, _, _ = self._shape_events(Reader(r.data, end_pos), 3, [], [], morph=True)
        shape = Shape(sid, bounds, [], [], is_morph=True)
        shape.morph = (ev1, [e for e in ev2 if e[0] == "E"], ftab, ltab)
        shape._cache = {}
        self.characters[sid] = shape

    # ------------------------------------------------------------------
    def bitmap_image(self, bid):
        """Return a PIL RGBA image for a bitmap character (cached)."""
        from PIL import Image
        b = self.characters.get(bid)
        if not isinstance(b, Bitmap):
            return None
        if b._image is not None:
            return b._image
        if b.kind in ("jpeg", "jpeg_tables"):
            data = b.data
            if b.kind == "jpeg_tables" and self.jpeg_tables:
                data = _strip_jpeg(self.jpeg_tables) + _strip_jpeg(data)
            data = _fix_jpeg(data)
            img = Image.open(io.BytesIO(data))
            img.load()
            img = img.convert("RGBA")
            if b.alpha:
                try:
                    a = zlib.decompress(b.alpha)
                    if len(a) == img.width * img.height:
                        img.putalpha(Image.frombytes("L", img.size, a))
                except zlib.error:
                    pass
        else:
            raw = zlib.decompress(b.data)
            w, h = b.width, b.height
            if b.fmt == 3:
                ncol = b.alpha[0] + 1
                csz = 4 if b.lossless_alpha else 3
                pal = raw[:ncol * csz]
                stride = (w + 3) & ~3
                px = raw[ncol * csz:]
                out = bytearray(w * h * 4)
                for yy in range(h):
                    for xx in range(w):
                        ci = px[yy * stride + xx]
                        o = (yy * w + xx) * 4
                        if ci < ncol:
                            c = pal[ci * csz:(ci + 1) * csz]
                            if csz == 4:
                                out[o:o + 4] = c
                            else:
                                out[o:o + 4] = bytes(c) + b"\xff"
                img = Image.frombytes("RGBA", (w, h), bytes(out))
                if b.lossless_alpha:
                    img = _unpremultiply(img)
            elif b.fmt == 4:
                stride = ((w * 2) + 3) & ~3
                out = bytearray(w * h * 4)
                for yy in range(h):
                    for xx in range(w):
                        v = struct.unpack_from(">H", raw, yy * stride + xx * 2)[0]
                        o = (yy * w + xx) * 4
                        out[o] = ((v >> 10) & 31) * 255 // 31
                        out[o + 1] = ((v >> 5) & 31) * 255 // 31
                        out[o + 2] = (v & 31) * 255 // 31
                        out[o + 3] = 255
                img = Image.frombytes("RGBA", (w, h), bytes(out))
            else:  # fmt 5: ARGB / XRGB 32-bit
                import numpy as np
                arr = np.frombuffer(raw[:w * h * 4], dtype=np.uint8).reshape(h, w, 4)
                rgba = arr[:, :, [1, 2, 3, 0]].copy()
                if not b.lossless_alpha:
                    rgba[:, :, 3] = 255
                img = Image.fromarray(rgba, "RGBA")
                if b.lossless_alpha:
                    img = _unpremultiply(img)
        b._image = img
        return img


def _unpremultiply(img):
    import numpy as np
    a = np.asarray(img).astype(np.float32)
    al = a[:, :, 3:4]
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = np.where(al > 0, np.clip(a[:, :, :3] * 255.0 / al, 0, 255), 0)
    out = np.concatenate([rgb, al], axis=2).astype(np.uint8)
    from PIL import Image
    return Image.fromarray(out, "RGBA")


def _strip_jpeg(d: bytes) -> bytes:
    # remove SOI/EOI markers used to join JPEGTables with image data
    if d.startswith(b"\xff\xd9\xff\xd8"):
        d = d[4:]
    if d.endswith(b"\xff\xd9"):
        d = d[:-2]
    if d.startswith(b"\xff\xd8"):
        d = d[2:]
    return d


def _fix_jpeg(d: bytes) -> bytes:
    # Old SWF JPEGs may contain an erroneous EOI+SOI pair right after the header.
    if d.startswith(b"\xff\xd9\xff\xd8"):
        d = d[4:]
    d = d.replace(b"\xff\xd9\xff\xd8", b"")
    if not d.startswith(b"\xff\xd8"):
        d = b"\xff\xd8" + d
    if not d.endswith(b"\xff\xd9"):
        d = d + b"\xff\xd9"
    return d


def build_geometry(events, ftab, ltab):
    """Turn shape events into ([(FillStyle, contours)], [(LineStyle, segments)])."""
    fill_edges: dict[int, list] = {}
    line_paths = []
    cur_line = None
    fs0 = fs1 = ls = 0
    for e in events:
        k = e[0]
        if k == "E":
            seg = e[1]
            if fs1:
                fill_edges.setdefault(fs1, []).append(seg)
            if fs0:
                fill_edges.setdefault(fs0, []).append(_reverse(seg))
            if ls:
                if cur_line is None:
                    cur_line = []
                    line_paths.append((ls, cur_line))
                cur_line.append(seg)
        elif k == "S":
            _, fs0, fs1, nls = e
            if nls != ls:
                cur_line = None
            ls = nls
        else:
            cur_line = None
    fills = [(ftab[i - 1], _stitch(fill_edges[i])) for i in sorted(fill_edges) if i - 1 < len(ftab)]
    lines = [(ltab[i - 1], segs) for i, segs in line_paths if i - 1 < len(ltab)]
    return fills, lines


def _as_quad(seg):
    if seg[0] == "Q":
        return seg
    _, x0, y0, x1, y1 = seg
    return ("Q", x0, y0, (x0 + x1) / 2, (y0 + y1) / 2, x1, y1)


def morph_geometry(shape, ratio: int):
    """Interpolated (fills, lines) for a morph shape at ratio 0..65535."""
    if ratio in shape._cache:
        return shape._cache[ratio]
    t = ratio / 65535.0
    ev1, edges2, ftab, ltab = shape.morph
    lerp = lambda a, b: a + (b - a) * t
    out = []
    k = 0
    for e in ev1:
        if e[0] == "E":
            s1 = e[1]
            s2 = edges2[k][1] if k < len(edges2) else s1
            k += 1
            if s1[0] == "L" and s2[0] == "L":
                seg = ("L",) + tuple(round(lerp(a, b), 3) for a, b in zip(s1[1:], s2[1:]))
            else:
                q1, q2 = _as_quad(s1), _as_quad(s2)
                seg = ("Q",) + tuple(round(lerp(a, b), 3) for a, b in zip(q1[1:], q2[1:]))
            out.append(("E", seg))
        else:
            out.append(e)

    def mix_fill(fs):
        if fs.color2 is None and fs.matrix2 is None:
            return fs
        nf = FillStyle(fs.kind, fs.color, fs.matrix, fs.gradient, fs.spread, fs.interp, fs.focal, fs.bitmap_id)
        if fs.color2 is not None:
            nf.color = tuple(int(lerp(a, b)) for a, b in zip(fs.color, fs.color2))
        if fs.matrix2 is not None:
            nf.matrix = Matrix(*(lerp(a, b) for a, b in zip(fs.matrix.to_list(), fs.matrix2.to_list())))
        if fs.gradient2:
            nf.gradient = [(int(lerp(r1, r2)), tuple(int(lerp(a, b)) for a, b in zip(c1, c2)))
                           for (r1, c1), (r2, c2) in zip(fs.gradient, fs.gradient2)]
        return nf
    ftab2 = [mix_fill(f) for f in ftab]
    ltab2 = []
    for l in ltab:
        nl = LineStyle(int(lerp(l.width, l.width2 if l.width2 is not None else l.width)), l.color)
        if l.color2 is not None:
            nl.color = tuple(int(lerp(a, b)) for a, b in zip(l.color, l.color2))
        ltab2.append(nl)
    geo = build_geometry(out, ftab2, ltab2)
    if len(shape._cache) < 64:
        shape._cache[ratio] = geo
    return geo


def _reverse(seg):
    if seg[0] == "L":
        return ("L", seg[3], seg[4], seg[1], seg[2])
    return ("Q", seg[5], seg[6], seg[3], seg[4], seg[1], seg[2])


def _seg_start(s):
    return (s[1], s[2])


def _seg_end(s):
    return (s[-2], s[-1])


def _stitch(segs):
    """Link oriented edges into closed contours (fill on the right)."""
    by_start: dict = {}
    for i, s in enumerate(segs):
        by_start.setdefault(_seg_start(s), []).append(i)
    used = [False] * len(segs)
    contours = []
    for i in range(len(segs)):
        if used[i]:
            continue
        used[i] = True
        contour = [segs[i]]
        first = _seg_start(segs[i])
        cur = _seg_end(segs[i])
        while cur != first:
            nxt = None
            for j in by_start.get(cur, ()):
                if not used[j]:
                    nxt = j
                    break
            if nxt is None:
                break
            used[nxt] = True
            contour.append(segs[nxt])
            cur = _seg_end(segs[nxt])
        contours.append(contour)
    return contours


# --------------------------------------------------------------------------
# AVM1 action decoding
# --------------------------------------------------------------------------
def decode_actions(blob: bytes):
    """Decode an action blob to a list of (offset, opcode, args, next_offset)."""
    r = Reader(blob)
    out = []
    while r.pos < len(blob):
        off = r.pos
        op = r.u8()
        if op == 0:
            out.append((off, 0, None, r.pos))
            break
        args = None
        if op >= 0x80:
            ln = r.u16()
            body_start = r.pos
            args = blob[body_start:body_start + ln]
            r.pos = body_start + ln
        out.append((off, op, args, r.pos))
    return out


def parse_push(args: bytes, cpool):
    r = Reader(args)
    vals = []
    while r.pos < len(args):
        t = r.u8()
        if t == 0:
            vals.append(r.string())
        elif t == 1:
            vals.append(r.f32())
        elif t == 2:
            vals.append(None)
        elif t == 3:
            vals.append(UNDEFINED)
        elif t == 4:
            vals.append(Register(r.u8()))
        elif t == 5:
            vals.append(bool(r.u8()))
        elif t == 6:
            vals.append(r.f64_avm())
        elif t == 7:
            vals.append(r.s32())
        elif t == 8:
            vals.append(cpool[r.u8()])
        elif t == 9:
            vals.append(cpool[r.u16()])
        else:
            raise ValueError(f"bad push type {t}")
    return vals


class _Undefined:
    def __repr__(self):
        return "undefined"

    def __bool__(self):
        return False


UNDEFINED = _Undefined()


@dataclass(frozen=True)
class Register:
    n: int


def parse_constant_pool(args: bytes):
    r = Reader(args)
    n = r.u16()
    return [r.string() for _ in range(n)]
