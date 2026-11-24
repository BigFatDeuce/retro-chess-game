extends Node
## Visual test of the interface and the game flow, on a separate save (user://profiles_test.json): every
## screen is captured (title, the trail of opponents, a locked opponent, profiles, profile editing, settings,
## a game with its history, pause, resign confirmation, victory with the unlock, defeat, promotion, resume).
## Run: godot --path game res://tests/menu_test.tscn -- <out_dir> --test-profile [--vp 3840x2160] [--full]
## --vp draws the game offscreen at exactly that many pixels (any size, whatever the monitor), laid out as the
## game would be on such a screen (2560 x 1440 layout, widened or heightened to the screen's shape); --full
## keeps the shots at full size (by default they are halved).

var out_dir := "user://shots"
var main: Node
var full := false
var _vp: SubViewport


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		out_dir = args[0]
	full = "--full" in args
	if "--lang" in args:
		Settings.values["language"] = args[args.find("--lang") + 1]  # not saved: the player's own setting stays
		Lang.apply(String(Settings.values["language"]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://src/main.gd").new()
	var i := args.find("--vp")
	if i >= 0 and i + 1 < args.size():
		var parts := args[i + 1].split("x")
		var px := Vector2i(int(parts[0]), int(parts[1]))
		_vp = SubViewport.new()
		_vp.size = px
		# the project's canvas_items + expand stretch: 2560 x 1440 at least, the rest follows the shape
		var aspect := float(px.x) / px.y
		var layout := Vector2i(roundi(1440.0 * aspect), 1440) if aspect >= 16.0 / 9.0 else Vector2i(2560, roundi(2560.0 / aspect))
		_vp.size_2d_override = layout
		_vp.size_2d_override_stretch = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# gentle on the graphics driver: a 4K offscreen target with 4x MSAA on top of the window crashed it once
		_vp.msaa_2d = Viewport.MSAA_2X
		Engine.max_fps = 20
		_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(_vp)
		var show := TextureRect.new()
		show.texture = _vp.get_texture()
		show.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		show.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		show.set_anchors_preset(Control.PRESET_FULL_RECT)
		var cl := CanvasLayer.new()
		cl.layer = 100
		add_child(cl)
		cl.add_child(show)
		_vp.add_child(main)
		print("offscreen ", px, " layout ", layout)
	else:
		add_child(main)
	_run()


func _shot(tag: String, wait := 0.7) -> void:
	await get_tree().create_timer(wait, true, false, true).timeout
	var img := (_vp.get_texture() if _vp else get_viewport().get_texture()).get_image()
	if not full:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out_dir.path_join(tag + ".jpg"), 0.88)
	print("shot ", tag, " ", img.get_size())


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _run() -> void:
	await _wait(1.5)
	await _shot("01_title")
	var m: MainMenu = main.menu
	m._sel_opp = ""
	m.show_screen("opponents")
	await _shot("02_opponents", 1.4)
	m._select_opponent("o3")
	await _shot("03_opponent_locked", 1.2)
	m.show_screen("profiles")
	await _shot("04_profiles")
	m._edit_id = ""
	m._edit_avatar = Profiles.avatars[3]
	m.show_screen("profile_edit")
	await _shot("05_profile_edit")
	m.show_screen("settings")
	await _shot("06_settings")
	# a game against the first opponent: two moves, its history, then pause and the resign question
	main.play("o1", "white")
	await _wait(2.0)
	var g: ChessGame = main.game
	for uci in ["e2e4", "g1f3"]:
		while not g.is_human_turn() or g.busy:
			await _wait(0.2)
		g.play_move(g.pos.move_from_uci(uci))
		await _wait(0.3)
	while not g.is_human_turn() or g.busy:
		await _wait(0.2)
	await _shot("07_game", 0.8)
	print("saved game moves: ", (Profiles.saved_game().get("moves", []) as Array).size())
	main.hud.show_pause()
	await _shot("08_pause")
	Ui.confirm(main.hud, "Abandonner ?", "La partie comptera comme une défaite.", "Abandonner", func() -> void: pass, "EmberButton", "flag")
	await _shot("09_resign_confirm")
	for c in main.hud.get_children():
		if c is CanvasLayer:
			c.queue_free()
	main.hud.hide_pause()
	# resume from the title
	main.to_menu()
	await _shot("10_title_resume", 1.2)
	main.resume()
	await _wait(1.5)
	print("resumed moves: ", g.uci_moves.size(), " ", g.san_moves)
	# a win: the second opponent opens
	print("unlocked o2 before: ", Profiles.is_unlocked("o2"))
	main._on_over({"result": ChessPosition.Result.CHECKMATE, "winner": 0, "human_won": true, "moves": 30})
	await _shot("11_victory", 2.8)
	print("unlocked o2 after: ", Profiles.is_unlocked("o2"), " beaten ", Profiles.beaten_count())
	main.hud.show_result({"result": ChessPosition.Result.CHECKMATE, "winner": 1, "human_won": false, "moves": 41}, false)
	await _shot("12_defeat", 1.6)
	main.to_menu()
	await _wait(0.8)
	m.show_screen("opponents")
	await _shot("13_opponents_after", 1.4)
	# the promotion picker
	main.duel()
	g.new_game(ChessPosition.WHITE, {}, "8/1P5k/8/8/8/8/8/4K3 w - - 0 1")
	main.hud.set_players({})
	await _wait(1.0)
	var promos: Array = []
	for sq in 64:
		var ms := Array(g.pos.legal_moves_from(sq)).filter(func(mv): return ChessPosition.move_promo(mv) != 0)
		if not ms.is_empty():
			promos = ms
	print("promotion choices: ", promos.size())
	main.hud.show_promotion(promos)
	await _shot("14_promotion")
	# the move markers: a knight that can go to empty squares and take two pawns
	main.hud._close_promo()
	g.new_game(ChessPosition.WHITE, {}, "4k3/8/3p1p2/8/4N3/8/8/4K3 w - - 0 1")
	await _wait(1.0)
	g._on_square_clicked(28)
	await _shot("15_marks", 0.9)
	# free play: every champion beaten, then any board at any strength
	for o: Dictionary in Profiles.opponents:
		Profiles.record_result(String(o["id"]), "win", "white")
	print("free play: always open")
	main.to_menu()
	await _shot("16_title_free", 1.2)
	m.show_screen("free")
	await _shot("17_free", 1.4)
	for e in [400, 800, 1350, 1400, 2200]:
		print("free ", e, " -> ", FreePlay.engine_for(e))
	main.play_free(1650, "tundra", "white")
	await _wait(1.5)
	g.play_move(g.pos.move_from_uci("d2d4"))
	while not g.is_human_turn() or g.busy:
		await _wait(0.2)
	await _shot("18_free_game", 0.8)
	print("free save: ", Profiles.saved_game().get("opp"), " elo ", Profiles.saved_game().get("elo"))
	main.to_menu()
	m.show_screen("settings")
	await _wait(0.5)
	for c in m.find_children("*", "SettingsPanel", true, false):
		(c as SettingsPanel)._show("display")
	await _shot("19_settings_display", 0.8)
	print("MENU TEST DONE")
	get_tree().quit()
