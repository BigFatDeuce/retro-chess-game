extends Node
## The mouse cursor: a cartoon glove (tools/build_cursor.py). It points by default, opens over a piece that can be
## taken, closes into a fist while a piece is held (the hand closing in a few frames), presses its finger while the
## button is held, and grabs the scenery while the view is dragged or tilted. Hardware cursor (no lag behind the
## mouse), its size following the window's height. Not on phones (no mouse).

const DIR := "res://assets/gen/cursor/"
const ORDER := ["point", "open", "grab1", "grab2", "fist"]  ## the hand closing, one step per frame of animation
const STEP := 0.045  ## s per frame of animation
const HEIGHT_K := 0.04  ## cursor size: 4 % of the window's height

var game: ChessGame  ## set by the game: what the hand is over

var _on := false
var _meta := {}
var _size := 0
var _shown := ""  ## the frame on screen
var _path: Array[String] = []  ## frames still to show before the wanted one
var _t := 0.0
var _cache := {}  ## "frame_size" -> Texture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_on = not OS.has_feature("mobile") and DisplayServer.get_name() != "headless"
	if not _on:
		set_process(false)
		return
	_meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "cursor.json"))
	get_tree().root.size_changed.connect(_resize)
	Settings.changed.connect(func(k: String) -> void:
		if k == "cursor_size":
			_resize())
	_resize()


func _resize() -> void:
	var want := float(DisplayServer.window_get_size().y) * HEIGHT_K * float(Settings.get_value("cursor_size"))
	var best := 48
	for s in _meta["sizes"]:
		if absf(float(s) - want) < absf(float(best) - want):
			best = int(s)
	if best != _size:
		_size = best
		var f := _shown if _shown != "" else "point"
		_shown = ""
		_show(f)


func _process(delta: float) -> void:
	var want := _wanted()
	var goal: String = _path.back() if not _path.is_empty() else _shown
	if want != goal:
		_path = _route(_shown, want)
		_t = STEP  # the first step at once
	if _path.is_empty():
		return
	_t += delta
	if _t >= STEP:
		_t = 0.0
		_show(_path.pop_front())


## The frames from one hand to another: through the hand closing (or opening) step by step; the pressed finger
## comes and goes at once.
func _route(from: String, to: String) -> Array[String]:
	var r: Array[String] = []
	var a := ORDER.find(from)
	var b := ORDER.find(to)
	if a < 0 or b < 0:
		r.append(to)
		return r
	var d := 1 if b > a else -1
	var i := a
	while i != b:
		i += d
		r.append(ORDER[i])
	return r


func _wanted() -> String:
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if game and is_instance_valid(game) and game.is_inside_tree() and game.is_visible_in_tree():
		var cam := game.camera
		if cam and (cam._tilting or (cam._drag and cam._drag_moved)):
			return "fist"
		if not _over_ui():
			var b := game.board
			if b.input_enabled and b.selected >= 0:
				return "fist"
			if b.input_enabled and b.hover >= 0 and not game.busy and not game.over and game.is_human_turn():
				var p := game.pos.board[b.hover]
				if p != ChessPosition.EMPTY and ChessPosition.piece_color(p) == game.pos.side:
					return "press" if held else "open"
	return "press" if held else "point"


## The mouse is over a panel or a button (menus, pause, the game's own buttons): the board below does not count.
func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP


func _show(frame: String) -> void:
	if frame == _shown or _size == 0:
		return
	_shown = frame
	var key := "%s_%d" % [frame, _size]
	if not _cache.has(key):
		_cache[key] = load(DIR + key + ".png")
	var tex: Texture2D = _cache[key]
	var hot: Array = _meta["hotspot"][frame]
	var at := Vector2(float(hot[0]), float(hot[1])) * _size
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP,
			Input.CURSOR_MOVE]:
		Input.set_custom_mouse_cursor(tex, shape, at)


func _exit_tree() -> void:
	if _on:
		Input.set_custom_mouse_cursor(null)
	_cache.clear()
