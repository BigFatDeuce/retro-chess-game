"""Tables from tests/human_bench.gd's games: how each computer player errs, and how strong it really is.

    python tools/bench_report.py <games.json> [...] [--anchor uci:1350=1350]

Per player (its moves while the game is still open, |value| <= 800 cp, judged by the engine at full strength):
    ACPL            average loss per move, in centipawns (each loss capped at 1000)
    gaffes %        moves losing 300+ (a piece or more), erreurs % moves losing 100-299
    pièce en prise  per 100 moves: after the move, one of its pieces (knight and up) can be taken for free, and the
                    move really cost 150+
    sacrif.         per 100 moves: the piece just moved stands en prise, unjustified (the move cost 200+)
    dame            per 100 moves: the same with the queen (moved en prise, or left en prise), cost 300+
    mat. perdu      per 100 moves: the move cost 200+ and the material balance fell by 200+ by the next reply
    tactique ratée  % of the positions where the best move won 150+ with a capture or a check, played elsewhere
                    losing 200+
    gratuite ratée  % of the times the opponent's last move left a piece (knight and up) en prise, best taken, and it
                    was not taken
    données         pieces given away (left en prise + moved en prise, unjustified) per 40 moves (about a game)
    ouverture       ACPL over its first 10 moves; développés = minor pieces developed in the first 10 moves;
                    roque = share of games castled by move 15; dame tôt = queen moves in the first 8
Strength: Elo from the scores between the players (maximum likelihood), anchored on --anchor.
"""
import json
import math
import sys
from collections import defaultdict


def load(paths):
    games = []
    for p in paths:
        games += json.load(open(p, encoding="utf-8"))["games"]
    return games


def stats(games):
    S = defaultdict(lambda: defaultdict(float))
    for g in games:
        mv = g["moves"]
        per_side = {0: 0, 1: 0}
        dev = {0: set(), 1: set()}
        castled = {0: False, 1: False}
        qearly = {0: 0, 1: 0}
        for i, m in enumerate(mv):
            p = m["by"]
            s = S[p]
            side = m["side"]
            per_side[side] += 1
            n_own = per_side[side]
            before = m["eval"]
            if i + 1 < len(mv):
                after = -mv[i + 1]["eval"]
            else:
                r = g["result"]
                after = 0.0 if r == "1/2" else (2000.0 if (r == "1-0") == (side == 0) else -2000.0)
            loss = max(0.0, min(1000.0, before - after))
            if abs(before) > 800:
                continue  # the game is already decided: its moves say little about the player
            s["moves"] += 1
            s["loss"] += loss
            s["blunder"] += loss >= 300
            s["mistake"] += 100 <= loss < 300
            s["hung"] += m["hanging"] >= 300 and loss >= 150
            sac = m["moved_en_prise"] >= 300 and loss >= 200 and m["gain"] < m["moved_en_prise"]
            s["sac"] += sac
            s["queen"] += loss >= 300 and (m["moved_en_prise"] >= 900 or m["hanging"] >= 900)
            if i + 1 < len(mv):
                drop = m["mat"] - (-mv[i + 1]["mat"])  # balance after our move vs after their reply (our view)
                s["matlost"] += loss >= 200 and drop >= 200
            # a piece of the opponent's left en prise by its last move: taken or not
            if i > 0 and mv[i - 1]["hanging"] >= 300 and m["best_tactic"]:
                s["free_pos"] += 1
                s["free_miss"] += m["gain"] < mv[i - 1]["hanging"]
            if m["best_tactic"] and before >= 150:
                s["tac_pos"] += 1
                s["tac_miss"] += loss >= 200
            if n_own <= 10:
                s["open_loss"] += loss
                s["open_moves"] += 1
                if m["develop"]:
                    dev[side].add(m["uci"][:2])
            if n_own <= 15 and m["castle"]:
                castled[side] = True
            if n_own <= 8 and m["piece"] == 5:
                qearly[side] += 1
        for side, who in ((0, g["white"]), (1, g["black"])):
            s = S[who]
            s["games"] += 1
            s["dev"] += len(dev[side])
            s["castled"] += castled[side]
            s["qearly"] += qearly[side]
            s["plies"] += len(mv)
            s["own_moves"] += sum(1 for m in mv if m["by"] == who)
    return S


def elo(games, anchor):
    players = sorted({g["white"] for g in games} | {g["black"] for g in games})
    score = defaultdict(float)
    count = defaultdict(int)
    for g in games:
        r = {"1-0": 1.0, "0-1": 0.0}.get(g["result"], 0.5)
        score[(g["white"], g["black"])] += r
        score[(g["black"], g["white"])] += 1 - r
        count[(g["white"], g["black"])] += 1
        count[(g["black"], g["white"])] += 1
    R = {p: 0.0 for p in players}
    for _ in range(3000):
        for p in players:
            if p == anchor[0]:
                continue
            exp = obs = 0.0
            n = 0
            for q in players:
                c = count[(p, q)]
                if c:
                    e = 1 / (1 + 10 ** ((R[q] - R[p]) / 400))
                    exp += c * e
                    obs += score[(p, q)]
                    n += c
            if n:
                obs = min(max(obs, 0.3), n - 0.3)  # a clean sweep would run away
                R[p] += 40 * (obs - exp) / n
    shift = anchor[1] - R.get(anchor[0], 0.0)
    return {p: R[p] + shift for p in players}, score, count


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    anchor = ("uci:1350", 1350.0)
    if "--anchor" in sys.argv:
        k, v = sys.argv[sys.argv.index("--anchor") + 1].split("=")
        anchor = (k, float(v))
        args = [a for a in args if a != sys.argv[sys.argv.index("--anchor") + 1]]
    games = load(args)
    S = stats(games)
    R, score, count = elo(games, anchor)

    def key(p):
        k, e = p.split(":")
        return ({"old": 0, "new": 1, "uci": 2, "human": 3}[k], int(e))
    print(f"{len(games)} parties\n")
    hdr = ("joueur", "Elo mes.", "ACPL", "gaffes%", "erreurs%", "en prise", "sacrif.", "dame", "mat.perdu",
           "tact.ratée%", "gratuite ratée%", "données/40 coups", "ouv.ACPL", "dévelop.", "roque%", "dame tôt",
           "coups/partie")
    print(" | ".join(hdr))
    for p in sorted(S, key=key):
        s = S[p]
        n = s["moves"]
        print(" | ".join([
            p, f"{R.get(p, 0):.0f}", f"{s['loss'] / n:.0f}", f"{100 * s['blunder'] / n:.1f}",
            f"{100 * s['mistake'] / n:.1f}", f"{100 * s['hung'] / n:.1f}", f"{100 * s['sac'] / n:.1f}",
            f"{100 * s['queen'] / n:.1f}", f"{100 * s['matlost'] / n:.1f}",
            f"{100 * s['tac_miss'] / max(1, s['tac_pos']):.0f}",
            f"{100 * s['free_miss'] / max(1, s['free_pos']):.0f}",
            f"{40 * (s['hung'] + s['sac']) / n:.2f}",
            f"{s['open_loss'] / max(1, s['open_moves']):.0f}", f"{s['dev'] / s['games']:.1f}",
            f"{100 * s['castled'] / s['games']:.0f}", f"{s['qearly'] / s['games']:.1f}",
            f"{s['plies'] / s['games'] / 2:.0f}"]))
    print("\nscores (A contre B) :")
    done = set()
    for (a, b), c in sorted(count.items()):
        if (b, a) in done:
            continue
        done.add((a, b))
        print(f"  {a} - {b} : {score[(a, b)]:.1f} / {c}")


if __name__ == "__main__":
    main()
