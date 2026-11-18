class_name HumanMind
extends RefCounted
## A human-like move choice on top of the engine's own evaluations (see docs/HUMAN_AI.md).
##
## The engine (Stockfish 11 at full strength, MultiPV) gives the true value of the reasonable moves; the player
## does not see all of it. For each move it weighs, a player of a given strength either sees its consequences
## (the engine's value) or only what is on the board right after it (the material it takes, a developing move, a
## check), with no thought for the reply. So a beginner misses the fork it could have played, walks into a pin, drifts
## without a plan: errors that a shallow look explains. Never a move
## nobody would think of: the moves weighed are the engine's best few plus the obvious ones (captures, checks,
## promotions).
## Like people, it looks twice at what it moves: a quick one-move check ("can this be taken next move? is a piece of
## mine attacked?") is done on most moves, more often the stronger the player, and a piece the opponent leaves en
## prise is usually seen and taken. So its weakness lies elsewhere: tactics two moves deep, plans and placement (a
## vaguer sense of position and more imprecision between moves that look alike), not pieces given away.
## Habits: develop, castle. When the game is won it plays more carefully (it finishes its games).
## TABLE is on the scale of Stockfish's own limited strength (UCI_Elo), which takes over from 1350: each row was
## measured in matches against UCI_Elo 1350 (tests/human_bench.gd, tools/bench_report.py, docs/HUMAN_AI.md).

const CAP := 3000  ## evaluations: centipawns up to +-1500, a mate in n = +-(3000 - 20 n)

## Strength (Elo, the scale of Stockfish's UCI_Elo, which takes over from 1350) -> [miss (not seeing a loss),
## miss_tac (not seeing a gain), noise (cp), k, greed, safe (the one-move check: "can what I move, or leave, be taken
## next move?"), spot (a piece the opponent left en prise is noticed), feel (the sense of position: how much of the
## small differences between moves is felt without calculating)]
const TABLE := {
	600: [0.97, 0.90, 200.0, 80, 1.0, 0.86, 0.68, 0.0],
	900: [0.97, 0.82, 160.0, 60, 1.0, 0.95, 0.80, 0.20],
	1075: [0.92, 0.70, 120.0, 44, 1.0, 0.97, 0.85, 0.35],
	1250: [0.84, 0.62, 90.0, 32, 0.95, 0.98, 0.90, 0.50],
	1500: [0.74, 0.55, 65.0, 24, 0.9, 0.99, 0.93, 0.65],
}


## The settings of a strength (Lichess rapid scale), interpolated between the rows of TABLE.
static func params(rating: float) -> Dictionary:
	var keys: Array = TABLE.keys()
	keys.sort()
	rating = clampf(rating, float(keys[0]), float(keys[-1]))
	var lo: int = keys[0]
	var hi: int = keys[-1]
	for i in keys.size() - 1:
		if rating >= keys[i] and rating <= keys[i + 1]:
			lo = keys[i]
			hi = keys[i + 1]
			break
	var t := 0.0 if hi == lo else (rating - lo) / float(hi - lo)
	var a: Array = TABLE[lo]
	var b: Array = TABLE[hi]
	return {
		"rating": rating,
		"depth": 8,  # the engine's look at every candidate: deep enough that "seen" means really seen
		"miss": lerpf(a[0], b[0], t),
		"miss_tac": lerpf(a[1], b[1], t),
		"noise": lerpf(a[2], b[2], t),
		"k": int(round(lerpf(a[3], b[3], t))),
		"greed": lerpf(a[4], b[4], t),
		"safe": lerpf(a[5], b[5], t),
		"spot": lerpf(a[6], b[6], t),
		"feel": lerpf(a[7], b[7], t),
	}


## Picks a move. `cands`: [{"uci", "deep" (mover's view, after the move), "gain" (material taken now, cp),
## "check", "develop", "castle", "queen_early", "lands" (the moved piece's value when it stands en prise after
## the move, else 0)}]; `best_deep` = the engine's value of the position.
## `style`: {"aggression": 0..1 (checks look better), "greed": multiplier of how much material on offer appeals}.
static func choose(cands: Array, best_deep: float, p: Dictionary, rng: RandomNumberGenerator, style := {}) -> Dictionary:
	var pick: Dictionary = {}
	var top := -INF
	var aggr := float(style.get("aggression", 0.0))
	var greed := float(p["greed"]) * float(style.get("greed", 1.0))
	# what an ordinary move seems worth to someone who does not look further: the middle of the moves weighed
	# (a hidden tactic then looks ordinary, and so does a move that drops a piece)
	var vals: Array[float] = []
	for c: Dictionary in cands:
		vals.append(clampf(float(c["deep"]), -CAP, CAP))
	vals.sort()
	var base := vals[vals.size() / 2] if not vals.is_empty() else best_deep
	# once per move, like a person: the quick safety look is done or not, the gift on the board is seen or not
	var checks := rng.randf() < float(p.get("safe", 0.0))
	var spots := rng.randf() < float(p.get("spot", 0.0))
	var noise := float(p["noise"])
	if best_deep >= 500.0:
		noise *= 0.5  # winning: more careful, the game gets finished
	for c: Dictionary in cands:
		var deep := clampf(float(c["deep"]), -CAP, CAP)
		var r := clampf((float(p["rating"]) - 600.0) / 1400.0, 0.0, 1.0)
		var loss := best_deep - deep
		# the material on offer is not always noticed either (a piece left hanging by the other side)
		var gain := float(c["gain"]) if rng.randf() >= float(p["miss_tac"]) else 0.0
		var shallow := base + gain * greed + _natural(c, aggr)
		# a feel for the position: small differences are sensed even unseen, a lost piece is not
		var d := deep - base
		shallow += d * maxf(0.0, 1.0 - absf(d) / 300.0) * float(p.get("feel", 0.7))
		var miss: float
		if deep > shallow + 100.0:
			miss = float(p["miss_tac"])  # a chance the shallow look does not show (a tactic)
		else:
			miss = float(p["miss"])
			# the stakes change how easily it is missed: the queen hanging is noticed far more than a pawn
			if loss >= 700.0:
				miss *= lerpf(0.4, 0.15, r)
			elif loss >= 80.0 and loss < 250.0:
				miss *= 1.1
			if float(c.get("lands", 0.0)) > 0.0:
				miss *= lerpf(0.35, 0.15, r)  # the piece being moved: "can it be taken there?" is checked first
		var seen := rng.randf() >= clampf(miss, 0.0, 0.97)
		# the one-move look: a piece that can be taken right after the move, or a free piece to take, is no secret
		if checks and (float(c.get("lands", 0.0)) > 0.0 or float(c.get("hangs", 0.0)) > 0.0 or bool(c.get("saves", false))):
			seen = true
		var gift := false
		if spots and bool(c.get("free", false)):
			seen = true
			gift = loss < 100.0  # a free piece, seen: taken (the hand goes to it first)
		var v := (deep if seen else shallow) + _habit(c)
		# the imprecision lies between moves that look alike; a move seen to drop material is not played by chance
		if not (seen and loss >= 150.0):
			v += rng.randfn(0.0, noise)
		if gift:
			v += 3.0 * noise
		if v > top:
			top = v
			pick = c
	return pick


## What looks good at a glance (only when the consequences are not seen).
static func _natural(c: Dictionary, aggr: float) -> float:
	var b := 0.0
	if bool(c.get("check", false)):
		b += 25.0 + 30.0 * aggr
	if bool(c.get("develop", false)):
		b += 20.0
	return b


## Habits, whatever is seen: castle, develop, leave the queen home early on.
static func _habit(c: Dictionary) -> float:
	var b := 0.0
	if bool(c.get("castle", false)):
		b += 90.0
	if bool(c.get("develop", false)):
		b += 18.0
	if bool(c.get("queen_early", false)):
		b -= 25.0
	return b


# --- the engine's side: what it is asked, and the candidates built from its answers -------------------------------

const VAL := [0, 100, 300, 315, 500, 900, 0]


## A UCI "info ... score" line's value for the side to move (the scale of CAP).
static func score(line: String) -> float:
	var p := line.split(" ")
	var i := p.find("score")
	if i < 0:
		return 0.0
	if p[i + 1] == "cp":
		return clampf(float(p[i + 2]), -1500.0, 1500.0)
	# a mate in n: beyond any material, the quicker the better; mated in n: the later the better
	var n := int(p[i + 2])
	return (CAP - absf(n) * 20.0) * signf(n) if n != 0 else -float(CAP)


## The engine's lines (MultiPV) up to "bestmove": {first move (uci) -> value}, from the last full iteration.
static func read_pv(lines: Array) -> Dictionary:
	var pv := {}
	for line: String in lines:
		if not line.begins_with("info") or line.find(" pv ") < 0 or line.find("bound") >= 0:
			continue
		var p := line.split(" ")
		var k := p.find("multipv")
		pv[int(p[k + 1]) if k >= 0 else 1] = [score(line), p[p.find("pv") + 1]]
	var out := {}
	for k in pv:
		out[pv[k][1]] = float(pv[k][0])
	return out


## The obvious moves (captures, checks, promotions) the engine did not list, to be valued with searchmoves.
static func extras(pos: ChessPosition, evals: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m in pos.legal_moves():
		var u := pos.move_to_uci(m)
		if not evals.has(u) and (gain(pos, m) > 0 or gives_check(pos, m)):
			out.append(u)
	return out.slice(0, 12)


## The candidates for choose() from the engine's values; "best" is the position's value. `ply`: the game's ply
## (pos.ply_count() when pos holds the whole game).
static func candidates(pos: ChessPosition, evals: Dictionary, ply := -1) -> Dictionary:
	if ply < 0:
		ply = pos.ply_count()
	var cands: Array = []
	var best := -INF
	var threatened := hanging(pos, pos.side) > 0.0  # one of our pieces can be taken: the moves that save it
	for u: String in evals:
		var m := pos.move_from_uci(u)
		if m < 0:
			continue
		best = maxf(best, evals[u])
		var g := gain(pos, m)
		var mover := pos.side
		var queen := ChessPosition.piece_type(pos.board[ChessPosition.move_from(m)]) == ChessPosition.QUEEN
		var free := g > 0.0 and en_prise(pos, ChessPosition.move_to(m), 1 - mover) > 0.0
		pos.make_move(m)
		var lands := en_prise(pos, ChessPosition.move_to(m), mover)
		var hangs := hanging(pos, mover, ChessPosition.move_to(m))
		pos.unmake_move()
		cands.append({"uci": u, "deep": evals[u], "gain": g, "check": gives_check(pos, m),
			"develop": ply < 24 and develops(pos, m),
			"castle": (ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE) != 0,
			"lands": lands if lands > g else 0.0, "hangs": hangs, "free": free,
			"saves": threatened and hangs == 0.0 and (lands == 0.0 or lands <= g), "queen_early": queen and ply < 16})
	return {"cands": cands, "best": best}


## Material taken by the move (and a promotion's gain), in centipawns.
static func gain(pos: ChessPosition, m: int) -> float:
	var g := 0.0
	var victim := pos.board[ChessPosition.move_to(m)]
	if victim != ChessPosition.EMPTY:
		g += VAL[ChessPosition.piece_type(victim)]
	if ChessPosition.move_flags(m) & ChessPosition.FLAG_EP:
		g += 100.0
	if ChessPosition.move_promo(m) != 0:
		g += VAL[ChessPosition.move_promo(m)] - 100.0
	return g


static func gives_check(pos: ChessPosition, m: int) -> bool:
	pos.make_move(m)
	var c := pos.in_check()
	pos.unmake_move()
	return c


## A knight or bishop leaving its home rank.
static func develops(pos: ChessPosition, m: int) -> bool:
	var pc := pos.board[ChessPosition.move_from(m)]
	var t := ChessPosition.piece_type(pc)
	if t != ChessPosition.KNIGHT and t != ChessPosition.BISHOP:
		return false
	return ChessPosition.move_from(m) / 8 == (0 if ChessPosition.piece_color(pc) == ChessPosition.WHITE else 7)


## The value of `side`'s piece on `sq` when it can be taken with profit: attacked and not defended, or attacked by
## a pawn (and worth more); else 0.
static func en_prise(pos: ChessPosition, sq: int, side: int) -> float:
	var pc := pos.board[sq]
	if pc == ChessPosition.EMPTY or ChessPosition.piece_color(pc) != side:
		return 0.0
	var t := ChessPosition.piece_type(pc)
	if t == ChessPosition.KING or not pos.is_square_attacked(sq, 1 - side):
		return 0.0
	if not pos.is_square_attacked(sq, side) or (t != ChessPosition.PAWN and _pawn_attacks(pos, sq, 1 - side)):
		return VAL[t]
	return 0.0


## The most valuable of `side`'s pieces (knight and up) left en prise, but the one on `skip`.
static func hanging(pos: ChessPosition, side: int, skip := -1) -> float:
	var worst := 0.0
	for sq in 64:
		var pc := pos.board[sq]
		if sq != skip and pc != ChessPosition.EMPTY and ChessPosition.piece_color(pc) == side 				and ChessPosition.piece_type(pc) >= ChessPosition.KNIGHT:
			worst = maxf(worst, en_prise(pos, sq, side))
	return worst


static func _pawn_attacks(pos: ChessPosition, sq: int, by: int) -> bool:
	var f := sq % 8
	var pr := sq / 8 - 1 if by == ChessPosition.WHITE else sq / 8 + 1
	if pr < 0 or pr > 7:
		return false
	for df in [-1, 1]:
		var ff: int = f + df
		if ff >= 0 and ff < 8 and pos.board[pr * 8 + ff] == ChessPosition.make_piece(ChessPosition.PAWN, by):
			return true
	return false
