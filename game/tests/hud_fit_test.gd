extends Node
## Headless: do the HUD's panels stay off the board? Starts a game, then compares the panels' screen rects with the
## board's projected outline (and the far row's pieces, about 170 layout px tall). Run:
## godot --headless --path game --resolution WxH res://tests/hud_fit_test.tscn

const PIECE_H := 170.0
const GAP := 24.0  ## room kept between a panel and the board


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	get_window().size = Vector2i(int(a[0]), int(a[1])) if a.size() >= 2 else Vector2i(1920, 1080)
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	Settings.values["pieces_tip"] = true  # the note of the first boards shown (not saved)
	main.play("o1", "white")
	for i in 60:
		await get_tree().process_frame
	var game: ChessGame = main.game
	var b: BoardView = game.board
	var xf := b.get_viewport().get_canvas_transform() * b.get_global_transform()
	# the board's outline and the tops of the far row's pieces, in screen px
	var pts: Array[Vector2] = []
	var lo := -BoardView.BORDER  # the wooden frame around the squares
	var hi := 8.0 + BoardView.BORDER
	for k in 41:
		var t := lerpf(lo, hi, k / 40.0)
		pts.append(xf * b.project(t, lo))
		pts.append(xf * b.project(t, hi))
		pts.append(xf * b.project(lo, t))
		pts.append(xf * b.project(hi, t))
	for k in 8:
		for dx in [0.1, 0.5, 0.9]:  # the far row's pieces: about a square wide, PIECE_H tall
			for h in [0.0, 0.5, 1.0]:
				pts.append(xf * b.project(k + dx, 7.5) - Vector2(0, h * PIECE_H * xf.get_scale().y))
	var bad := 0
	for c: Control in [main.hud._left, main.hud._right, main.hud._sets]:
		var r := c.get_global_rect().grow(GAP)
		var n := 0
		for p in pts:
			if r.has_point(p):
				n += 1
		bad += n
		print("panel ", r, " : ", n)
	print("vp ", get_viewport().get_visible_rect().size, " canvas ", b.get_viewport().get_canvas_transform(), " board xf ", b.get_global_transform())
	print("board x ", _range(pts, true), " y ", _range(pts, false))
	print("a8 corner ", xf * b.project(0.0, 8.0), " a1 corner ", xf * b.project(0.0, 0.0), " cam ", game.camera.zoom, game.camera.position, game.camera.offset)
	for c in main.hud._right.get_children():
		print("  ", c.get_class(), " ", c.size)
	if main.hud._tip:
		for c in main.hud._tip.find_children("*", "Control", true, false):
			if c is FxButton or c is Label or c is BoxContainer:
				print("    ", c.get_class(), " ", c.size)
	print("HUD_FIT ", "OK" if bad == 0 else "CHEVAUCHE (%d points)" % bad)
	get_tree().quit()


func _range(pts: Array[Vector2], x: bool) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.x if x else p.y)
		hi = maxf(hi, p.x if x else p.y)
	return Vector2(lo, hi)
