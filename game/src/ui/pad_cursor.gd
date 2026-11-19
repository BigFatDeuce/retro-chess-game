extends Node
## Playing with a gamepad: the left stick moves the mouse cursor (the glove), A clicks where it points, Start opens
## the pause like Esc. The d-pad (not the stick) moves the focus between buttons; B goes back (ui_cancel). Once the
## stick has moved the cursor, A clicks under it instead of pressing the focused button, until the d-pad is used.

const DEADZONE := 0.18
const SPEED := 1500.0  ## layout px per second, stick fully pushed (the layout is 2560 px wide)

var _pos := Vector2.ZERO
var _active := false
var _idle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	for d in Input.get_connected_joypads():
		v += Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
	var m := minf(v.length(), 1.0)
	if m < DEADZONE:
		_idle += delta
		return
	var vp := get_viewport()
	if not _active or _idle > 0.5:
		_pos = vp.get_mouse_position()  # the mouse may have moved meanwhile
	_active = true
	_idle = 0.0
	var k := (m - DEADZONE) / (1.0 - DEADZONE)
	var r := vp.get_visible_rect()
	_pos = (_pos + v.normalized() * SPEED * k * k * delta).clamp(r.position, r.end - Vector2.ONE)
	vp.warp_mouse(_pos)
	var e := InputEventMouseMotion.new()  # where warping does nothing (browser), the game still sees the motion
	e.position = _to_window(_pos)
	e.global_position = e.position
	Input.parse_input_event(e)


func _input(event: InputEvent) -> void:
	var jm := event as InputEventJoypadMotion
	if jm and jm.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		# the stick is the cursor's: it must not also move the focus (ui_left, ui_right…), which picks buttons
		# on its way (on the champions' path, each one loads its board)
		get_viewport().set_input_as_handled()
		return
	var b := event as InputEventJoypadButton
	if b == null:
		return
	if b.button_index == JOY_BUTTON_START and b.pressed:
		get_viewport().set_input_as_handled()
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = true
		Input.parse_input_event(k)
		var up := k.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
	elif b.button_index == JOY_BUTTON_A and _active:
		get_viewport().set_input_as_handled()
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = b.pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if b.pressed else 0
		e.position = _to_window(get_viewport().get_mouse_position() if _idle > 0.5 else _pos)  # the mouse may have moved
		e.global_position = e.position
		Input.parse_input_event(e)
	elif b.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		_active = false  # back to the buttons' focus


## Layout (viewport) px -> window px, as input events carry them.
func _to_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p
