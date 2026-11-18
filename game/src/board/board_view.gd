class_name BoardView
extends Node2D
## The board seen from the front with the camera height of the library's world: the ground is flattened about as
## much as in the creatures' own 3/4 view (rows about 0.58 of a square deep), with a slight perspective so the
## board still reads as a chessboard. Squares, border, ground and decor come from the board's theme
## (data/boards.json, baked by tools/build_boards.py).
## Layout reference 2560x1440. Board coordinates: u across (0..8, left to right on screen),
## v depth (0..8, front edge to back edge). A square's centre is (col + 0.5, row + 0.5).
## `flipped` turns the board for the black side: the player's own pieces are always in front.

signal square_clicked(sq: int)
signal view_changed  ## the view was tilted: whatever stands on the board is placed again

const SQUARE := 210.0  ## front-row square width (layout px)
const PIECE_K := 1.0  ## pieces.json scales are on-screen scales on the front row
const K := 0.035  ## perspective: scale at depth v is 1 / (1 + K v)
const FRONT_Y := 1330.0  ## screen y of the front edge
const DEPTH_SPAN := 805.0  ## screen height of the board
const CX := 1280.0
const BORDER := 0.42  ## frame width, squares
const TILT_DEPTH := 0.5  ## full tilt: the board 50 % deeper on screen, as if the player stood up to look down on it

var flipped := false:
	set(v):
		flipped = v
		queue_redraw()
var colors := {
	"light": Color("e9dcb8"), "dark": Color("8a6a4a"), "frame": Color("4a3626"), "frame_edge": Color("2e2117"),
	"select": Color(1.0, 0.86, 0.35, 0.5), "move": Color(0.35, 0.9, 0.3, 0.85),
	"capture": Color(0.95, 0.3, 0.2, 0.8), "last": Color(1.0, 0.92, 0.45, 0.3), "check": Color(1.0, 0.15, 0.1, 0.6),
	"hover": Color(1, 1, 1, 0.16), "label": Color(0.98, 0.94, 0.8, 0.9),
}
var theme_key := ""
var tex_light: Array[Texture2D] = []
var tex_dark: Array[Texture2D] = []
var tex_ground: Texture2D
var tex_border: Texture2D
var ground_repeat := 4.0
var square_repeat := 0.0  ## > 0: painted square textures laid across the board (squares per repeat)
var decor_layer: Node2D  ## where the theme's standing objects go (the y-sorted layer of the pieces)
var _decor: Array[Node] = []
var obstacles: Array[Vector3] = []  ## standing decor footprints: (u, v, radius in squares), for the critters
var _ground: Polygon2D  ## the ground around the board (ground.gdshader), drawn behind the board
var _ground_variation := 1.0  ## the board's blend of two ground copies (off in performance mode)
var _avg := {}  ## mean colours of the theme (light, dark, border, ground): the soft edges are drawn in them


## Performance mode: the ground drawn from one copy of its texture.
func set_plain_ground(on: bool) -> void:
	if _ground:
		(_ground.material as ShaderMaterial).set_shader_parameter("variation", 0.0 if on else _ground_variation)

var selected := -1
var targets: Array[int] = []  ## legal destinations of the selected piece
var capture_targets: Array[int] = []
var last_from := -1
var last_to := -1
var check_sq := -1
var hover := -1
var input_enabled := true

var tilt := 0.0  ## 0 seated (the usual view) .. 1 standing: rows spread out, pieces hide each other less (set_tilt)
var _c := 0.0  ## projection constant (screen y = horizon + _c * s(v))
var _horizon := 0.0
var _pulse := 0.0
var _marks: Node2D  ## the markers (selection, moves, captures, check, last move): redrawn alone while they move
var _shown_sel := -2  ## the selection the markers last popped in for
var _sel_t := 0.0  ## time since that selection (the markers pop in from the piece outwards)


func _init() -> void:
	_set_projection()


## The board's depth on screen grows with the tilt; the front edge stays where it is (the camera follows).
func _set_projection() -> void:
	var s8 := 1.0 / (1.0 + K * 8.0)
	_c = DEPTH_SPAN * (1.0 + TILT_DEPTH * tilt) / (1.0 - s8)
	_horizon = FRONT_Y - _c


## Tilts the view (0..1): board, ground and decor at once; the pieces and critters follow (view_changed).
func set_tilt(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if is_equal_approx(t, tilt):
		return
	tilt = t
	_set_projection()
	if _ground:
		var m := _ground.material as ShaderMaterial
		m.set_shader_parameter("horizon", _horizon)
		m.set_shader_parameter("proj_c", _c)
	for sp in _decor:
		if is_instance_valid(sp) and sp.has_meta("uv"):
			var uv: Vector2 = sp.get_meta("uv")
			(sp as Node2D).position = project(uv.x, uv.y)
	queue_redraw()
	if _marks:
		_marks.queue_redraw()
	view_changed.emit()


func _ready() -> void:
	_ground = Polygon2D.new()
	_ground.name = "Ground"
	_ground.show_behind_parent = true
	_ground.polygon = PackedVector2Array([Vector2(-3000, -2000), Vector2(5600, -2000), Vector2(5600, 3600),
		Vector2(-3000, 3600)])
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/board/ground.gdshader")
	m.set_shader_parameter("horizon", _horizon)
	m.set_shader_parameter("proj_c", _c)
	m.set_shader_parameter("k", K)
	m.set_shader_parameter("square", SQUARE)
	m.set_shader_parameter("cx", CX)
	_ground.material = m
	_ground.visible = false
	_ground.z_index = -2
	add_child(_ground)
	move_child(_ground, 0)
	_marks = Node2D.new()
	_marks.name = "Marks"
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


func scale_at(v: float) -> float:
	return 1.0 / (1.0 + K * v)


## Board point (u across, v depth) -> layout point.
func project(u: float, v: float) -> Vector2:
	var s := scale_at(v)
	return Vector2(CX + (u - 4.0) * SQUARE * s, _horizon + _c * s)


## Layout point -> board point (u, v); outside values mean off the board.
func unproject(p: Vector2) -> Vector2:
	var s := (p.y - _horizon) / _c
	if s <= 0.0:
		return Vector2(-1, -1)
	var v := (1.0 / s - 1.0) / K
	var u := (p.x - CX) / (SQUARE * s) + 4.0
	return Vector2(u, v)


## Screen column / row of a square (file a..h = 0..7, rank 1..8 = 0..7), board turned for black.
func cell_of(sq: int) -> Vector2i:
	var f := sq & 7
	var r := sq >> 3
	return Vector2i(7 - f, 7 - r) if flipped else Vector2i(f, r)


func square_at_cell(c: Vector2i) -> int:
	if c.x < 0 or c.x > 7 or c.y < 0 or c.y > 7:
		return -1
	return (7 - c.y) * 8 + (7 - c.x) if flipped else c.y * 8 + c.x


## Where a piece standing on `sq` has its feet.
func square_pos(sq: int) -> Vector2:
	var c := cell_of(sq)
	return project(c.x + 0.5, c.y + 0.5)


func square_at_point(p: Vector2) -> int:
	var b := unproject(p)
	if b.x < 0.0 or b.y < 0.0:
		return -1
	return square_at_cell(Vector2i(int(floor(b.x)), int(floor(b.y))))


func _quad(c0: float, r0: float, c1: float, r1: float) -> PackedVector2Array:
	return PackedVector2Array([project(c0, r0), project(c1, r0), project(c1, r1), project(c0, r1)])


func _square_quad(sq: int, inset := 0.0) -> PackedVector2Array:
	var c := cell_of(sq)
	return _quad(c.x + inset, c.y + inset, c.x + 1.0 - inset, c.y + 1.0 - inset)


func _process(delta: float) -> void:
	_pulse += delta
	_sel_t += delta
	if selected != _shown_sel:
		_shown_sel = selected
		_sel_t = 0.0
	# only the markers are redrawn (the board itself is drawn again only when its theme or turn changes)
	if (check_sq >= 0 or selected >= 0) and _marks:
		_marks.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	# the event's own position: a tap (or a click with no move before it) does not update the mouse position first
	if event is InputEventMouseMotion:
		var h := square_at_point(_local(event.position))
		if h != hover:
			hover = h
			if _marks:
				_marks.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sq := square_at_point(_local(event.position))
		if sq >= 0:
			square_clicked.emit(sq)
			get_viewport().set_input_as_handled()
	# a tap also arrives as a mouse click (emulated): only one of the two may count, or it selects then unselects
	elif event is InputEventScreenTouch and event.pressed and not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true):
		var sq := square_at_point(_local(event.position))
		if sq >= 0:
			square_clicked.emit(sq)
			get_viewport().set_input_as_handled()


func _local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


# --- theme ----------------------------------------------------------------------------------------------------------

## Loads a baked board: textures, then the decor objects into `decor_layer`.
func load_theme(key: String) -> void:
	theme_key = key
	for n in _decor:
		if is_instance_valid(n):
			n.queue_free()
	_decor.clear()
	obstacles.clear()
	var dir := "res://assets/gen/boards%s/%s/" % [Atlas.sprite_set, key]
	var text := FileAccess.get_file_as_string(dir + "board.json")
	if text.is_empty():
		push_error("Plateau introuvable : " + key)
		return
	var meta: Dictionary = JSON.parse_string(text)
	var density := float(meta.get("density", 1.0))
	tex_light.clear()
	tex_dark.clear()
	for f in meta["light"]:
		tex_light.append(load(dir + String(f)))
	for f in meta["dark"]:
		tex_dark.append(load(dir + String(f)))
	_avg = {}
	for k: String in meta.get("avg", {}):
		_avg[k] = Color(String(meta["avg"][k]))
	tex_ground = load(dir + String(meta["ground"]))
	tex_border = load(dir + String(meta["border"]))
	ground_repeat = float(meta.get("ground_repeat", 4.0))
	if _ground:
		var gm := _ground.material as ShaderMaterial
		gm.set_shader_parameter("tex", tex_ground)
		gm.set_shader_parameter("rep", ground_repeat)
		_ground_variation = float(meta.get("ground_variation", 1.0))
		gm.set_shader_parameter("variation", 0.0 if Settings.performance() else _ground_variation)
		_ground.visible = true
	square_repeat = float(meta.get("square_repeat", 0.0))
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if decor_layer:
		for d in meta["decor"]:
			var sp := Sprite2D.new()
			sp.texture = load(dir + String(d["file"]))
			sp.centered = false
			var o: Array = d["o"]
			sp.offset = -Vector2(o[0], o[1])
			var u := float(d["u"])
			var v := float(d["v"])
			if flipped:
				u = 8.0 - u
			sp.position = project(u, v)
			sp.set_meta("uv", Vector2(u, v))
			var k := scale_at(v) / density
			sp.scale = Vector2(-k if d.get("flip", false) else k, k)
			sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			if d.get("flat", false):
				sp.z_index = -1  # lies on the ground: under the pieces and the standing decor
			elif sp.texture:
				obstacles.append(Vector3(u, v, sp.texture.get_width() / density / SQUARE * 0.32))
			decor_layer.add_child(sp)
			_decor.append(sp)
	queue_redraw()


# --- drawing --------------------------------------------------------------------------------------------------------

func _draw() -> void:
	_draw_border()
	var rng := RandomNumberGenerator.new()
	var uv := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	for sq in 64:
		var c := cell_of(sq)
		var light := ((sq & 7) + (sq >> 3)) % 2 == 1
		var q := _square_quad(sq)
		var set_: Array[Texture2D] = tex_light if light else tex_dark
		if not set_.is_empty():
			rng.seed = sq * 7919 + 13  # the same look for a square every time
			var tex: Texture2D = set_[rng.randi() % set_.size()]
			if square_repeat > 0.0:
				# one painting laid across the whole board: no seam, no repeated pattern square after square
				var r := square_repeat
				var uvw := PackedVector2Array([Vector2(c.x, -c.y) / r, Vector2(c.x + 1, -c.y) / r,
					Vector2(c.x + 1, -c.y - 1) / r, Vector2(c.x, -c.y - 1) / r])
				draw_colored_polygon(q, Color.WHITE, uvw, tex)
				continue
			var turn := rng.randi() % 4  # a quarter turn: the same tile never repeats identically
			var uv2 := PackedVector2Array()
			for i in 4:
				uv2.append(uv[(i + turn) % 4])
			draw_colored_polygon(q, Color.WHITE, uv2, tex)
		else:
			draw_colored_polygon(q, colors["light"] if light else colors["dark"])
		if c.y == 0:
			_label(project(c.x + 0.5, -0.24), "abcdefgh"[sq & 7], scale_at(-0.2))
		if c.x == 0:
			_label(project(-0.22, c.y + 0.5), str((sq >> 3) + 1), scale_at(c.y + 0.5))
	# soft inner shadow along the frame: the squares sit a little below it
	var w := 0.07
	for q in [_quad(0, 0, 8, w), _quad(0, 8 - w, 8, 8), _quad(0, 0, w, 8), _quad(8 - w, 0, 8, 8)]:
		draw_colored_polygon(q, Color(0, 0, 0, 0.25))
	# the browser's renderer (Compatibility) has no 2D edge smoothing at all, whatever the setting says
	if get_viewport() and (get_viewport().msaa_2d == Viewport.MSAA_DISABLED
			or RenderingServer.get_current_rendering_method() == "gl_compatibility"):
		_soft_edges()
	if _marks:
		_marks.queue_redraw()


func _draw_border() -> void:
	var b := BORDER
	var col: Color = Color.WHITE if tex_border else colors["frame"]
	# shade the frame casts on the ground in front of it
	var lip_h := 22.0
	var sh := PackedVector2Array([project(-b, -b) + Vector2(0, lip_h), project(8.0 + b, -b) + Vector2(0, lip_h),
		project(8.0 + b + 0.1, -b - 0.3) + Vector2(0, lip_h), project(-b - 0.1, -b - 0.3) + Vector2(0, lip_h)])
	draw_colored_polygon(sh, Color(0, 0, 0, 0.28))
	# the four bands, one texture tile per square along them
	_border_quad(-b, -b, 0.0, 0.0, col)
	_border_quad(8.0, -b, 8.0 + b, 0.0, col)
	_border_quad(-b, 8.0, 0.0, 8.0 + b, col)
	_border_quad(8.0, 8.0, 8.0 + b, 8.0 + b, col)
	for i in 8:
		_border_quad(i, -b, i + 1, 0.0, col)
		_border_quad(i, 8.0, i + 1, 8.0 + b, col)
		_border_quad(-b, i, 0.0, i + 1, col)
		_border_quad(8.0, i, 8.0 + b, i + 1, col)
	# the front face of the frame: its thickness, darker
	var lip := PackedVector2Array([project(-b, -b), project(8.0 + b, -b),
		project(8.0 + b, -b) + Vector2(0, lip_h), project(-b, -b) + Vector2(0, lip_h)])
	if tex_border:
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(9, 0.12), Vector2(0, 0.12)])
		draw_colored_polygon(lip, Color(0.5, 0.45, 0.4), uvs, tex_border)
	else:
		draw_colored_polygon(lip, colors["frame_edge"])
	# side faces (seen because of the perspective)
	for side in [[-b, -1.0], [8.0 + b, 1.0]]:
		var u0: float = side[0]
		var face := PackedVector2Array([project(u0, -b), project(u0, 8.0 + b),
			project(u0, 8.0 + b) + Vector2(0, lip_h * scale_at(8.0)), project(u0, -b) + Vector2(0, lip_h)])
		draw_colored_polygon(face, Color(0.18, 0.13, 0.09, 0.9))


## Without edge smoothing (the browser's graphics have none; performance mode turns it off), the slanted edges
## of the board show steps. A thin smoothed line in the mean colour of both sides runs along each of them: the
## lines between the squares' columns, the frame's inner and outer edges and the side faces. Horizontal edges
## need none.
func _soft_edges() -> void:
	if _avg.is_empty():
		return
	var lt: Color = _avg["light"]
	var dk: Color = _avg["dark"]
	var bd: Color = _avg.get("border", colors["frame"])
	var gr: Color = _avg.get("ground", Color("5a7a30"))
	var face := Color(0.18, 0.13, 0.09)
	var width := 1.6
	for row in 8:
		for col in range(0, 9):
			var a := project(col, row)
			var b := project(col, row + 1)
			var c: Color
			if col == 0 or col == 8:
				var sq := square_at_cell(Vector2i(mini(col, 7), row))
				var light := ((sq & 7) + (sq >> 3)) % 2 == 1
				c = (lt if light else dk).lerp(bd, 0.5)
			else:
				c = lt.lerp(dk, 0.5)
			c.a = 0.8
			draw_line(a, b, c, width, true)
		# the edge of the soft inner shadow along the frame
		for col: float in [0.07, 8.0 - 0.07]:
			var sq := square_at_cell(Vector2i(0 if col < 4.0 else 7, row))
			var light := ((sq & 7) + (sq >> 3)) % 2 == 1
			var c := (lt if light else dk).darkened(0.12)
			c.a = 0.6
			draw_line(project(col, row), project(col, row + 1), c, width, true)
	var bw := BORDER
	var lip_h := 22.0
	for u0: float in [-bw, 8.0 + bw]:
		var top := project(u0, 8.0 + bw)
		var bottom := project(u0, -bw)
		# the frame's outer edge meets the ground; the side face (drawn over the band's outer strip) meets the band
		var g := face.lerp(gr, 0.5)
		g.a = 0.85
		draw_line(bottom, top, g, width, true)
		var e := bd.lerp(face, 0.5)
		e.a = 0.85
		draw_line(bottom + Vector2(0, lip_h), top + Vector2(0, lip_h * scale_at(8.0)), e, width, true)


func _border_quad(u0: float, v0: float, u1: float, v1: float, col: Color) -> void:
	var q := _quad(u0, v0, u1, v1)
	if tex_border:
		var uvs := PackedVector2Array([Vector2(u0, -v0), Vector2(u1, -v0), Vector2(u1, -v1), Vector2(u0, -v1)])
		draw_colored_polygon(q, col, uvs, tex_border)
	else:
		draw_colored_polygon(q, col)


## Ellipse drawn on the ground of a cell (follows the perspective).
func _ground_ellipse(c: Vector2i, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(project(c.x + 0.5 + cos(a) * radius, c.y + 0.5 + sin(a) * radius))
	return pts


# --- markers -------------------------------------------------------------------------------------------------------
# Drawn on their own layer (_marks) over the squares and under the creatures. A move is a small emerald lying on
# the square (dark rim: it reads on light and dark squares alike) over a soft glow; a capture is a pulsing ember
# ring under the target with four corner brackets; the selected piece gets gold corner brackets; check is a red
# glow under the king. They pop in from the selected piece outwards and breathe gently (still with "Réduire les
# animations").

const MOVE_RIM := Color(0.07, 0.24, 0.08, 0.92)
const MOVE_LO := Color(0.2, 0.68, 0.22)
const MOVE_HI := Color(0.72, 1.0, 0.5)
const EMBER := Color(1.0, 0.36, 0.18)
const EMBER_RIM := Color(0.28, 0.04, 0.02, 0.9)
const GOLD := Color(1.0, 0.85, 0.32)
const GOLD_RIM := Color(0.3, 0.18, 0.03, 0.85)


func _draw_marks() -> void:
	var ci := _marks.get_canvas_item()
	var still := Pal.reduced_motion()
	var t := 0.0 if still else _pulse
	if last_from >= 0:
		_marks.draw_colored_polygon(_square_quad(last_from), colors["last"])
		_marks.draw_colored_polygon(_square_quad(last_to), colors["last"])
	if check_sq >= 0:
		var c := cell_of(check_sq)
		var a := 0.75 + 0.25 * sin(t * 6.0)
		_radial(ci, c, 0.62, Color(1.0, 0.12, 0.05, 0.75 * a), Color(1.0, 0.12, 0.05, 0.0))
		_ring_ell(c, 0.47, 0.035, Color(1.0, 0.3, 0.2, 0.8 * a))
	if selected >= 0:
		var c := cell_of(selected)
		_marks.draw_colored_polygon(_square_quad(selected), Color(1.0, 0.86, 0.35, 0.22))
		_brackets(c, 0.04 + (0.0 if still else 0.015 * sin(t * 4.0)), 0.24, 0.05, GOLD, GOLD_RIM)
	var origin := Vector2(cell_of(selected)) if selected >= 0 else Vector2.ZERO
	for sq in targets:
		var c := cell_of(sq)
		var d := Vector2(c).distance_to(origin)
		var k := 1.0 if still else _pop(clampf((_sel_t - d * 0.035) / 0.22, 0.0, 1.0))
		if k <= 0.0:
			continue
		var on := sq == hover and input_enabled
		if sq in capture_targets:
			if on:
				_marks.draw_colored_polygon(_square_quad(sq), Color(1.0, 0.35, 0.2, 0.22))
			var p := 1.0 + 0.04 * sin(t * 5.0 + d)
			_radial(ci, c, 0.5 * k, Color(EMBER.r, EMBER.g, EMBER.b, 0.0), Color(EMBER.r, EMBER.g, EMBER.b, 0.35), 0.6)
			_ring_ell(c, 0.45 * p * k, 0.085, EMBER_RIM)
			_ring_ell(c, 0.435 * p * k, 0.055, EMBER)
			_brackets(c, 0.05 + (0.0 if still else 0.02 * (0.5 + 0.5 * sin(t * 5.0 + d))), 0.2 * k, 0.06, EMBER, EMBER_RIM)
		else:
			if on:
				_marks.draw_colored_polygon(_square_quad(sq), Color(0.45, 1.0, 0.35, 0.2))
			var b := (1.0 + 0.07 * sin(t * 4.0 + d * 0.9)) * k * (1.25 if on else 1.0)
			_radial(ci, c, 0.34 * b, Color(0.5, 1.0, 0.4, 0.4), Color(0.5, 1.0, 0.4, 0.0))
			_marks.draw_colored_polygon(_ell(c, 0.175 * b, Vector2(0, 0.014)), Color(0, 0, 0, 0.25))
			_marks.draw_colored_polygon(_ell(c, 0.17 * b), MOVE_RIM)
			_radial(ci, c, 0.135 * b, MOVE_HI, MOVE_LO, 0.0, Vector2(-0.03, 0.03) * b)
			_marks.draw_colored_polygon(_ell(c, 0.045 * b, Vector2(-0.05, 0.055) * b), Color(1, 1, 1, 0.75))


## 0 -> 1 with a small overshoot.
static func _pop(x: float) -> float:
	var c1 := 1.70158
	var y := x - 1.0
	return 1.0 + (c1 + 1.0) * y * y * y + c1 * y * y


## An ellipse lying on the ground around a cell's centre (+ offset, in squares).
func _ell(c: Vector2i, r: float, off := Vector2.ZERO, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(project(c.x + 0.5 + off.x + cos(a) * r, c.y + 0.5 + off.y + sin(a) * r))
	return pts


## A disc on the ground, `inner` colour at the centre (offset `hot`) fading to `outer` at the rim; `hole` > 0
## leaves the middle empty (a ring that fades inwards).
func _radial(ci: RID, c: Vector2i, r: float, inner: Color, outer: Color, hole := 0.0, hot := Vector2.ZERO) -> void:
	if r <= 0.0:
		return
	var n := 32
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	if hole <= 0.0:
		pts.append(project(c.x + 0.5 + hot.x, c.y + 0.5 + hot.y))
		cols.append(inner)
		for i in n:
			var a := TAU * i / n
			pts.append(project(c.x + 0.5 + cos(a) * r, c.y + 0.5 + sin(a) * r))
			cols.append(outer)
			idx.append_array([0, 1 + i, 1 + (i + 1) % n])
	else:
		for i in n:
			var a := TAU * i / n
			pts.append(project(c.x + 0.5 + cos(a) * r * hole, c.y + 0.5 + sin(a) * r * hole))
			pts.append(project(c.x + 0.5 + cos(a) * r, c.y + 0.5 + sin(a) * r))
			cols.append(inner)
			cols.append(outer)
			var j := (i + 1) % n
			idx.append_array([2 * i, 2 * i + 1, 2 * j + 1, 2 * i, 2 * j + 1, 2 * j])
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)


func _ring_ell(c: Vector2i, r: float, w: float, col: Color) -> void:
	if r <= w:
		return
	var o := _ell(c, r)
	var i := _ell(c, r - w)
	for k in o.size():
		var j := (k + 1) % o.size()
		_marks.draw_colored_polygon(PackedVector2Array([o[k], o[j], i[j], i[k]]), col)


## Four L-shaped corners just inside a square (inset, arm length, thickness in squares), with a dark rim.
func _brackets(c: Vector2i, inset: float, arm: float, th: float, col: Color, rim: Color) -> void:
	if arm <= 0.0:
		return
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		var x0 := c.x + corner.x + sx * inset
		var y0 := c.y + corner.y + sy * inset
		for pass_i in 2:
			var e := 0.02 if pass_i == 0 else 0.0
			var cl := rim if pass_i == 0 else col
			# the arm along the row, then the arm along the column
			_box(x0 - sx * e, y0 - sy * e, x0 + sx * (arm + e), y0 + sy * (th + e), cl)
			_box(x0 - sx * e, y0 - sy * e, x0 + sx * (th + e), y0 + sy * (arm + e), cl)


func _box(u0: float, v0: float, u1: float, v1: float, col: Color) -> void:
	_marks.draw_colored_polygon(_quad(minf(u0, u1), minf(v0, v1), maxf(u0, u1), maxf(v0, v1)), col)


func _dot(c: Vector2i, radius: float, col: Color) -> void:
	draw_colored_polygon(_ground_ellipse(c, radius), col)


func _ring(c: Vector2i, radius: float, width: float, col: Color) -> void:
	var outer := _ground_ellipse(c, radius)
	var inner := _ground_ellipse(c, radius - width)
	for i in outer.size():
		var j := (i + 1) % outer.size()
		draw_colored_polygon(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), col)


func _label(p: Vector2, text: String, s: float) -> void:
	var font := ThemeDB.fallback_font
	var size := int(28 * s)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string_outline(font, p + Vector2(-w / 2.0, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6,
		Color(0, 0, 0, 0.6))
	draw_string(font, p + Vector2(-w / 2.0, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colors["label"])
