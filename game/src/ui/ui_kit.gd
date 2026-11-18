class_name UiKit
extends RefCounted
## The game's interface look, shared by the menus: dark ink panels with a gold edge, ivory text, rounded buttons.
## Everything is built in code (no theme resource to keep in sync).

const GOLD := Color("e8c872")
const INK := Color(0.07, 0.08, 0.07, 0.86)
const TEXT := Color("f2ead8")
const DIM := Color("a8a08c")
const GREEN := Color("8fd16a")


static func label(text: String, size: int, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, border: Color, radius := 14, width := 3, margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	if margin > 0:
		sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func style_button(b: BaseButton, size := 40) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", box(Color(0.14, 0.13, 0.11, 0.92), Color(GOLD.r, GOLD.g, GOLD.b, 0.45)))
	b.add_theme_stylebox_override("hover", box(Color(0.24, 0.2, 0.13, 0.96), GOLD))
	b.add_theme_stylebox_override("pressed", box(Color(0.32, 0.26, 0.14, 0.98), GOLD))
	b.add_theme_stylebox_override("hover_pressed", box(Color(0.32, 0.26, 0.14, 0.98), GOLD))
	b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.1, 0.09, 0.7), Color(0.4, 0.38, 0.32, 0.4)))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(GOLD.r, GOLD.g, GOLD.b, 0.8)))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.42))


static func button(text: String, size := 40, min_size := Vector2(440, 92)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	style_button(b, size)
	return b


## A gold-edged ink panel holding a vertical box; returns the box.
static func card(parent: Control, title := "", margin := 48) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", box(INK, Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 22, 3, margin))
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	pc.add_child(v)
	if title != "":
		var t := label(title, 60, GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	return v


static func slider(value: float, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(520, 48)
	# the track's thickness is its style box's content margin (a margin of 0 draws nothing)
	var track := box(Color(0.24, 0.22, 0.18), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 8, 1)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	s.add_theme_stylebox_override("slider", track)
	var fill := box(GOLD.darkened(0.15), Color(0, 0, 0, 0), 8, 0)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := box(GOLD, Color(0, 0, 0, 0), 8, 0)
	fill_hi.content_margin_top = 7
	fill_hi.content_margin_bottom = 7
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	var g := _knob(GOLD)
	s.add_theme_icon_override("grabber", g)
	s.add_theme_icon_override("grabber_highlight", _knob(Color("fff1c4")))
	return s


## An on/off switch at the interface's size (the default one is drawn for a 1x desktop theme).
static func toggle(on: bool) -> CheckButton:
	var cb := CheckButton.new()
	cb.button_pressed = on
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_icon_override("checked", _switch(true))
	cb.add_theme_icon_override("unchecked", _switch(false))
	cb.add_theme_icon_override("checked_disabled", _switch(true))
	cb.add_theme_icon_override("unchecked_disabled", _switch(false))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		cb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return cb


static func _switch(on: bool) -> Texture2D:
	var w := 112
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h / 2.0
	var track := GOLD.darkened(0.1) if on else Color(0.3, 0.28, 0.24)
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, r, w - r)
			var d := px.distance_to(Vector2(cx, r))
			var a := clampf(r - d, 0.0, 1.0)
			var col := Color(track.r, track.g, track.b, a)
			var dk := px.distance_to(Vector2(knob_x, r))
			var ka := clampf(r - 6.0 - dk, 0.0, 1.0)
			col = col.lerp(Color("fff6dc"), ka)
			col.a = maxf(a, ka)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _knob(c: Color) -> Texture2D:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 40:
			var d := Vector2(x - 19.5, y - 19.5).length()
			var a := clampf(18.0 - d, 0.0, 1.0)
			var edge := clampf(d - 14.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r * (1.0 - edge * 0.5), c.g * (1.0 - edge * 0.5), c.b * (1.0 - edge * 0.5), a))
	return ImageTexture.create_from_image(img)


## A creature of the local library as a portrait: its HD portrait, else the first idle frame of a piece
## ("white_king") or of an ambient critter ("tofu") cut out of its atlas page.
static func avatar_texture(id: String) -> Texture2D:
	# HD portrait rendered from the vector drawing (tools/build_portraits.py), else the atlas frame
	var hd := "res://assets/gen/portraits/%s.png" % id
	var piece := id.begins_with("white_") or id.begins_with("black_")
	if ResourceLoader.exists(hd) and not (piece and Atlas.still_pieces()):
		return load(hd)
	var path := Atlas.critter_path(id)
	if id.begins_with("white_") or id.begins_with("black_"):
		var parts := id.split("_")
		path = Atlas.piece_path(parts[0], parts[1])
	var at := Atlas.get_atlas(path)
	if at == null or not at.has("static_R"):
		return null
	var f: Dictionary = at.anims["static_R"]["frames"][0]
	var t := AtlasTexture.new()
	t.atlas = at.page(int(f["page"]))
	t.region = f["rect"]
	return t


## Portrait in a round frame (TextureRect inside a styled panel), `px` wide.
static func avatar(id: String, px: int, ring := GOLD) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.16, 0.2, 0.15, 0.95), ring, px / 2, 3, 6))
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = avatar_texture(id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	return p


static func elo_text(o: Dictionary) -> String:
	return Lang.f("≈ %d Elo", [int(o.get("elo", 0))]) + ("" if o.get("measured", false) else Lang.t(" (estimé)"))
