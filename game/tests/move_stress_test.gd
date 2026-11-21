extends Node
## Headless stress test of the pieces' moves: thousands of moves played through the game itself (animations, captures,
## castling, en passant, promotions), by direct call, by clicks (as a player does) and from the network side, on every
## board and every set of pieces, white or black at the bottom. After each move the board on screen must be exactly the
## position: the right piece on every square, standing on it, no piece left over, no hidden rebuild.
## Also: every special move, game endings, moves cut short by a new game / resign / the menus, random clicks.
## Settings and profiles are not touched. Run (the log must also hold no "SCRIPT ERROR" and no "ERROR:" line):
##   godot --headless --path game res://tests/move_stress_test.tscn [-- --quick] [-- --seed N]

const BOARDS := ["prairie", "forest", "fields", "moor", "beach", "mountain", "swamp", "tundra", "graveyard", "village"]
const SETS := ["", "classic", "staunton"]
const MAX_WAIT := 120.0  ## seconds of game time a move may take before it counts as stuck

var game: ChessGame
var rng := RandomNumberGenerator.new()
var fails := 0
var checks := 0
var moves_played := 0
var promo_asked: Array = []
var overs := 0
var quick := false


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	quick = "--quick" in args
	var seed_i := args.find("--seed")
	rng.seed = int(args[seed_i + 1]) if seed_i >= 0 and seed_i + 1 < args.size() else 20261121
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fail(what: String) -> void:
	fails += 1
	print("BAD ", what, "  [", game.pos.get_fen(), "]")


func _expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		_fail(what)


## Waits for the staging to end; false when it never does.
func _settle() -> bool:
	var t := 0.0
	# the camera eases the view to its tilt: the pieces go back on their squares once it is there and nothing moves
	while game.busy or absf(game.board.tilt - game.camera.target_tilt) > 0.0001:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > MAX_WAIT:
			return false
	await _frames(3)
	return true


func _live_pieces() -> Array:
	var out := []
	for n in game.layer.get_children():
		if n is Piece and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _ids() -> Dictionary:
	var d := {}
	for n in _live_pieces():
		d[n.get_instance_id()] = true
	return d


## The board shows exactly the position, and nothing else.
func _state_ok(tag: String) -> bool:
	var before := fails
	_expect(game.sync_ok(), tag + ": pieces / position out of step")
	var count := 0
	for sq in 64:
		if game.pos.board[sq] != ChessPosition.EMPTY:
			count += 1
	var live := _live_pieces()
	_expect(live.size() == count, tag + ": %d piece nodes for %d pieces" % [live.size(), count])
	for sq: int in game.pieces:
		var p: Piece = game.pieces[sq]
		if not is_instance_valid(p):
			_fail(tag + ": freed piece on " + ChessPosition.sq_name(sq))
			continue
		_expect(p in live, tag + ": piece of " + ChessPosition.sq_name(sq) + " not on the board")
		_expect(p.visible and p.modulate.a > 0.95, tag + ": piece of " + ChessPosition.sq_name(sq) + " invisible")
		var on := game.board.square_at_point(p.position)
		_expect(on == sq, tag + ": piece of %s stands on %s (at %s, square at %s, tilt %.2f)" % [ChessPosition.sq_name(sq),
			ChessPosition.sq_name(on) if on >= 0 else "off the board", p.position, game.board.square_pos(sq), game.board.tilt])
	var ck := game.pos.king_sq[game.pos.side] if game.pos.in_check() and not game.over else -1
	if not game.over:
		_expect(game.board.check_sq == ck, tag + ": check marker on the wrong square")
	return fails == before


func _start(board: String, piece_set: String, side: int, fen := ChessPosition.START_FEN, two := true, remote := false) -> void:
	Settings.values["piece_set"] = piece_set
	game.board_key = board
	game.two_humans = two
	game.remote = remote
	game.new_game(side, {}, fen)
	game.ai.cancel()
	await _frames(3)


## Plays one move the way picked: "call" (play_move), "click" (the squares, as a player), "remote" (network side).
func _play(m: int, how: String) -> void:
	var uci := game.pos.move_to_uci(m)
	match how:
		"remote":
			game.remote_move(uci)
		"click":
			var from := ChessPosition.move_from(m)
			var to := ChessPosition.move_to(m)
			promo_asked = []
			game._on_square_clicked(from)
			if ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE and rng.randf() < 0.5:
				to = (from & ~7) | (7 if (to & 7) == 6 else 0)  # king, then its rook
			game._on_square_clicked(to)
			if not promo_asked.is_empty():
				var pick: int = m if m in promo_asked else promo_asked[rng.randi() % promo_asked.size()]
				game.play_move(pick)
			elif not game.busy and not game.over:
				_fail("click %s did nothing" % uci)
				game.play_move(m)
		_:
			game.play_move(m)


func _random_game(board: String, piece_set: String, black_bottom: bool, plies: int) -> void:
	var tag := "%s/%s/%s" % [board, piece_set if piece_set != "" else "creatures", "black" if black_bottom else "white"]
	if black_bottom:
		await _start(board, piece_set, ChessPosition.BLACK, ChessPosition.START_FEN, false, true)
	else:
		await _start(board, piece_set, ChessPosition.WHITE)
	_expect(game.board.flipped == black_bottom, tag + ": board not turned for black")
	for ply in plies:
		if game.over:
			break
		var legal := Array(game.pos.legal_moves())
		if legal.is_empty():
			break
		# castling, captures and promotions more often than chance would give
		var m: int = legal[rng.randi() % legal.size()]
		for k in 3:
			var c: int = legal[rng.randi() % legal.size()]
			if ChessPosition.move_flags(c) & (ChessPosition.FLAG_CASTLE | ChessPosition.FLAG_EP | ChessPosition.FLAG_CAPTURE) or ChessPosition.move_promo(c):
				m = c
				break
		var how := "call"
		if black_bottom and not game.is_human_turn():
			how = "remote"
		elif rng.randf() < 0.5:
			how = "click"
		var ids := _ids()
		var san := game.pos.move_to_san(m)
		if rng.randf() < 0.08:
			game.camera.target_tilt = rng.randf()  # the player tilts the view (V, right drag), maybe mid-move
		if rng.randf() < 0.05:
			game.set_see_through(not game.see_through)
		await _play(m, how)
		if not await _settle():
			_fail("%s: move %s (%s) never ends" % [tag, san, how])
			return
		moves_played += 1
		var fresh := 0
		for id in _ids():
			if not ids.has(id):
				fresh += 1
		_expect(fresh <= (1 if ChessPosition.move_promo(m) else 0), "%s: board rebuilt after %s" % [tag, san])
		if not _state_ok("%s after %s (%s)" % [tag, san, how]):
			return
	game.camera.target_tilt = 0.0


## Each special move, both sides, by call and by clicks; the position after it must be the expected one.
func _special_moves() -> void:
	var cases := [
		["white O-O", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", ["e1g1"], "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1"],
		["white O-O-O", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", ["e1c1"], "r3k2r/8/8/8/8/8/8/2KR3R b kq - 1 1"],
		["black O-O", "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", ["e8g8"], "r4rk1/8/8/8/8/8/8/R3K2R w KQ - 1 2"],
		["black O-O-O", "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", ["e8c8"], "2kr3r/8/8/8/8/8/8/R3K2R w KQ - 1 2"],
		["white e.p.", "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", ["e5d6"], "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1"],
		["black e.p.", "4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1", ["d4e3"], "4k3/8/8/8/8/4p3/8/4K3 w - - 0 2"],
		["promo Q", "1r2k3/P7/8/8/8/8/7p/4K1N1 w - - 0 1", ["a7a8q"], "Qr2k3/8/8/8/8/8/7p/4K1N1 b - - 0 1"],
		["promo N", "1r2k3/P7/8/8/8/8/7p/4K1N1 w - - 0 1", ["a7a8n"], "Nr2k3/8/8/8/8/8/7p/4K1N1 b - - 0 1"],
		["promo R takes", "1r2k3/P7/8/8/8/8/7p/4K1N1 w - - 0 1", ["a7b8r"], "1R2k3/8/8/8/8/8/7p/4K1N1 b - - 0 1"],
		["promo B takes", "1r2k3/P7/8/8/8/8/7p/4K1N1 w - - 0 1", ["a7b8b"], "1B2k3/8/8/8/8/8/7p/4K1N1 b - - 0 1"],
		["black promo takes", "1r2k3/P7/8/8/8/8/7p/4K1N1 b - - 0 1", ["h2g1q"], "1r2k3/P7/8/8/8/8/8/4K1q1 w - - 0 2"],
		["black promo", "1r2k3/P7/8/8/8/8/7p/4K1N1 b - - 0 1", ["h2h1n"], "1r2k3/P7/8/8/8/8/8/4K1Nn w - - 0 2"],
		["rook taken, castling lost", "r3k2r/8/8/8/8/8/6b1/R3K2R b KQkq - 0 1", ["g2h1"], "r3k2r/8/8/8/8/8/8/R3K2b w Qkq - 0 2"],
		["king takes", "4k3/8/8/8/8/8/3q4/4K3 w - - 0 1", ["e1d2"], "4k3/8/8/8/8/8/3K4/8 b - - 0 1"],
		["double push then e.p. lost", "4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1", ["d7d5", "e1d1", "e8d8"],
			"3k4/8/8/3pP3/8/8/8/3K4 w - - 2 3"],
	]
	for set_name in SETS:
		for how in ["call", "click"]:
			for c in cases:
				await _start(BOARDS[rng.randi() % BOARDS.size()], set_name, ChessPosition.WHITE, c[1])
				var tag := "%s [%s, %s]" % [c[0], set_name if set_name != "" else "creatures", how]
				for u: String in c[2]:
					var m := game.pos.move_from_uci(u)
					if m < 0:
						_fail(tag + ": %s not legal" % u)
						break
					await _play(m, how)
					if not await _settle():
						_fail(tag + ": never ends")
						break
					moves_played += 1
				_expect(game.pos.get_fen() == c[3], tag + ": position " + game.pos.get_fen())
				_state_ok(tag)


## Mate, stalemate, resign: the game ends once, the board stays right and takes no more moves.
func _endings() -> void:
	var cases := [
		["mate", "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1a8", ChessPosition.Result.CHECKMATE],
		["stalemate", "7k/8/6Q1/8/8/8/8/K7 w - - 0 1", "g6f7", ChessPosition.Result.STALEMATE],
		["black mates", "r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1", "a8a1", ChessPosition.Result.CHECKMATE],
	]
	for c in cases:
		for side in [ChessPosition.WHITE, ChessPosition.BLACK]:
			await _start("prairie", "", side, c[1], side == ChessPosition.WHITE, side == ChessPosition.BLACK)
			var ends := [0]
			var cb := func(_r: Dictionary) -> void: ends[0] += 1
			game.game_over.connect(cb)
			game.play_move(game.pos.move_from_uci(c[2]))
			await _settle()
			var t := 0.0
			while ends[0] == 0 and t < MAX_WAIT:  # mate: the kings' staging comes before the end
				await get_tree().process_frame
				t += get_process_delta_time()
			await _frames(5)
			var tag: String = c[0] + (" (black at the bottom)" if side == ChessPosition.BLACK else "")
			_expect(ends[0] == 1, tag + ": game_over %d times" % ends[0])
			_expect(game.over and game.pos.result() == c[3], tag + ": not over as it should")
			_state_ok(tag)
			var any := Array(game.pos.legal_moves())
			if not any.is_empty():
				game.play_move(any[0])
				_expect(not game.busy, tag + ": a move played after the end")
			game.game_over.disconnect(cb)
	# resign, then nothing moves any more
	await _start("forest", "", ChessPosition.WHITE, ChessPosition.START_FEN, false, true)
	game.resign()
	await _frames(5)
	_expect(game.over, "resign: game not over")
	game._on_square_clicked(ChessPosition.sq_from_name("e2"))
	game._on_square_clicked(ChessPosition.sq_from_name("e4"))
	await _frames(3)
	_expect(not game.busy and game.pos.board[ChessPosition.sq_from_name("e2")] != ChessPosition.EMPTY, "resign: a move went through")


## A move cut short by a new game, a resignation or the menus' showcase, at any moment of its staging.
func _interruptions(rounds: int) -> void:
	var fens := [
		["castle", "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1", ["e1g1", "e1c1"]],
		["capture", "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", ["e4d5"]],
		["promotion", "1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1", ["a7a8q", "a7b8n"]],
		["e.p.", "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", ["e5d6"]],
		["walk", ChessPosition.START_FEN, ["e2e4", "g1f3", "b1c3"]],
	]
	for i in rounds:
		var f: Array = fens[i % fens.size()]
		var tag := "cut %s #%d" % [f[0], i]
		await _start(BOARDS[i % BOARDS.size()], SETS[i % SETS.size()], ChessPosition.WHITE, f[1])
		var ms: Array = f[2]
		game.play_move(game.pos.move_from_uci(ms[i % ms.size()]))
		await _frames(rng.randi_range(0, 90))
		match i % 3:
			0:
				await _start(BOARDS[(i + 3) % BOARDS.size()], "", ChessPosition.WHITE)
				await _frames(rng.randi_range(30, 120))
				_expect(game.pos.get_fen() == ChessPosition.START_FEN and not game.busy, tag + ": new game not clean")
				_state_ok(tag + " -> new game")
			1:
				game.resign()
				await _settle()
				await _frames(60)
				_state_ok(tag + " -> resign")
			2:
				game.showcase(BOARDS[(i + 5) % BOARDS.size()])
				await _frames(rng.randi_range(30, 120))
				_expect(game.pos.get_fen() == ChessPosition.START_FEN and not game.busy, tag + ": showcase not clean")
				_state_ok(tag + " -> showcase")


## Random clicks anywhere, at any time (also while a move is staged): only legal moves go through.
func _random_clicks(n: int) -> void:
	await _start("village", "", ChessPosition.WHITE)
	var made := [0]
	var count := func(_san: String) -> void: made[0] += 1
	game.move_made.connect(count)
	for i in n:
		var sq := rng.randi() % 64
		var legal := Array(game.pos.legal_moves())
		if rng.randf() < 0.5 and not legal.is_empty():  # half the clicks aimed at a piece that can move, or where it can go
			var m: int = legal[rng.randi() % legal.size()]
			sq = ChessPosition.move_from(m) if rng.randf() < 0.5 else ChessPosition.move_to(m)
		game._on_square_clicked(sq)
		if not promo_asked.is_empty():
			game.play_move(promo_asked[0])
			promo_asked = []
		if rng.randf() < 0.3:
			await _frames(rng.randi_range(1, 20))
		if game.over:
			await _start("village", "", ChessPosition.WHITE)
	await _settle()
	game.move_made.disconnect(count)
	moves_played += made[0]
	_state_ok("random clicks (%d moves went through)" % made[0])
	print("random clicks: %d clicks, %d moves" % [n, made[0]])


func _run() -> void:
	Lang.apply("fr")
	Audio.muted_cues = true
	for bus in AudioServer.bus_count:
		AudioServer.set_bus_mute(bus, true)
	Atlas.choose_set(Vector2(1920, 1080))
	game = ChessGame.new()
	game.two_humans = true
	add_child(game)
	game.promotion_needed.connect(func(opts: Array) -> void: promo_asked = opts)
	game.game_over.connect(func(_r: Dictionary) -> void: overs += 1)
	await _frames(5)
	game.choreo.speed = 8.0
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()

	print("== special moves")
	await _special_moves()
	print("== endings")
	await _endings()
	print("== interrupted moves")
	await _interruptions(12 if quick else 45)
	print("== random clicks")
	await _random_clicks(300 if quick else 1500)
	print("== random games")
	var games := 6 if quick else 30
	for g in games:
		var before := fails
		await _random_game(BOARDS[g % BOARDS.size()], SETS[g % SETS.size()], g % 2 == 1, 60 if quick else 160)
		print("game %d/%d %s/%s: %s, %d moves so far" % [g + 1, games, BOARDS[g % BOARDS.size()], SETS[g % SETS.size()],
			"ok" if fails == before else "FAILED", moves_played])
	Engine.time_scale = 1.0
	print("MOVES %d, CHECKS %d, FAILS %d, %.0f s" % [moves_played, checks, fails, (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(1 if fails else 0)
