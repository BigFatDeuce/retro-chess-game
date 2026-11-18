"""Small AVM1 interpreter.

Enough of ActionScript 2 bytecode to evaluate Dofus lang databases (which build
large object literals) and to trace the GAC/SOMA hook calls made by sprite
frame scripts. It is not a general Flash VM.
"""
from __future__ import annotations

import math

from swf import UNDEFINED, Register, Reader, decode_actions, parse_constant_pool, parse_push



def _safe(fn, *args):
    """Flash Math returns NaN (never raises) on domain errors."""
    try:
        return float(fn(*args))
    except (ValueError, OverflowError, TypeError):
        return float("nan")


def _math1(fn):
    return NativeFunction(lambda t, a: _safe(fn, to_number(a[0]) if a else float("nan")))

class ASObject(dict):
    """Plain AS2 object; keys are property names (str)."""


class ASArray(list):
    pass


class ASFunction:
    def __init__(self, name, params, body, interp, regs=0, v2=False, preload=None):
        self.name = name
        self.params = params
        self.body = body
        self.interp = interp
        self.v2 = v2
        self.regs = regs
        self.preload = preload or []

    def __repr__(self):
        return f"<function {self.name}>"


class NativeFunction:
    def __init__(self, fn, name=""):
        self.fn = fn
        self.name = name

    def __call__(self, this, args):
        return self.fn(this, args)


def to_number(v):
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
    if v is None or v is UNDEFINED:
        return 0.0 if v is None else math.nan
    if isinstance(v, str):
        try:
            s = v.strip()
            if s.lower().startswith("0x"):
                return float(int(s, 16))
            return float(s) if s else 0.0
        except ValueError:
            return math.nan
    return math.nan


def to_str(v):
    if v is UNDEFINED:
        return "undefined"
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if v.is_integer():
            return str(int(v))
        return repr(v)
    if isinstance(v, ASArray):
        return ",".join(to_str(x) for x in v)
    return str(v)


def to_bool(v):
    if isinstance(v, str):
        return len(v) > 0
    if isinstance(v, float) and math.isnan(v):
        return False
    return bool(v) and v is not UNDEFINED


def num_out(v: float):
    """Normalise numbers: integral floats become ints for nicer JSON."""
    if isinstance(v, float) and v.is_integer() and abs(v) < 2**53:
        return int(v)
    return v


def key_of(v):
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    if isinstance(v, int) and not isinstance(v, bool):
        return str(v)
    return to_str(v)


class Interpreter:
    def __init__(self, hooks=None, max_steps=50_000_000):
        self.globals = ASObject()
        self.hooks = hooks or {}
        self.max_steps = max_steps
        self.steps = 0
        g = self.globals
        g["_global"] = g
        g["_root"] = g
        g["Object"] = NativeFunction(lambda this, a: ASObject(), "Object")
        g["Array"] = NativeFunction(lambda this, a: ASArray(a) if len(a) != 1 else ASArray([UNDEFINED] * int(to_number(a[0]))), "Array")
        g["String"] = NativeFunction(lambda this, a: to_str(a[0]) if a else "", "String")
        g["Number"] = NativeFunction(lambda this, a: to_number(a[0]) if a else 0.0, "Number")
        g["Math"] = ASObject(
            floor=NativeFunction(lambda t, a: float(math.floor(to_number(a[0])))),
            ceil=NativeFunction(lambda t, a: float(math.ceil(to_number(a[0])))),
            round=NativeFunction(lambda t, a: float(math.floor(to_number(a[0]) + 0.5))),
            abs=NativeFunction(lambda t, a: abs(to_number(a[0]))),
            max=NativeFunction(lambda t, a: max(to_number(x) for x in a)),
            min=NativeFunction(lambda t, a: min(to_number(x) for x in a)),
            random=NativeFunction(lambda t, a: 0.5),
            PI=math.pi, E=math.e, LN2=math.log(2), LN10=math.log(10), LOG2E=1 / math.log(2),
            LOG10E=1 / math.log(10), SQRT2=math.sqrt(2), SQRT1_2=math.sqrt(0.5),
            sin=_math1(math.sin), cos=_math1(math.cos), tan=_math1(math.tan),
            asin=_math1(math.asin), acos=_math1(math.acos), atan=_math1(math.atan),
            atan2=NativeFunction(lambda t, a: _safe(math.atan2, to_number(a[0]), to_number(a[1]))),
            sqrt=_math1(math.sqrt), exp=_math1(math.exp), log=_math1(math.log),
            pow=NativeFunction(lambda t, a: _safe(math.pow, to_number(a[0]), to_number(a[1]))),
        )
        g["random"] = NativeFunction(lambda t, a: 0.0)
        g["ASSetPropFlags"] = NativeFunction(lambda t, a: UNDEFINED)

    # ------------------------------------------------------------------
    def get_member(self, obj, name):
        name = key_of(name)
        gp = getattr(obj, "get_prop", None)
        if gp is not None:
            v = gp(name)
            if v is not NotImplemented:
                return v
        if isinstance(obj, ASArray):
            if name == "length":
                return float(len(obj))
            if name.isdigit():
                i = int(name)
                return obj[i] if i < len(obj) else UNDEFINED
            if name == "push":
                return NativeFunction(lambda this, a: (this.extend(a), float(len(this)))[1])
            if name == "join":
                return NativeFunction(lambda this, a: (to_str(a[0]) if a else ",").join(to_str(x) for x in this))
            return UNDEFINED
        if isinstance(obj, str):
            if name == "length":
                return float(len(obj))
            if name == "split":
                return NativeFunction(lambda this, a: ASArray(this.split(to_str(a[0]))) if a else ASArray([this]))
            if name == "toUpperCase":
                return NativeFunction(lambda this, a: this.upper())
            if name == "toLowerCase":
                return NativeFunction(lambda this, a: this.lower())
            if name == "substr":
                return NativeFunction(lambda this, a: this[int(to_number(a[0])):][: int(to_number(a[1])) if len(a) > 1 else None])
            if name == "charAt":
                return NativeFunction(lambda this, a: this[int(to_number(a[0]))] if int(to_number(a[0])) < len(this) else "")
            return UNDEFINED
        if isinstance(obj, dict):
            v = obj.get(name, UNDEFINED)
            if v is UNDEFINED and hasattr(obj, "missing"):
                return obj.missing(name)
            return v
        return UNDEFINED

    def set_member(self, obj, name, value):
        name = key_of(name)
        sp = getattr(obj, "set_prop", None)
        if sp is not None and sp(name, value):
            return
        if isinstance(obj, ASArray):
            if name.isdigit():
                i = int(name)
                while len(obj) <= i:
                    obj.append(UNDEFINED)
                obj[i] = value
            elif name == "length":
                n = int(to_number(value))
                del obj[n:]
            return
        if isinstance(obj, dict):
            obj[name] = value

    def call(self, fn, this, args):
        if isinstance(fn, NativeFunction):
            return fn(this, args)
        if isinstance(fn, ASFunction):
            return self.run_function(fn, this, args)
        return UNDEFINED

    def run_function(self, fn: ASFunction, this, args):
        scope = ASObject()
        regs = [UNDEFINED] * max(4, fn.regs + 1)
        if fn.v2:
            ri = 1
            for flag in fn.preload:
                if flag == "this":
                    regs[ri] = this
                    ri += 1
                elif flag == "arguments":
                    regs[ri] = ASArray(args)
                    ri += 1
                elif flag in ("_root", "_global"):
                    regs[ri] = self.globals
                    ri += 1
            for i, (reg, pname) in enumerate(fn.params):
                v = args[i] if i < len(args) else UNDEFINED
                if reg:
                    regs[reg] = v
                else:
                    scope[pname] = v
        else:
            for i, pname in enumerate(fn.params):
                scope[pname] = args[i] if i < len(args) else UNDEFINED
        scope["this"] = this
        return self.execute(fn.body, scope=scope, regs=regs, this=this)

    # ------------------------------------------------------------------
    def lookup(self, name, scope, this):
        if name == "this":
            return this
        if scope is not None and name in scope:
            return scope[name]
        if isinstance(this, dict) and name in this:
            return this[name]
        gp = getattr(this, "get_prop", None)
        if gp is not None:
            v = gp(name)
            if v is not NotImplemented:
                return v
        if name in self.globals:
            return self.globals[name]
        if "." in name or "/" in name:
            parts = name.replace("/", ".").split(".")
            v = self.lookup(parts[0], scope, this)
            for p in parts[1:]:
                v = self.get_member(v, p)
            return v
        h = self.hooks.get("missing_var")
        if h:
            return h(name, this)
        return UNDEFINED

    def execute(self, blob: bytes, scope=None, regs=None, this=None):
        ops = decode_actions(blob)
        index = {off: i for i, (off, _, _, _) in enumerate(ops)}
        stack = []
        cpool = []
        regs = regs if regs is not None else [UNDEFINED] * 4
        pop = lambda: stack.pop() if stack else UNDEFINED
        i = 0
        n = len(ops)
        while i < n:
            self.steps += 1
            if self.steps > self.max_steps:
                raise RuntimeError("AVM1 step limit")
            off, op, args, nxt = ops[i]
            i += 1
            if op == 0:
                break
            elif op == 0x88:
                cpool = parse_constant_pool(args)
            elif op == 0x96:
                for v in parse_push(args, cpool):
                    if isinstance(v, Register):
                        stack.append(regs[v.n] if v.n < len(regs) else UNDEFINED)
                    elif isinstance(v, float) or (isinstance(v, int) and not isinstance(v, bool)):
                        stack.append(float(v))
                    else:
                        stack.append(v)
            elif op == 0x17:
                pop()
            elif op == 0x4C:
                v = pop(); stack += [v, v]
            elif op == 0x4D:
                a = pop(); b = pop(); stack += [a, b]
            elif op == 0x87:
                r = args[0]
                while len(regs) <= r:
                    regs.append(UNDEFINED)
                regs[r] = stack[-1] if stack else UNDEFINED
            elif op == 0x1C:
                name = to_str(pop())
                stack.append(self.lookup(name, scope, this))
            elif op == 0x1D:
                v = pop(); name = to_str(pop())
                if "." in name:
                    parts = name.split(".")
                    o = self.lookup(parts[0], scope, this)
                    for p in parts[1:-1]:
                        o = self.get_member(o, p)
                    self.set_member(o, parts[-1], v)
                elif scope is not None and name in scope:
                    scope[name] = v
                elif hasattr(this, "set_prop"):
                    self.set_member(this, name, v)
                else:
                    self.globals[name] = v
            elif op == 0x3C:  # DefineLocal
                v = pop(); name = to_str(pop())
                (scope if scope is not None else self.globals)[name] = v
            elif op == 0x41:  # DefineLocal2
                name = to_str(pop())
                tgt = scope if scope is not None else self.globals
                tgt.setdefault(name, UNDEFINED)
            elif op == 0x4E:
                name = pop(); obj = pop()
                stack.append(self.get_member(obj, name))
            elif op == 0x4F:
                v = pop(); name = pop(); obj = pop()
                self.set_member(obj, name, v)
            elif op == 0x43:  # InitObject
                cnt = int(to_number(pop()))
                o = ASObject()
                for _ in range(cnt):
                    v = pop(); k = pop()
                    o[key_of(k)] = v
                stack.append(o)
            elif op == 0x42:  # InitArray
                cnt = int(to_number(pop()))
                stack.append(ASArray(pop() for _ in range(cnt)))
            elif op == 0x40:  # NewObject
                name = to_str(pop()); cnt = int(to_number(pop()))
                a = [pop() for _ in range(cnt)]
                ctor = self.lookup(name, scope, this)
                if name == "Array":
                    stack.append(ASArray(a) if len(a) != 1 else ASArray([UNDEFINED] * int(to_number(a[0]))))
                elif name == "Object" or ctor is UNDEFINED:
                    stack.append(ASObject())
                else:
                    o = ASObject()
                    r = self.call(ctor, o, a)
                    stack.append(r if isinstance(r, dict) else o)
            elif op == 0x53:  # NewMethod
                name = pop(); obj = pop(); cnt = int(to_number(pop()))
                a = [pop() for _ in range(cnt)]
                stack.append(ASObject())
            elif op == 0x3D:  # CallFunction
                name = to_str(pop()); cnt = int(to_number(pop()))
                a = [pop() for _ in range(cnt)]
                h = self.hooks.get("call:" + name)
                if h:
                    stack.append(h(this, a))
                else:
                    fn = self.lookup(name, scope, this)
                    stack.append(self.call(fn, this, a))
            elif op == 0x52:  # CallMethod
                name = pop(); obj = pop(); cnt = int(to_number(pop()))
                a = [pop() for _ in range(cnt)]
                if name is UNDEFINED or name == "":
                    stack.append(self.call(obj, this, a))
                else:
                    name = to_str(name)
                    h = self.hooks.get("method")
                    if h:
                        res = h(obj, name, a, this)
                        if res is not NotImplemented:
                            stack.append(res)
                            continue
                    fn = self.get_member(obj, name)
                    stack.append(self.call(fn, obj, a))
            elif op in (0x9B, 0x8E):  # DefineFunction / DefineFunction2
                r = Reader(args)
                fname = r.string()
                nparams = r.u16()
                if op == 0x8E:
                    nregs = r.u8()
                    flags = r.u16()
                    params = []
                    for _ in range(nparams):
                        reg = r.u8()
                        params.append((reg, r.string()))
                    preload = []
                    if flags & 0x0001: preload.append("this")
                    if flags & 0x0004: preload.append("arguments")
                    if flags & 0x0010: preload.append("super")
                    if flags & 0x0040: preload.append("_root")
                    if flags & 0x0080: preload.append("_parent")
                    if flags & 0x0100: preload.append("_global")
                else:
                    params = [r.string() for _ in range(nparams)]
                    nregs = 0
                    preload = []
                size = r.u16()
                body_start = off + 3 + len(args)
                body = blob[body_start: body_start + size]
                fn = ASFunction(fname, params, body, self, nregs, op == 0x8E, preload)
                # skip body
                tgt = body_start + size
                while i < n and ops[i][0] < tgt:
                    i += 1
                if fname:
                    (scope if scope is not None else self.globals)[fname] = fn
                else:
                    stack.append(fn)
            elif op == 0x3E:  # Return
                return pop()
            elif op == 0x99:  # Jump
                tgt = nxt + int.from_bytes(args[:2], "little", signed=True)
                i = index.get(tgt, n)
            elif op == 0x9D:  # If
                cond = pop()
                if to_bool(cond):
                    tgt = nxt + int.from_bytes(args[:2], "little", signed=True)
                    i = index.get(tgt, n)
            elif op == 0x12:
                stack.append(not to_bool(pop()))
            elif op == 0x47:  # Add2
                b = pop(); a = pop()
                if isinstance(a, str) or isinstance(b, str):
                    stack.append(to_str(a) + to_str(b))
                else:
                    stack.append(to_number(a) + to_number(b))
            elif op == 0x0A:
                b = pop(); a = pop(); stack.append(to_number(a) + to_number(b))
            elif op == 0x0B:
                b = pop(); a = pop(); stack.append(to_number(a) - to_number(b))
            elif op == 0x0C:
                b = pop(); a = pop(); stack.append(to_number(a) * to_number(b))
            elif op == 0x0D:
                b = pop(); a = pop()
                bn = to_number(b)
                stack.append(to_number(a) / bn if bn else math.inf)
            elif op == 0x3F:
                b = pop(); a = pop()
                bn = to_number(b)
                stack.append(math.fmod(to_number(a), bn) if bn else math.nan)
            elif op == 0x50:
                stack.append(to_number(pop()) + 1)
            elif op == 0x51:
                stack.append(to_number(pop()) - 1)
            elif op == 0x60:
                b = int(to_number(pop())); a = int(to_number(pop())); stack.append(float(a & b))
            elif op == 0x61:
                b = int(to_number(pop())); a = int(to_number(pop())); stack.append(float(a | b))
            elif op == 0x63:
                b = int(to_number(pop())) & 31; a = int(to_number(pop())); stack.append(float(a << b))
            elif op == 0x64:
                b = int(to_number(pop())) & 31; a = int(to_number(pop())); stack.append(float(a >> b))
            elif op in (0x49, 0x66, 0x0E):  # Equals2, StrictEquals, Equals
                b = pop(); a = pop()
                if op == 0x49 and (isinstance(a, float) or isinstance(b, float)) and not (a is UNDEFINED or b is UNDEFINED or a is None or b is None):
                    stack.append(to_number(a) == to_number(b))
                else:
                    stack.append(a == b and type(a) == type(b) or (a is b))
            elif op in (0x48, 0x0F):  # Less2 / Less
                b = pop(); a = pop()
                if isinstance(a, str) and isinstance(b, str):
                    stack.append(a < b)
                else:
                    stack.append(to_number(a) < to_number(b))
            elif op == 0x67:  # Greater
                b = pop(); a = pop()
                stack.append(to_number(a) > to_number(b))
            elif op == 0x10:  # And
                b = pop(); a = pop(); stack.append(to_bool(a) and to_bool(b))
            elif op == 0x11:
                b = pop(); a = pop(); stack.append(to_bool(a) or to_bool(b))
            elif op == 0x44:  # TypeOf
                v = pop()
                t = ("undefined" if v is UNDEFINED else "null" if v is None else "boolean" if isinstance(v, bool)
                     else "number" if isinstance(v, float) else "string" if isinstance(v, str)
                     else "function" if isinstance(v, (ASFunction, NativeFunction)) else "object")
                stack.append(t)
            elif op == 0x4A:
                stack.append(to_number(pop()))
            elif op == 0x4B:
                stack.append(to_str(pop()))
            elif op == 0x21:  # StringAdd
                b = pop(); a = pop(); stack.append(to_str(a) + to_str(b))
            elif op == 0x3A:  # Delete
                name = pop(); obj = pop()
                if isinstance(obj, dict):
                    obj.pop(key_of(name), None)
                stack.append(True)
            elif op == 0x3B:
                pop(); stack.append(True)
            elif op == 0x07:  # Stop
                h = self.hooks.get("stop")
                if h:
                    h(this)
            elif op == 0x06:  # Play
                h = self.hooks.get("play")
                if h:
                    h(this)
            elif op == 0x81:  # GotoFrame
                h = self.hooks.get("goto")
                if h:
                    h(this, int.from_bytes(args[:2], "little") + 1, False)
            elif op == 0x8C:  # GoToLabel
                h = self.hooks.get("goto")
                if h:
                    h(this, Reader(args).string(), False)
            elif op == 0x9F:  # GotoFrame2
                v = pop()
                play = bool(args[0] & 1)
                h = self.hooks.get("goto")
                if h:
                    h(this, v if isinstance(v, str) else int(to_number(v)), play)
            elif op == 0x30:  # RandomNumber
                mx = int(to_number(pop()))
                h = self.hooks.get("random")
                stack.append(float(h(mx)) if h else (0.0 if mx <= 1 else 1.0))
            elif op == 0x34:  # GetTime
                stack.append(0.0)
            elif op == 0x22:  # GetProperty
                idx = int(to_number(pop())); target = pop()
                h = self.hooks.get("get_property")
                stack.append(h(target, idx, this) if h else UNDEFINED)
            elif op == 0x23:  # SetProperty
                v = pop(); idx = int(to_number(pop())); target = pop()
                h = self.hooks.get("set_property")
                if h:
                    h(target, idx, v, this)
            elif op == 0x26:  # Trace
                pop()
            elif op == 0x8B:  # SetTarget
                pass
            elif op == 0x20:  # SetTarget2
                pop()
            elif op == 0x55:  # Enumerate2
                obj = pop()
                stack.append(None)
                if isinstance(obj, dict):
                    for k in reversed(list(obj.keys())):
                        stack.append(k)
                elif isinstance(obj, list):
                    for k in reversed(range(len(obj))):
                        stack.append(str(k))
            elif op == 0x46:  # Enumerate
                name = to_str(pop())
                obj = self.lookup(name, scope, this)
                stack.append(None)
                if isinstance(obj, dict):
                    for k in reversed(list(obj.keys())):
                        stack.append(k)
            elif op == 0x94:  # With
                pass
            elif op == 0x69:  # Extends
                pop(); pop()
            elif op == 0x54:  # InstanceOf
                pop(); pop(); stack.append(False)
            elif op == 0x2B:  # CastOp
                o = pop(); pop(); stack.append(o)
            elif op == 0x2C:  # ImplementsOp
                pop(); cnt = int(to_number(pop()))
                for _ in range(cnt):
                    pop()
            elif op == 0x24:  # CloneSprite
                depth = pop(); newname = pop(); src = pop()
                h = self.hooks.get("clone_sprite")
                if h:
                    h(src, newname, depth, this)
            elif op == 0x25:  # RemoveSprite
                tgt = pop()
                h = self.hooks.get("remove_sprite")
                if h:
                    h(tgt, this)
            elif op == 0x9A:  # GetURL2
                pop(); pop()
            elif op == 0x83:  # GetURL
                pass
            elif op == 0x8D:  # WaitForFrame2
                pop()
            elif op == 0x28:  # StartDrag
                pop(); pop()
                if to_bool(pop()):
                    pop(); pop(); pop(); pop()
            elif op == 0x29:  # EndDrag
                pass
            elif op == 0x09:  # StopSounds
                pass
            elif op == 0x31:  # MBStringLength
                stack.append(float(len(to_str(pop()))))
            elif op == 0x14:  # StringLength
                stack.append(float(len(to_str(pop()))))
            elif op == 0x15:  # StringExtract
                cnt = int(to_number(pop())); idx = int(to_number(pop())); s = to_str(pop())
                stack.append(s[idx - 1: idx - 1 + cnt])
            elif op == 0x13:  # StringEquals
                b = pop(); a = pop(); stack.append(to_str(a) == to_str(b))
            elif op == 0x29:
                pass
            elif op == 0x68:  # StringGreater
                b = pop(); a = pop(); stack.append(to_str(a) > to_str(b))
            elif op == 0x18:  # ToInteger
                stack.append(float(int(to_number(pop()))))
            elif op == 0x32 or op == 0x33 or op == 0x35 or op == 0x36:
                pass
            elif op == 0x2A:  # Throw
                return UNDEFINED
            elif op == 0x8F:  # Try - skip
                pass
            elif op == 0x04 or op == 0x05:  # NextFrame / PrevFrame
                pass
            elif op == 0x08:  # ToggleQuality
                pass
            else:
                h = self.hooks.get("unknown")
                if h:
                    h(op)
        return UNDEFINED


class HookObject(ASObject):
    """Object whose unknown members resolve via a callback (for GAC / SOMA)."""

    def __init__(self, name, cb):
        super().__init__()
        self._name = name
        self._cb = cb

    def missing(self, member):
        return NativeFunction(lambda this, a, m=member: self._cb(m, this, a), f"{self._name}.{member}")


def to_json(v):
    """Convert interpreter values to JSON-serialisable python."""
    if v is UNDEFINED:
        return None
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            return None
        return num_out(v)
    if isinstance(v, ASArray):
        return [to_json(x) for x in v]
    if isinstance(v, dict):
        return {k: to_json(x) for k, x in v.items() if not k.startswith("_") and k != "this"
                and not isinstance(x, (ASFunction, NativeFunction))}
    if isinstance(v, (ASFunction, NativeFunction)):
        return None
    return v
