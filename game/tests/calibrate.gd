extends SceneTree
## Measures the strength of the opponents by matches between levels, anchored on the engine's own
## calibrated strength-limited mode (UCI_Elo).
## Run: godot --headless --path game -s tests/calibrate.gd -- <games> <idA>:<idB> [<idA>:<idB> ...]
##   ids: o1..o10 from data/opponents.json, or anchorNNNN (UCI_Elo NNNN, 1350 minimum)
## Prints the score of A and the Elo difference it implies. One engine plays both sides: the settings of the
## side to move are sent before each search (the engine is a single instance in the process).

const MAX_PLIES := 300

var engine: Object
var rng := RandomNumberGenerator.new()
var opponents := {}


func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/opponents.json"))
	for o in data["opponents"]:
		opponents[o["id"]] = o["engine"]
	engine = ClassDB.instantiate("StockfishEngine")
	engine.start()
	_send_wait("uci", "uciok")
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 20
	rng.seed = 12345
	for pair in args.slice(1):
		var ab: PackedStringArray = String(pair).split(":")
		_match(ab[0], ab[1], games)
	quit()


func _level(id: String) -> Dictionary:
	if id.begins_with("anchor"):
		return {"uci_elo": int(id.substr(6)), "movetime": 300}
	return opponents[id]


func _send_wait(cmd: String, until: String, timeout := 60.0) -> String:
	engine.send(cmd)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		for line: String in engine.poll():
			if line.begins_with(until):
				return line
		OS.delay_msec(1)
	push_error("délai dépassé : " + cmd)
	return ""


func _configure(lv: Dictionary) -> void:
	if lv.has("uci_elo"):
		engine.send("setoption name Skill Level value 20")
		engine.send("setoption name UCI_LimitStrength value true")
		engine.send("setoption name UCI_Elo value %d" % int(lv["uci_elo"]))
	else:
		engine.send("setoption name UCI_LimitStrength value false")
		engine.send("setoption name Skill Level value %d" % int(lv.get("skill", 20)))


func _best(pos: ChessPosition, moves: PackedStringArray, lv: Dictionary) -> int:
	var r := float(lv.get("random", 0.0))
	var legal := pos.legal_moves()
	if r > 0.0 and rng.randf() < r:
		return legal[rng.randi() % legal.size()]
	_configure(lv)
	var cmd := "position startpos"
	if not moves.is_empty():
		cmd += " moves " + " ".join(moves)
	engine.send(cmd)
	var go := "go depth %d" % int(lv["depth"]) if lv.has("depth") else "go movetime %d" % int(lv.get("movetime", 300))
	var line := _send_wait(go, "bestmove")
	var m := pos.move_from_uci(line.split(" ")[1] if line.split(" ").size() > 1 else "")
	return m if m >= 0 else legal[0]


## Returns 1 / 0.5 / 0 for white.
func _game(white: Dictionary, black: Dictionary) -> float:
	var pos := ChessPosition.new()
	var moves := PackedStringArray()
	engine.send("ucinewgame")
	_send_wait("isready", "readyok")
	for ply in MAX_PLIES:
		var res := pos.result()
		if res == ChessPosition.Result.CHECKMATE:
			return 0.0 if pos.side == ChessPosition.WHITE else 1.0
		if res != ChessPosition.Result.ONGOING:
			return 0.5
		var m := _best(pos, moves, white if pos.side == ChessPosition.WHITE else black)
		moves.append(pos.move_to_uci(m))
		pos.make_move(m)
	return 0.5  # adjudicated draw after MAX_PLIES


func _match(a: String, b: String, games: int) -> void:
	var la := _level(a)
	var lb := _level(b)
	var score := 0.0
	var t0 := Time.get_ticks_msec()
	for g in games:
		if g % 2 == 0:
			score += _game(la, lb)
		else:
			score += 1.0 - _game(lb, la)
	var s := clampf(score / games, 0.01, 0.99)
	var diff := -400.0 * log(1.0 / s - 1.0) / log(10.0)
	print("%s vs %s : %.1f / %d  (%.0f %%)  -> %s %+.0f Elo par rapport à %s   [%.0f s]" % [
		a, b, score, games, s * 100.0, a, diff, b, (Time.get_ticks_msec() - t0) / 1000.0])
