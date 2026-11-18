class_name FxButton
extends Button
## The game's button: a theme variation of the planks (UiTheme), an optional drawn icon (Icon), a lift on hover,
## a squash on press, a gold glow when focused by keyboard or gamepad, its sounds, and an optional slow pulse
## for the action the screen leads to. Animations shrink to nothing with "Réduire les animations".

var icon_name := ""
var icon_px := 56.0
var icon_color := Pal.CREAM
var icon_line := Pal.OUTLINE
var pulse := false:
	set(v):
		pulse = v
		_pulse_t = 0.0
var hover_sound := true

var _tween: Tween
var _pulse_t := 0.0
var _placeholder: ImageTexture
var _held: Control  ## see hold()


## text, variation ("Button", "LeafButton", "EmberButton", "GoldButton", "DarkButton", "IconButton",
## "ChipButton"), icon name (Icon.NAMES) and the minimum size.
static func make(p_text: String, variation := "Button", p_icon := "", min_size := Vector2.ZERO) -> FxButton:
	var b := FxButton.new()
	b.text = p_text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	if p_icon != "":
		b.set_icon_name(p_icon)
	return b


func set_icon_name(n: String, px := -1.0) -> void:
	icon_name = n
	if px > 0.0:
		icon_px = px
	elif text == "":
		icon_px = 62.0
	# an empty image keeps the icon's room in the button's layout; the icon itself is drawn in _draw()
	var side := int(icon_px)
	_placeholder = ImageTexture.create_from_image(Image.create(side, side, false, Image.FORMAT_RGBA8))
	icon = _placeholder
	icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if text != "" else HORIZONTAL_ALIGNMENT_CENTER
	queue_redraw()


## Makes the button hold any content (a portrait and texts...), sized to it, pressed down with it. Methods,
## not lambdas: a fit still pending when the screen is replaced is dropped with the button.
func hold(content: Control) -> void:
	_held = content
	add_child(content)
	content.minimum_size_changed.connect(_fit_held)
	resized.connect(_fit_held)
	button_down.connect(func() -> void:
		if is_instance_valid(_held):
			_held.position.y += 5)
	button_up.connect(_fit_held)
	_fit_held.call_deferred()


func _fit_held() -> void:
	if not is_instance_valid(_held):
		return
	var sb := get_theme_stylebox("normal")
	var pad := Vector2(sb.content_margin_left + sb.content_margin_right, sb.content_margin_top + sb.content_margin_bottom)
	custom_minimum_size = _held.get_combined_minimum_size() + pad
	_held.position = Vector2(sb.content_margin_left, sb.content_margin_top)
	_held.size = size - pad


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(_on_enter.bind(false))
	focus_exited.connect(_on_exit)
	button_down.connect(func() -> void: _scale_to(0.96, 0.06))
	button_up.connect(func() -> void: _scale_to(1.04 if is_hovered() else 1.0, 0.12))
	pressed.connect(func() -> void: Audio.play("ui.click"))
	set_process(pulse)


func _on_enter(sound := true) -> void:
	if disabled:
		return
	_scale_to(1.04, 0.1)
	if sound and hover_sound:
		Audio.play("ui.hover", -16.0)


func _on_exit() -> void:
	if not has_focus() or not is_hovered():
		_scale_to(1.0, 0.14)


func _scale_to(s: float, t: float) -> void:
	if _tween:
		_tween.kill()
	if Pal.reduced_motion():
		scale = Vector2.ONE
		return
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * s, t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(pulse and is_visible_in_tree())


func _process(delta: float) -> void:
	if not pulse or Pal.reduced_motion():
		self_modulate = Color.WHITE
		return
	_pulse_t += delta
	var k := 0.5 + 0.5 * sin(_pulse_t * 3.0)
	self_modulate = Color(1, 1, 1).lerp(Color(1.18, 1.14, 1.0), k * 0.6)


func _draw() -> void:
	if icon_name == "":
		return
	var st := "normal"
	if disabled:
		st = "disabled"
	elif button_pressed or (is_pressed() and toggle_mode) or get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED:
		st = "pressed"
	elif get_draw_mode() == DRAW_HOVER:
		st = "hover"
	var sb := get_theme_stylebox(st)
	var content := Rect2(sb.content_margin_left, sb.content_margin_top,
		size.x - sb.content_margin_left - sb.content_margin_right,
		size.y - sb.content_margin_top - sb.content_margin_bottom)
	var r: Rect2
	if text == "":
		r = Rect2(content.get_center() - Vector2(icon_px, icon_px) * 0.5, Vector2(icon_px, icon_px))
	else:
		r = Rect2(Vector2(content.position.x, content.get_center().y - icon_px * 0.5), Vector2(icon_px, icon_px))
	var col := icon_color if not disabled else Color("d8d4c8")
	Icon.paint(self, icon_name, r, col, icon_line)
