"""Builds the engine extension for Linux and macOS from Windows, with Zig (a C/C++ cross compiler, tools/bin/zig).

    python native/build_cross.py                 # every target
    python native/build_cross.py linux macos     # some of them

Targets (outputs in game/bin/, named as in retrochess_ai.gdextension):
  linux        libretrochess_ai.linux.x86_64.so       glibc 2.28 and newer (2018 on), x86-64-v2 (popcnt)
  macos_x86    libretrochess_ai.macos.x86_64.dylib    macOS 11 and newer, Intel (ad-hoc signed here: Zig only signs arm64)
  macos_arm    libretrochess_ai.macos.arm64.dylib     macOS 11 and newer, Apple Silicon (ad-hoc signed by the linker)
"macos" means both macOS targets. The same sources and options as CMakeLists.txt: godot-cpp (template_release, threads,
no exceptions) and Stockfish 11 (C++14, IS_64BIT USE_POPCNT). Objects are kept in native/build/<target>/ and only
rebuilt when their source is newer.
"""
import hashlib
import os
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

NATIVE = Path(__file__).resolve().parent
ROOT = NATIVE.parent
ZIG = ROOT / "tools" / "bin" / "zig" / ("zig.exe" if os.name == "nt" else "zig")
GCPP = NATIVE / "thirdparty" / "godot-cpp"
SF = NATIVE / "thirdparty" / "stockfish" / "src"
GEN_ROOT = NATIVE / "build" / "godot-cpp-gen"
GEN = GEN_ROOT / "gen"  # the generator writes into a gen/ folder of the directory it is given
OUT = ROOT / "game" / "bin"

TARGETS = {
    "linux": {"triple": "x86_64-linux-gnu.2.28", "cpu": "x86_64_v2", "file": "libretrochess_ai.linux.x86_64.so",
              "defs": ["LINUX_ENABLED", "UNIX_ENABLED"], "link": ["-Wl,--no-undefined", "-Wl,--gc-sections", "-lpthread"]},
    "macos_x86": {"triple": "x86_64-macos.11.0", "cpu": "x86_64_v2", "file": "libretrochess_ai.macos.x86_64.dylib",
                  "defs": ["MACOS_ENABLED", "UNIX_ENABLED"],
                  "link": ["-Wl,-undefined,error", "-Wl,-dead_strip", "-Wl,-headerpad_max_install_names"]},
    "macos_arm": {"triple": "aarch64-macos.11.0", "cpu": "", "file": "libretrochess_ai.macos.arm64.dylib",
                  "defs": ["MACOS_ENABLED", "UNIX_ENABLED"], "link": ["-Wl,-undefined,error", "-Wl,-dead_strip", "-Wl,-headerpad_max_install_names"]},
}


def adhoc_sign(path: Path, ident: str) -> None:
    """Ad-hoc code signature of a 64-bit Mach-O without one (a CodeDirectory of SHA-256 page hashes, as `ld -adhoc_codesign`
    writes): Godot's built-in signer, when it exports the .app, can then replace it."""
    b = bytearray(path.read_bytes())
    magic, _cpu, _sub, _ft, ncmds, sizeofcmds = struct.unpack_from("<IiiIII", b, 0)
    assert magic == 0xFEEDFACF, "Mach-O 64 bits attendu"
    off, linkedit, text, first_sect = 32, None, None, len(b)
    for _ in range(ncmds):
        cmd, cs = struct.unpack_from("<II", b, off)
        assert cmd != 0x1D, "déjà signé"
        if cmd == 0x19:  # LC_SEGMENT_64
            name = bytes(b[off + 8:off + 24]).rstrip(b"\0")
            if name == b"__LINKEDIT":
                linkedit = off
            if name == b"__TEXT":
                text = off
            for k in range(struct.unpack_from("<I", b, off + 64)[0]):
                so = struct.unpack_from("<I", b, off + 72 + 80 * k + 48)[0]
                if so:
                    first_sect = min(first_sect, so)
        off += cs
    assert off + 16 <= first_sect and linkedit is not None and text is not None
    sig_off = (len(b) + 15) & ~15
    page = 4096
    n_pages = (sig_off + page - 1) // page
    ident_b = ident.encode() + b"\0"
    cd_len = 88 + len(ident_b) + 32 * n_pages
    sig_size = (12 + 8 + cd_len + 15) & ~15
    # load command, header, __LINKEDIT covering the signature: all before the page hashes
    struct.pack_into("<IIII", b, off, 0x1D, 16, sig_off, sig_size)
    struct.pack_into("<II", b, 16, ncmds + 1, sizeofcmds + 16)
    le_fileoff = struct.unpack_from("<Q", b, linkedit + 40)[0]
    le_filesize = sig_off + sig_size - le_fileoff
    struct.pack_into("<QQ", b, linkedit + 32, (le_filesize + 0x3FFF) & ~0x3FFF, 0)
    struct.pack_into("<Q", b, linkedit + 48, le_filesize)
    b += bytes(sig_off - len(b))
    hashes = b"".join(hashlib.sha256(bytes(b[i:min(i + page, sig_off)])).digest() for i in range(0, sig_off, page))
    text_off, text_size = struct.unpack_from("<QQ", b, text + 40)
    cd = struct.pack(">9I4BIIIIQQQQ", 0xFADE0C02, cd_len, 0x20400, 0x2, 88 + len(ident_b), 88, 0, n_pages, sig_off,
                     32, 2, 0, 12, 0, 0, 0, 0, 0, text_off, text_size, 0) + ident_b + hashes
    blob = struct.pack(">III", 0xFADE0CC0, 12 + 8 + len(cd), 1) + struct.pack(">II", 0, 20) + cd
    path.write_bytes(bytes(b) + blob + bytes(sig_size - len(blob)))


def generate_bindings() -> None:
    """godot-cpp's generated classes (as its CMake does), once."""
    if (GEN / "src").exists():
        return
    sys.path.insert(0, str(GCPP))
    from binding_generator import generate_bindings  # noqa: E402
    generate_bindings(str(GCPP / "gdextension" / "extension_api.json"), True, "64", "single", str(GEN_ROOT))
    print("bindings générés :", GEN, flush=True)


def compile_one(args) -> str:
    src, obj, cmd = args
    if obj.exists() and obj.stat().st_mtime >= src.stat().st_mtime:
        return ""
    obj.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(cmd + ["-c", str(src), "-o", str(obj)], capture_output=True, text=True)
    if r.returncode != 0:
        return f"{src.name}:\n{r.stderr[-3000:]}"
    return ""


def build(name: str) -> None:
    t = TARGETS[name]
    bdir = NATIVE / "build" / name
    base = [str(ZIG), "c++", "-target", t["triple"], "-O3", "-fPIC", "-fno-exceptions", "-fvisibility=hidden",
            "-ffunction-sections", "-fdata-sections", "-w"] + (["-mcpu=" + t["cpu"]] if t["cpu"] else [])
    gcpp_cmd = base + ["-std=c++17", "-DGDEXTENSION", "-DTHREADS_ENABLED", "-DNDEBUG"] + [f"-D{d}" for d in t["defs"]] + [
        f"-I{GCPP / 'include'}", f"-I{GEN / 'include'}", f"-I{GCPP / 'gdextension'}"]
    sf_cmd = base[:]
    sf_cmd.remove("-fno-exceptions")
    sf_cmd += ["-std=c++14", "-DNDEBUG", "-DIS_64BIT", "-DUSE_POPCNT", f"-I{SF}"]
    ext_cmd = gcpp_cmd[:]
    ext_cmd.remove("-fno-exceptions")
    ext_cmd += [f"-I{SF}"]
    jobs = []
    for src in sorted(list((GCPP / "src").rglob("*.cpp")) + list((GEN / "src").rglob("*.cpp"))):
        rel = src.relative_to(GCPP if GCPP in src.parents else GEN)
        jobs.append((src, bdir / "godot-cpp" / rel.with_suffix(".o"), gcpp_cmd))
    for src in sorted(list(SF.glob("*.cpp")) + list((SF / "syzygy").glob("*.cpp"))):
        if src.name != "main.cpp":
            jobs.append((src, bdir / "stockfish" / src.relative_to(SF).with_suffix(".o"), sf_cmd))
    for src in sorted((NATIVE / "src").glob("*.cpp")):
        jobs.append((src, bdir / "ext" / src.with_suffix(".o").name, ext_cmd))
    print(f"{name} : {len(jobs)} fichiers", flush=True)
    with ThreadPoolExecutor(max(2, (os.cpu_count() or 4) - 2)) as ex:
        errors = [e for e in ex.map(compile_one, jobs) if e]
    if errors:
        sys.exit(f"{name} : {len(errors)} erreurs\n" + "\n".join(errors[:5]))
    out = OUT / t["file"]
    objs = [str(o) for _, o, _ in jobs]
    rsp = bdir / "objects.rsp"
    rsp.write_text("\n".join(o.replace("\\", "/") for o in objs), encoding="utf-8")
    cmd = [str(ZIG), "c++", "-target", t["triple"], "-shared", "-o", str(out), f"@{rsp}", "-s"] + t["link"]
    if name.startswith("macos"):
        cmd += ["-Wl,-install_name,@rpath/" + t["file"]]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"{name} : édition de liens\n{r.stderr[-3000:]}")
    if name == "macos_x86":
        adhoc_sign(out, out.stem)
    print(f"{name} : {out.name} ({out.stat().st_size / 1e6:.1f} Mo)", flush=True)


def main() -> None:
    want = sys.argv[1:] or list(TARGETS)
    names = []
    for w in want:
        names += [k for k in TARGETS if k.startswith("macos")] if w == "macos" else [w]
    generate_bindings()
    for n in names:
        build(n)


if __name__ == "__main__":
    main()
