extends Node
## Headless: the game says why a move is refused (castling, pins, a king with no safe square), and the gamepad's A
## clicks where the pad cursor points, while the stick leaves the buttons' focus alone. Uses its own profile file. Run:
## godot --headless --path game res://tests/refusal_test.tscn -- --test-profile

var said: Array[String] = []


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _expect(game: ChessGame, fen: String, clicks: Array, want: String) -> bool:
	game.pos.set_fen(fen)
	game._clear_selection()
	said.clear()
	for c: String in clicks:
		game._on_square_clicked(ChessPosition.sq_from_name(c))
	var got := said[-1] if not said.is_empty() else ""
	var ok := got.contains(want) if want != "" else got == ""
	print("OK  " if ok else "BAD ", clicks, " -> ", got)
	return ok


func _run() -> void:
	Lang.apply("fr")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	# the champions' path: the stick moves the cursor only, never the focus (which would pick champions)
	main.menu.show_screen("opponents")
	await _frames(30)
	var sel: String = main.menu._sel_opp
	var focus := get_viewport().gui_get_focus_owner()
	for i in 30:
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXIS_LEFT_X if i % 2 else JOY_AXIS_LEFT_Y
		jm.axis_value = 1.0 if i % 4 < 2 else -1.0
		Input.parse_input_event(jm)
		await _frames(2)
	var still: bool = main.menu._sel_opp == sel and get_viewport().gui_get_focus_owner() == focus
	print("OK  " if still else "BAD ", "stick on the path: ", sel, " -> ", main.menu._sel_opp)
	var ok := still
	main.play("o1", "white")
	await _frames(60)
	var game: ChessGame = main.game
	game.move_refused.connect(func(t: String) -> void: said.append(t))
	# the player's case: a bishop on h3 watches f1
	var f := "4k3/8/8/8/8/7b/3PPP1P/3QK2R w K - 0 1"
	ok = await _expect(game, f, ["e1"], "attaquées (f1)") and ok
	ok = await _expect(game, f, ["e1", "h1"], "passerait par f1") and ok
	ok = await _expect(game, f, ["e1", "g1"], "passerait par f1") and ok
	ok = await _expect(game, "4k3/8/8/8/8/8/8/4K2R w - - 0 1", ["e1", "h1"], "déjà bougé") and ok
	ok = await _expect(game, "4k3/8/8/8/8/8/8/R3K1NR w KQ - 0 1", ["e1", "h1"], "entre le roi") and ok
	ok = await _expect(game, "4k3/8/8/8/8/8/8/R3K2r w Q - 0 1", ["e1", "a1"], "en échec") and ok
	ok = await _expect(game, "4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1", ["e2"], "clouée") and ok
	ok = await _expect(game, "4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1", ["e1", "e2"], "clouée") and ok  # picks the pinned knight
	ok = await _expect(game, "4k3/8/8/8/8/8/3r4/4K3 w - - 0 1", ["e1", "e2"], "mettrait ton roi") and ok
	ok = await _expect(game, "4k3/8/8/8/8/8/8/4K2R w K - 0 1", ["e1", "h1"], "") and ok  # castles
	ok = ok and game._selected == -1 and game.busy  # king then rook: the castling move is under way
	# the gamepad: A clicks under the pad cursor (select e2, then e4)
	main.play("o1", "white")  # a fresh game: the pieces on the board match the position again
	await _frames(60)
	game = main.game
	var b: BoardView = game.board
	print("busy ", game.busy, " human ", game.is_human_turn(), " input ", b.input_enabled)
	var xf := b.get_global_transform_with_canvas()
	for c in ["e2", "e4"]:
		var sq := ChessPosition.sq_from_name(c)
		Pad._active = true
		Pad._idle = 0.0
		Pad._pos = xf * b.project(sq % 8 + 0.5, sq / 8 + 0.5)
		for pressed in [true, false]:
			var e := InputEventJoypadButton.new()
			e.button_index = JOY_BUTTON_A
			e.pressed = pressed
			Pad._input(e)
			await _frames(2)
		print("pad click ", c, " selected ", game._selected)
	for i in 600:
		if not game.busy:
			break
		await get_tree().process_frame
	var moved := game.pos.board[ChessPosition.sq_from_name("e4")] != ChessPosition.EMPTY
	print("pad move e2e4: ", moved)
	ok = ok and moved
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
