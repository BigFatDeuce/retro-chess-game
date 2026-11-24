extends SceneTree
## Stockfish extension smoke test: UCI handshake, legal best moves, a short self-play game.

var eng
var failures := 0

func wait_for(prefix: String, timeout_ms := 10000) -> String:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		for l in eng.poll():
			if l.begins_with(prefix):
				return l
		OS.delay_msec(2)
	return ""

func _init() -> void:
	if not ClassDB.class_exists("StockfishEngine"):
		print("FAIL extension non chargée"); quit(1); return
	eng = ClassDB.instantiate("StockfishEngine")
	eng.start()
	eng.send("uci")
	var ok := wait_for("uciok")
	print("uci: ", ok)
	eng.send("isready")
	print("ready: ", wait_for("readyok"))
	var p := ChessPosition.new()
	var moves := []
	var t0 := Time.get_ticks_msec()
	while p.result() == ChessPosition.Result.ONGOING and p.ply_count() < 120:
		eng.send("position startpos moves " + " ".join(moves))
		eng.send("go movetime 30")
		var bm := wait_for("bestmove")
		var uci := bm.split(" ")[1] if bm != "" else ""
		var m := p.move_from_uci(uci)
		if m < 0:
			failures += 1
			print("FAIL coup illégal ou absent : '%s' dans %s" % [bm, p.get_fen()])
			break
		p.make_move(m)
		moves.append(uci)
	print("partie auto : %d demi-coups, résultat %d, %d ms" % [p.ply_count(), p.result(), Time.get_ticks_msec() - t0])
	eng.send("setoption name Skill Level value 0")
	eng.send("position startpos")
	eng.send("go depth 1")
	print("skill 0: ", wait_for("bestmove"))
	print("%d échec(s)" % failures)
	quit(1 if failures else 0)
