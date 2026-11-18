class_name Ui
extends RefCounted
## Building blocks shared by the screens: labels, gold titles, panels, separators, dialogs, toasts and the
## entrance animations (all shortened by "Réduire les animations").

const TITLE_SHADER := preload("res://src/ui/kit/title_gradient.gdshader")


static func label(text: String, variation := "", size := 0, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if col.a > 0.0:
		l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Wrapped text of a given width.
static func para(text: String, width: float, variation := "", size := 0, col := Color(0, 0, 0, 0)) -> Label:
	var l := label(text, variation, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


## A title in the logo's gold: white fill turned into a gradient by a shader, dark outline, shadow.
static func title(text: String, size := Pal.FS_TITLE, top := Color(1.0, 0.9, 0.42), bottom := Color(0.97, 0.56, 0.1)) -> Label:
	var l := label(text, "Title", size, Color.WHITE)
	l.add_theme_constant_override("outline_size", maxi(10, size / 5))
	l.add_theme_constant_override("shadow_outline_size", maxi(10, size / 5))
	var m := ShaderMaterial.new()
	m.shader = TITLE_SHADER
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("bottom_color", bottom)
	l.material = m
	var fit := func() -> void:
		m.set_shader_parameter("y_top", l.size.y * 0.22)
		m.set_shader_parameter("y_bottom", l.size.y * 0.82)
		m.set_shader_parameter("width", l.size.x)
	l.resized.connect(fit)
	return l


## Sweeps a light band across a title (victory, unlocks).
static func shine(l: Label, every := 3.5) -> void:
	var m := l.material as ShaderMaterial
	if m == null or Pal.reduced_motion():
		return
	var tw := l.create_tween().set_loops()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("shine", v), 0.0, 1.0, 0.9)
	tw.tween_callback(func() -> void: m.set_shader_parameter("shine", -1.0))
	tw.tween_interval(every)


static func panel(variation := "", margin := -1) -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if margin >= 0:
		var sb: StyleBox = p.get_theme_stylebox("panel").duplicate()
		sb.content_margin_left = margin
		sb.content_margin_right = margin
		sb.content_margin_top = margin
		sb.content_margin_bottom = margin
		p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep := Pal.S3, align := BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.alignment = align
	return v


static func hbox(sep := Pal.S3, align := BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = align
	return h


static func spacer(w := 0.0, h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


## Anchors a control at a point of its parent (0..1) and lets it grow around that point.
static func anchor_at(c: Control, at: Vector2, grow := Vector2(0.5, 0.5)) -> Control:
	c.anchor_left = at.x
	c.anchor_right = at.x
	c.anchor_top = at.y
	c.anchor_bottom = at.y
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if grow.x == 0.5 else (Control.GROW_DIRECTION_END if grow.x == 0.0 else Control.GROW_DIRECTION_BEGIN)
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if grow.y == 0.5 else (Control.GROW_DIRECTION_END if grow.y == 0.0 else Control.GROW_DIRECTION_BEGIN)
	return c


## A gilded rule with a diamond in the middle.
static func separator(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 22)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var y := c.size.y * 0.5
		var w := c.size.x
		var pts := PackedVector2Array([Vector2(0, y), Vector2(w * 0.5 - 18, y)])
		c.draw_polyline_colors(pts, PackedColorArray([Pal.with_alpha(Pal.GOLD, 0.0), Pal.with_alpha(Pal.GOLD, 0.8)]), 3.0, true)
		pts = PackedVector2Array([Vector2(w * 0.5 + 18, y), Vector2(w, y)])
		c.draw_polyline_colors(pts, PackedColorArray([Pal.with_alpha(Pal.GOLD, 0.8), Pal.with_alpha(Pal.GOLD, 0.0)]), 3.0, true)
		var d := PackedVector2Array([Vector2(w * 0.5, y - 10), Vector2(w * 0.5 + 12, y), Vector2(w * 0.5, y + 10), Vector2(w * 0.5 - 12, y)])
		var o := PackedVector2Array([Vector2(w * 0.5, y - 14), Vector2(w * 0.5 + 16, y), Vector2(w * 0.5, y + 14), Vector2(w * 0.5 - 16, y)])
		c.draw_colored_polygon(o, Pal.OUTLINE)
		c.draw_colored_polygon(d, Pal.GOLD))
	return c


## A soft dark border around the screen (menus over the living board).
static func vignette(strength := 0.65) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.03, 0.02, 0.01, strength))
	g.add_point(0.55, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return full_rect(tr) as TextureRect


static func veil(alpha := 0.55, stop_mouse := true) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(Pal.VEIL, alpha)
	c.mouse_filter = Control.MOUSE_FILTER_STOP if stop_mouse else Control.MOUSE_FILTER_IGNORE
	return full_rect(c) as ColorRect


# --- motion ---------------------------------------------------------------------------------------------------------

static func fade_in(c: CanvasItem, delay := 0.0, t := Pal.T_MED) -> Tween:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(Pal.dur(delay))
	tw.tween_property(c, "modulate:a", 1.0, Pal.dur(t))
	return tw


## Scales a control up from a little smaller while it fades in (dialogs, cards).
static func pop_in(c: Control, delay := 0.0, from := 0.86) -> Tween:
	c.modulate.a = 0.0
	if Pal.reduced_motion():
		c.modulate.a = 1.0
		return null
	var go := func() -> void:
		if not is_instance_valid(c):
			return
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2.ONE * from
	c.create_tween().tween_callback(go)
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, Pal.T_MED).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, Pal.T_SLOW).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


## Slides a control in from an offset while it fades in.
static func slide_in(c: Control, offset: Vector2, delay := 0.0, t := Pal.T_SLOW) -> void:
	c.modulate.a = 0.0
	if Pal.reduced_motion():
		c.modulate.a = 1.0
		return
	var go := func() -> void:
		if not is_instance_valid(c):
			return
		var to := c.position
		c.position = to + offset
		var tw := c.create_tween().set_parallel()
		tw.tween_property(c, "modulate:a", 1.0, Pal.T_MED).set_delay(delay)
		tw.tween_property(c, "position", to, t).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# containers place their children at the end of the frame: start from the final place (a tween callback
	# runs on the next frame and dies with the control)
	c.create_tween().tween_callback(go)


## Each child appears a little after the previous one.
static func stagger(children: Array, step := 0.05, delay := 0.0) -> void:
	var i := 0
	for c in children:
		if c is Control:
			pop_in(c, delay + step * i, 0.92)
			i += 1


# --- dialogs ----------------------------------------------------------------------------------------------------------

## A modal question over everything: title, text, a cancel button (focused) and the action. `on_yes` runs
## when the action is chosen; Esc or a click on the veil cancels.
static func confirm(host: Node, p_title: String, text: String, yes_text: String, on_yes: Callable,
		yes_variation := "EmberButton", yes_icon := "", no_text := "Annuler") -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var root := full_rect(Control.new())
	root.theme = UiTheme.ensure()
	layer.add_child(root)
	var v := veil(0.6)
	root.add_child(v)
	var p := panel()
	root.add_child(p)
	anchor_at(p, Vector2(0.5, 0.5))
	var box := vbox(Pal.S4, BoxContainer.ALIGNMENT_CENTER)
	box.custom_minimum_size = Vector2(1000, 0)
	p.add_child(box)
	var t := title(p_title, Pal.FS_H2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var body := para(text, 1000, "", Pal.FS_BODY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	box.add_child(spacer(0, Pal.S1))
	var row := hbox(Pal.S4, BoxContainer.ALIGNMENT_CENTER)
	box.add_child(row)
	var no := FxButton.make(no_text, "DarkButton", "close", Vector2(380, 108))
	var yes := FxButton.make(yes_text, yes_variation, yes_icon, Vector2(420, 108))
	row.add_child(no)
	row.add_child(yes)
	var close := func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	no.pressed.connect(close)
	yes.pressed.connect(func() -> void:
		close.call()
		on_yes.call())
	v.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close.call())
	root.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			close.call())
	var esc := Node.new()
	esc.set_script(_EscCatcher)
	esc.set("on_cancel", close)
	layer.add_child(esc)
	pop_in(p)
	no.grab_focus.call_deferred()
	return root


## A short message at the top of the screen.
static func toast(host: Control, text: String, icon_name := "", hold := 1.6, col := Pal.CREAM) -> void:
	for c in host.get_children():
		if c.has_meta("toast"):
			c.queue_free()
	var p := panel("Plate")
	p.set_meta("toast", true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(p)
	anchor_at(p, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	p.offset_top = 150
	var h := hbox(Pal.S2, BoxContainer.ALIGNMENT_CENTER)
	p.add_child(h)
	if icon_name != "":
		h.add_child(Icon.make(icon_name, 48, Pal.GOLD_HI))
	h.add_child(label(text, "", Pal.FS_BODY, col))
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, Pal.dur(0.18))
	tw.tween_interval(hold)
	tw.tween_property(p, "modulate:a", 0.0, Pal.dur(0.4))
	tw.tween_callback(p.queue_free)


## Helper node: Esc / B closes the dialog it belongs to.
const _EscCatcher := preload("res://src/ui/kit/esc_catcher.gd")


## The three sets of chess pieces as buttons (each with its two kings), the chosen one held down; picking one sets
## Settings "piece_set" and then calls `on_pick` (the set's key). `king_px`: the kings' height; without `names`,
## the kings alone (the names in the tooltips).
static func piece_set_picker(king_px := 64.0, on_pick := Callable(), names := true) -> HBoxContainer:
	var h := hbox(Pal.S2)
	var g := ButtonGroup.new()
	for s in [["", "Créatures"], ["classic", "Bonta / Brâkmar"], ["staunton", "Classiques"]]:
		var key: String = s[0]
		var b := FxButton.make("", "ChipButton")
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = String(Settings.get_value("piece_set")) == key
		b.tooltip_text = Lang.t(s[1])
		var v := vbox(Pal.S1, BoxContainer.ALIGNMENT_CENTER)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kings := hbox(0, BoxContainer.ALIGNMENT_CENTER)
		kings.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["white", "black"]:
			var t := TextureRect.new()
			t.texture = _king_texture(key, side)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Vector2(king_px * 0.62, king_px)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			kings.add_child(t)
		v.add_child(kings)
		if names:
			var l := label(s[1], "", Pal.FS_SMALL - 6)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		b.hold(v)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			Settings.set_value("piece_set", key)
			if on_pick.is_valid():
				on_pick.call(key))
		h.add_child(b)
	return h


## A set's king, for the picker: the creature's portrait, or the still piece's own picture.
static func _king_texture(set_key: String, side: String) -> Texture2D:
	var paths: Array = ["res://assets/gen/portraits/%s_king.png" % side]
	if set_key != "":
		paths = ["res://assets/gen/%s_1x/%s_king_0.png" % [set_key, side], "res://assets/gen/%s/%s_king_0.png" % [set_key, side]]
	for p in paths:
		if ResourceLoader.exists(p):
			return load(p)
	return null
