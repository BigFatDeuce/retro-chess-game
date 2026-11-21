"""Builds the game's sounds and music from the local library (read only: nothing is written next to it).

- Sound effects: the MP3 data of the DefineSound tags of the library's effects.swf, copied unchanged to
  game/assets/gen/audio/sfx/<file>.mp3. Only what the game uses is copied: every `sound:<name>` cue found
  in the baked atlases (pieces, fx, critters, painted sets), plus the sounds named in game/data/sounds.json
  (interface, steps, ambience, defeat). A cue name is resolved through game/data/sfx_map.json (sound name -> effects file, from the
  library's audio lang table), after lower-casing and turning spaces into underscores.
- Music: the tracks of game/data/music.json (local music library), converted to Ogg Vorbis without
  metadata (ffmpeg) into game/assets/gen/audio/music/<id>.ogg. A track with an "intro" (a short jingle) starts
  with it, then the track fades in (victory and defeat).

Usage: python build_audio.py [--force]
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "swf"))
import swf as S  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
LIB = Path(os.environ.get("GAME_ASSETS_DIR", os.path.expandvars(r"%LOCALAPPDATA%/Ankama/Retro/resources/app/retroclient")))  # a Dofus Retro install
OUT = GAME / "assets/gen/audio"


def norm(name: str) -> str:
    return name.strip().lower().replace(" ", "_").removesuffix(".mp3")


def resolve(name: str, smap: dict) -> str:
    """Cue or sound name -> effects file base name (fx_123)."""
    n = norm(name)
    if n.startswith("fx_"):
        return n
    return smap.get(n, smap.get(name, ""))


def cues() -> set:
    found = set()
    for d in ["pieces", "pieces_1x", "fx", "fx_1x", "critters", "critters_1x", "classic", "classic_1x", "staunton",
              "staunton_1x"]:
        for f in (GAME / "assets/gen" / d).glob("*.json"):
            a = json.loads(f.read_text(encoding="utf-8"))
            for anim in a.get("anims", {}).values():
                for tags in anim.get("events", {}).values():  # frame -> [tag]
                    for e in tags:
                        if e.startswith("sound:"):
                            found.add(e[6:])
    return found


def build_sfx(force: bool):
    smap = {k.lower(): v for k, v in json.loads((GAME / "data/sfx_map.json").read_text(encoding="utf-8"))["map"].items()}
    sounds = json.loads((GAME / "data/sounds.json").read_text(encoding="utf-8"))
    wanted = {}
    for c in cues():
        wanted[resolve(c, smap)] = c
    for group in ["ui", "game", "steps", "ambient"]:
        for key, val in sounds.get(group, {}).items():
            for n in (val if isinstance(val, list) else [val.get("sound", val) if isinstance(val, dict) else val]):
                wanted[resolve(n, smap)] = f"{group}.{key}"
    wanted.pop("", None)
    s = S.SWF(LIB / "audio/effects.swf")
    names = {cid: n for n, cid in s.exports.items()}
    out = OUT / "sfx"
    out.mkdir(parents=True, exist_ok=True)
    done = {}
    for cid, c in s.characters.items():
        if not isinstance(c, S.Sound):
            continue
        base = norm(names.get(cid, f"sound_{cid}"))
        if base not in wanted or c.fmt != 2:
            continue
        dst = out / f"{base}.mp3"
        if force or not dst.exists():
            dst.write_bytes(c.data[2:])  # MP3SOUNDDATA starts with SeekSamples (SI16)
        done[base] = round(c.samples / c.rate, 2)
    missing = sorted(set(wanted) - set(done))
    lengths = dict(sorted(done.items()))
    (GAME / "data/sfx_lengths.json").write_text(json.dumps(lengths, indent=0), encoding="utf-8")
    print(f"sfx: {len(done)} copied, missing: {[(m, wanted[m]) for m in missing]}")
    for base in sorted(done):
        print(f"  {base:10s} {done[base]:6.2f}s  {wanted[base]}")


def build_music(force: bool):
    music = json.loads((GAME / "data/music.json").read_text(encoding="utf-8"))
    out = OUT / "music"
    out.mkdir(parents=True, exist_ok=True)
    for tid, t in music["tracks"].items():
        dst = out / f"{tid}.ogg"
        if dst.exists() and not force:
            continue
        src = Path(t["source"])
        if not src.exists():
            print("missing music", tid, src)
            continue
        enc = ["-map_metadata", "-1", "-ac", "2", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4", str(dst)]
        intro = Path(t["intro"]) if t.get("intro") else None
        if intro and intro.exists():
            # "intro": a short jingle first (victory fanfare, defeat cue), a breath, then the track fading in
            gap = float(t.get("gap", 0.6))
            fmt = "aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo"
            graph = (f"[0:a]{fmt},volume={float(t.get('intro_db', 0))}dB,alimiter=limit=0.95,apad=pad_dur={gap}[a0];[1:a]{fmt},afade=t=in:d={float(t.get('fade_in', 2.0))}[a1];"
                     "[a0][a1]concat=n=2:v=0:a=1[out]")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(intro), "-i", str(src),
                            "-filter_complex", graph, "-map", "[out]"] + enc, check=True)
        else:
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-map", "0:a"] + enc, check=True)
        print("music", tid, dst.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    f = "--force" in sys.argv
    build_sfx(f)
    build_music(f)
