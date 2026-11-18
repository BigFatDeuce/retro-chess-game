class_name UiTheme
extends RefCounted
## Builds the game's theme once (fonts, buttons, panels, fields, sliders, switches, scroll bars, tooltips) and
## installs it over Godot's default theme, so every Control, in any CanvasLayer or popup, wears it.
## Button variations: "Button" (wood), "LeafButton" (main action), "EmberButton" (danger), "GoldButton",
## "DarkButton" (secondary), "IconButton" (round), "ChipButton" (toggle pill).
## Label variations: "Title", "H2", "Dim", "Small", "Ink", "InkDim", "Hud". Panels: "PanelContainer" (walnut and
## wood), "Plate" (HUD), "Parchment", "Clear".

static var theme: Theme
static var display: Font  ## Fredoka Bold: titles, buttons
static var body: Font  ## Nunito ExtraBold: text, numbers
static var body_light: Font  ## Nunito SemiBold: long text


static func ensure() -> Theme:
	if theme == null:
		_build()
		ThemeDB.get_default_theme().merge_with(theme)
		ThemeDB.fallback_font = body
	return theme


static func _font(path: String, fallbacks: Array[Font] = []) -> Font:
	var f: FontFile = load(path)
	f.fallbacks = fallbacks
	return f


static func _build() -> void:
	body = _font("res://assets/fonts/Nunito-ExtraBold.ttf")
	body_light = _font("res://assets/fonts/Nunito-SemiBold.ttf")
	display = _font("res://assets/fonts/Fredoka-Bold.ttf", [body])
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = Pal.FS_BODY
	theme = t

	# --- labels
	_label(t, "Label", body, Pal.FS_BODY, Pal.TEXT)
	_label(t, "Title", display, Pal.FS_TITLE, Pal.CREAM, 16, Vector2(0, 7))
	_label(t, "H2", display, Pal.FS_H2, Pal.CREAM, 12, Vector2(0, 5))
	_label(t, "Dim", body_light, Pal.FS_SMALL, Pal.DIM)
	_label(t, "Small", body, Pal.FS_SMALL, Pal.TEXT)
	_label(t, "Ink", body, Pal.FS_BODY, Pal.INK)
	_label(t, "InkDim", body_light, Pal.FS_SMALL, Pal.with_alpha(Pal.INK, 0.75))
	_label(t, "Hud", body, Pal.FS_BODY, Pal.CREAM, 10)
	for v in ["Title", "H2", "Dim", "Small", "Ink", "InkDim", "Hud"]:
		t.set_type_variation(v, "Label")

	# --- buttons
	_button(t, "Button", Pal.WOOD_HI, Pal.WOOD, Pal.WOOD_LO)
	_button(t, "LeafButton", Pal.LEAF_HI, Pal.LEAF, Pal.LEAF_LO)
	_button(t, "EmberButton", Pal.EMBER_HI, Pal.EMBER, Pal.EMBER_LO)
	_button(t, "GoldButton", Pal.GOLD_HI, Pal.GOLD, Pal.GOLD_LO)
	_button(t, "DarkButton", Color("5a4030"), Color("3b2a1e"), Color("21160e"))
	_button(t, "IconButton", Color("5a4030"), Color("3b2a1e"), Color("21160e"), 999.0, 7.0, 0.0)
	_button(t, "ChipButton", Color("4a3526"), Color("33241a"), Color("1c130c"), 999.0, 6.0, Pal.S3)
	# a chip that is on: leaf green
	var on := PlankBox.button(Pal.LEAF_HI, Pal.LEAF, Pal.LEAF_LO, 999.0, 6.0).margins(Pal.S3, Pal.S1)
	t.set_stylebox("pressed", "ChipButton", on.with({"sink": 3.0, "lip": 3.0}).margins(Pal.S3, Pal.S1))
	t.set_stylebox("hover_pressed", "ChipButton", on.with({"sink": 3.0, "lip": 3.0, "fill_top": Pal.LEAF_HI.lightened(0.1)}).margins(Pal.S3, Pal.S1))
	t.set_font_size("font_size", "ChipButton", Pal.FS_SMALL + 2)
	for v in ["LeafButton", "EmberButton", "GoldButton", "DarkButton", "IconButton", "ChipButton"]:
		t.set_type_variation(v, "Button")

	# --- panels
	t.set_stylebox("panel", "PanelContainer", PlankBox.panel())
	t.set_stylebox("panel", "Panel", PlankBox.panel())
	t.set_stylebox("panel", "Plate", PlankBox.plate())
	t.set_stylebox("panel", "Parchment", PlankBox.parchment())
	t.set_stylebox("panel", "Clear", StyleBoxEmpty.new())
	for v in ["Plate", "Parchment", "Clear"]:
		t.set_type_variation(v, "PanelContainer")

	# --- text field (parchment)
	var field := PlankBox.new()
	field.fill_top = Pal.CREAM
	field.fill_bottom = Pal.PARCHMENT
	field.rim = 0.0
	field.radius = 18.0
	field.shadow = 0.0
	field.gloss = 0.0
	field.groove = 0.0
	field.bevel = 0.0
	field.margins(Pal.S3, Pal.S2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field.with({"glow": Pal.with_alpha(Pal.GOLD_HI, 0.7), "glow_size": 10.0, "only_glow": true}))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_font("font", "LineEdit", body)
	t.set_font_size("font_size", "LineEdit", 42)
	t.set_color("font_color", "LineEdit", Pal.INK)
	t.set_color("font_placeholder_color", "LineEdit", Pal.MUTED)
	t.set_color("caret_color", "LineEdit", Pal.INK)
	t.set_color("selection_color", "LineEdit", Pal.with_alpha(Pal.SKY, 0.45))
	t.set_constant("caret_width", "LineEdit", 4)

	# --- slider: dark groove, leaf fill, wooden knob
	var groove := PlankBox.new()
	groove.fill_top = Color("1a110b")
	groove.fill_bottom = Color("2c1e14")
	groove.rim = 0.0
	groove.radius = 12.0
	groove.outline_w = 4.0
	groove.shadow = 0.0
	groove.bevel = 0.0
	groove.groove = 0.0
	groove.content_margin_top = 11
	groove.content_margin_bottom = 11
	t.set_stylebox("slider", "HSlider", groove)
	var fill := groove.with({"fill_top": Pal.LEAF_HI, "fill_bottom": Pal.LEAF, "gloss": 0.25})
	fill.content_margin_top = 11
	fill.content_margin_bottom = 11
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill.with({"fill_top": Pal.LEAF_HI.lightened(0.15)}))
	t.set_icon("grabber", "HSlider", knob(58, false))
	t.set_icon("grabber_highlight", "HSlider", knob(58, true))
	t.set_icon("grabber_disabled", "HSlider", knob(58, false))
	t.set_constant("center_grabber", "HSlider", 0)

	# --- switch
	t.set_icon("checked", "CheckButton", switch(true))
	t.set_icon("unchecked", "CheckButton", switch(false))
	t.set_icon("checked_disabled", "CheckButton", switch(true))
	t.set_icon("unchecked_disabled", "CheckButton", switch(false))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", PlankBox.new().with({"only_glow": true, "glow": Pal.with_alpha(Pal.GOLD_HI, 0.7), "glow_size": 10.0, "radius": 40.0}))

	# --- scroll bars: thin wooden grip
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 14
	track.content_margin_right = 14
	var grip := PlankBox.button(Pal.WOOD_HI, Pal.WOOD, Pal.WOOD_LO, 10.0, 0.0)
	grip.shadow = 0.0
	grip.outline_w = 3.0
	grip.gloss = 0.0
	grip.content_margin_left = 10
	grip.content_margin_right = 10
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grip)
		t.set_stylebox("grabber_highlight", bar, grip.with({"fill_top": Pal.WOOD_HI.lightened(0.15)}))
		t.set_stylebox("grabber_pressed", bar, grip.with({"fill_top": Pal.GOLD_HI}))

	# --- progress bar
	var pb_bg := groove.duplicate()
	pb_bg.content_margin_top = 0
	pb_bg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := groove.with({"fill_top": Pal.GOLD_HI, "fill_bottom": Pal.GOLD_LO, "gloss": 0.3})
	pb_fill.content_margin_top = 0
	pb_fill.content_margin_bottom = 0
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))

	# --- tooltips
	var tip := PlankBox.parchment()
	tip.rim = 0.0
	tip.margins(Pal.S2, Pal.S1)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", body)
	t.set_font_size("font_size", "TooltipLabel", Pal.FS_TINY + 2)
	t.set_color("font_color", "TooltipLabel", Pal.INK)


static func _label(t: Theme, type: String, font: Font, size: int, col: Color, outline := 0, shadow := Vector2.ZERO) -> void:
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, col)
	t.set_color("font_outline_color", type, Pal.OUTLINE)
	t.set_constant("outline_size", type, outline)
	if shadow != Vector2.ZERO:
		t.set_color("font_shadow_color", type, Pal.with_alpha(Pal.OUTLINE, 0.55))
		t.set_constant("shadow_offset_x", type, int(shadow.x))
		t.set_constant("shadow_offset_y", type, int(shadow.y))
		t.set_constant("shadow_outline_size", type, outline)


static func _button(t: Theme, type: String, top: Color, bottom: Color, edge: Color, rad := 26.0, lip := 9.0, pad := float(Pal.S4)) -> void:
	var n := PlankBox.button(top, bottom, edge, rad, lip).margins(pad, Pal.S2)
	var h := n.with({"fill_top": top.lightened(0.14), "fill_bottom": bottom.lightened(0.1), "gloss": 0.32}).margins(pad, Pal.S2)
	var p := n.with({"sink": lip - 2.0, "lip": 2.0, "shadow": 0.2, "fill_top": bottom, "fill_bottom": top}).margins(pad, Pal.S2)
	p.content_margin_top += lip - 2.0
	var d := n.with({"fill_top": Pal.STONE_HI, "fill_bottom": Pal.STONE, "lip_top": Pal.STONE_LO, "gloss": 0.05, "shadow": 0.2}).margins(pad, Pal.S2)
	var f := n.with({"only_glow": true, "glow": Pal.with_alpha(Pal.GOLD_HI, 0.85), "glow_size": 12.0})
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, f)
	t.set_font("font", type, display)
	t.set_font_size("font_size", type, Pal.FS_BUTTON)
	t.set_color("font_color", type, Pal.CREAM)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_pressed_color", type, Pal.CREAM)
	t.set_color("font_hover_pressed_color", type, Pal.CREAM)
	t.set_color("font_focus_color", type, Color.WHITE)
	t.set_color("font_disabled_color", type, Color("d8d4c8"))
	t.set_color("font_outline_color", type, Pal.OUTLINE)
	t.set_constant("outline_size", type, 11)
	t.set_constant("h_separation", type, Pal.S2)
	t.set_constant("icon_max_width", type, 72)


# --- small drawn textures -------------------------------------------------------------------------------------------

## Wooden slider knob with a dark outline.
static func knob(px: int, hot: bool) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	var r := px * 0.5 - 1.0
	var top := Pal.GOLD_HI if hot else Pal.WOOD_HI
	var bot := Pal.GOLD_LO if hot else Pal.WOOD_LO
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var a := clampf(r - d, 0.0, 1.0)
			var inner := clampf(r - 5.0 - d, 0.0, 1.0)
			var col := Pal.OUTLINE.lerp(top.lerp(bot, clampf((p.y - (c.y - r)) / (2.0 * r), 0.0, 1.0)), inner)
			# a light spot at the top left
			var spot := clampf(1.0 - p.distance_to(c - Vector2(r, r) * 0.32) / (r * 0.35), 0.0, 1.0)
			col = col.lerp(Color(1, 1, 1), spot * 0.45 * inner)
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## On/off switch: leaf green track with the knob right, or stone track with the knob left.
static func switch(on: bool) -> Texture2D:
	var w := 156
	var h := 82
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5 - 1.0
	var top := Pal.LEAF_HI if on else Pal.STONE
	var bot := Pal.LEAF_LO if on else Pal.STONE_LO
	var kx := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, h * 0.5, w - h * 0.5)
			var d := p.distance_to(Vector2(cx, h * 0.5))
			var a := clampf(r - d, 0.0, 1.0)
			var inner := clampf(r - 4.5 - d, 0.0, 1.0)
			var col := Pal.OUTLINE.lerp(top.lerp(bot, float(y) / h), inner)
			var dk := p.distance_to(Vector2(kx, h * 0.5))
			var kr := r - 8.0
			var k_out := clampf(kr + 3.5 - dk, 0.0, 1.0)
			var k_in := clampf(kr - dk, 0.0, 1.0)
			col = col.lerp(Pal.OUTLINE, k_out)
			col = col.lerp(Pal.CREAM.lerp(Pal.PARCHMENT_LO, clampf((p.y - (h * 0.5 - kr)) / (2.0 * kr), 0.0, 1.0)), k_in)
			col.a = maxf(a, k_out)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
