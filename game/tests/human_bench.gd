extends SceneTree
## Plays computer opponents against each other and judges every move with the engine at full strength.
## Run: godot --headless --path game -s tests/human_bench.gd -- <out.json> <games per pair> <seed> <A>:<B> [<A>:<B> ...]
##   players: new:<rating>  the human-like model (src/ai/human_mind.gd), a Lichess rapid rating
##            uci:<elo>  the engine's own limited strength (UCI_Elo, 1350..2850)
## Writes every game (moves, judged values, flags) to out.json; tools/bench_report.py turns them into tables.

const MAX_PLIES := 240
const JUDGE_DEPTH := 11
const VAL := [0, 100, 300, 315, 500, 900, 0]

var engine: Object
var rng := RandomNumberGenerator.new()
var think_ms := {}  ## player -> [total ms, moves]


func _initialize() -> void:
	engine = ClassDB.instantiate("StockfishEngine")
	engine.start()
	_wait("uci", "uciok")
	_wait("setoption name Hash value 64\nisready", "readyok")
	var args := OS.get_cmdline_user_args()
	if args[0] == "--humans":
		_judge_humans(String(args[1]), String(args[2]), int(args[3]), int(args[4]))
		quit()
		return
	var out := String(args[0])
	var games := int(args[1])
	rng.seed = int(args[2])
	var all_games: Array = []
	for pair in args.slice(3):
		var ab := String(pair).split(":")
		var a := ab[0] + ":" + ab[1]
		var b := ab[2] + ":" + ab[3]
		for g in games:
			var w := a if g % 2 == 0 else b
			var bl := b if g % 2 == 0 else a
			var t0 := Time.get_ticks_msec()
			var rec := _game(w, bl)
			print("%s - %s : %s  (%d coups, %.0f s)" % [w, bl, rec["result"], rec["moves"].size(), (Time.get_ticks_msec() - t0) / 1000.0])
			all_games.append(rec)
			var f := FileAccess.open(out, FileAccess.WRITE)
			f.store_string(JSON.stringify({"games": all_games, "think_ms": think_ms}))
			f.close()
	quit()


## Human games (tools/lichess_sample.py): replayed and judged move by move like the computer players' ones,
## the player named "human:<band>". Games `first` .. `first + count - 1` of the file (to share the work).
## Run: ... -s tests/human_bench.gd -- --humans <sample.json> <out.json> <first> <count>
func _judge_humans(src: String, out: String, first: int, count: int) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src))
	var all_games: Array = []
	var list: Array = data["games"].slice(first, first + count)
	for hg: Dictionary in list:
		var who := "human:%d" % int(hg["band"])
		var pos := ChessPosition.new()
		var moves := PackedStringArray()
		engine.send("ucinewgame")
		_wait("isready", "readyok")
		var rec := {"white": who, "black": who, "moves": [], "result": String(hg["result"]).replace("1/2-1/2", "1/2")}
		var ok := true
		for san: String in hg["san"]:
			var m := _from_san(pos, san)
			if m < 0:
				ok = false
				break
			var posline := "position startpos" + (" moves " + " ".join(moves) if not moves.is_empty() else "")
			var j := _judge(posline)
			var mover := pos.side
			var bm := pos.move_from_uci(String(j[1]))
			var info := {"uci": pos.move_to_uci(m), "by": who, "side": mover, "eval": j[0], "best": j[1],
				"best_tactic": bm >= 0 and (_gain(pos, bm) > 0 or _gives_check(pos, bm)),
				"gain": _gain(pos, m), "piece": ChessPosition.piece_type(pos.board[ChessPosition.move_from(m)]),
				"castle": (ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE) != 0, "develop": _develops(pos, m)}
			pos.make_move(m)
			moves.append(info["uci"])
			info["moved_en_prise"] = _en_prise(pos, ChessPosition.move_to(m), mover)
			info["hanging"] = _hanging(pos, mover)
			info["mat"] = _material(pos, mover)
			rec["moves"].append(info)
		if not ok:
			print("coup illisible, partie ignorée")
			continue
		all_games.append(rec)
		print("%s : %d coups" % [who, rec["moves"].size()])
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"games": all_games, "think_ms": {}}))
		f.close()


func _from_san(pos: ChessPosition, san: String) -> int:
	var want := san.replace("+", "").replace("#", "")
	for m in pos.legal_moves():
		if pos.move_to_san(m).replace("+", "").replace("#", "") == want:
			return m
	return -1


# --- engine ---------------------------------------------------------------------------------------------------------

func _wait(cmd: String, until: String, timeout := 120.0) -> Array:
	for c in cmd.split("\n"):
		engine.send(c)
	var lines: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		for line: String in engine.poll():
			lines.append(line)
			if line.begins_with(until):
				return lines
		OS.delay_msec(1)
	push_error("délai dépassé : " + cmd)
	return lines


func _full(multipv: int) -> void:
	engine.send("setoption name UCI_LimitStrength value false")
	engine.send("setoption name Skill Level value 20")
	engine.send("setoption name MultiPV value %d" % multipv)


static func _score(line: String) -> float:
	return HumanMind.score(line)


## Runs `go` and returns {multipv -> [cp, first move]} of the last full iteration, and "best".
func _analyse(posline: String, go: String) -> Dictionary:
	engine.send(posline)
	var lines := _wait(go, "bestmove")
	var pv := {}
	for line: String in lines:
		if not line.begins_with("info") or line.find(" pv ") < 0 or line.find("bound") >= 0:
			continue
		var p := line.split(" ")
		var k := p.find("multipv")
		var idx := int(p[k + 1]) if k >= 0 else 1
		pv[idx] = [_score(line), p[p.find("pv") + 1]]
	var last: String = lines.back() if not lines.is_empty() else ""
	return {"pv": pv, "best": last.split(" ")[1] if last.split(" ").size() > 1 else ""}


# --- players --------------------------------------------------------------------------------------------------------

func _move(player: String, pos: ChessPosition, posline: String) -> int:
	var kind := player.split(":")[0]
	var elo := int(player.split(":")[1])
	var legal := pos.legal_moves()
	var t0 := Time.get_ticks_msec()
	var m := -1
	if kind == "new":
		m = _new_move(elo, pos, posline)
	else:
		# the engine's own limited strength
		engine.send("setoption name MultiPV value 1")
		engine.send("setoption name Skill Level value 20")
		engine.send("setoption name UCI_LimitStrength value true")
		engine.send("setoption name UCI_Elo value %d" % elo)
		m = pos.move_from_uci(_analyse(posline, "go movetime 300")["best"])
	var tm: Array = think_ms.get(player, [0, 0])
	think_ms[player] = [tm[0] + Time.get_ticks_msec() - t0, tm[1] + 1]
	return m if m >= 0 else legal[0]


func _new_move(elo: int, pos: ChessPosition, posline: String) -> int:
	var p := HumanMind.params(elo)
	var legal := pos.legal_moves()
	_full(mini(int(p["k"]), legal.size()))
	engine.send(posline)
	var evals := HumanMind.read_pv(_wait("go depth %d" % int(p["depth"]), "bestmove"))
	var extra := HumanMind.extras(pos, evals)
	if not extra.is_empty():
		_full(extra.size())
		engine.send(posline)
		evals.merge(HumanMind.read_pv(_wait("go depth %d searchmoves %s" % [int(p["depth"]) - 2, " ".join(extra)], "bestmove")))
	_full(1)
	var c := HumanMind.candidates(pos, evals)
	if (c["cands"] as Array).is_empty():
		return legal[0]
	return pos.move_from_uci(String(HumanMind.choose(c["cands"], c["best"], p, rng)["uci"]))


func _gain(pos: ChessPosition, m: int) -> float:
	var g := 0.0
	var victim := pos.board[ChessPosition.move_to(m)]
	if victim != ChessPosition.EMPTY:
		g += VAL[ChessPosition.piece_type(victim)]
	if ChessPosition.move_flags(m) & ChessPosition.FLAG_EP:
		g += 100.0
	if ChessPosition.move_promo(m) != 0:
		g += VAL[ChessPosition.move_promo(m)] - 100.0
	return g


func _gives_check(pos: ChessPosition, m: int) -> bool:
	pos.make_move(m)
	var c := pos.in_check()
	pos.unmake_move()
	return c


func _develops(pos: ChessPosition, m: int) -> bool:
	var pc := pos.board[ChessPosition.move_from(m)]
	var t := ChessPosition.piece_type(pc)
	if t != ChessPosition.KNIGHT and t != ChessPosition.BISHOP:
		return false
	var rank := ChessPosition.move_from(m) / 8
	return rank == (0 if ChessPosition.piece_color(pc) == ChessPosition.WHITE else 7)


# --- a game ---------------------------------------------------------------------------------------------------------

func _judge(posline: String) -> Array:
	_full(1)
	var r := _analyse(posline, "go depth %d" % JUDGE_DEPTH)
	var v: Array = r["pv"].get(1, [0.0, ""])
	return [clampf(float(v[0]), -2000.0, 2000.0), String(r["best"])]


func _game(white: String, black: String) -> Dictionary:
	var pos := ChessPosition.new()
	var moves := PackedStringArray()
	engine.send("ucinewgame")
	_wait("isready", "readyok")
	var rec := {"white": white, "black": black, "moves": [], "result": "1/2"}
	var streak := 0
	var last_lead := 0.0
	for ply in MAX_PLIES:
		var res := pos.result()
		if res == ChessPosition.Result.CHECKMATE:
			rec["result"] = "0-1" if pos.side == ChessPosition.WHITE else "1-0"
			break
		if res != ChessPosition.Result.ONGOING:
			break
		var posline := "position startpos" + (" moves " + " ".join(moves) if not moves.is_empty() else "")
		var j := _judge(posline)  # before the move: value for the side to move, and the best move
		var mover := pos.side
		var lead := float(j[0]) if mover == ChessPosition.WHITE else -float(j[0])  # white's view
		streak = streak + 1 if absf(lead) >= 800.0 and signf(lead) == signf(last_lead) else 0
		last_lead = lead
		if streak >= 8:
			rec["result"] = "1-0" if lead > 0 else "0-1"
			rec["adjudicated"] = true
			break
		var player := white if mover == ChessPosition.WHITE else black
		var m := _move(player, pos, posline)
		var bm := pos.move_from_uci(String(j[1]))
		var info := {"uci": pos.move_to_uci(m), "by": player, "side": mover, "eval": j[0], "best": j[1],
			"best_tactic": bm >= 0 and (_gain(pos, bm) > 0 or _gives_check(pos, bm)),
			"gain": _gain(pos, m), "piece": ChessPosition.piece_type(pos.board[ChessPosition.move_from(m)]),
			"castle": (ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE) != 0,
			"develop": _develops(pos, m)}
		pos.make_move(m)
		moves.append(info["uci"])
		info["moved_en_prise"] = _en_prise(pos, ChessPosition.move_to(m), mover)
		info["hanging"] = _hanging(pos, mover)
		info["mat"] = _material(pos, mover)
		rec["moves"].append(info)
	return rec


func _material(pos: ChessPosition, side: int) -> float:
	var s := 0.0
	for sq in 64:
		var pc := pos.board[sq]
		if pc != ChessPosition.EMPTY:
			s += VAL[ChessPosition.piece_type(pc)] * (1 if ChessPosition.piece_color(pc) == side else -1)
	return s


## Our piece on `sq` can be taken with profit: attacked and not defended, or attacked by a pawn (and worth more).
func _en_prise(pos: ChessPosition, sq: int, side: int) -> float:
	var pc := pos.board[sq]
	if pc == ChessPosition.EMPTY or ChessPosition.piece_color(pc) != side:
		return 0.0
	var t := ChessPosition.piece_type(pc)
	if t == ChessPosition.KING:
		return 0.0
	var opp := 1 - side
	if not pos.is_square_attacked(sq, opp):
		return 0.0
	if not pos.is_square_attacked(sq, side) or (t != ChessPosition.PAWN and _pawn_attacks(pos, sq, opp)):
		return VAL[t]
	return 0.0


func _pawn_attacks(pos: ChessPosition, sq: int, by: int) -> bool:
	var f := sq % 8
	var r := sq / 8
	var pr := r - 1 if by == ChessPosition.WHITE else r + 1
	if pr < 0 or pr > 7:
		return false
	for df in [-1, 1]:
		var ff: int = f + df
		if ff >= 0 and ff < 8 and pos.board[pr * 8 + ff] == ChessPosition.make_piece(ChessPosition.PAWN, by):
			return true
	return false


## The most valuable of our pieces (knight and up) left en prise.
func _hanging(pos: ChessPosition, side: int) -> float:
	var worst := 0.0
	for sq in 64:
		var pc := pos.board[sq]
		if pc != ChessPosition.EMPTY and ChessPosition.piece_color(pc) == side and ChessPosition.piece_type(pc) >= ChessPosition.KNIGHT:
			worst = maxf(worst, _en_prise(pos, sq, side))
	return worst
