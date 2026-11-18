extends SceneTree
## The game's AiPlayer with human-like levels: plays a short game between two levels through the real node
## (two-step search, signals), checks every move is legal, and that a cancel in the middle of a search is clean.
## Run: godot --headless --path game -s tests/ai_test.gd

var ai: AiPlayer
var got := ""


func _initialize() -> void:
	ai = AiPlayer.new()
	root.add_child(ai)
	ai.move_ready.connect(func(u: String) -> void: got = u)
	_run()


func _wait_move() -> String:
	got = ""
	var t0 := Time.get_ticks_msec()
	while got == "" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	return got


func _run() -> void:
	await process_frame
	var pos := ChessPosition.new()
	var moves := PackedStringArray()
	var levels := [{"human": 600, "style": {"greed": 1.4}}, {"human": 1800, "style": {"aggression": 0.8}}]
	var ms := [0, 0]
	var fails := 0
	# a cancel mid-search: the next answer must still come, for the right position
	ai.configure(levels[0])
	ai.think(ChessPosition.START_FEN, moves, pos)
	await process_frame
	ai.cancel()
	for ply in 60:
		if pos.result() != ChessPosition.Result.ONGOING:
			break
		var lv: Dictionary = levels[ply % 2]
		ai.configure(lv)
		var t0 := Time.get_ticks_msec()
		ai.think(ChessPosition.START_FEN, moves, pos)
		var u := await _wait_move()
		ms[ply % 2] += Time.get_ticks_msec() - t0
		var m := pos.move_from_uci(u)
		if m < 0:
			print("ÉCHEC : coup illégal '%s' au demi-coup %d" % [u, ply])
			fails += 1
			break
		moves.append(u)
		pos.make_move(m)
	print("coups : ", " ".join(moves))
	print("temps moyen : 600 = %d ms, 1800 = %d ms" % [ms[0] / maxi(1, (moves.size() + 1) / 2), ms[1] / maxi(1, moves.size() / 2)])
	print("OK" if fails == 0 and moves.size() >= 20 else "ÉCHEC")
	quit()
