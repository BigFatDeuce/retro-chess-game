# Human-like chess opponents with Stockfish

How Retro Chess makes its opponents play like real people of a given rating, from 400 to 2400, using any UCI engine.
It is meant to be reused: this page explains the idea, the method, the measurements and how to put it in your own
project. The code is MIT (credit "Retro Chess by BigFatDeuce", see [LICENSE](../LICENSE)).

## The problem

Engines are made to be strong; playing weakly *like a human* is another matter.

- **Stockfish's Skill Level / UCI_Elo** searches shallowly and then picks among its best few moves with a random term.
  Its lowest setting is about 1350–1320 Elo, and that scale is anchored on engine-vs-engine matches (CCRL), not on
  people.
- **A share of random moves** is the usual way to go lower. That was the old system in Retro Chess: the 550 level
  played about half its moves at random. It gave a player far worse than any real beginner. It blundered a piece every
  four moves and gave away its queen about once a game, with moves like g2-g4 that no human plays. Its displayed
  ratings were inconsistent too: the "1000" lost 20 games out of 20 to UCI_Elo 1350.

What real beginners do is different: they play sensible-looking moves, but **don't see** what the move allows (the
knight left en prise, the fork, the queen that grabs a defended pawn). Their mistakes are *explained by a shallow look*.

## The idea

Let the engine, at full strength, tell the true value of the candidate moves. Then let a small model decide, move by
move, **which consequences the player sees**:

1. **Candidates.** The engine's best *k* moves (MultiPV, depth 8), plus the "obvious" moves it did not list: captures,
   checks and promotions, valued with `go searchmoves`. A move nobody would consider is never played. Beginners consider
   almost anything (k = 60 at 600), strong players fewer (k = 10 at 2000).
2. **Seen or not seen.** For each candidate the player either sees its consequences (the engine's value) or judges it
   at a glance:
   - the material it takes right away (itself not always noticed: a piece hung by the opponent can go unseen);
   - a check, a developing move;
   - a feel for the position: small differences (up to about 3 pawns) are sensed even unseen, a lost piece is not.
3. **The stakes change what is seen.** The chance of not seeing falls with the rating. A queen left en prise is noticed
   far more often than a pawn, and so is the piece being moved ("can it be taken there?" is the first thing people
   check). Chances you have yourself (tactics) are missed more easily than losses.
4. **Habits.** Castling, developing knights and bishops, not taking the queen out early.
5. **Noise.** A little Gaussian noise between close moves, halved when the game is won (beginners do finish their
   games).
6. **Style.** Each opponent can have a fixed character: `greed` (how much material on offer appeals) and `aggression`
   (how much checks appeal). The same opponent is recognisable from one game to the next.

The player then plays the candidate with the highest perceived value.

### In pseudocode

```
params = interpolate TABLE at rating              # miss, miss_tac, noise, k, greed
evals  = engine.multipv(k, depth 8) + engine.searchmoves(captures/checks it left out, depth 6)
best   = max(evals)
base   = median(evals)                            # what an ordinary move seems worth at a glance
for each candidate c:
    gain    = c.material_taken if random() > miss_tac else 0
    shallow = base + gain * greed + check/develop bonus
    d = c.value - base
    shallow += d * max(0, 1 - |d| / 300) * feel(rating)     # small differences are sensed, big ones are not
    if c.value > shallow + 100:  p_miss = miss_tac           # a chance hidden from the shallow look
    else:
        p_miss = miss
        if best - c.value >= 700: p_miss *= lerp(0.4, 0.15, r)   # the queen: noticed
        if c leaves the moved piece en prise: p_miss *= lerp(0.35, 0.15, r)
    v = (c.value if random() >= p_miss else shallow) + habits(c) + gauss(noise)
play the candidate with the highest v
```

Values are centipawns for the side to move, clamped to ±1500; a mate in n counts ±(3000 − 20 n).

### The table (Lichess rapid rating → settings)

| Rating | miss (a loss unseen) | miss_tac (a chance unseen) | noise (cp) | k | greed |
|---|---|---|---|---|---|
| 400 | 0.97 | 0.88 | 140 | 80 | 1.0 |
| 600 | 0.97 | 0.80 | 110 | 60 | 1.0 |
| 800 | 0.92 | 0.66 | 90 | 44 | 1.0 |
| 1000 | 0.84 | 0.58 | 78 | 32 | 0.95 |
| 1200 | 0.74 | 0.52 | 68 | 24 | 0.9 |
| 1400 | 0.64 | 0.47 | 60 | 18 | 0.8 |
| 1700 | 0.52 | 0.42 | 52 | 13 | 0.7 |
| 2000 | 0.40 | 0.38 | 45 | 10 | 0.6 |
| 2400 | 0.18 | 0.25 | 30 | 7 | 0.4 |

Between two rows everything is interpolated.

## How it was tuned: real games

1. **Human data.** 640 rated rapid/classical games from the [Lichess open database](https://database.lichess.org/)
   (public domain), October 2026. Only games that ended normally, at least 15 moves, both players in the same band (±75
   around 600, 800 … 2000). The file is read as a stream and only the chosen games are kept
   ([tools/lichess_sample.py](../tools/lichess_sample.py)).
2. **The same judge for everyone.** Every move of every game, human or bot, is judged by Stockfish at depth 11
   ([game/tests/human_bench.gd](../game/tests/human_bench.gd)). Only moves played while the game is still open count
   (|value| ≤ 800 cp).
3. **An error profile per player** ([tools/bench_report.py](../tools/bench_report.py)):
   - ACPL (average loss per move);
   - blunders (a loss of 300+) and mistakes (100–299);
   - pieces left en prise, unjustified sacrifices, queens lost, per 100 moves;
   - winning tactics missed;
   - castling by move 15, development.
4. **Fitting.** The bots play each other. The table is adjusted until each level's profile matches the humans of its
   rating, then neighbouring levels play matches to check that strength really increases.

### Result

| Level | ACPL (human) | Blunders | En prise /100 | Unjustified sacrifices /100 | Queen lost /100 |
|---|---|---|---|---|---|
| 600 | 224 (211) | 23 % (21 %) | 9.4 (9.1) | 3.6 (3.7) | 0.6 (1.2) |
| 800 | 187 (178) | 15 % (16 %) | 8.6 (6.2) | 4.1 (2.2) | 0.4 (0.5) |
| 1000 | 166 (147) | 12 % (12 %) | 6.7 (4.4) | 2.9 (1.4) | 0.6 (0.3) |
| 1200 | 135 (144) | 8 % (11 %) | 4.7 (4.2) | 2.2 (1.2) | 0.6 (0.1) |
| 1400 | 117 (125) | 6 % (8 %) | 3.6 (3.0) | 1.2 (0.8) | 0.3 (0.1) |
| 2000 | 98 (105) | 4 % (6 %) | 2.6 (1.8) | 1.3 (0.6) | 0.3 (0.1) |

The old "550" level, for comparison: ACPL 239, 26 % blunders, 13 pieces en prise and 2 queens lost per 100 moves.

Each level beats the one below it (20 games per pair):

| Match | Score of the stronger level |
|---|---|
| 800 vs 600 | 18–2 |
| 1000 vs 800 | 14–6 |
| 1200 vs 1000 | 13–7 |
| 1400 vs 1200 | 13–7 |
| 1700 vs 1400 | 13–7 |
| 2000 vs 1700 | 12–8 |
| 2400 vs 2000 | 16–4 |

Cost: about 30 ms per move natively (two searches at depth 8 and 6). The browser version runs the same engine in
WebAssembly.

Known limits:
- the bots make a few more small mistakes (100–299) than people;
- below 1000 they castle a little less;
- the ratings come from the human error profile that is imitated, not from games against humans;
- the spacing between levels is a bit tighter than between humans above 1200.

## Reusing it

The whole model is [game/src/ai/human_mind.gd](../game/src/ai/human_mind.gd), about 250 lines of GDScript with no
dependency besides a chess move generator. Porting it to another language is a matter of an afternoon.

**In a Godot project**, copy `human_mind.gd` and a position class with the same few calls as
[chess_position.gd](../game/src/chess/chess_position.gd), which can be copied too: legal moves, make/unmake, UCI
conversion, attacked squares. Then, with any UCI engine:

```gdscript
var p := HumanMind.params(800)                       # a Lichess rapid rating
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
answers over several frames).

**Another engine** works as long as it speaks UCI with MultiPV and `searchmoves`. A stronger engine changes nothing at
these depths. Stockfish 11 is used here because it is small enough for the browser and phones.

**Another population** (blitz players, another site, children…): sample their games with `lichess_sample.py` (or your
own PGN), judge them with `human_bench.gd --humans`, compare with `bench_report.py`, and adjust `TABLE`.

### Reproducing the measurements

You need Godot 4.7 and the engine extension built from [native/](../native/README.md); the scripts run headless and
do not need the game's art.

```
python -I tools/lichess_sample.py sample.json --month 2026-10 --per-band 80
godot --headless --path game -s tests/human_bench.gd -- --humans sample.json judged.json 0 640
godot --headless --path game -s tests/human_bench.gd -- bots.json 20 801 new:600:new:800 new:800:new:1000
python tools/bench_report.py judged.json bots.json --anchor new:1000=1000
```

The player names in `human_bench.gd` are:
- `new:<rating>` for this model;
- `uci:<elo>` for Stockfish's own UCI_Elo;
- `human:<band>` for the judged human games.

## Credits

- [Stockfish](https://stockfishchess.org/), GPLv3: the engine that values the moves.
- [Lichess](https://lichess.org/): the open game database the model was tuned on.
- The idea of predicting human moves rather than playing weak engine moves is also behind
  [Maia](https://maiachess.com/) ([paper](https://arxiv.org/abs/2006.01855)), a neural network trained on Lichess
  games. It is more faithful, but starts at 1100 and needs lc0 and a network, too heavy for a browser game.
