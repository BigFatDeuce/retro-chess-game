extends Node
## Visual test: plays scripted moves with both sides by hand and saves screenshots along the way.
## Run: godot --path game res://tests/stage_test.tscn -- <out_dir> <scenario> [board]
## Scenarios: opening (walks, leap, pawn and queen captures), ranged (projectile, beam, meteor), promo, mate

var game: ChessGame
var out_dir := "user://shots"
var shot_every := 0.25
var _t := 0.0
var _n := 0
var _done := false

const SCENARIOS := {
	"opening": {"fen": "", "moves": ["e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5a5", "g1f3", "c8g4", "f1e2", "b8c6", "e1g1", "e8c8"]},
	"ranged": {"fen": "r7/1b4k1/8/8/8/8/8/R3K2Q w - - 0 1", "moves": ["a1a8", "b7h1"]},
	"kingfire": {"fen": "4k3/8/8/8/8/8/2q5/4K3 w - - 0 1", "moves": ["e1d2", "c2d2", "e8d8"]},
	"knights": {"fen": "7k/8/3p4/8/4N3/8/5n2/4K3 w - - 0 1", "moves": ["e4d6", "f2d1", "d6b7", "h8g7"]},
	"promo": {"fen": "8/1P5k/8/8/8/8/6p1/4K3 w - - 0 1", "moves": ["b7b8q", "g2g1n", "b8b5"]},
	"mate": {"fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "moves": ["a1a8"]},
	"camera": {"fen": "", "moves": ["e2e4", "e7e5"], "camera": true},
	"look": {"fen": "", "moves": ["e2e4", "e7e5"]},
	"queen2": {"fen": "2k5/P7/8/8/8/8/8/3QK3 w - - 0 1", "moves": ["a7a8q", "c8b7", "a8a1"]},
	"black": {"fen": "", "moves": ["e2e4", "e7e5", "g1f3", "b8c6"], "side": "black"},
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var scen: String = args[1] if args.size() > 1 else "opening"
	for s in ["classic", "staunton"]:  # --classic, --staunton: that set of pieces (not saved: the test only)
		if "--" + s in args:
			Settings.values["piece_set"] = s
			args.erase("--" + s)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.set_default_clear_color(Color("1d2a22"))
	Atlas.choose_set(get_viewport().get_visible_rect().size * get_window().get_final_transform().get_scale())
	game = ChessGame.new()
	game.two_humans = true
	add_child(game)
	var hud := GameHud.new()
	add_child(hud)
	hud.setup(game, "Test", "")
	if args.size() > 2:
		game.board_key = args[2]  # third argument: the board (data/boards.json)
	var s: Dictionary = SCENARIOS[scen]
	var fen: String = s["fen"] if s["fen"] != "" else ChessPosition.START_FEN
	game.two_humans = s.get("side", "white") == "white"
	game.new_game(ChessPosition.BLACK if s.get("side", "") == "black" else ChessPosition.WHITE, {}, fen)
	if not game.two_humans:
		game.ai.cancel()
		game.two_humans = true
	game.game_over.connect(func(r): print("RESULT ", r))
	_run(s["moves"], scen, s.get("camera", false))


func _run(moves: Array, scen: String, cam := false) -> void:
	await get_tree().create_timer(0.6).timeout
	for u in moves:
		var m := game.pos.move_from_uci(u)
		if m < 0:
			print("ILLEGAL ", u, " in ", game.pos.get_fen())
			continue
		print("move ", u)
		game.play_move(m)
		while game.busy:
			await get_tree().process_frame
		print("  sync ", game.sync_ok(), " fen ", game.pos.get_fen())
	if cam:
		await _camera_check()
	await get_tree().create_timer(2.5).timeout
	_shot("final")
	_done = true
	print("DONE ", scen, " shots ", _n)
	get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	if _t >= shot_every and not _done:
		_t = 0.0
		_shot("%04d" % _n)


func _shot(tag: String) -> void:
	_n += 1
	var img := get_viewport().get_texture().get_image()
	if not tag == "final":
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out_dir.path_join(tag + ".jpg"), 0.85)


## Zooms and pans the camera as far as it goes, then checks that every square still answers a click at its
## place on screen, and that the view stays inside the scene.
func _camera_check() -> void:
	var c := game.camera
	c.target_zoom = 9.0  # clamped by _zoom_at only: set through it
	c.target_zoom = 1.0
	c._zoom_at(10.0, Vector2(2200, 300))
	c.target_pos += Vector2(5000, -5000)
	await get_tree().create_timer(1.5).timeout
	print("camera zoom ", c.zoom, " pos ", c.position)
	_shot("cam_corner")
	c.reset()
	c._zoom_at(1.3, Vector2(1280, 900))
	await get_tree().create_timer(1.2).timeout
	var bad := 0
	for sq in 64:
		var cell := game.board.cell_of(sq)
		var world := game.board.get_global_transform() * game.board.project(cell.x + 0.5, cell.y + 0.5)
		var screen := get_viewport().get_canvas_transform() * world
		var local := game.board.get_global_transform_with_canvas().affine_inverse() * screen
		if game.board.square_at_point(local) != sq:
			bad += 1
	print("camera clicks ok ", bad == 0, " (", bad, " wrong)")
	_shot("cam_zoom")
	c.reset()
	game.set_see_through(false)
	await get_tree().create_timer(1.0).timeout
	var shown := 0
	for n in game.layer.get_children():
		if n is Piece and n.ghost.visible:
			shown += 1
	print("see-through off, ghosts shown: ", shown)
	_shot("see_through_off")
	game.set_see_through(true)
	await get_tree().create_timer(1.0).timeout
