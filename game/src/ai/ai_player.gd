class_name AiPlayer
extends Node
## An opponent driven by the embedded engine (StockfishEngine GDExtension, UCI in memory).
## A level is a dictionary from data/opponents.json:
##   human (a Lichess rapid rating): plays like a person of that strength (HumanMind, docs/HUMAN_AI.md), with an
##     optional style {"aggression": 0..1};
##   or the engine's own settings: skill (0-20), depth or movetime, uci_elo (UCI_LimitStrength, >= 1350).

signal move_ready(uci: String)

var engine: Object
var level: Dictionary = {}
var thinking := false
var _ignore := 0  ## bestmoves still due from searches that were cancelled
var _ready_ok := false
var _rng := RandomNumberGenerator.new()
# a human-like move is thought in two searches: the engine's best k moves, then the obvious ones it left out
var _phase := 0  ## 0 none, 1 the best moves, 2 the obvious ones
var _lines: Array = []
var _evals := {}
var _pos: ChessPosition
var _posline := ""
var _ply := 0


func _ready() -> void:
	if ClassDB.class_exists("StockfishEngine"):
		engine = ClassDB.instantiate("StockfishEngine")
	elif WebEngine.supported():
		engine = WebEngine.new()  # browser: the same engine in WebAssembly, in a Web Worker
	else:
		push_error("Moteur d'échecs absent (bin/retrochess_ai)")
		return
	engine.start()
	engine.send("uci")
	engine.send("isready")


func available() -> bool:
	return engine != null


func configure(p_level: Dictionary) -> void:
	level = p_level
	if engine == null:
		return
	engine.send("ucinewgame")
	engine.send("setoption name MultiPV value 1")
	if level.has("human"):
		engine.send("setoption name UCI_LimitStrength value false")
		engine.send("setoption name Skill Level value 20")
	elif level.has("uci_elo"):
		engine.send("setoption name Skill Level value 20")
		engine.send("setoption name UCI_LimitStrength value true")
		engine.send("setoption name UCI_Elo value %d" % int(level["uci_elo"]))
	else:
		engine.send("setoption name UCI_LimitStrength value false")
		engine.send("setoption name Skill Level value %d" % int(level.get("skill", 20)))
	engine.send("isready")


## Starts thinking about `pos`, reached from `start_fen` by `moves` (UCI), so the engine knows the history
## (repetitions). Emits move_ready once.
func think(start_fen: String, moves: PackedStringArray, pos: ChessPosition) -> void:
	if thinking:
		cancel()
	thinking = true
	if engine == null:
		var legal2 := pos.legal_moves()
		_emit_later(pos.move_to_uci(legal2[0]) if not legal2.is_empty() else "")
		return
	var cmd := "position fen " + start_fen
	if not moves.is_empty():
		cmd += " moves " + " ".join(moves)
	if level.has("human"):
		_pos = pos.duplicate_position()  # the game may move on (an undo) while the engine thinks
		_posline = cmd
		_ply = pos.ply_count()
		var p := HumanMind.params(float(level["human"]))
		_ask(1, mini(int(p["k"]), pos.legal_moves().size()), "go depth %d" % int(p["depth"]))
		return
	engine.send(cmd)
	if level.has("depth"):
		engine.send("go depth %d" % int(level["depth"]))
	else:
		engine.send("go movetime %d" % int(level.get("movetime", 500)))


func _ask(phase: int, multipv: int, go: String) -> void:
	_phase = phase
	_lines.clear()
	engine.send("setoption name MultiPV value %d" % maxi(1, multipv))
	engine.send(_posline)
	engine.send(go)


## The human-like move, once the engine has answered (see HumanMind).
func _human_step() -> void:
	var p := HumanMind.params(float(level["human"]))
	if _phase == 1:
		_evals = HumanMind.read_pv(_lines)
		var extra := HumanMind.extras(_pos, _evals)
		if not extra.is_empty():
			_ask(2, extra.size(), "go depth %d searchmoves %s" % [int(p["depth"]) - 2, " ".join(extra)])
			return
	else:
		_evals.merge(HumanMind.read_pv(_lines))
	_phase = 0
	engine.send("setoption name MultiPV value 1")
	thinking = false
	var c := HumanMind.candidates(_pos, _evals, _ply)
	var uci := ""
	if not (c["cands"] as Array).is_empty():
		uci = String(HumanMind.choose(c["cands"], c["best"], p, _rng, level.get("style", {}))["uci"])
	else:
		var legal := _pos.legal_moves()
		uci = _pos.move_to_uci(legal[0]) if not legal.is_empty() else ""
	move_ready.emit(uci)


func cancel() -> void:
	if thinking and engine != null:
		engine.send("stop")
		_ignore += 1
	thinking = false
	if _phase != 0:
		_phase = 0
		engine.send("setoption name MultiPV value 1")


func _emit_later(uci: String) -> void:
	await get_tree().process_frame
	if thinking:
		thinking = false
		move_ready.emit(uci)


func _process(_delta: float) -> void:
	if engine == null:
		return
	for line: String in engine.poll():
		if _phase != 0 and _ignore == 0 and line.begins_with("info"):
			_lines.append(line)
		if line.begins_with("bestmove"):
			if _ignore > 0:
				_ignore -= 1
				continue
			if thinking and _phase != 0:
				_human_step()
				continue
			if thinking:
				thinking = false
				var parts: PackedStringArray = String(line).split(" ")
				move_ready.emit(parts[1] if parts.size() > 1 else "")
