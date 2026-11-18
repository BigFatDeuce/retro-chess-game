extends Node
## Entry point and flow: the menus over a living board, then games against the ladder's opponents
## (or two players on one screen), saved after every move (resumed from the title) and recorded in the
## current profile when they end.

var game: ChessGame
var hud: GameHud
var menu: MainMenu
var opponent_id := ""  ## "" = two players, FreePlay.ID = a free game (free_opp)
var free_opp: Dictionary = {}  ## the free game's opponent (FreePlay.opponent)
var side := "white"
var online: OnlineClient  ## the line to the online room (a game against a friend at a distance)
var net_game := 0  ## the room's game number being played here (0 = no online game on the board)
var net_opp: Dictionary = {}  ## the friend, for the HUD: {name, avatar, remote: true}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("1d2a22"))
	UiTheme.ensure()
	# the size the game is drawn at, in pixels (inside a SubViewport: the tests' captures at a given resolution)
	var vp := get_viewport()
	var px: Vector2 = Vector2((vp as SubViewport).size) if vp is SubViewport else vp.get_visible_rect().size * get_window().get_final_transform().get_scale()
	Atlas.choose_set(px)
	game = ChessGame.new()
	add_child(game)
	online = OnlineClient.new()
	online.name = "Online"
	add_child(online)
	online.room_changed.connect(_on_room)
	online.opponent_moved.connect(_on_net_move)
	online.opponent_state.connect(_on_net_opponent)
	online.opponent_resigned.connect(func() -> void:
		if net_game > 0:
			game.opponent_resign())
	online.rematch_asked.connect(func() -> void:
		if net_game > 0:
			hud.rematch_note(Lang.f("%s propose une revanche", [online.opponent_name()])))
	online.line_changed.connect(func(up: bool) -> void:
		if net_game > 0:
			hud.notice("" if up else "Connexion perdue… reconnexion en cours"))
	online.failed.connect(func(why: String) -> void:
		if net_game > 0:
			hud.notice("La connexion au serveur a été perdue."))
	hud = GameHud.new()
	add_child(hud)
	hud.setup(game)
	hud.visible = false
	game.game_over.connect(_on_over)
	game.move_made.connect(_on_move)
	hud.restart_requested.connect(_restart)
	hud.resign_requested.connect(func() -> void:
		if net_game > 0:
			online.resign()
		game.resign())
	hud.menu_requested.connect(func() -> void:
		if net_game > 0 and not game.over:
			online.resign()  # leaving an online game gives it up
		to_menu())
	hud.next_requested.connect(_next_opponent)
	hud.path_requested.connect(func() -> void:
		to_menu()
		menu.show_screen("free" if opponent_id == FreePlay.ID else "opponents"))
	menu = MainMenu.new()
	menu.game = game
	menu.online = online
	add_child(menu)
	menu.play_requested.connect(play)
	menu.resume_requested.connect(resume)
	menu.duel_requested.connect(duel)
	menu.free_requested.connect(play_free)
	menu.preview_board.connect(func(key: String) -> void: game.showcase(key))
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	Settings.changed.connect(func(k: String) -> void:
		if k == "language" and hud.visible:
			hud.set_players(_opp()))
	var first := Profiles.opponent(Profiles.next_challenge())
	game.showcase(String(first.get("board", "prairie")))


## The current opponent: a champion, the free game's, the friend online, or {} for two players.
func _opp() -> Dictionary:
	if net_game > 0:
		return net_opp
	if opponent_id == FreePlay.ID:
		return free_opp
	return Profiles.opponent(opponent_id) if opponent_id != "" else {}


## Free play: any board, any strength.
func play_free(elo: int, board: String, p_side: String) -> void:
	opponent_id = FreePlay.ID
	free_opp = FreePlay.opponent(elo, board)
	side = p_side
	game.two_humans = false
	game.board_key = board
	_start()


func to_menu() -> void:
	get_tree().paused = false
	hud.hide_result()
	hud.hide_pause()
	hud.visible = false
	hud.notice("")
	game.two_humans = false
	if net_game > 0 or online.active:
		online.leave()
	net_game = 0
	game.remote = false
	var o := _opp() if opponent_id != "" else Profiles.opponent(Profiles.next_challenge())
	game.showcase(String(o.get("board", game.board_key)))
	menu.visible = true
	menu.show_screen("title")


func play(opp_id: String, p_side: String) -> void:
	var o := Profiles.opponent(opp_id)
	if o.is_empty():
		return
	opponent_id = opp_id
	side = p_side
	game.two_humans = false
	game.board_key = String(o.get("board", "prairie"))
	_start()


## Two players on one screen, on one of the boards the profile has opened.
func duel() -> void:
	opponent_id = ""
	side = "white"
	game.two_humans = true
	var open: Array = []
	for o in Profiles.opponents:
		if Profiles.is_unlocked(o["id"]):
			open.append(o["board"])
	game.board_key = String(open.pick_random()) if not open.is_empty() else "prairie"
	_start()


## The game saved in the current profile, where it was left.
func resume() -> void:
	var g := Profiles.saved_game()
	if g.is_empty():
		return
	opponent_id = String(g.get("opp", ""))
	side = String(g.get("side", "white"))
	if opponent_id == FreePlay.ID:
		free_opp = FreePlay.opponent(int(g.get("elo", 1200)), String(g.get("board", "prairie")))
	game.two_humans = opponent_id == ""
	game.board_key = String(g.get("board", "prairie"))
	_start(String(g.get("fen", ChessPosition.START_FEN)), PackedStringArray(g.get("moves", [])))


func _start(fen := ChessPosition.START_FEN, moves := PackedStringArray()) -> void:
	menu.visible = false
	hud.visible = true
	hud.hide_result()
	var engine: Dictionary = _opp().get("engine", {})
	game.remote = net_game > 0
	game.new_game(ChessPosition.BLACK if side == "black" else ChessPosition.WHITE, engine, fen, moves)
	hud.set_players(_opp())
	# the three first boards of the ladder: the classic pieces offered to whoever does not like the monsters
	var first: Array = Profiles.opponents.slice(0, 3).map(func(o: Dictionary) -> String: return String(o.get("board", "")))
	hud.pieces_tip(net_game == 0 and game.board_key in first)
	if moves.is_empty() and net_game == 0:
		Profiles.clear_game()  # an online game leaves the saved game alone


func _restart() -> void:
	if net_game > 0:
		online.ask_rematch()  # the room starts the new game when both want it
		hud.rematch_note(Lang.f("En attente de %s…", [online.opponent_name()]))
		return
	_start()


func _next_opponent() -> void:
	var i := Profiles.index_of(opponent_id)
	if i >= 0 and i + 1 < Profiles.opponents.size():
		play(Profiles.opponents[i + 1]["id"], side)


## Each move is saved: leaving (or a crash) never loses the game.
func _on_move(_san: String) -> void:
	if net_game > 0:
		# my move goes to the room (the friend's own moves came from it); the end of the game too
		var n := game.uci_moves.size() - 1
		if (n % 2 == 0) == (side == "white"):
			online.send_move(game.uci_moves[n], n)
		return
	if game.over:
		return
	var g := {"opp": opponent_id, "side": side, "board": game.board_key, "fen": game.start_fen,
		"moves": Array(game.uci_moves)}
	if opponent_id == FreePlay.ID:
		g["elo"] = int(free_opp.get("elo", 1200))
	Profiles.store_game(g)


func _on_over(r: Dictionary) -> void:
	if net_game > 0:
		online.report_over()
		await get_tree().create_timer(0.8).timeout
		hud.show_result(r, false)
		return
	Profiles.clear_game()
	var can_next := false
	if opponent_id != "" and opponent_id != FreePlay.ID and not game.two_humans:
		var outcome := "draw"
		if int(r.get("winner", -1)) >= 0:
			outcome = "win" if r.get("human_won", false) else "loss"
		var info := Profiles.record_result(opponent_id, outcome, side)
		var unlocked := String(info.get("unlocked", ""))
		if unlocked != "":
			r["unlocked"] = unlocked
		var i := Profiles.index_of(opponent_id)
		can_next = outcome == "win" and i + 1 < Profiles.opponents.size()
	await get_tree().create_timer(0.8).timeout
	hud.show_result(r, can_next)


# --- online games ---------------------------------------------------------------------------------------------------

## The room's state: the game starts when the friend is there (a new game after a rematch); on a reconnection,
## the moves played meanwhile are caught up.
func _on_room(info: Dictionary) -> void:
	if String(info.get("state", "")) != "playing":
		return
	var number := int(info.get("game", 1))
	var moves := PackedStringArray(info.get("moves", []))
	var opp: Dictionary = info.get("opponent", {}) if info.get("opponent") is Dictionary else {}
	if number != net_game:
		net_game = number
		opponent_id = ""
		side = String(info.get("you", "white"))
		net_opp = {"name": String(opp.get("name", "Adversaire")), "avatar": String(opp.get("avatar", "tofu")),
			"remote": true, "board": String(info.get("board", "prairie"))}
		net_opp["avatar"] = Profiles.RETIRED.get(net_opp["avatar"], net_opp["avatar"])  # a friend on an older version
		if UiKit.avatar_texture(String(net_opp["avatar"])) == null:
			net_opp["avatar"] = "tofu"  # a portrait this version does not have
		game.two_humans = false
		game.board_key = String(info.get("board", "prairie"))
		if not menu.boards.has(game.board_key):
			game.board_key = "prairie"  # a board this version does not have
		_start(ChessPosition.START_FEN, moves)
		hud.notice("" if bool(opp.get("online", true)) else Lang.f("%s s'est déconnecté : la partie reprendra à son retour.", [net_opp["name"]]))
		return
	# same game: what the friend played while the line was down
	var have := game.uci_moves.size()
	for i in range(have, moves.size()):
		_on_net_move(moves[i], i)
	var res: Variant = info.get("result")
	if res is Dictionary and String((res as Dictionary).get("why", "")) == "resign" and not game.over 			and String((res as Dictionary).get("winner", "")) == side:
		game.opponent_resign()


func _on_net_move(uci: String, n: int) -> void:
	if net_game == 0:
		return
	# the moves come in order; one already on the board (or still being staged) is not played twice
	var expected := game.uci_moves.size() + (1 if game.busy else 0)
	if n != expected:
		return
	game.remote_move(uci)


func _on_net_opponent(state: String) -> void:
	if net_game == 0:
		return
	match state:
		"left":
			hud.notice(Lang.f("%s s'est déconnecté : la partie reprendra à son retour.", [String(net_opp.get("name", ""))]))
		"back", "joined":
			hud.notice("")
