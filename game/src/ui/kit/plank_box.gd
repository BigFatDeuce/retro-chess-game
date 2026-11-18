@tool
class_name PlankBox
extends StyleBox
## The interface's panels and buttons, drawn as anti-aliased polygons (sharp at any resolution, no texture):
## a soft drop shadow, a dark outline, a wooden rim with a vertical gradient and a light bevel, a groove, the
## body (walnut, parchment, leaf...) with an optional gloss, rivets in the corners, and an outer glow (focus,
## selection). A `lip` gives buttons their thickness: the face sits on a darker edge it sinks into when pressed.

@export var fill_top := Pal.WALNUT_HI
@export var fill_bottom := Pal.WALNUT_LO
@export var rim_top := Pal.WOOD_HI
@export var rim_bottom := Pal.WOOD_LO
@export var outline := Pal.OUTLINE
@export var outline_w := Pal.OUTLINE_W
@export var rim := 12.0  ## thickness of the wooden frame (0 = none)
@export var radius := float(Pal.RADIUS)
@export var lip := 0.0  ## thickness under the face
@export var lip_top := Pal.WOOD_LO
@export var lip_bottom := Pal.OUTLINE
@export var shadow := 0.45  ## alpha of the drop shadow (0 = none)
@export var shadow_offset := Vector2(0, 10)
@export var shadow_size := 18.0
@export var gloss := 0.0  ## white highlight over the top of the body
@export var bevel := 0.35  ## light line along the top of the rim
@export var groove := 0.55  ## dark line between rim and body
@export var rivets := false
@export var glow := Color(0, 0, 0, 0)
@export var glow_size := 0.0
@export var only_glow := false  ## draws the glow alone (focus outline over a button)
@export var sink := 0.0  ## px the whole shape is pushed down (a pressed button)

const SEG := 7  ## points per rounded corner


func _get_draw_rect(rect: Rect2) -> Rect2:
	var g := maxf(shadow_size + shadow_offset.length(), glow_size) + 2.0
	return rect.grow(g)


func _draw(ci: RID, rect: Rect2) -> void:
	if sink > 0.0:
		rect = Rect2(rect.position + Vector2(0, sink), rect.size - Vector2(0, sink))
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var rad := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if glow.a > 0.0 and glow_size > 0.0:
		_ring(ci, rect.grow(glow_size), rad + glow_size, rect.grow(1.0), rad + 1.0,
			Pal.with_alpha(glow, 0.0), glow)
	if only_glow:
		return
	if shadow > 0.0:
		var sr := Rect2(rect.position + shadow_offset, rect.size)
		_ring(ci, sr.grow(shadow_size), rad + shadow_size, sr, rad,
			Color(Pal.SHADOW, 0.0), Color(Pal.SHADOW.r, Pal.SHADOW.g, Pal.SHADOW.b, shadow))
		if fill_top.a >= 0.99:
			_fill(ci, sr, rad, Color(Pal.SHADOW, shadow), Color(Pal.SHADOW, shadow))
	# outline
	var inner := rect.grow(-outline_w)
	var rad_in := maxf(rad - outline_w, 0.0)
	_ring(ci, rect, rad, inner, rad_in, outline, outline)
	var face := inner
	if lip > 0.0:
		_fill(ci, inner, rad_in, lip_top, lip_bottom, inner.position.y + inner.size.y - lip - rad_in, inner.end.y)
		face = Rect2(inner.position, inner.size - Vector2(0, lip))
		# a dark seam where the face meets its edge
		_ring(ci, face.grow(2.0), rad_in + 2.0, face, rad_in, Pal.with_alpha(outline, 0.9), Pal.with_alpha(outline, 0.9))
	var body := face
	var rad_body := rad_in
	if rim > 0.0:
		body = face.grow(-rim)
		rad_body = maxf(rad_in - rim, 3.0)
		_ring_grad(ci, face, rad_in, body, rad_body, rim_top, rim_bottom)
		if groove > 0.0:
			var g := Pal.with_alpha(outline, groove)
			_ring(ci, body.grow(2.5), rad_body + 2.5, body, rad_body, g, g)
	_fill(ci, body, rad_body, fill_top, fill_bottom)
	if gloss > 0.0:
		var half := Rect2(body.position, Vector2(body.size.x, body.size.y * 0.55))
		_fill(ci, half.grow(-2.0), maxf(rad_body - 2.0, 2.0), Color(1, 1, 1, gloss), Color(1, 1, 1, 0.0))
	if bevel > 0.0:
		_bevel(ci, face, rad_in)
	if rivets and rim >= 8.0:
		var r := clampf(rim * 0.42, 4.0, 11.0)
		var k := rim * 0.5 + rad_in * 0.29
		for c: Vector2 in [face.position, Vector2(face.end.x, face.position.y), face.end, Vector2(face.position.x, face.end.y)]:
			var d: Vector2 = (face.get_center() - c).sign()
			_rivet(ci, c + d * k, r)


# --- shapes ---------------------------------------------------------------------------------------------------------

static func rr_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = clampf(rad, 0.01, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centres := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for k in 4:
		var a0 := -PI * 0.5 + PI * 0.5 * k
		for i in SEG + 1:
			var a := a0 + PI * 0.5 * i / SEG
			pts.append(centres[k] + Vector2(cos(a), sin(a)) * rad)
	return pts


static func _lerp_y(y: float, y0: float, y1: float, top: Color, bottom: Color) -> Color:
	return top.lerp(bottom, clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0))


static func _fill(ci: RID, r: Rect2, rad: float, top: Color, bottom: Color, y0 := NAN, y1 := NAN) -> void:
	if is_nan(y0):
		y0 = r.position.y
		y1 = r.end.y
	var pts := rr_points(r, rad)
	var verts := PackedVector2Array([r.get_center()])
	verts.append_array(pts)
	var cols := PackedColorArray()
	for v in verts:
		cols.append(_lerp_y(v.y, y0, y1, top, bottom))
	var idx := PackedInt32Array()
	var n := pts.size()
	for i in n:
		idx.append(0)
		idx.append(1 + i)
		idx.append(1 + (i + 1) % n)
	RenderingServer.canvas_item_add_triangle_array(ci, idx, verts, cols)


## A band between two rounded rectangles: outer edge colour, inner edge colour.
static func _ring(ci: RID, outer: Rect2, rad_o: float, inner: Rect2, rad_i: float, c_out: Color, c_in: Color) -> void:
	var a := rr_points(outer, rad_o)
	var b := rr_points(inner, rad_i)
	var verts := a.duplicate()
	verts.append_array(b)
	var cols := PackedColorArray()
	for i in a.size():
		cols.append(c_out)
	for i in b.size():
		cols.append(c_in)
	RenderingServer.canvas_item_add_triangle_array(ci, _ring_idx(a.size()), verts, cols)


## A band coloured by height (the wooden rim).
static func _ring_grad(ci: RID, outer: Rect2, rad_o: float, inner: Rect2, rad_i: float, top: Color, bottom: Color) -> void:
	var a := rr_points(outer, rad_o)
	var verts := a.duplicate()
	verts.append_array(rr_points(inner, rad_i))
	var cols := PackedColorArray()
	for v in verts:
		cols.append(_lerp_y(v.y, outer.position.y, outer.end.y, top, bottom))
	RenderingServer.canvas_item_add_triangle_array(ci, _ring_idx(a.size()), verts, cols)


static func _ring_idx(n: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for i in n:
		var j := (i + 1) % n
		idx.append_array([i, j, n + i, j, n + j, n + i])
	return idx


func _bevel(ci: RID, face: Rect2, rad: float) -> void:
	var pts := rr_points(face.grow(-2.5), maxf(rad - 2.5, 1.0))
	# the upper part of the outline: last corner (top left) then the first (top right)
	var line := PackedVector2Array()
	for i in range(3 * (SEG + 1) + SEG / 2, 4 * (SEG + 1)):
		line.append(pts[i])
	for i in range(0, SEG / 2 + 1):
		line.append(pts[i])
	var cols := PackedColorArray()
	for i in line.size():
		var t := float(i) / maxf(line.size() - 1, 1)
		var a := bevel * (1.0 - absf(t - 0.5) * 0.8)
		cols.append(Color(1, 0.97, 0.88, a))
	RenderingServer.canvas_item_add_polyline(ci, line, cols, 2.5, true)


static func _rivet(ci: RID, c: Vector2, r: float) -> void:
	RenderingServer.canvas_item_add_circle(ci, c + Vector2(0, 1.5), r + 2.5, Pal.with_alpha(Pal.OUTLINE, 0.9))
	RenderingServer.canvas_item_add_circle(ci, c, r, Pal.RIVET_LO)
	RenderingServer.canvas_item_add_circle(ci, c - Vector2(r, r) * 0.12, r * 0.78, Pal.RIVET)
	RenderingServer.canvas_item_add_circle(ci, c - Vector2(r, r) * 0.32, r * 0.28, Color(1, 1, 1, 0.85))


# --- presets ----------------------------------------------------------------------------------------------------------

## A copy with other settings (states of a button).
func with(fields: Dictionary) -> PlankBox:
	var b: PlankBox = duplicate()
	for k in fields:
		b.set(k, fields[k])
	return b


func margins(h: float, v: float) -> PlankBox:
	var edge := outline_w + rim
	content_margin_left = edge + h
	content_margin_right = edge + h
	content_margin_top = edge + v
	content_margin_bottom = edge + v + lip
	return self


## Walnut panel framed in wood, with rivets.
static func panel(alpha := 0.95) -> PlankBox:
	var b := PlankBox.new()
	b.fill_top = Pal.with_alpha(Pal.WALNUT_HI, alpha)
	b.fill_bottom = Pal.with_alpha(Pal.WALNUT_LO, alpha)
	b.rim = 14.0
	b.rivets = true
	return b.margins(Pal.S5, Pal.S4)


## Thin-framed walnut plate (HUD).
static func plate(alpha := 0.9) -> PlankBox:
	var b := PlankBox.new()
	b.fill_top = Pal.with_alpha(Pal.WALNUT_HI, alpha)
	b.fill_bottom = Pal.with_alpha(Pal.WALNUT_LO, alpha)
	b.rim = 7.0
	b.radius = 20.0
	b.outline_w = 4.0
	b.shadow = 0.35
	b.shadow_size = 14.0
	b.shadow_offset = Vector2(0, 6)
	return b.margins(Pal.S3, Pal.S2)


static func parchment() -> PlankBox:
	var b := PlankBox.new()
	b.fill_top = Pal.PARCHMENT
	b.fill_bottom = Pal.PARCHMENT_LO
	b.rim = 8.0
	b.radius = 18.0
	b.groove = 0.35
	return b.margins(Pal.S3, Pal.S2)


## A button face: colours of the face (top, bottom) and of its edge.
static func button(top: Color, bottom: Color, edge: Color, rad := 26.0, lip_px := 9.0) -> PlankBox:
	var b := PlankBox.new()
	b.fill_top = top
	b.fill_bottom = bottom
	b.rim = 0.0
	b.radius = rad
	b.lip = lip_px
	b.lip_top = edge
	b.lip_bottom = edge.darkened(0.35)
	b.gloss = 0.22
	b.bevel = 0.55
	b.groove = 0.0
	b.shadow = 0.4
	b.shadow_size = 12.0
	b.shadow_offset = Vector2(0, 7)
	return b.margins(Pal.S4, Pal.S2)
