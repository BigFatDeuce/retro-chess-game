"""Timeline player + Skia rasteriser for Dofus Retro SWF symbols.

The player reproduces what the Flash client does with a sprite symbol:
nested timelines advance every tick, frame scripts run, and the client's
global hooks are emulated:

  GAC.applyColor(clip, zone)          -> flat colour from the appearance (setTransform ra=0, rb=R ...)
  GAC.applyAccessory(anchor, slot, dir, headRef?, flag?)
                                       -> attach the accessory symbol "{itemType}_{gfx}" in the anchor
  GAC.applyAnim(this, "static")       -> the animation is over
  GAC.applyEnd(this)                  -> the animation is over (hold last frame)
  SOMA.playSound(name)                -> recorded as a timed sound cue

Everything is rendered from vectors, so output resolution is free.
"""
from __future__ import annotations

import math
import random as _random
from dataclasses import dataclass, field

import numpy as np
import skia

import swf as S
from avm1 import ASObject, Interpreter, UNDEFINED, NativeFunction, to_str, to_number

TWIP = 20.0


# --------------------------------------------------------------------------
# Library: several SWFs whose exported symbols can reference each other
# --------------------------------------------------------------------------
class Library:
    def __init__(self):
        self.swfs: list[S.SWF] = []
        self.exports: dict[str, tuple] = {}

    def add(self, swf_obj: S.SWF, prefer=False):
        self.swfs.append(swf_obj)
        for name, cid in swf_obj.exports.items():
            if prefer or name not in self.exports:
                self.exports[name] = (swf_obj, cid)
        return swf_obj

    def lookup(self, name):
        return self.exports.get(name)


# --------------------------------------------------------------------------
# Appearance: what GAC hooks resolve to
# --------------------------------------------------------------------------
@dataclass
class Appearance:
    colors: dict = field(default_factory=dict)  # zone(int) -> 0xRRGGBB, -1/None = keep original
    # slot -> symbol name, e.g. {1: "16_249", 2: "17_12", 0: "2_5", 4: "82_3"}
    accessories: dict = field(default_factory=dict)
    # optional fine tuning per zone: (r_mult, g_mult, b_mult) applied to the flat colour
    tint: dict = field(default_factory=dict)
    # character ids never drawn: guides the client covers at run time (e.g. the Pandawa's carry marker)
    hidden: set = field(default_factory=set)


# --------------------------------------------------------------------------
# Display objects
# --------------------------------------------------------------------------
class DisplayObject(ASObject):
    """A placed character. Also behaves as an AS object for the interpreter."""

    def __init__(self, player, swf_obj, char, cid, parent=None, name=None):
        super().__init__()
        self.player = player
        self.swf = swf_obj
        self.char = char
        self.cid = cid
        self.parent = parent
        self.inst_name = name
        self.matrix = S.IDENTITY
        self.cxform = S.CX_IDENTITY
        self.color_override: S.CXForm | None = None
        self.ratio = 0
        self.clip_depth = None
        self.blend = None
        self.filters = None
        self.visible = True
        self.children: dict[int, DisplayObject] = {}
        self.frame = 0  # 0-based current frame
        self.playing = True
        self.fresh = True
        self.anim_name = None
        self.ended = False
        self.clip_actions = None
        self.script_controlled = False
        self.removed = False

    # AS2 properties --------------------------------------------------------
    PROPS = ("_x", "_y", "_xscale", "_yscale", "_rotation", "_alpha", "_visible", "_name",
             "_currentframe", "_totalframes", "_parent", "_width", "_height", "_target", "_root")

    def _decomp(self):
        m = self.matrix
        xs = math.hypot(m.a, m.b)
        ys = math.hypot(m.c, m.d)
        if m.a * m.d - m.b * m.c < 0:
            ys = -ys
        rot = math.degrees(math.atan2(m.b, m.a)) if xs else 0.0
        return xs, ys, rot

    def _recompose(self, xs, ys, rot, tx, ty):
        r = math.radians(rot)
        ca, sa = math.cos(r), math.sin(r)
        self.matrix = S.Matrix(xs * ca, xs * sa, -ys * sa, ys * ca, tx, ty)
        self.script_controlled = True

    def get_prop(self, name):
        n = name.lower() if name.startswith("_") else name
        if n not in self.PROPS:
            return NotImplemented
        m = self.matrix
        if n == "_x":
            return m.tx / TWIP
        if n == "_y":
            return m.ty / TWIP
        if n in ("_xscale", "_yscale", "_rotation"):
            xs, ys, rot = self._decomp()
            return {"_xscale": xs * 100, "_yscale": ys * 100, "_rotation": rot}[n]
        if n == "_alpha":
            return self.cxform.am * 100
        if n == "_visible":
            return self.visible
        if n == "_name":
            return self.inst_name or ""
        if n == "_currentframe":
            return float(self.frame + 1)
        if n == "_totalframes":
            return float(self.frame_count)
        if n == "_parent":
            return self.parent if self.parent is not None else UNDEFINED
        if n == "_root":
            r = self
            while r.parent is not None:
                r = r.parent
            return r
        if n in ("_width", "_height"):
            return 0.0
        return UNDEFINED

    def set_prop(self, name, value):
        n = name.lower() if name.startswith("_") else name
        if n not in self.PROPS:
            return False
        v = to_number(value)
        if v != v:  # NaN assignments are ignored by the Flash player
            return True
        m = self.matrix
        xs, ys, rot = self._decomp()
        if n == "_x":
            self._recompose(xs, ys, rot, v * TWIP, m.ty)
        elif n == "_y":
            self._recompose(xs, ys, rot, m.tx, v * TWIP)
        elif n == "_xscale":
            self._recompose(v / 100, ys, rot, m.tx, m.ty)
        elif n == "_yscale":
            self._recompose(xs, v / 100, rot, m.tx, m.ty)
        elif n == "_rotation":
            self._recompose(xs, ys, v, m.tx, m.ty)
        elif n == "_alpha":
            c = self.cxform
            self.cxform = S.CXForm(c.rm, c.gm, c.bm, max(0.0, v / 100), c.ra, c.ga, c.ba, c.aa)
            self.script_controlled = True
        elif n == "_visible":
            self.visible = bool(value) and value is not UNDEFINED
        return True

    # AS2 view ------------------------------------------------------------
    def missing(self, name):
        if name == "_parent":
            return self.parent if self.parent is not None else UNDEFINED
        if name == "lastAnimation":
            return self.player.anim_label or UNDEFINED
        if name == "_currentframe":
            return float(self.frame + 1)
        if name == "_totalframes":
            return float(self.frame_count)
        if name in ("gotoAndStop", "gotoAndPlay", "stop", "play", "nextFrame", "prevFrame",
                    "attachMovie", "createEmptyMovieClip", "duplicateMovieClip", "removeMovieClip",
                    "getDepth", "swapDepths", "end", "getNextHighestDepth", "hitTest", "localToGlobal",
                    "globalToLocal", "getBounds", "setMask", "lineStyle", "beginFill", "endFill",
                    "moveTo", "lineTo", "clear"):
            return NativeFunction(lambda this, a, n=name: self.player.mc_call(this, n, a), name)
        for ch in self.children.values():
            if ch.inst_name == name:
                return ch
        # The client resolves instance names case-insensitively (scripts say R_Tete, clips are R_tete).
        low = name.lower()
        for ch in self.children.values():
            if ch.inst_name and ch.inst_name.lower() == low:
                return ch
        return UNDEFINED

    def __hash__(self):
        return id(self)

    def __eq__(self, other):
        return self is other

    @property
    def is_sprite(self):
        return isinstance(self.char, S.Sprite)

    @property
    def frame_count(self):
        return self.char.frame_count if self.is_sprite else 1


# --------------------------------------------------------------------------
# Player
# --------------------------------------------------------------------------
class Player:
    def __init__(self, library: Library, appearance: Appearance | None = None, accessory_dir=None):
        self.lib = library
        self.app = appearance or Appearance()
        self.accessory_dir = accessory_dir
        self.events: list = []  # (tick, kind, data)
        self.tick = 0
        self.anim_label = None
        self.done = False
        self.done_tick = None
        self.pending_scripts: list = []
        self.rng = _random.Random(1)
        self.pending_load = []
        self.root_params = {}
        gac = _Hooked("GAC", self._gac)
        soma = _Hooked("SOMA", self._soma)
        self.vm = Interpreter(hooks={
            "stop": lambda this: self._set_playing(this, False),
            "play": lambda this: self._set_playing(this, True),
            "goto": self._goto_hook,
            "missing_var": lambda name, this: this.missing(name) if isinstance(this, DisplayObject) else UNDEFINED,
            "random": lambda n: self.rng.randrange(n) if n > 0 else 0,
            "get_property": self._get_property,
            "set_property": self._set_property,
            "remove_sprite": lambda tgt, this: self._remove(self._resolve(tgt, this)),
            "clone_sprite": lambda src, name, depth, this: self._duplicate(self._resolve(src, this), to_str(name), depth),
        })
        self.vm.globals["Math"]["random"] = NativeFunction(lambda t, a: self.rng.random())
        self.vm.globals["GAC"] = gac
        self.vm.globals["SOMA"] = soma
        self.vm.globals["_global"]["GAC"] = gac
        self.vm.max_steps = 10**7

    # -- hooks ------------------------------------------------------------
    def _set_playing(self, this, v):
        if isinstance(this, DisplayObject):
            this.playing = v

    def _goto_hook(self, this, target, play):
        if isinstance(this, DisplayObject):
            self.goto(this, target)
            this.playing = play

    _PROP_IDX = ["_x", "_y", "_xscale", "_yscale", "_currentframe", "_totalframes", "_alpha", "_visible",
                 "_width", "_height", "_rotation", "_target", "_framesloaded", "_name"]

    def _resolve(self, target, this):
        if isinstance(target, DisplayObject):
            return target
        if not isinstance(this, DisplayObject):
            return None
        path = to_str(target) if target not in (None, UNDEFINED) else ""
        if path in ("", "this"):
            return this
        cur = this
        for part in path.replace("/", ".").split("."):
            if part in ("", "this"):
                continue
            if part == "_parent" or part == "..":
                cur = cur.parent
            else:
                cur = cur.missing(part)
            if not isinstance(cur, DisplayObject):
                return None
        return cur

    def _get_property(self, target, idx, this):
        obj = self._resolve(target, this)
        if obj is None or idx >= len(self._PROP_IDX):
            return UNDEFINED
        return obj.get_prop(self._PROP_IDX[idx])

    def _set_property(self, target, idx, value, this):
        obj = self._resolve(target, this)
        if obj is not None and idx < len(self._PROP_IDX):
            obj.set_prop(self._PROP_IDX[idx], value)

    def _remove(self, obj):
        if obj is None:
            return
        obj.removed = True
        p = obj.parent
        if p is None:
            self.done = True
            if self.done_tick is None:
                self.done_tick = self.tick
            return
        for d, c in list(p.children.items()):
            if c is obj:
                del p.children[d]

    def _duplicate(self, src, name, depth):
        if src is None or src.parent is None:
            return UNDEFINED
        dup = DisplayObject(self, src.swf, src.char, src.cid, src.parent, name)
        dup.matrix, dup.cxform, dup.clip_actions = src.matrix, src.cxform, src.clip_actions
        src.parent.children[int(to_number(depth))] = dup
        self._init_clip(dup)
        return dup

    def _attach(self, this, linkage, name, depth):
        ref = None
        if linkage in this.swf.exports:
            ref = (this.swf, this.swf.exports[linkage])
        else:
            ref = self.lib.lookup(linkage)
        if ref is None:
            return UNDEFINED
        child = self.instantiate(ref[0], ref[1], this, name)
        if child is None:
            return UNDEFINED
        this.children[int(to_number(depth))] = child
        self._init_clip(child)
        return child

    def _init_clip(self, child):
        if child.is_sprite:
            self._apply_frame_ops(child, 0)
            self.pending_scripts.append((child, 0))
        self._flush_scripts()
        self._clip_event(child, 0x01)

    def _clip_event(self, inst, flag):
        if inst.clip_actions:
            for ef, blob in inst.clip_actions:
                if ef & flag:
                    try:
                        self.vm.execute(blob, scope=None, this=inst)
                    except RuntimeError:
                        pass

    def mc_call(self, this, name, args):
        if not isinstance(this, DisplayObject):
            return UNDEFINED
        if name == "attachMovie":
            return self._attach(this, to_str(args[0]), to_str(args[1]) if len(args) > 1 else "", args[2] if len(args) > 2 else 0)
        if name == "createEmptyMovieClip":
            child = DisplayObject(self, this.swf, S.Sprite(-1, [S.Frame()]), -1, this, to_str(args[0]))
            this.children[int(to_number(args[1])) if len(args) > 1 else 0] = child
            return child
        if name == "duplicateMovieClip":
            return self._duplicate(this, to_str(args[0]), args[1] if len(args) > 1 else 0)
        if name == "removeMovieClip":
            self._remove(this)
            return UNDEFINED
        if name == "getDepth":
            if this.parent:
                for d, c in this.parent.children.items():
                    if c is this:
                        return float(d)
            return 0.0
        if name == "getNextHighestDepth":
            return float(max(this.children.keys(), default=0) + 1)
        if name == "swapDepths":
            return UNDEFINED
        if name == "end":
            self.events.append((self.tick, "impact", this.inst_name))
            return UNDEFINED
        if name in ("gotoAndStop", "gotoAndPlay"):
            tgt = args[0] if args else 1
            self.goto(this, tgt if isinstance(tgt, str) else int(to_number(tgt)))
            this.playing = name == "gotoAndPlay"
        elif name == "stop":
            this.playing = False
        elif name == "play":
            this.playing = True
        elif name == "nextFrame":
            self.goto(this, this.frame + 2)
            this.playing = False
        elif name == "prevFrame":
            self.goto(this, max(1, this.frame))
            this.playing = False
        return UNDEFINED

    def _soma(self, member, this, args):
        if member == "playSound" and args:
            self.events.append((self.tick, "sound", to_str(args[0])))
        return UNDEFINED

    def _gac(self, member, this, args):
        if member == "applyColor":
            mc = args[0] if args else None
            zone = int(to_number(args[1])) if len(args) > 1 else 0
            if isinstance(mc, DisplayObject):
                col = self.app.colors.get(zone)
                if col is not None and col != -1:
                    r, g, b = (col >> 16) & 255, (col >> 8) & 255, col & 255
                    tr, tg, tb = self.app.tint.get(zone, (1.0, 1.0, 1.0))
                    mc.color_override = S.CXForm(0, 0, 0, 1, r * tr, g * tg, b * tb, 0)
        elif member == "applyAccessory":
            anchor = args[0] if args else None
            slot = int(to_number(args[1])) if len(args) > 1 else -1
            direction = to_str(args[2]) if len(args) > 2 else "R"
            if isinstance(anchor, DisplayObject):
                self._attach_accessory(anchor, slot, direction)
            # Hat slot passes the head clip: frame 2 is the short-hair variant worn under a hat.
            head = args[3] if len(args) > 3 else None
            if slot == 1 and isinstance(head, DisplayObject) and self.app.accessories.get(1):
                if head.is_sprite and head.frame_count > 1:
                    self.goto(head, 2)
                    head.playing = False
        elif member in ("applyAnim", "applyEnd"):
            if not self.done:
                self.done = True
                self.done_tick = self.tick
                self.events.append((self.tick, "end", member))
            clip = args[0] if args else None
            if isinstance(clip, DisplayObject):
                clip.playing = False
        return UNDEFINED

    def _attach_accessory(self, anchor: DisplayObject, slot: int, direction: str):
        sym = self.app.accessories.get(slot)
        if not sym:
            return
        ref = self.lib.lookup(sym)
        if ref is None:
            self.events.append((self.tick, "missing_accessory", sym))
            return
        swf_obj, cid = ref
        acc = self.instantiate(swf_obj, cid, anchor, name="accessory")
        if acc is None:
            return
        # accessories sit above the anchor's own content
        anchor.children[100000 + slot] = acc
        if acc.is_sprite:
            self._apply_frame_ops(acc, 0)
            self.pending_scripts.append((acc, 0))
            labels = acc.char.labels()
            d = direction.lstrip("W") if direction not in labels else direction
            if d in labels:
                self.goto(acc, d)
            acc.playing = False
            self._run_new_frame_scripts(acc)

    # -- instance management ---------------------------------------------
    def instantiate(self, swf_obj, cid, parent, name=None):
        char = swf_obj.characters.get(cid)
        if char is None:
            # imported symbol: resolve through the library by export name
            for url, m in swf_obj.imports:
                for ename, icid in m.items():
                    if icid == cid:
                        ref = self.lib.lookup(ename)
                        if ref:
                            return self.instantiate(ref[0], ref[1], parent, name)
            return None
        return DisplayObject(self, swf_obj, char, cid, parent, name)

    def root_instance(self, symbol):
        """symbol: export name, or (swf, char_id) with char_id 0 meaning the file's root timeline."""
        if isinstance(symbol, tuple):
            swf_obj, cid = symbol
            if cid == 0:
                inst = DisplayObject(self, swf_obj, swf_obj.root, 0, None, "root")
            else:
                inst = self.instantiate(swf_obj, cid, None, name=str(cid))
            inst.update(self.root_params)
            self.anim_label = "root"
            self._enter_frame0(inst)
            return inst
        ref = self.lib.lookup(symbol)
        if ref is None:
            raise KeyError(symbol)
        inst = self.instantiate(ref[0], ref[1], None, name=symbol)
        self.anim_label = symbol
        inst.update(self.root_params)
        self._enter_frame0(inst)
        return inst

    def _enter_frame0(self, inst: DisplayObject):
        if inst.is_sprite:
            inst.frame = 0
            inst.children = {}
            self._apply_frame_ops(inst, 0)
            self.pending_scripts.append((inst, 0))
        self._flush_scripts()

    def _apply_frame_ops(self, inst: DisplayObject, fi: int):
        fr = inst.char.frames[fi]
        for op in fr.ops:
            if isinstance(op, S.PlaceOp):
                self._place(inst, op)
            elif op[0] == "remove":
                inst.children.pop(op[1], None)
            elif op[0] == "sound":
                snd = inst.swf.characters.get(op[1])
                self.events.append((self.tick, "swf_sound", op[1]))

    def _place(self, parent: DisplayObject, op: S.PlaceOp):
        existing = parent.children.get(op.depth)
        if op.char_id is not None and (not op.move or existing is None or existing.cid != op.char_id):
            child = self.instantiate(parent.swf, op.char_id, parent, op.name)
            if child is None:
                return
            if existing is not None and op.move:
                child.matrix = existing.matrix
                child.cxform = existing.cxform
                child.inst_name = existing.inst_name if op.name is None else op.name
                child.clip_depth = existing.clip_depth
            parent.children[op.depth] = child
            child.clip_actions = op.clip_actions
            if op.matrix is not None:
                child.matrix = op.matrix
            if child.is_sprite:
                self._apply_frame_ops(child, 0)
                self.pending_scripts.append((child, 0))
            if op.clip_actions:
                self.pending_load.append(child)
            existing = child
        if existing is None:
            return
        if op.matrix is not None and not existing.script_controlled:
            existing.matrix = op.matrix
        if op.cxform is not None and not existing.script_controlled:
            existing.cxform = op.cxform
        if op.ratio is not None:
            existing.ratio = op.ratio
        if op.name is not None:
            existing.inst_name = op.name
        if op.clip_depth is not None:
            existing.clip_depth = op.clip_depth
        if op.blend is not None:
            existing.blend = op.blend
        if op.filters is not None:
            existing.filters = op.filters
        if op.visible is not None:
            existing.visible = bool(op.visible)

    def goto(self, inst: DisplayObject, target):
        if not inst.is_sprite:
            return
        if isinstance(target, str):
            labels = inst.char.labels()
            if target not in labels:
                low = {k.lower(): v for k, v in labels.items()}
                if target.lower() not in low:
                    return
                fi = low[target.lower()]
            else:
                fi = labels[target]
        else:
            fi = max(0, min(inst.frame_count - 1, int(target) - 1))
        if fi == inst.frame:
            return
        if fi < inst.frame:
            # rebuild the display list from scratch, keeping accessories attached
            keep = {d: c for d, c in inst.children.items() if d >= 100000}
            inst.children = dict(keep)
            for f in range(0, fi + 1):
                self._apply_frame_ops(inst, f)
        else:
            for f in range(inst.frame + 1, fi + 1):
                self._apply_frame_ops(inst, f)
        inst.frame = fi
        self.pending_scripts.append((inst, fi))

    def _run_new_frame_scripts(self, inst):
        self._flush_scripts()

    pending_load: list = None

    def _flush_scripts(self):
        if self.pending_load is None:
            self.pending_load = []
        guard = 0
        while (self.pending_scripts or self.pending_load) and guard < 10000:
            guard += 1
            if self.pending_scripts:
                inst, fi = self.pending_scripts.pop(0)
                if inst.removed or fi >= len(inst.char.frames):
                    continue
                for blob in inst.char.frames[fi].actions:
                    try:
                        self.vm.execute(blob, scope=None, this=inst)
                    except (RuntimeError, IndexError, TypeError, ValueError, ZeroDivisionError, OverflowError):
                        pass
            else:
                self._clip_event(self.pending_load.pop(0), 0x01)

    def step(self, root: DisplayObject):
        """Advance one tick (Flash order: parents first, then children)."""
        self.tick += 1
        self._advance(root)
        self._flush_scripts()
        self._enter_frame_events(root)
        self._flush_scripts()

    def _enter_frame_events(self, inst, depth=0):
        if depth > 40 or inst.removed:
            return
        self._clip_event(inst, 0x02)
        fn = inst.get("onEnterFrame")
        if fn is not None and fn is not UNDEFINED:
            try:
                self.vm.call(fn, inst, [])
            except (RuntimeError, IndexError, TypeError, ValueError, ZeroDivisionError, OverflowError):
                pass
        for ch in list(inst.children.values()):
            self._enter_frame_events(ch, depth + 1)

    def _advance(self, inst: DisplayObject):
        if not inst.is_sprite:
            return
        kids_before = list(inst.children.values())
        if inst.playing and inst.frame_count > 1:
            nf = inst.frame + 1
            if nf >= inst.frame_count:
                nf = 0
                keep = {d: c for d, c in inst.children.items() if d >= 100000}
                inst.children = dict(keep)
                self._apply_frame_ops(inst, 0)
            else:
                self._apply_frame_ops(inst, nf)
            inst.frame = nf
            self.pending_scripts.append((inst, nf))
        for ch in kids_before:
            if ch in inst.children.values():
                self._advance(ch)


class _Hooked(ASObject):
    def __init__(self, name, cb):
        super().__init__()
        self._n = name
        self._cb = cb

    def missing(self, member):
        return NativeFunction(lambda this, a, m=member: self._cb(m, this, a), f"{self._n}.{member}")


# --------------------------------------------------------------------------
# Skia rendering
# --------------------------------------------------------------------------
_path_cache: dict = {}


# Paths are cached per (shape, kind, index). The cache keeps a reference to the shape it was built for and
# checks identity: keyed by id() alone, a freed temporary shape (copies made to retile or strip a
# background) could hand its id to a new shape, which then drew the old shape's geometry.
def _contours_path(contours, key=None, owner=None):
    if key is not None and key in _path_cache and _path_cache[key][0] is owner:
        return _path_cache[key][1]
    p = skia.Path()
    p.setFillType(skia.PathFillType.kEvenOdd)
    for c in contours:
        if not c:
            continue
        p.moveTo(c[0][1], c[0][2])
        for seg in c:
            if seg[0] == "L":
                p.lineTo(seg[3], seg[4])
            else:
                p.quadTo(seg[3], seg[4], seg[5], seg[6])
        p.close()
    if key is not None:
        _path_cache[key] = (owner, p)
    return p


def _line_path(segs, key=None, owner=None):
    if key is not None and key in _path_cache and _path_cache[key][0] is owner:
        return _path_cache[key][1]
    p = skia.Path()
    if segs:
        p.moveTo(segs[0][1], segs[0][2])
        lx, ly = segs[0][1], segs[0][2]
        for seg in segs:
            if (seg[1], seg[2]) != (lx, ly):
                p.moveTo(seg[1], seg[2])
            if seg[0] == "L":
                p.lineTo(seg[3], seg[4])
            else:
                p.quadTo(seg[3], seg[4], seg[5], seg[6])
            lx, ly = seg[-2], seg[-1]
    if key is not None:
        _path_cache[key] = (owner, p)
    return p


def _skm(m: S.Matrix) -> skia.Matrix:
    return skia.Matrix.MakeAll(m.a, m.c, m.tx, m.b, m.d, m.ty, 0, 0, 1)


def _color(rgba, cx: S.CXForm):
    r, g, b, a = cx.apply(rgba)
    f = lambda v: 0 if v != v else int(v)
    return skia.Color(f(r), f(g), f(b), f(a))


def _cx_filter(cx: S.CXForm):
    m = [cx.rm, 0, 0, 0, cx.ra / 255.0,
         0, cx.gm, 0, 0, cx.ga / 255.0,
         0, 0, cx.bm, 0, cx.ba / 255.0,
         0, 0, 0, cx.am, cx.aa / 255.0]
    return skia.ColorFilters.Matrix(m)


_img_cache: dict = {}


def _skimage(swf_obj, bid):
    key = (id(swf_obj), bid)
    if key in _img_cache:
        return _img_cache[key]
    pil = swf_obj.bitmap_image(bid)
    if pil is None:
        _img_cache[key] = None
        return None
    arr = np.ascontiguousarray(np.asarray(pil.convert("RGBA")))
    img = skia.Image.fromarray(arr, colorType=skia.ColorType.kRGBA_8888_ColorType,
                               alphaType=skia.AlphaType.kUnpremul_AlphaType)
    _img_cache[key] = img
    return img


def _fill_paint(fs: S.FillStyle, cx: S.CXForm, swf_obj):
    paint = skia.Paint(AntiAlias=True)
    k = fs.kind
    if k == 0x00:
        paint.setColor(_color(fs.color, cx))
        return paint
    if k in (0x10, 0x12, 0x13):
        cols = [_color(c, cx) for _, c in fs.gradient]
        pos = [r / 255.0 for r, _ in fs.gradient]
        if len(cols) == 1:
            paint.setColor(cols[0])
            return paint
        mode = [skia.TileMode.kClamp, skia.TileMode.kMirror, skia.TileMode.kRepeat, skia.TileMode.kClamp][fs.spread]
        lm = _skm(fs.matrix)
        if k == 0x10:
            sh = skia.GradientShader.MakeLinear([(-16384, 0), (16384, 0)], cols, pos, mode, 0, lm)
        elif k == 0x12:
            sh = skia.GradientShader.MakeRadial((0, 0), 16384, cols, pos, mode, 0, lm)
        else:
            sh = skia.GradientShader.MakeTwoPointConical((fs.focal * 16384, 0), 0, (0, 0), 16384,
                                                         cols, pos, mode, 0, lm)
        paint.setShader(sh)
        return paint
    if k in (0x40, 0x41, 0x42, 0x43):
        img = _skimage(swf_obj, fs.bitmap_id)
        if img is None:
            paint.setColor(skia.ColorTRANSPARENT)
            return paint
        tile = skia.TileMode.kRepeat if k in (0x40, 0x42) else skia.TileMode.kClamp
        # Flash's "non-smoothed" flag only matters at 1:1; our renders magnify the client's bitmaps
        # (ground paintings up to 5x): nearest-neighbour turned them into blocks. Always resample,
        # bicubically when magnifying.
        mag = math.hypot(fs.matrix.a, fs.matrix.b) * CURRENT_PX_PER_TWIP[0]
        samp = (skia.SamplingOptions(skia.CubicResampler.Mitchell()) if mag > 1.05
                else skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear))
        sh = img.makeShader(tile, tile, samp, _skm(fs.matrix))
        paint.setShader(sh)
        if not cx.is_identity():
            paint.setColorFilter(_cx_filter(cx))
        return paint
    paint.setColor(skia.ColorTRANSPARENT)
    return paint


_BLEND = {
    2: skia.BlendMode.kSrcOver,  # layer
    3: skia.BlendMode.kMultiply,
    4: skia.BlendMode.kScreen,
    5: skia.BlendMode.kLighten,
    6: skia.BlendMode.kDarken,
    7: skia.BlendMode.kDifference,
    8: skia.BlendMode.kPlus,
    9: skia.BlendMode.kSrcOver,  # subtract (approx)
    10: skia.BlendMode.kDifference,  # invert (approx)
    11: skia.BlendMode.kSrcOver,  # alpha
    12: skia.BlendMode.kSrcOver,  # erase
    13: skia.BlendMode.kOverlay,
    14: skia.BlendMode.kHardLight,
}


def shape_geometry(shape: S.Shape, ratio: int):
    if shape.is_morph:
        return S.morph_geometry(shape, ratio)
    return shape.fills, shape.lines


# Attach points the client fills at run time and never shows themselves: "mcFix" holds the creature a
# Pandawa carries (its drawing is only a positioning guide).
HIDDEN_ANCHORS = {"mcFix"}


def draw_instance(canvas: skia.Canvas, inst: DisplayObject, m: S.Matrix, cx: S.CXForm, px_scale: float):
    if not inst.visible or inst.inst_name in HIDDEN_ANCHORS:
        return
    if inst.cid in getattr(getattr(inst.player, "app", None), "hidden", ()):
        return
    m = m * inst.matrix
    cx = cx * inst.cxform
    if inst.color_override is not None:
        cx = inst.color_override if cx.is_identity() else S.CXForm(
            0, 0, 0, cx.am * inst.color_override.am,
            inst.color_override.ra * cx.rm + cx.ra,
            inst.color_override.ga * cx.gm + cx.ga,
            inst.color_override.ba * cx.bm + cx.ba, cx.aa)
    if cx.am <= 0 and cx.aa <= 0:
        return
    layer = False
    if inst.blend and inst.blend > 1 or inst.filters:
        paint = skia.Paint()
        if inst.blend and inst.blend > 1:
            paint.setBlendMode(_BLEND.get(inst.blend, skia.BlendMode.kSrcOver))
        if inst.filters:
            imf = _image_filter(inst.filters, px_scale, m)
            if imf is not None:
                paint.setImageFilter(imf)
        canvas.saveLayer(None, paint)
        layer = True
    ch = inst.char
    if isinstance(ch, S.Shape):
        _draw_shape(canvas, inst, ch, m, cx)
    elif isinstance(ch, S.Sprite):
        _draw_children(canvas, inst, m, cx, px_scale)
    if layer:
        canvas.restore()


def _draw_children(canvas, inst, m, cx, px_scale):
    items = sorted(inst.children.items())
    clip_until = []  # stack of (clip_depth)
    for depth, child in items:
        while clip_until and depth > clip_until[-1]:
            clip_until.pop()
            canvas.restore()
        if child.clip_depth:
            path = mask_path(child, m)
            canvas.save()
            canvas.clipPath(path, skia.ClipOp.kIntersect, True)
            clip_until.append(child.clip_depth)
            continue
        draw_instance(canvas, child, m, cx, px_scale)
    while clip_until:
        clip_until.pop()
        canvas.restore()


def mask_path(inst: DisplayObject, m: S.Matrix) -> skia.Path:
    out = skia.Path()
    m = m * inst.matrix
    ch = inst.char
    if isinstance(ch, S.Shape):
        fills, _ = shape_geometry(ch, inst.ratio)
        for i, (fs, contours) in enumerate(fills):
            p = _contours_path(contours, None if ch.is_morph else (id(ch), "f", i), ch)
            q = skia.Path(p)
            q.transform(_skm(m))
            out.addPath(q)
    elif isinstance(ch, S.Sprite):
        for _, c in sorted(inst.children.items()):
            if c.clip_depth:
                continue
            out.addPath(mask_path(c, m))
    out.setFillType(skia.PathFillType.kWinding)
    return out


def _draw_shape(canvas, inst, shape: S.Shape, m: S.Matrix, cx: S.CXForm):
    fills, lines = shape_geometry(shape, inst.ratio)
    canvas.save()
    canvas.concat(_skm(m))
    for i, (fs, contours) in enumerate(fills):
        p = _contours_path(contours, None if shape.is_morph else (id(shape), "f", i), shape)
        canvas.drawPath(p, _fill_paint(fs, cx, inst.swf))
        if fs.kind in (0x40, 0x41, 0x42, 0x43):
            # how much this drawing magnifies the bitmap (output px per bitmap px), and over how many px
            mag = math.hypot(fs.matrix.a, fs.matrix.b) * math.hypot(m.a, m.b) / CURRENT_SS[0]
            r = p.getBounds()
            BITMAP_USE.append((mag, r.width() * r.height() * (math.hypot(m.a, m.b) / CURRENT_SS[0]) ** 2))
    if lines:
        sx = math.hypot(m.a, m.b)
        sy = math.hypot(m.c, m.d)
        scale = max(1e-6, (sx + sy) / 2)
        for i, (ls, segs) in enumerate(lines):
            p = _line_path(segs, None if shape.is_morph else (id(shape), "l", i), shape)
            paint = skia.Paint(AntiAlias=True, Style=skia.Paint.kStroke_Style)
            if ls.fill is not None:
                paint = _fill_paint(ls.fill, cx, inst.swf)
                paint.setStyle(skia.Paint.kStroke_Style)
            else:
                paint.setColor(_color(ls.color, cx))
            # Flash: minimum stroke is a 1px hairline (in render space, ~1/scale twips)
            w = ls.width
            min_w = 1.0 / scale
            paint.setStrokeWidth(max(w, min_w))
            cap = [skia.Paint.kRound_Cap, skia.Paint.kButt_Cap, skia.Paint.kSquare_Cap][min(ls.start_cap, 2)]
            join = [skia.Paint.kRound_Join, skia.Paint.kBevel_Join, skia.Paint.kMiter_Join][min(ls.join, 2)]
            paint.setStrokeCap(cap)
            paint.setStrokeJoin(join)
            canvas.drawPath(p, paint)
    canvas.restore()


CURRENT_PX_PER_TWIP = [1.0 / TWIP]
CURRENT_SS = [1]
BITMAP_USE: list = []  ## (magnification, area in output px) of every bitmap drawn since the list was cleared


def _image_filter(filters, px_scale, m):
    imf = None
    sc = px_scale * TWIP  # filter sizes are in pixels of the stage; scale them with the output
    for f in filters:
        if f[0] == "blur":
            _, bx, by, passes = f
            imf = skia.ImageFilters.Blur(bx * sc / 2.5, by * sc / 2.5, skia.TileMode.kDecal, imf)
        elif f[0] == "glow":
            _, col, bx, by, strength, fl = f
            inner = bool(fl & 0x80)
            knock = bool(fl & 0x40)
            if inner:
                continue
            c = skia.Color(col[0], col[1], col[2], min(255, int(col[3] * min(strength, 2.0))))
            if knock:
                imf = skia.ImageFilters.DropShadowOnly(0, 0, bx * sc / 2.5, by * sc / 2.5, c, imf)
            else:
                imf = skia.ImageFilters.DropShadow(0, 0, bx * sc / 2.5, by * sc / 2.5, c, imf)
        elif f[0] == "dropshadow":
            _, col, bx, by, ang, dist, strength, fl = f
            c = skia.Color(col[0], col[1], col[2], min(255, int(col[3] * min(strength, 2.0))))
            dx = math.cos(ang) * dist * sc
            dy = math.sin(ang) * dist * sc
            imf = skia.ImageFilters.DropShadow(dx, dy, bx * sc / 2.5, by * sc / 2.5, c, imf)
        elif f[0] == "colormatrix":
            mm = list(f[1])
            for i in (4, 9, 14, 19):
                mm[i] /= 255.0
            imf = skia.ImageFilters.ColorFilter(skia.ColorFilters.Matrix(mm), imf)
    return imf


# --------------------------------------------------------------------------
# High-level: render an animation symbol to RGBA frames
# --------------------------------------------------------------------------
@dataclass
class RenderedAnim:
    name: str
    frames: list  # list of numpy RGBA arrays (H, W, 4), all the same size
    origin: tuple  # pixel position of the symbol origin inside each frame
    events: list  # (frame_index, kind, data)
    scale: float
    ended_at: int | None


def render_symbol(lib: Library, symbol: str, appearance: Appearance | None = None, scale: float = 2.0,
                  max_frames: int = 400, canvas_size=(1024, 1024), origin=None, until_end=True,
                  stop_on_loop=True, supersample: int = 1, attach: str | None = None, frame_hook=None):
    """Play `symbol` until its end hook fires or its root timeline loops, rasterising each tick."""
    pl = Player(lib, appearance)
    root = pl.root_instance(symbol)
    if attach:
        # The client attaches named parts (shoot, move, duplicate...) inside the spell clip, which carries
        # cellFrom/cellTo/level: reproduce that so the part's scripts find their _parent values.
        pl._attach(root, attach, attach, 1)
        pl._flush_scripts()
    W, H = canvas_size
    ss = supersample
    ox, oy = origin if origin else (W // 2, int(H * 0.7))
    px_per_twip = scale / TWIP
    CURRENT_PX_PER_TWIP[0] = px_per_twip * ss
    CURRENT_SS[0] = ss
    base = S.Matrix(px_per_twip * ss, 0, 0, px_per_twip * ss, ox * ss, oy * ss)
    frames = []
    events = []
    n_root = root.frame_count
    ticks = 0
    first_sig = None
    while ticks < max_frames:
        surf = skia.Surface(W * ss, H * ss)
        cv = surf.getCanvas()
        cv.clear(skia.ColorTRANSPARENT)
        draw_instance(cv, root, base, S.CX_IDENTITY, px_per_twip * ss)
        img = surf.makeImageSnapshot().toarray(colorType=skia.ColorType.kRGBA_8888_ColorType,
                                                alphaType=skia.AlphaType.kUnpremul_AlphaType)
        if ss > 1:
            img = _downsample(img, ss)
        frames.append(frame_hook(img, (ox, oy)) if frame_hook else img)
        for t, k, d in pl.events:
            events.append((len(frames) - 1, k, d))
        pl.events.clear()
        if until_end and pl.done:
            break
        if first_sig is None:
            first_sig = _signature(root)
        pl.step(root)
        ticks += 1
        if stop_on_loop and not pl.done and _signature(root) == first_sig:
            break
    return RenderedAnim(symbol if isinstance(symbol, str) else "root", frames, (ox, oy), events, scale, pl.done_tick)


def _signature(inst, depth=0):
    if depth > 40:
        return ()
    return (inst.cid, inst.frame, inst.playing,
            tuple((d, _signature(c, depth + 1)) for d, c in sorted(inst.children.items())))


def _any_playing(inst, depth=0):
    if depth > 30:
        return False
    if inst.is_sprite and inst.playing and inst.frame_count > 1:
        return True
    return any(_any_playing(c, depth + 1) for c in inst.children.values())


def _downsample(img, ss):
    h, w = img.shape[0] // ss, img.shape[1] // ss
    a = img[:h * ss, :w * ss].astype(np.float32)
    al = a[:, :, 3:4] / 255.0
    pre = np.concatenate([a[:, :, :3] * al, a[:, :, 3:4]], axis=2)
    pre = pre.reshape(h, ss, w, ss, 4).mean(axis=(1, 3))
    alpha = pre[:, :, 3:4]
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = np.where(alpha > 0, pre[:, :, :3] * 255.0 / alpha, 0)
    return np.clip(np.concatenate([rgb, alpha], axis=2), 0, 255).astype(np.uint8)


def crop_frames(frames, origin, pad=2):
    """Crop all frames to their common bounding box; returns (frames, new_origin, bbox)."""
    ys, xs = [], []
    for f in frames:
        a = f[:, :, 3]
        r = np.where(a.max(axis=1) > 0)[0]
        c = np.where(a.max(axis=0) > 0)[0]
        if len(r):
            ys += [r[0], r[-1]]
            xs += [c[0], c[-1]]
    if not ys:
        return [f[:1, :1] for f in frames], (0, 0), (0, 0, 1, 1)
    h, w = frames[0].shape[:2]
    y0, y1 = max(0, min(ys) - pad), min(h, max(ys) + 1 + pad)
    x0, x1 = max(0, min(xs) - pad), min(w, max(xs) + 1 + pad)
    out = [f[y0:y1, x0:x1] for f in frames]
    return out, (origin[0] - x0, origin[1] - y0), (x0, y0, x1, y1)
