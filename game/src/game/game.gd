class_name ChessGame
extends Node2D
## One game: the rules (ChessPosition) are the truth, the board shows them.
## Flow: a move is chosen (click or engine) -> the choreographer stages it -> the move is applied to the
## position -> the pieces on the board are checked against the position (rebuilt if they ever differ).

signal game_over(result: Dictionary)
signal turn_changed(side: int)
signal promotion_needed(moves: Array)
signal see_through_changed(on: bool)
signal move_made(san: String)  ## after each move is staged and applied (history, saves)
signal move_refused(text: String)  ## why the move tried (or the piece picked) is not allowed, translated

const PIECE_ROLES := {ChessPosition.PAWN: "pawn", ChessPosition.KNIGHT: "knight", ChessPosition.BISHOP: "bishop",
	ChessPosition.ROOK: "rook", ChessPosition.QUEEN: "queen", ChessPosition.KING: "king"}

var pos := ChessPosition.new()
var start_fen := ChessPosition.START_FEN
var uci_moves := PackedStringArray()
var san_moves := PackedStringArray()
var human_side := ChessPosition.WHITE
var two_humans := false  ## both sides played by hand (tests, local games)
var remote := false  ## the other side is a player at a distance: its moves come from the network (remote_move)
var level: Dictionary = {}
var board_key := "prairie"
var pieces_def: Dictionary = {}
## Every still piece (classic or staunton set) fights the same way: it hops up to its victim and knocks it over (tools/build_classic.py).
const CLASSIC_DEF := {"attacks": {"melee": {"anim": "anim0"}}, "highlight": "anim1"}
var busy := false  ## a move is being staged
var over := false

var board: BoardView
var layer: Node2D
var choreo: Choreographer
var ai: AiPlayer
var camera: BoardCamera
var life: AmbientLife
var pieces: Dictionary = {}  ## square -> Piece

var _selected := -1
var _sel_moves: Array = []
var _castle_by_rook: Dictionary = {}  ## rook square -> castling move, while the king is selected
var _think_started := 0.0
var _hide_check := 0.0
var _loaded_board := ""
var _epoch := 0  ## +1 at each new game or showcase: a staging still running for an older one stops there
var see_through := true  ## pieces hidden behind others are shown through them (F1)
var _view_dirty := false  ## the view was tilted: the pieces go back on their squares once nothing moves


func _ready() -> void:
	pieces_def = JSON.parse_string(FileAccess.get_file_as_string("res://data/pieces.json"))
	board = BoardView.new()
	board.name = "Board"
	add_child(board)
	layer = Node2D.new()
	layer.name = "Pieces"
	layer.y_sort_enabled = true
	board.add_child(layer)
	board.decor_layer = layer
	choreo = Choreographer.new()
	choreo.name = "Choreographer"
	add_child(choreo)
	choreo.setup(board, layer, pieces_def.get("fx", {}))
	ai = AiPlayer.new()
	ai.name = "AI"
	add_child(ai)
	ai.move_ready.connect(_on_ai_move)
	board.square_clicked.connect(_on_square_clicked)
	Settings.changed.connect(_on_setting)
	life = AmbientLife.new()
	life.name = "AmbientLife"
	add_child(life)
	life.setup(board, layer)
	camera = BoardCamera.new()
	camera.name = "Camera"
	camera.board = board
	add_child(camera)
	board.view_changed.connect(func() -> void: _view_dirty = true)
	Glove.game = self
	Atlas.piece_set = String(Settings.get_value("piece_set"))  # set by Settings too; tests change the values directly
	for k in ["anim_speed", "see_through", "ambient_life"]:
		_on_setting(k)


## A new game from `fen`; `moves` (UCI) are replayed at once first, to resume a saved game.
func new_game(p_human_side: int, p_level: Dictionary, fen := ChessPosition.START_FEN, moves := PackedStringArray()) -> void:
	ai.cancel()
	_epoch += 1
	human_side = p_human_side
	level = p_level
	start_fen = fen
	var err := pos.set_fen(fen)
	if err != "":
		push_error("Position refusée : " + err)
		pos.set_fen(ChessPosition.START_FEN)
		start_fen = ChessPosition.START_FEN
	uci_moves = PackedStringArray()
	san_moves = PackedStringArray()
	over = false
	busy = false
	board.flipped = human_side == ChessPosition.BLACK and not two_humans
	_load_board()
	camera.reset()
	camera.set_process_unhandled_input(true)
	Audio.music(board_key)
	Audio.ambient(board_key)
	Audio.play("game.start", -4.0)
	board.last_from = -1
	board.last_to = -1
	for u in moves:
		var m := pos.move_from_uci(u)
		if m < 0:
			push_error("Partie reprise : coup illisible '%s', reprise arrêtée là" % u)
			break
		san_moves.append(pos.move_to_san(m))
		pos.make_move(m)
		uci_moves.append(u)
		board.last_from = ChessPosition.move_from(m)
		board.last_to = ChessPosition.move_to(m)
	_clear_selection()
	ai.configure(level)
	_rebuild_pieces()
	_update_check()
	_next_turn()


func is_human_turn() -> bool:
	return two_humans or pos.side == human_side


## Pieces hidden behind others are shown through them (PieceGhost): a piece is hidden when the body of a
## piece standing in front of it covers a good part of its own.
func _process(delta: float) -> void:
	if _view_dirty and not busy:
		_view_dirty = false
		for sq: int in pieces:
			if is_instance_valid(pieces[sq]):
				choreo.place_on(pieces[sq], sq)
	_hide_check -= delta
	if _hide_check > 0.0:
		return
	_hide_check = 0.1
	if not see_through:
		for n in layer.get_children():
			if n is Piece:
				n.hidden_amount = 0.0
		return
	var list: Array[Piece] = []
	for n in layer.get_children():
		if n is Piece and is_instance_valid(n) and n.modulate.a > 0.5:
			list.append(n)
	for p in list:
		var body := p.body_rect()
		var area := body.get_area()
		var covered := 0.0
		if area > 1.0:
			for q in list:
				if q == p or q.position.y <= p.position.y + 2.0:
					continue
				var front := q.body_rect().grow_individual(-q.body_rect().size.x * 0.12, -q.body_rect().size.y * 0.1,
					-q.body_rect().size.x * 0.12, 0.0)
				covered = maxf(covered, body.intersection(front).get_area() / area)
		p.hidden_amount = covered if covered > 0.3 else 0.0


func set_see_through(on: bool) -> void:
	if on == see_through:
		return
	see_through = on
	_hide_check = 0.0
	Settings.set_value("see_through", on)
	see_through_changed.emit(on)


func _on_setting(key: String) -> void:
	match key:
		"anim_speed":
			choreo.speed = float(Settings.get_value("anim_speed"))
		"see_through":
			set_see_through(bool(Settings.get_value("see_through")))
		"piece_set":
			# never in the middle of a move: the staging holds the pieces it moves
			while busy and is_inside_tree():
				await get_tree().process_frame
			if not pieces.is_empty():
				_rebuild_pieces()
		"performance":
			board.set_plain_ground(Settings.performance())
			board.queue_redraw()  # edge smoothing on or off: the soft edges follow
		"ambient_life":
			var on := bool(Settings.get_value("ambient_life"))
			life.enabled = on
			for c in life.get_critters():
				c.visible = on
				c.set_process(on)


## Loads the board's theme unless it is already there (same board, same orientation: the decor is placed
## for the side at the bottom).
func _load_board() -> void:
	var want := "%s|%s" % [board_key, board.flipped]
	if want == _loaded_board:
		return
	_loaded_board = want
	board.load_theme(board_key)
	life.load_theme(board_key)
	_on_setting("ambient_life")


## The board as a living backdrop for the menus: the armies in place, nobody plays, the camera stays put.
func showcase(key: String) -> void:
	ai.cancel()
	_epoch += 1
	over = true
	busy = false
	two_humans = false
	board_key = key
	board.flipped = false
	pos.set_fen(ChessPosition.START_FEN)
	start_fen = ChessPosition.START_FEN
	uci_moves = PackedStringArray()
	san_moves = PackedStringArray()
	_load_board()
	board.last_from = -1
	board.last_to = -1
	board.check_sq = -1
	_clear_selection()
	board.input_enabled = false
	_rebuild_pieces()
	camera.reset()
	camera.set_process_unhandled_input(false)
	Audio.music("menu")
	Audio.ambient(key)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F1:
		set_see_through(not see_through)
		get_viewport().set_input_as_handled()


# --- pieces ---------------------------------------------------------------------------------------------------------

func _side_name(c: int) -> String:
	return "white" if c == ChessPosition.WHITE else "black"


func _make_piece(p: int, sq: int) -> Piece:
	var side := _side_name(ChessPosition.piece_color(p))
	var role: String = PIECE_ROLES[ChessPosition.piece_type(p)]
	var node := Piece.new()
	node.home_right = (side == "white") != board.flipped
	node.setup(side, role, CLASSIC_DEF if Atlas.still_pieces() else pieces_def["sides"][side][role])
	layer.add_child(node)
	choreo.place_on(node, sq)
	return node


func _rebuild_pieces() -> void:
	for n in layer.get_children():
		if n is Piece:
			n.queue_free()
	pieces.clear()
	for sq in 64:
		var p := pos.board[sq]
		if p != ChessPosition.EMPTY:
			pieces[sq] = _make_piece(p, sq)


## The board must show exactly the position: same piece kind and side on every square.
func sync_ok() -> bool:
	for sq in 64:
		var p := pos.board[sq]
		var has := pieces.has(sq) and is_instance_valid(pieces[sq])
		if p == ChessPosition.EMPTY:
			if has:
				return false
			continue
		if not has:
			return false
		var node: Piece = pieces[sq]
		if node.side != _side_name(ChessPosition.piece_color(p)) or node.role != PIECE_ROLES[ChessPosition.piece_type(p)]:
			return false
		if node.square != sq:
			return false
	return true


# --- input ----------------------------------------------------------------------------------------------------------

func _on_square_clicked(sq: int) -> void:
	if busy or over or not is_human_turn():
		return
	var p := pos.board[sq]
	if _selected >= 0:
		var options := _sel_moves.filter(func(m): return ChessPosition.move_to(m) == sq)
		if options.is_empty() and _castle_by_rook.has(sq):
			options = [_castle_by_rook[sq]]  # king, then its rook: castles (the usual gesture)
		if not options.is_empty():
			_clear_selection()
			if options.size() > 1:
				promotion_needed.emit(options)  # the UI answers with play_move()
			else:
				play_move(options[0])
			return
		var why := _refusal(_selected, sq)
		if why != "":
			move_refused.emit(why)
			return
	if p != ChessPosition.EMPTY and ChessPosition.piece_color(p) == pos.side:
		if sq == _selected:
			_clear_selection()
			return
		_selected = sq
		Audio.play("game.select", -6.0)
		_sel_moves = Array(pos.legal_moves_from(sq))
		board.selected = sq
		var t: Array[int] = []
		var caps: Array[int] = []
		_castle_by_rook = {}
		for m in _sel_moves:
			var to := ChessPosition.move_to(m)
			if not to in t:
				t.append(to)
			if ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE:
				# the rook of that side (h or a file of the king's rank) is a target too
				var rook_sq := sq - sq % 8 + (7 if to % 8 > sq % 8 else 0)
				_castle_by_rook[rook_sq] = m
				if not rook_sq in t:
					t.append(rook_sq)
			if ChessPosition.move_flags(m) & (ChessPosition.FLAG_CAPTURE | ChessPosition.FLAG_EP):
				caps.append(to)
		board.targets = t
		board.capture_targets = caps
		board.queue_redraw()
		if _sel_moves.is_empty():
			var why := _stuck(sq)
			if why != "":
				move_refused.emit(why)
	else:
		_clear_selection()


## Why the selected piece cannot go to `to` ("" when it simply does not move that way): castling refused, or a move
## that would leave the own king in check.
func _refusal(from: int, to: int) -> String:
	var us := pos.side
	var p := pos.board[from]
	if ChessPosition.piece_type(p) == ChessPosition.KING and from == (4 if us == ChessPosition.WHITE else 60):
		var own_rook := ChessPosition.make_piece(ChessPosition.ROOK, us)
		if to == from + 2 or (to == from + 3 and pos.board[to] == own_rook):
			return _castle_refusal(from, true)
		if to == from - 2 or (to == from - 4 and pos.board[to] == own_rook):
			return _castle_refusal(from, false)
	if pos.board[to] != ChessPosition.EMPTY and ChessPosition.piece_color(pos.board[to]) == us:
		return ""
	for m in pos.pseudo_moves():
		if ChessPosition.move_from(m) == from and ChessPosition.move_to(m) == to:
			if pos.in_check():
				return Lang.t("Ton roi est en échec : ce coup ne le protège pas.")
			if ChessPosition.piece_type(p) == ChessPosition.KING:
				return Lang.t("Ce coup mettrait ton roi en échec.")
			return Lang.t("Cette pièce est clouée : la bouger exposerait ton roi.")
	return ""


func _castle_refusal(ksq: int, king_side: bool) -> String:
	var us := pos.side
	var flag: int
	if us == ChessPosition.WHITE:
		flag = ChessPosition.CASTLE_WK if king_side else ChessPosition.CASTLE_WQ
	else:
		flag = ChessPosition.CASTLE_BK if king_side else ChessPosition.CASTLE_BQ
	if not pos.castling & flag:
		return Lang.t("Roque impossible : le roi ou cette tour a déjà bougé.")
	for s in ([ksq + 1, ksq + 2] if king_side else [ksq - 1, ksq - 2, ksq - 3]):
		if pos.board[s] != ChessPosition.EMPTY:
			return Lang.t("Roque impossible : des pièces sont entre le roi et la tour.")
	if pos.in_check():
		return Lang.t("Roque impossible : ton roi est en échec.")
	for s in ([ksq + 1, ksq + 2] if king_side else [ksq - 1, ksq - 2]):
		if pos.is_square_attacked(s, 1 - us):
			return Lang.f("Roque impossible : le roi passerait par %s, une case attaquée.", [ChessPosition.sq_name(s)])
	return ""


## Why a piece of the side to move has no move at all ("" when it is only hemmed in by its own pieces).
func _stuck(sq: int) -> String:
	var tos: Array[String] = []
	for m in pos.pseudo_moves():
		if ChessPosition.move_from(m) == sq and not ChessPosition.move_flags(m) & ChessPosition.FLAG_CASTLE:
			var n := ChessPosition.sq_name(ChessPosition.move_to(m))
			if not n in tos:
				tos.append(n)
	if tos.is_empty():
		return ""
	if ChessPosition.piece_type(pos.board[sq]) == ChessPosition.KING:
		return Lang.f("Ton roi ne peut pas bouger : les cases libres autour de lui sont attaquées (%s).", [", ".join(tos)])
	if pos.in_check():
		return Lang.t("Ton roi est en échec : cette pièce ne peut pas le protéger.")
	return Lang.t("Cette pièce est clouée : la bouger exposerait ton roi.")


func _clear_selection() -> void:
	_selected = -1
	_sel_moves = []
	_castle_by_rook = {}
	board.selected = -1
	board.targets = []
	board.capture_targets = []
	board.queue_redraw()


# --- turns ----------------------------------------------------------------------------------------------------------

func _next_turn() -> void:
	turn_changed.emit(pos.side)
	if not two_humans and pos.side == human_side and not uci_moves.is_empty():
		Audio.play("game.your_turn", -10.0)
	board.input_enabled = is_human_turn()
	if not is_human_turn() and not over and not remote:
		_think_started = Time.get_ticks_msec() / 1000.0
		ai.think(start_fen, uci_moves, pos)


func _on_ai_move(uci: String) -> void:
	if over or busy:
		return
	var m := pos.move_from_uci(uci)
	if m < 0:
		push_error("Coup du moteur illégal ou absent : '%s' (position %s)" % [uci, pos.get_fen()])
		var legal := pos.legal_moves()
		if legal.is_empty():
			return
		m = legal[0]
	# a short pause so an instant answer does not look mechanical
	var waited := Time.get_ticks_msec() / 1000.0 - _think_started
	if waited < 0.6:
		await get_tree().create_timer(0.6 - waited).timeout
	if over:
		return
	play_move(m)


## Stages then applies a legal move.
func play_move(m: int) -> void:
	if busy or over:
		return
	if not m in Array(pos.legal_moves()):
		push_error("Coup refusé : %d" % m)
		return
	busy = true
	board.input_enabled = false
	_clear_selection()
	var from := ChessPosition.move_from(m)
	var to := ChessPosition.move_to(m)
	var flags := ChessPosition.move_flags(m)
	var mover: Piece = pieces[from]
	var info := {"mover": mover, "from": from, "to": to,
		"knight": ChessPosition.piece_type(pos.board[from]) == ChessPosition.KNIGHT}
	if flags & ChessPosition.FLAG_EP:
		var cap_sq := to - 8 if pos.side == ChessPosition.WHITE else to + 8
		info["captured"] = pieces.get(cap_sq)
		info["captured_sq"] = cap_sq
	elif flags & ChessPosition.FLAG_CAPTURE:
		info["captured"] = pieces.get(to)
		info["captured_sq"] = to
	if flags & ChessPosition.FLAG_CASTLE:
		var kingside := (to & 7) == 6
		var rook_from := (from & ~7) | (7 if kingside else 0)
		info["rook"] = pieces.get(rook_from)
		info["rook_from"] = rook_from
		info["rook_to"] = (from & ~7) | (5 if kingside else 3)
	var san := pos.move_to_san(m)
	board.check_sq = -1
	# the map follows the move at once: the staging only animates nodes it was handed
	pieces.erase(from)
	if info.has("captured_sq"):
		pieces.erase(info["captured_sq"])
	if info.get("rook"):
		pieces.erase(info["rook_from"])
		pieces[info["rook_to"]] = info["rook"]
	pieces[to] = mover
	var epoch := _epoch
	await choreo.play_move(info)
	if epoch != _epoch:
		return  # the game was left (menu, new game) while this move was being staged
	pos.make_move(m)
	uci_moves.append(pos.move_to_uci(m))
	san_moves.append(san)
	move_made.emit(san)
	var promo := ChessPosition.move_promo(m)
	if promo:
		var np := _make_piece(ChessPosition.make_piece(promo, ChessPosition.piece_color(pos.board[to])), to)
		pieces[to] = np
		await choreo.promote(mover, np)
		if epoch != _epoch:
			return
	board.last_from = from
	board.last_to = to
	if not sync_ok():
		push_error("Plateau désynchronisé après %s : reconstruction depuis la position" % san)
		_rebuild_pieces()
	var res := pos.result()
	_update_check()
	if res == ChessPosition.Result.ONGOING and pos.in_check():
		await choreo.check(pieces.get(pos.king_sq[pos.side]))
		if epoch != _epoch:
			return
	busy = false
	if res != ChessPosition.Result.ONGOING:
		await _finish(res)
		return
	_next_turn()


func _update_check() -> void:
	board.check_sq = pos.king_sq[pos.side] if pos.in_check() else -1
	board.queue_redraw()


func _finish(res: int) -> void:
	over = true
	board.input_enabled = false
	var winner := -1
	if res == ChessPosition.Result.CHECKMATE:
		winner = 1 - pos.side
		await choreo.mate(pieces.get(pos.king_sq[winner]), pieces.get(pos.king_sq[pos.side]))
	Audio.music("victory" if winner == human_side or two_humans else "defeat")
	game_over.emit({"result": res, "winner": winner, "human_won": winner == human_side,
		"moves": san_moves.size()})


## A move of the player at a distance (online game), played as soon as the board is free.
func remote_move(uci: String) -> void:
	var epoch := _epoch
	while busy and not over and epoch == _epoch:
		await get_tree().process_frame
	if over or epoch != _epoch or is_human_turn():
		return
	var m := pos.move_from_uci(uci)
	if m < 0:
		push_error("Coup reçu illégal : '%s' (position %s)" % [uci, pos.get_fen()])
		return
	play_move(m)


## The player at a distance resigned: the game is won.
func opponent_resign() -> void:
	if over:
		return
	over = true
	board.input_enabled = false
	_clear_selection()
	Audio.music("victory")
	game_over.emit({"result": -1, "winner": human_side, "human_won": true, "resigned": true, "opponent_resigned": true,
		"moves": san_moves.size()})


func resign() -> void:
	if over:
		return
	ai.cancel()
	over = true
	board.input_enabled = false
	Audio.music("defeat")
	game_over.emit({"result": -1, "winner": 1 - human_side, "human_won": false, "resigned": true,
		"moves": san_moves.size()})
