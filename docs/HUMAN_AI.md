# Human-like chess opponents with Stockfish

How Retro Chess makes opponents weaker than Stockfish's own weakest setting (UCI_Elo 1350) without making them silly,
using any UCI engine. Above 1350 the game simply uses Stockfish's limited-strength mode (UCI_Elo). This page explains
the idea, the method, the measurements and how to put it in your own project. The code is free software under the
GPL-3.0-or-later (see [LICENSE](../LICENSE)).

## The problem

Engines are made to be strong; playing weakly *in a way that feels right* is another matter.

- **Stockfish's Skill Level / UCI_Elo** works well, but cannot go below about 1350 (on its own scale, anchored on
  engine matches, CCRL).
- **A share of random moves** is the usual way to go lower. It gives an opponent that blunders a piece every four
  moves and gives its queen away once a game, with moves nobody plays (g2-g4 dropping a piece).
- **Copying real beginners** is not enough either. A first version of this model reproduced the mistakes of Lichess
  players of each rating. It was faithful, but not fun to play against: a real 600 player misses about a third of the
  free pieces and gives several pieces away per game. Against the computer, that feels like an opponent who does not
  look at the board.

The goal became: weak opponents who **look at the board** (they take a piece you leave and don't hand theirs over),
and whose weakness lies elsewhere: tactics two moves deep, plans, placement.

## The idea

Let the engine, at full strength, tell the true value of the candidate moves. Then let a small model decide, move by
move, **which consequences the player sees**:

1. **Candidates.** The engine's best *k* moves (MultiPV, depth 8), plus the "obvious" moves it did not list: captures,
   checks and promotions, valued with `go searchmoves`. A move nobody would consider is never played. Weak players
   consider almost anything (k = 80 at 600), stronger ones fewer (k = 24 at 1500).
2. **The one-move check.** On most moves, more often the stronger the player, the player looks one move ahead: can the
   piece I move be taken? Does my move leave a piece en prise? Is one of my pieces attacked now, and which moves save
   it? When the check is done, those moves are judged at their true value.
3. **Gifts.** A piece the opponent leaves en prise is usually noticed, and then taken.
4. **Everything else is seen or not.** For each other candidate, the player either sees its consequences (the engine's
   value) or judges it at a glance:
   - the material it takes right away;
   - a check, a developing move;
   - a sense of position for the small differences between moves, from almost none at 600 to good at 1500.
5. **Imprecision.** Gaussian noise between moves that look alike: large at the bottom (moves without a plan), small at
   the top. A move the player saw drops material gets no noise: it is not played by chance. Noise is halved when the
   game is won (they finish their games).
6. **Habits and style.** Castling, developing, not taking the queen out early. Each opponent can have a fixed
   character: `greed` (how much material on offer appeals) and `aggression` (how much checks appeal).

The player then plays the candidate with the highest perceived value.

### In pseudocode

```
params = interpolate TABLE at elo                 # miss, miss_tac, noise, k, greed, safe, spot, feel
evals  = engine.multipv(k, depth 8) + engine.searchmoves(captures/checks it left out, depth 6)
best   = max(evals); base = median(evals)          # what an ordinary move seems worth at a glance
checks = random() < safe                           # once per move: the one-move look is done or not
spots  = random() < spot                           # once per move: a gift on the board is noticed or not
for each candidate c:
    shallow = base + c.material_taken * greed + check/develop bonus
    d = c.value - base
    shallow += d * max(0, 1 - |d| / 300) * feel                # small differences are sensed, big ones are not
    p_miss = miss_tac if c.value > shallow + 100 else miss     # a hidden chance, or a hidden loss
    seen = random() >= p_miss
    if checks and (c leaves a piece en prise, or c's moved piece can be taken, or c saves an attacked piece):
        seen = true
    if spots and c takes a piece left en prise: seen = true; gift = (c loses less than 100)
    v = (c.value if seen else shallow) + habits(c)
    if not (seen and best - c.value >= 150): v += gauss(noise)
    if gift: v += 3 * noise
play the candidate with the highest v
```

Values are centipawns for the side to move, clamped to ±1500; a mate in n counts ±(3000 − 20 n).

### The table (Elo on Stockfish's UCI_Elo scale → settings)

| Elo | miss | miss_tac | noise (cp) | k | greed | safe | spot | feel |
|---|---|---|---|---|---|---|---|---|
| 600 | 0.97 | 0.90 | 200 | 80 | 1.0 | 0.86 | 0.68 | 0.00 |
| 900 | 0.97 | 0.82 | 160 | 60 | 1.0 | 0.95 | 0.80 | 0.20 |
| 1075 | 0.92 | 0.70 | 120 | 44 | 1.0 | 0.97 | 0.85 | 0.35 |
| 1250 | 0.84 | 0.62 | 90 | 32 | 0.95 | 0.98 | 0.90 | 0.50 |
| 1500 | 0.74 | 0.55 | 65 | 24 | 0.9 | 0.99 | 0.93 | 0.65 |

Between two rows everything is interpolated. From 1350 up the game uses UCI_Elo itself.

## How it was tuned

1. **One judge for everyone.** Every move of every game is judged by Stockfish at depth 11
   ([game/tests/human_bench.gd](../game/tests/human_bench.gd)). Only moves played while the game is still open count
   (|value| ≤ 800 cp).
2. **Error profiles** ([tools/bench_report.py](../tools/bench_report.py)):
   - ACPL (average loss per move);
   - blunders (300+) and mistakes (100–299);
   - pieces left en prise, unjustified sacrifices, queens lost;
   - winning tactics missed;
   - free pieces not taken (the opponent's last move left a piece en prise and taking it was best);
   - pieces given away per 40 moves (about a game);
   - opening quality, development, castling.
3. **Real players as a reference.** 640 rated rapid and classical games from the
   [Lichess open database](https://database.lichess.org/) (public domain), 600 to 2000, were judged the same way
   ([tools/lichess_sample.py](../tools/lichess_sample.py), `human_bench.gd --humans`). They showed what human mistakes
   look like, and why copying them exactly was not the goal: a Lichess 600 player gives about 5 pieces away per
   40 moves.
4. **Targets, then the scale.** The settings were adjusted until the opponents gave away about one or two pieces a
   game and took most free pieces. Then matches against UCI_Elo 1350 and between neighbouring levels placed each row on
   Stockfish's scale.

### Result (30 games per pair, colours alternated)

| Level | Measured Elo | ACPL | Blunders | Free pieces not taken | Pieces given / 40 moves |
|---|---|---|---|---|---|
| 600 | 524 | 203 | 20 % | 35 % | 2.2 |
| 800 | 789 | 176 | 15 % | 26 % | 1.6 |
| 950 | 842 | 172 | 14 % | 17 % | 1.9 |
| 1150 | 1071 | 142 | 9 % | 19 % | 2.1 |
| 1250 | 1238 | 125 | 8 % | 17 % | 1.1 |
| Stockfish UCI_Elo 1350 | 1350 (anchor) | 110 | 7 % | 37 % | 1.2 |
| *Before: random moves, "550"* | *about 390* | *237* | *25 %* | *58 %* | *8.0* |
| *Lichess players, 600* | | *211* | *21 %* | *34 %* | *5.1* |

Cost: about 30–40 ms per move natively. The browser version runs the same engine in WebAssembly, about 60 ms for 40
candidates.

Known limits:
- below 1000 the bots castle rarely (the imprecision drowns the habit);
- the bottom of the scale rests on a chain of matches, not on direct matches with UCI_Elo 1350;
- "free pieces not taken" also counts some cases where a stronger move existed.

## Reusing it

The whole model is [game/src/ai/human_mind.gd](../game/src/ai/human_mind.gd), about 270 lines of GDScript with no
dependency besides a chess move generator. Porting it to another language is a matter of an afternoon.

**In a Godot project**, copy `human_mind.gd` and a position class with the same few calls as
[chess_position.gd](../game/src/chess/chess_position.gd), which can be copied too: legal moves, make/unmake, UCI
conversion, attacked squares. Then, with any UCI engine:

```gdscript
var p := HumanMind.params(800)                       # an Elo on UCI_Elo's scale (below 1350)
engine.send("setoption name MultiPV value %d" % p["k"])
engine.send("position fen " + fen)
engine.send("go depth %d" % p["depth"])
# ... collect the engine's lines until "bestmove"
var evals := HumanMind.read_pv(lines)                # first move -> value
var extra := HumanMind.extras(pos, evals)            # captures / checks it did not list
# if extra is not empty: MultiPV = extra.size(), "go depth 6 searchmoves <extra>", then evals.merge(read_pv(...))
var c := HumanMind.candidates(pos, evals)
var move: String = HumanMind.choose(c["cands"], c["best"], p, rng, {"greed": 1.2})["uci"]
```

[game/src/ai/ai_player.gd](../game/src/ai/ai_player.gd) shows the same thing done asynchronously in a game (the engine
answers over several frames), and the switch to UCI_Elo from 1350.

**Another engine** works as long as it speaks UCI with MultiPV and `searchmoves`. A stronger engine changes nothing at
these depths. Stockfish 11 is used here because it is small enough for the browser and phones.

**Other targets** (closer to real players, or even cleaner): judge reference games with `human_bench.gd --humans`
(the Lichess sample or your own PGN), compare with `bench_report.py`, and adjust `TABLE`.

### Reproducing the measurements

You need Godot 4.7 and the engine extension built from [native/](../native/README.md); the scripts run headless and
do not need the game's art.

```
python -I tools/lichess_sample.py sample.json --month 2026-10 --per-band 80
godot --headless --path game -s tests/human_bench.gd -- --humans sample.json judged.json 0 640
godot --headless --path game -s tests/human_bench.gd -- bots.json 30 961 new:600:new:800 new:1250:uci:1350
python tools/bench_report.py judged.json bots.json --anchor uci:1350=1350
```

The player names in `human_bench.gd` are:
- `new:<elo>` for this model;
- `uci:<elo>` for Stockfish's own UCI_Elo;
- `human:<band>` for the judged human games.

## Credits

- [Stockfish](https://stockfishchess.org/), GPLv3: the engine that values the moves, and plays the stronger
  opponents itself.
- [Lichess](https://lichess.org/): the open game database used as the human reference.
- The idea of predicting human moves rather than playing weak engine moves is also behind
  [Maia](https://maiachess.com/) ([paper](https://arxiv.org/abs/2006.01855)), a neural network trained on Lichess
  games. It is more faithful, but starts at 1100 and needs lc0 and a network, too heavy for a browser game.
