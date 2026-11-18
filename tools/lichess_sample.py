"""A sample of human games by rating band, read as a stream from the Lichess open database (public domain).

    python -I tools/lichess_sample.py <out.json> [--month 2026-10] [--per-band 80] [--max-mb 600]

Only the start of the month's file is read (HTTP stream, zstd decompressed on the fly): nothing is kept but the
games chosen. A game is kept when it is rated, rapid or classical, ended normally (not on time or abandon), lasts
at least 15 moves, and both players stand in the same band (each within +-75 of the band's centre).
Output: {"games": [{"band", "white_elo", "black_elo", "result", "tc", "san": [...]}]}
"""
import io
import json
import re
import sys
import urllib.request

import zstandard

BANDS = [600, 800, 1000, 1200, 1400, 1600, 1800, 2000]
HALF = 75


def main():
    out = sys.argv[1]
    month = sys.argv[sys.argv.index("--month") + 1] if "--month" in sys.argv else "2026-10"
    per = int(sys.argv[sys.argv.index("--per-band") + 1]) if "--per-band" in sys.argv else 80
    max_mb = float(sys.argv[sys.argv.index("--max-mb") + 1]) if "--max-mb" in sys.argv else 600
    url = f"https://database.lichess.org/standard/lichess_db_standard_rated_{month}.pgn.zst"
    req = urllib.request.Request(url, headers={"User-Agent": "retro-chess-bench"})
    resp = urllib.request.urlopen(req)
    counted = {"n": 0}

    class Counting(io.RawIOBase):
        def readable(self):
            return True

        def readinto(self, b):
            data = resp.read(len(b))
            counted["n"] += len(data)
            b[:len(data)] = data
            return len(data)

    reader = zstandard.ZstdDecompressor().stream_reader(Counting())
    text = io.TextIOWrapper(reader, encoding="utf-8", errors="replace")
    kept = {b: [] for b in BANDS}
    head = {}
    moves = []
    seen = 0
    for line in text:
        line = line.strip()
        if line.startswith("["):
            m = re.match(r'\[(\w+) "(.*)"\]', line)
            if m:
                head[m.group(1)] = m.group(2)
            continue
        if not line:
            continue
        # the moves line ends a game
        seen += 1
        g = head
        head = {}
        ev = g.get("Event", "")
        if "Rated" not in ev or not ("Rapid" in ev or "Classical" in ev):
            continue
        if g.get("Termination") != "Normal":
            continue
        try:
            we, be = int(g["WhiteElo"]), int(g["BlackElo"])
        except (KeyError, ValueError):
            continue
        band = next((b for b in BANDS if abs(we - b) <= HALF and abs(be - b) <= HALF), None)
        if band is None or len(kept[band]) >= per:
            continue
        mv = re.sub(r"\{[^}]*\}", " ", line)  # clock comments
        mv = re.sub(r"\d+\.(\.\.)?", " ", mv)
        san = [t for t in mv.split() if t not in ("1-0", "0-1", "1/2-1/2", "*") and not t.startswith("$")]
        san = [t.rstrip("!?") for t in san]
        if len(san) < 30:
            continue
        kept[band].append({"band": band, "white_elo": we, "black_elo": be, "result": g.get("Result", "*"),
                           "tc": g.get("TimeControl", ""), "san": san})
        if seen % 2000 == 0 or all(len(v) >= per for v in kept.values()):
            print(f"{counted['n'] / 1e6:.0f} Mo lus, {seen} parties vues :",
                  {b: len(v) for b, v in kept.items()}, flush=True)
        if all(len(v) >= per for v in kept.values()) or counted["n"] > max_mb * 1e6:
            break
    games = [g for b in BANDS for g in kept[b]]
    json.dump({"month": month, "games": games}, open(out, "w", encoding="utf-8"))
    print(f"fini : {len(games)} parties gardées, {counted['n'] / 1e6:.0f} Mo lus,",
          {b: len(v) for b, v in kept.items()})


if __name__ == "__main__":
    main()
