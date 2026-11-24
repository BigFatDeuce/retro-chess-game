extends Node
## Tilted view: captures at 0 and full tilt, and every square still answers a click at its place on screen.
## godot --path game --resolution 1280x720 res://tests/tilt_test.tscn -- <out_dir>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	Atlas.choose_set(get_viewport().get_visible_rect().size * get_window().get_final_transform().get_scale())
	var game := ChessGame.new()
	add_child(game)
	game.two_humans = true
	game.board_key = "forest"
	game.new_game(ChessPosition.WHITE, {}, ChessPosition.START_FEN)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("tilt0.png"))
	game.camera.target_tilt = 1.0
	await get_tree().create_timer(0.6).timeout
	game.play_move(game.pos.move_from_uci("e2e4"))  # a move while the view settles
	await get_tree().create_timer(2.5).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("tilt1.png"))
	var bad := 0
	for sq in 64:
		var cell := game.board.cell_of(sq)
		var screen := get_viewport().get_canvas_transform() * (game.board.get_global_transform() * game.board.project(cell.x + 0.5, cell.y + 0.5))
		var local := game.board.get_global_transform_with_canvas().affine_inverse() * screen
		if game.board.square_at_point(local) != sq:
			bad += 1
	var off := 0
	for sq: int in game.pieces:
		if game.pieces[sq].position.distance_to(game.board.square_pos(sq)) > 1.0:
			off += 1
	var adrift := 0
	var critters: Array = game.life.get_critters()
	for c in critters:
		if c.position.distance_to(game.board.project(c.uv.x, c.uv.y)) > 1.0:
			adrift += 1
	print("tilt ", game.board.tilt, " zoom ", game.camera.zoom.x, " wrong clicks ", bad, " pieces off square ", off,
		" critters adrift ", adrift, "/", critters.size())
	print("TILT_TEST ", "OK" if bad == 0 and off == 0 and adrift == 0 else "FAILED")
	get_tree().quit()
