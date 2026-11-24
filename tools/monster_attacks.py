"""Lists the real spells (cast animation + visual effect) of the monsters drawn with a given gfx id.
Usage: python monster_attacks.py <gfx> [<gfx>...]"""
import json, sys
from pathlib import Path
import os
RD = Path(os.environ.get("RETRO_DEFENDERS_DIR", Path(__file__).resolve().parents[2] / "Retro-Defenders"))  # its extracted game data
M = json.load(open(RD / "extract/lang/json/monsters.json", encoding="utf-8"))["M"]
SV = json.load(open(RD / "extract/thirdparty/spell_visuals_codebreak.json", encoding="utf-8"))
SP = json.load(open(RD / "extract/lang/json/spells.json", encoding="utf-8"))
SPN = SP.get("S", SP)
def sname(i):
    s = SPN.get(str(i)); 
    return (s or {}).get("n") if isinstance(s, dict) else None
def attacks(gfx):
    out = []
    for mid, m in M.items():
        if not isinstance(m, dict) or m.get("g") != gfx: continue
        spells = set()
        for g, gd in m.items():
            if g.startswith("g") and isinstance(gd, dict):
                for s in gd.get("s", []): spells.add(s["i"])
        lst = []
        for s in sorted(spells):
            v = SV.get(str(s), {})
            inf = v.get("infos", "?")
            lst.append((s, sname(s) or v.get("name"), v.get("sprite"), inf))
        out.append((mid, m.get("n"), lst))
    return out
if __name__ == "__main__":
    for g in sys.argv[1:]:
        for mid, n, lst in attacks(int(g)):
            print(f"{g} [{mid}] {n}: " + " | ".join(f"{s}:{nm} fx{sp} ({inf})" for s, nm, sp, inf in lst))
