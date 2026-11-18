"""Checks game/data/pieces.json against the local library: sprites exist, every referenced
animation exists in both directions, and named spells belong to the creature (when it has data).
Usage: python tools/validate_data.py"""
import json, os, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "swf"))
sys.path.insert(0, str(ROOT / "tools"))
import swf as S  # noqa: E402
import monster_attacks as MA  # noqa: E402
from preview import SPRITES  # noqa: E402

errors = []
data = json.loads((ROOT / "game/data/pieces.json").read_text(encoding="utf-8"))
for side, roles in data["sides"].items():
    for role in data["roles"]:
        p = roles.get(role)
        if not p:
            errors.append(f"{side}.{role} manquant"); continue
        f = SPRITES / f"{p['gfx']}.swf"
        if not f.exists():
            errors.append(f"{side}.{role} : sprite {p['gfx']} introuvable"); continue
        exports = set(S.SWF(str(f)).exports)
        anims = {"static", "walk", "hit", "die", p.get("highlight", "static")}
        for kind, a in p["attacks"].items():
            anims.add(a["anim"])
        for a in anims:
            for d in "RL":
                if a + d not in exports:
                    errors.append(f"{side}.{role} ({p['gfx']}) : animation {a}{d} absente")
        real = {n for _, _, lst in MA.attacks(p["gfx"]) for _, n, _, _ in lst if n}
        for kind, a in p["attacks"].items():
            if real and a["spell"] not in real:
                errors.append(f"{side}.{role} : sort « {a['spell']} » inconnu de la créature ({sorted(real)})")
        print(f"ok  {side:5} {role:6} {p['name']:24} gfx {p['gfx']}  sorts réels: {'oui' if real else 'aucune fiche'}")
print("\n".join(errors) if errors else "aucune erreur")
sys.exit(1 if errors else 0)
