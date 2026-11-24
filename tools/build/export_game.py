"""Builds distribuables de Retro Chess : PC (Windows, Linux, macOS), navigateur (Web), Android.

    python tools/build/export_game.py windows   -> build/windows/RetroChess.exe, build/release/RetroChess-windows.zip
    python tools/build/export_game.py linux     -> build/linux/RetroChess.x86_64, build/release/RetroChess-linux.tar.gz
    python tools/build/export_game.py macos     -> build/release/RetroChess-macos.zip (RetroChess.app universel, signé ad hoc)
    python tools/build/export_game.py lite      -> build/lite/ : projet allégé, importé (long la première fois)
    python tools/build/export_game.py web       -> build/web/ (découpé pour Cloudflare ; servir : serve_web.py)
    python tools/build/export_game.py android   -> build/release/RetroChess-android.apk (clé de débogage de Godot)
    python tools/build/export_game.py all
    python tools/build/export_game.py source    -> build/release/RetroChess-engine-source.zip (moteur, GPLv3)
    python tools/build/export_game.py deploy    -> build/web publié sur retro-chess.holy-c.men (wrangler)

Windows et Linux partent du projet de travail (game/) : textures en BC7, jeux de sprites 4K et 1x, le moteur natif.
Le navigateur, Android et macOS partent d'un projet allégé, build/lite/ :
  - sans les jeux 4K (pieces, boards, critters, fx) : Atlas.choose_set prend alors le jeu « _1x » ;
  - textures des atlas en Basis Universal (mode d'import 4) : petits fichiers, transcodés pour chaque appareil ;
    portraits, illustrations et logo gardent leur réglage (nets de près).
Navigateur : le moteur d'échecs est le même Stockfish 11 compilé en WebAssembly (native/web, un Web Worker) ;
Cloudflare refuse les fichiers de plus de 25 Mio : .pck et .wasm sont découpés et recollés par fetch().
macOS : le projet allégé a ses textures pour les deux familles de GPU (Intel : BC, Apple : ASTC) ; l'app n'est pas
notarisée (premier lancement : clic droit > Ouvrir). Moteur natif Linux et macOS : native/build_cross.py.
Rien n'est modifié dans game/ hors export_presets.cfg ; build/ est régénérable.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
BUILD = ROOT / "build"
LITE = BUILD / "lite"
RELEASE = BUILD / "release"
GODOT = ROOT / "tools" / "bin" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
WEB_ENGINE = ROOT / "native" / "web" / "out"

FULL_SETS = ("pieces", "boards", "critters", "fx", "classic", "staunton")      # jeux 4K : absents du projet allégé
KEEP_IMPORT = ("cursor",)                                      # dossiers qui gardent leur import (curseur : sans perte, le système en refait une image)
SCALED = ("pieces_1x", "critters_1x", "fx_1x", "classic_1x", "staunton_1x")          # atlas réduits (page_scale, lu par src/render/atlas.gd)
LITE_SCALE = 1.0                                        # le jeu « 1x » vise 1440 lignes : pleine taille (comme Windows)
COPY_DIRS = ("src", "data", "scenes", "bin")

WINDOWS_PRESET = '''[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests/*"
export_path="../build/windows/RetroChess.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=true
application/icon="res://assets/brand/icon.ico"
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version="__VERSION__.0"
application/product_version="__VERSION__.0"
application/company_name=""
application/product_name="Retro Chess"
application/file_description="Retro Chess"
application/copyright="© 2026 BigFatDeuce, GPL-3.0-or-later"
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=true

[preset.1]

name="Linux"
platform="Linux"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests/*"
export_path="../build/linux/RetroChess.x86_64"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
'''

LITE_PRESETS = '''[preset.0]

name="Web"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="lite"
export_filter="all_resources"
include_filter="*.json"
exclude_filter="bin/*, tests/*"
export_path="../web/index.html"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell="res://assets/web/loading_shell.html"
html/head_include="<style>body{background:#0a0d1c}</style>"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false

[preset.1]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="lite"
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests/*"
export_path="../release/RetroChess-android.apk"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=__CODE__
version/name="__VERSION__"
package/unique_name="org.retrochess.game"
package/name="Retro Chess"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
launcher_icons/main_192x192="res://assets/brand/icon_192.png"
launcher_icons/adaptive_foreground_432x432="res://assets/brand/icon_fg.png"
launcher_icons/adaptive_background_432x432="res://assets/brand/icon_bg.png"
launcher_icons/adaptive_monochrome_432x432="res://assets/brand/icon_mono.png"
graphics/opengl_debug=false
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
apk_expansion/enable=false
permissions/custom_permissions=PackedStringArray("android.permission.REQUEST_INSTALL_PACKAGES")
permissions/internet=true

[preset.2]

name="macOS"
platform="macOS"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="lite"
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests/*"
export_path="../release/RetroChess-macos.zip"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.2.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
export/distribution_type=1
binary_format/architecture="universal"
application/icon="res://assets/brand/icon.icns"
application/icon_interpolation=4
application/bundle_identifier="org.retrochess.game"
application/signature=""
application/app_category="Board-games"
application/short_version="__VERSION__"
application/version="__VERSION__"
application/copyright="© 2026 BigFatDeuce, GPL-3.0-or-later"
application/min_macos_version_x86_64="11.00"
application/min_macos_version_arm64="11.00"
application/export_angle=0
display/high_res=true
shader_baker/enabled=false
codesign/codesign=1
codesign/custom_options=PackedStringArray()
'''


def version():
    m = re.search(r'config/version="([^"]+)"', (GAME / "project.godot").read_text(encoding="utf-8"))
    return m.group(1) if m else "0.0.0"


def fill(text):
    v = version()
    code = sum(int(x) * k for x, k in zip(v.split("."), (10000, 100, 1)))
    return text.replace("__VERSION__", v).replace("__CODE__", str(code))


def run_godot(args, cwd, log, timeout=6 * 3600):
    t0 = time.time()
    with open(log, "w", encoding="utf-8", errors="replace") as f:
        code = subprocess.run([str(GODOT)] + args, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout).returncode
    print(f"  godot {' '.join(args[:4])} … : code {code}, {time.time() - t0:.0f} s, journal {log}", flush=True)
    return code


def size_of(path):
    p = Path(path)
    if p.is_file():
        return p.stat().st_size
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())


# --- Windows -------------------------------------------------------------------------------------------------

def export_windows():
    out = BUILD / "windows"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    (GAME / "export_presets.cfg").write_text(fill(WINDOWS_PRESET), encoding="utf-8")
    code = run_godot(["--headless", "--path", ".", "--export-release", "Windows Desktop", str(out / "RetroChess.exe")],
                     GAME, BUILD / "export_windows.log")
    exe = out / "RetroChess.exe"
    ok = exe.exists() and code == 0
    print(f"Windows : {'OK' if ok else 'ÉCHEC'} (code {code}), {size_of(out) / 1e6:.0f} Mo dans {out}", flush=True)
    if not ok:
        return False
    RELEASE.mkdir(parents=True, exist_ok=True)
    z = RELEASE / "RetroChess-windows.zip"
    z.unlink(missing_ok=True)
    readme = (f"Retro Chess {version()}\r\n\r\nUnzip into a folder, then run RetroChess.exe.\r\n"
              "Updates install from inside the game.\r\n\r\nhttps://github.com/BigFatDeuce/retro-chess-game\r\n")
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("RetroChess/README.txt", readme)
        for f in sorted(out.rglob("*")):
            if f.is_file():
                zf.write(f, "RetroChess/" + f.relative_to(out).as_posix())
    print(f"  {z.name} : {z.stat().st_size / 1e6:.0f} Mo", flush=True)
    return True


# --- Linux ---------------------------------------------------------------------------------------------------

def export_linux():
    """Même projet que Windows ; archive tar.gz (garde le droit d'exécution du binaire)."""
    out = BUILD / "linux"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    (GAME / "export_presets.cfg").write_text(fill(WINDOWS_PRESET), encoding="utf-8")
    code = run_godot(["--headless", "--path", ".", "--export-release", "Linux", str(out / "RetroChess.x86_64")],
                     GAME, BUILD / "export_linux.log")
    ok = (out / "RetroChess.x86_64").exists() and code == 0
    print(f"Linux : {'OK' if ok else 'ÉCHEC'} (code {code}), {size_of(out) / 1e6:.0f} Mo dans {out}", flush=True)
    if not ok:
        return False
    return package_linux()


def package_linux():
    """build/linux -> RetroChess-linux.tar.gz. Un binaire Linux ne contient pas d'icône : l'archive fournit icons/ et
    install.sh, qui ajoute le jeu au menu des applications avec son icône."""
    import io
    import tarfile
    from PIL import Image
    out = BUILD / "linux"
    RELEASE.mkdir(parents=True, exist_ok=True)
    z = RELEASE / "RetroChess-linux.tar.gz"
    z.unlink(missing_ok=True)
    readme = (f"Retro Chess {version()}\n\nExtract, then run ./RetroChess.x86_64 (x86-64, glibc 2.28 or newer).\n"
              "./install.sh adds the game, with its icon, to the applications menu (./install.sh --remove undoes it).\n"
              "The game tells you when an update is out.\n\nhttps://github.com/BigFatDeuce/retro-chess-game\n").encode()

    def add(tf, name, data=None, path=None, mode=0o644):
        info = tarfile.TarInfo("RetroChess/" + name)
        info.mode, info.mtime = mode, int(time.time())
        if path is not None:
            info.size = path.stat().st_size
            with open(path, "rb") as f:
                tf.addfile(info, f)
        else:
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

    with tarfile.open(z, "w:gz", compresslevel=6) as tf:
        add(tf, "README.txt", readme)
        add(tf, "install.sh", (ROOT / "tools" / "build" / "linux" / "install.sh").read_bytes().replace(b"\r\n", b"\n"),
            mode=0o755)
        with Image.open(GAME / "assets" / "brand" / "icon.ico") as ico:  # each size drawn on its own by make_icon.py
            for px in (16, 24, 32, 48, 64, 128, 256):
                buf = io.BytesIO()
                ico.ico.getimage((px, px)).convert("RGBA").save(buf, "PNG")
                add(tf, f"icons/{px}.png", buf.getvalue())
        add(tf, "icons/512.png", path=GAME / "assets" / "brand" / "icon.png")
        for f in sorted(out.rglob("*")):
            if f.is_file():
                rel = f.relative_to(out).as_posix()
                add(tf, rel, path=f, mode=0o755 if rel == "RetroChess.x86_64" or f.suffix == ".so" else 0o644)
    print(f"  {z.name} : {z.stat().st_size / 1e6:.0f} Mo", flush=True)
    return True


# --- Projet allégé (navigateur, Android, macOS) ---------------------------------------------------------------------

def lite_project():
    proj = (GAME / "project.godot").read_text(encoding="utf-8")
    proj = re.sub(r'"compress/mode": \d+', '"compress/mode": 4', proj)
    # Basis Universal en haute qualité (UASTC) : la même netteté que les textures BC7 de Windows (ETC1S, plus
    # léger, pixelisait les créatures)
    proj = proj.replace('"compress/high_quality": false', '"compress/high_quality": true')
    (LITE / "project.godot").write_text(proj, encoding="utf-8")
    (LITE / "export_presets.cfg").write_text(fill(LITE_PRESETS), encoding="utf-8")


def shrink(args):
    """Réduit une page d'atlas (alpha prémultiplié pendant le filtrage : pas de liseré sombre au bord des formes)."""
    src, dst, scale = args
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    im = Image.open(src).convert("RGBA")
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    im = im.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, compress_level=3)


def make_lite():
    print("projet allégé :", LITE, flush=True)
    LITE.mkdir(parents=True, exist_ok=True)
    for d in COPY_DIRS:
        shutil.rmtree(LITE / d, ignore_errors=True)
        shutil.copytree(GAME / d, LITE / d)
    lite_project()
    shutil.copy2(GAME / "default_bus_layout.tres", LITE / "default_bus_layout.tres")
    copied = 0
    jobs = []
    for src in (GAME / "assets").rglob("*"):
        if not src.is_file():
            continue
        rel = src.relative_to(GAME / "assets")
        parts = rel.parts
        gen_dir = parts[1] if parts[0] == "gen" and len(parts) > 2 else ""
        if gen_dir in FULL_SETS:
            continue
        # textures of the atlases: the lite project's default import (Basis) applies
        if src.name.endswith(".png.import") and parts[0] == "gen" and gen_dir not in KEEP_IMPORT:
            continue
        dst = LITE / "assets" / rel
        if gen_dir in SCALED and src.suffix == ".png" and LITE_SCALE != 1.0:
            if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
                jobs.append((str(src), str(dst), LITE_SCALE))
            continue
        if gen_dir in SCALED and src.suffix == ".json" and LITE_SCALE != 1.0:
            d = json.loads(src.read_text(encoding="utf-8"))
            if isinstance(d, dict) and "pages" in d:
                d["page_scale"] = LITE_SCALE
            new = json.dumps(d, ensure_ascii=False, separators=(",", ":"))
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.exists() or dst.read_text(encoding="utf-8") != new:
                dst.write_text(new, encoding="utf-8")
            continue
        if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime or dst.stat().st_size != src.stat().st_size:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1
    print(f"  {copied} fichiers copiés, {len(jobs)} pages d'atlas à réduire (×{LITE_SCALE})", flush=True)
    if jobs:
        with ProcessPoolExecutor(max(2, (os.cpu_count() or 4) - 2)) as ex:
            list(ex.map(shrink, jobs, chunksize=2))
    # an atlas imported with older defaults (e.g. before the switch to high quality) is imported again
    want = '"compress/high_quality": true' in (LITE / "project.godot").read_text(encoding="utf-8")
    for imp in (LITE / "assets" / "gen").rglob("*.png.import"):
        if imp.parent.name in KEEP_IMPORT or imp.parent.parent.name in KEEP_IMPORT:
            continue
        if ("compress/high_quality=true" in imp.read_text(encoding="utf-8")) != want:
            imp.unlink()
    print("  import par Godot (long la première fois)…", flush=True)
    run_godot(["--headless", "--path", ".", "--import"], LITE, BUILD / "lite_import.log")
    run_godot(["--headless", "--path", ".", "--import"], LITE, BUILD / "lite_import2.log")
    print(f"  importées : {size_of(LITE / '.godot' / 'imported') / 1e6:.0f} Mo", flush=True)


def export_lite(preset, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    # Android: signed with Godot's debug key (same key on every build: the updates install over the game)
    mode = "--export-debug" if preset == "Android" else "--export-release"
    code = run_godot(["--headless", "--path", ".", mode, preset, str(out)], LITE, BUILD / f"export_{preset.lower()}.log")
    ok = out.exists() and code == 0
    print(f"{preset} : {'OK' if ok else 'ÉCHEC'} (code {code}), {size_of(out) / 1e6:.0f} Mo", flush=True)
    return ok


# --- Navigateur ----------------------------------------------------------------------------------------------

PART_SIZE = 24 * 1024 * 1024
SPLIT_SHIM = """<script>
// Retro Chess: big files are published in parts under 25 MiB (Cloudflare); fetch() puts them back together.
(function () {
\tconst SPLIT = %s;
\tconst AHEAD = 3;
\tconst nativeFetch = window.fetch.bind(window);
\twindow.fetch = function (input, init) {
\t\tconst url = typeof input === 'string' ? input : (input && input.url) || String(input);
\t\tconst clean = url.split('#')[0].split('?')[0];
\t\tconst entry = SPLIT[clean.substring(clean.lastIndexOf('/') + 1)];
\t\tif (!entry) return nativeFetch(input, init);
\t\tconst base = clean.substring(0, clean.lastIndexOf('/') + 1);
\t\tconst pending = [];
\t\tlet next = 0;
\t\tconst ask = () => {
\t\t\twhile (next < entry.parts.length && pending.length < AHEAD) {
\t\t\t\tpending.push(nativeFetch(base + entry.parts[next++], init).then((r) => {
\t\t\t\t\tif (!r.ok) throw new Error('part ' + r.url + ': HTTP ' + r.status);
\t\t\t\t\treturn r;
\t\t\t\t}));
\t\t\t}
\t\t};
\t\tconst body = new ReadableStream({
\t\t\tasync pull(ctl) {
\t\t\t\task();
\t\t\t\tif (pending.length === 0) { ctl.close(); return; }
\t\t\t\ttry {
\t\t\t\t\tconst r = await pending.shift();
\t\t\t\t\task();
\t\t\t\t\tconst reader = r.body.getReader();
\t\t\t\t\tfor (;;) {
\t\t\t\t\t\tconst { done, value } = await reader.read();
\t\t\t\t\t\tif (done) break;
\t\t\t\t\t\tctl.enqueue(value);
\t\t\t\t\t}
\t\t\t\t} catch (e) { ctl.error(e); }
\t\t\t},
\t\t});
\t\treturn Promise.resolve(new Response(body, { status: 200, headers: { 'Content-Type': entry.type, 'Content-Length': String(entry.size) } }));
\t};
})();
</script>
"""

# the canvas is drawn at the screen's own pixels by default (Auto, up to 2160 lines), less when the player picks a
# lower resolution or the performance mode (Settings: window.rcSetHeight, remembered by the page)
DPR_SHIM = """<script>
(function () {
\tconst own = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio') || Object.getOwnPropertyDescriptor(Window.prototype, 'devicePixelRatio');
\tif (!own || !own.get) return;
\tconst real = () => own.get.call(window) || 1;
\tlet maxH = 2160;
\ttry { maxH = Math.min(2160, Math.max(360, parseInt(localStorage.getItem('rc-res'), 10) || 2160)); } catch (e) {}
\twindow.rcSetHeight = function (h) {
\t\tmaxH = Math.min(2160, Math.max(360, h | 0));
\t\ttry { localStorage.setItem('rc-res', String(maxH)); } catch (e) {}
\t\twindow.dispatchEvent(new Event('resize'));
\t};
\ttry { Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: () => Math.min(real(), maxH / Math.max(1, window.innerHeight)) }); } catch (e) {}
})();
</script>
"""


# Mobile browsers (Brave, Safari…) only let a page start its sound from inside a touch, click or key handler. The
# engine resumes its AudioContext later, in its own frame loop: there it is refused and the game stays silent. Every
# AudioContext the page creates is resumed here, inside the gesture itself, with a silent sound played to unlock it.
AUDIO_SHIM = """<script>
(function () {
\tconst AC = window.AudioContext || window.webkitAudioContext;
\tif (!AC) return;
\tconst all = [];
\tconst Wrapped = function (opts) { const c = new AC(opts); all.push(c); return c; };
\tWrapped.prototype = AC.prototype;
\twindow.AudioContext = Wrapped;
\tif (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
\tconst unlock = function () {
\t\tfor (const c of all) {
\t\t\tif (c.state !== 'running') {
\t\t\t\ttry { c.resume(); } catch (e) {}
\t\t\t\ttry { const s = c.createBufferSource(); s.buffer = c.createBuffer(1, 1, c.sampleRate); s.connect(c.destination); s.start(0); } catch (e) {}
\t\t\t}
\t\t}
\t};
\tfor (const ev of ['pointerdown', 'touchstart', 'touchend', 'mousedown', 'click', 'keydown']) {
\t\twindow.addEventListener(ev, unlock, { capture: true, passive: true });
\t}
\tdocument.addEventListener('visibilitychange', function () { if (!document.hidden) unlock(); });
\t// ?audio-debug: a small panel with the state of the sound (contexts, sounds started, errors)
\tif (/audio-debug/.test(location.search)) {
\t\tconst info = { starts: 0, errors: [] };
\t\tconst st = AudioBufferSourceNode.prototype.start;
\t\tAudioBufferSourceNode.prototype.start = function () { info.starts++; return st.apply(this, arguments); };
\t\twindow.addEventListener('error', function (e) { info.errors.push(String(e.message).slice(0, 80)); });
\t\twindow.addEventListener('unhandledrejection', function (e) { info.errors.push(String(e.reason).slice(0, 80)); });
\t\tconst box = document.createElement('div');
\t\tbox.style.cssText = 'position:fixed;left:4px;top:4px;z-index:99;background:rgba(0,0,0,.75);color:#9f9;font:12px monospace;padding:6px;white-space:pre;pointer-events:none';
\t\tsetInterval(function () {
\t\t\tif (!box.parentNode && document.body) document.body.appendChild(box);
\t\t\tbox.textContent = 'contexts: ' + all.map(function (c) { return c.state + ' ' + c.sampleRate + ' t=' + c.currentTime.toFixed(1); }).join(' | ')
\t\t\t\t+ '\\nsons lancés: ' + info.starts + '\\n' + info.errors.slice(-4).join('\\n');
\t\t}, 500);
\t}
})();
</script>
"""


def finish_web(out_dir: Path) -> None:
    for f in ("stockfish.js", "stockfish.wasm", "stockfish_worker.js"):
        shutil.copy2(WEB_ENGINE / f, out_dir / f)
    html = out_dir / "index.html"
    split = {}
    for f in sorted(out_dir.iterdir()):
        if f.is_file() and f.stat().st_size > PART_SIZE and f.suffix in (".pck", ".wasm"):
            parts = []
            with f.open("rb") as src:
                while chunk := src.read(PART_SIZE):
                    name = f"{f.name}.part{len(parts):03d}"
                    (out_dir / name).write_bytes(chunk)
                    parts.append(name)
            split[f.name] = {"size": f.stat().st_size, "parts": parts,
                             "type": "application/wasm" if f.suffix == ".wasm" else "application/octet-stream"}
            f.unlink()
            print(f"  {f.name} : {split[f.name]['size'] / 1e6:.0f} Mo en {len(parts)} morceaux", flush=True)
    text = html.read_text(encoding="utf-8")
    tag = '<script src="index.js"></script>'
    assert tag in text, "index.html : chargeur index.js introuvable"
    shims = AUDIO_SHIM + DPR_SHIM + (SPLIT_SHIM % json.dumps(split) if split else "")
    html.write_text(text.replace(tag, shims + "\t\t" + tag, 1), encoding="utf-8")
    (out_dir / "_headers").write_text("/index.html\n  Cache-Control: no-cache\n/\n  Cache-Control: no-cache\n"
                                      "/*.pck.part*\n  Content-Type: application/octet-stream\n"
                                      "/*.wasm.part*\n  Content-Type: application/wasm\n", encoding="utf-8")
    big = [f.name for f in out_dir.iterdir() if f.is_file() and f.stat().st_size > 25 * 1024 * 1024]
    print(f"  navigateur : {size_of(out_dir) / 1e6:.0f} Mo, " + ("aucun fichier au-dessus de 25 Mio" if not big else f"TROP GROS : {big}"), flush=True)


# --- Source du moteur (GPLv3) --------------------------------------------------------------------------------

def engine_source():
    RELEASE.mkdir(parents=True, exist_ok=True)
    z = RELEASE / "RetroChess-engine-source.zip"
    z.unlink(missing_ok=True)
    native = ROOT / "native"
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(native.rglob("*")):
            rel = f.relative_to(native)
            if not f.is_file() or ".git" in rel.parts or rel.parts[0] == "build" or (len(rel.parts) > 1 and rel.parts[1] == "out"):
                continue
            if "godot-cpp" in rel.parts and ("gen" in rel.parts or f.suffix in (".obj", ".lib", ".a", ".o")):
                continue
            zf.write(f, "retrochess-engine/" + rel.as_posix())
    print(f"  {z.name} : {z.stat().st_size / 1e6:.1f} Mo", flush=True)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    BUILD.mkdir(exist_ok=True)
    if what == "deploy":
        big = [p.name for p in (BUILD / "web").iterdir() if p.is_file() and p.stat().st_size > 25 * 1024 * 1024]
        if big:
            sys.exit("trop gros pour Cloudflare (25 Mio) : " + ", ".join(big))
        npx = shutil.which("npx") or "npx"
        sys.exit(subprocess.run([npx, "--yes", "wrangler@4", "deploy", "-c",
                                 str(ROOT / "tools" / "build" / "cloudflare" / "wrangler.jsonc")]).returncode)
    if what == "source":
        engine_source()
        return
    if what in ("windows", "all"):
        export_windows()
    if what in ("linux", "all"):
        export_linux()
    if what in ("lite", "web", "android", "macos", "all"):
        make_lite()
    if what in ("web", "all"):
        shutil.rmtree(BUILD / "web", ignore_errors=True)
        if export_lite("Web", BUILD / "web" / "index.html"):
            finish_web(BUILD / "web")
    if what in ("android", "all"):
        export_lite("Android", RELEASE / "RetroChess-android.apk")
    if what in ("macos", "all"):
        export_lite("macOS", RELEASE / "RetroChess-macos.zip")
    if what == "all":
        engine_source()


if __name__ == "__main__":
    main()
