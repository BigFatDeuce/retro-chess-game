class_name BoardCamera
extends Camera2D
## A camera that can be moved a little around the board: drag the scenery (left button outside the board,
## middle button anywhere, one finger outside the board) to pan, wheel or pinch to zoom in, right button held and
## dragged up (or Page Up / Page Down) to tilt the board as if standing up to look down on it, double click or
## Home to come back. The pan is held within a small margin so the view never leaves the scene.

const HOME := Vector2(1280, 720)  ## centre of the layout (2560 x 1440)
const MAX_ZOOM := 1.45
const MARGIN := Vector2(170, 120)  ## how far past the layout edges the view may go (layout px)
const DRAG_START := 12.0  ## px a press must travel before it pans (so a click stays a click)
const SMOOTH := 12.0
const TILT_DRAG := 420.0  ## px of vertical drag for the full tilt
const TILT_ZOOM := 0.22  ## full tilt: the view steps back a little (zoom / 1.22) so the deeper board still fits
const TILT_LIFT := 140.0  ## full tilt: the view rises with the board's far edge (layout px)

var board: BoardView
var target_zoom := 1.0
var target_pos := HOME
var target_tilt := 0.0  ## 0..1, see BoardView.set_tilt
var frame_offset := Vector2.ZERO  ## shifts the whole view (the menus set the board beside their panels)

var _drag := false  ## a pan gesture is held
var _tilting := false  ## the right button is held: vertical moves tilt the board
var _drag_moved := false
var _press_at := Vector2.ZERO
var _touches: Dictionary = {}  ## index -> screen position
var _pinch_dist := 0.0


func _ready() -> void:
	position = HOME
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	make_current()


func reset() -> void:
	target_zoom = 1.0
	target_pos = HOME
	target_tilt = 0.0
	frame_offset = Vector2.ZERO


func _process(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTH * delta)
	var t := 0.0
	if board:
		t = lerpf(board.tilt, target_tilt, k)
		if absf(t - target_tilt) < 0.002:
			t = target_tilt
		board.set_tilt(t)
		t = board.tilt
	var want := target_zoom / (1.0 + TILT_ZOOM * t)
	var z := lerpf(zoom.x, want, k) if absf(zoom.x - want) > 0.0005 else want
	zoom = Vector2(z, z)
	target_pos = _clamped(target_pos, target_zoom)
	position = position.lerp(target_pos, k)
	offset = offset.lerp(frame_offset + Vector2(0, -TILT_LIFT * t), 1.0 - exp(-5.0 * delta))


## The view centre that keeps the visible area within the layout plus MARGIN at zoom z.
func _clamped(p: Vector2, z: float) -> Vector2:
	var half := HOME / z
	var lo := half - MARGIN
	var hi := HOME * 2.0 - half + MARGIN
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))


func _screen_to_layout_scale() -> float:
	## event px (viewport coordinates, already in the layout space with the canvas_items stretch) -> world px
	return 1.0 / zoom.x


func _on_board(screen_pos: Vector2) -> bool:
	if board == null:
		return false
	var local := board.get_global_transform_with_canvas().affine_inverse() * screen_pos
	return board.square_at_point(local) >= 0


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var nz := clampf(target_zoom * factor, 1.0, MAX_ZOOM)
	# keep the point under the cursor in place
	var vp := get_viewport()
	var world := vp.get_canvas_transform().affine_inverse() * screen_pos
	var off := world - target_pos
	target_pos = world - off * (target_zoom / nz)
	target_zoom = nz


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(1.08, mb.position)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / 1.08, mb.position)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and mb.double_click:
					reset()
					get_viewport().set_input_as_handled()
				_tilting = mb.pressed
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed and mb.double_click and not _on_board(mb.position):
					reset()
					get_viewport().set_input_as_handled()
				elif mb.pressed and (mb.button_index != MOUSE_BUTTON_LEFT or not _on_board(mb.position)):
					_drag = true
					_drag_moved = false
					_press_at = mb.position
				elif not mb.pressed:
					_drag = false
	elif event is InputEventMouseMotion and _tilting:
		target_tilt = clampf(target_tilt - (event as InputEventMouseMotion).relative.y / TILT_DRAG, 0.0, 1.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_press_at) > DRAG_START:
			_drag_moved = true
		if _drag_moved:
			target_pos = _clamped(target_pos - mm.relative * _screen_to_layout_scale(), target_zoom)
			position = target_pos
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_drag = not _on_board(st.position)
				_drag_moved = false
				_press_at = st.position
			elif _touches.size() == 2:
				_drag = false
				_pinch_dist = _pinch_span()
		else:
			_touches.erase(st.index)
			if _touches.is_empty():
				_drag = false
			if st.double_tap and not _on_board(st.position):
				reset()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		var before: Vector2 = _touches[sd.index]
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var span := _pinch_span()
			if _pinch_dist > 1.0:
				_zoom_at(span / _pinch_dist, _pinch_mid())
			_pinch_dist = span
			target_pos -= (sd.position - before) * 0.5 * _screen_to_layout_scale()
			get_viewport().set_input_as_handled()
		elif _drag:
			if sd.position.distance_to(_press_at) > DRAG_START:
				_drag_moved = true
			if _drag_moved:
				target_pos -= sd.relative * _screen_to_layout_scale()
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_HOME:
				reset()
			KEY_PAGEUP:
				target_tilt = minf(target_tilt + 0.25, 1.0)
			KEY_PAGEDOWN:
				target_tilt = maxf(target_tilt - 0.25, 0.0)
			KEY_KP_ADD, KEY_EQUAL:
				_zoom_at(1.1, get_viewport().get_visible_rect().size * 0.5)
			KEY_KP_SUBTRACT, KEY_MINUS:
				_zoom_at(1.0 / 1.1, get_viewport().get_visible_rect().size * 0.5)


func _pinch_span() -> float:
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1]) if v.size() >= 2 else 0.0


func _pinch_mid() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5 if v.size() >= 2 else Vector2.ZERO
