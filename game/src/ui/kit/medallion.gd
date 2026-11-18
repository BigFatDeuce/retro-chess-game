@tool
class_name Medallion
extends Control
## A creature's portrait in a round frame, drawn in code: drop shadow, dark outline, metal ring (gold when the
## opponent is beaten, leaf green when open, stone when locked, wood otherwise), a coloured background disc,
## the portrait clipped to the circle (a dark silhouette when locked), a gloss, and a badge (star, lock, swords).
## `selected` adds a breathing glow.

enum State { PLAIN, OPEN, BEATEN, LOCKED, CURRENT }

var texture: Texture2D:
	set(v):
		texture = v
		# a character's portrait is already framed as a bust: shown whole; a creature's is enlarged on its head
		var bust := v != null and v.resource_path.get_file().begins_with("npc_")
		zoom = 1.0 if bust else 1.18
		focus = Vector2.ZERO if bust else Vector2(0.0, 0.06)
		queue_redraw()
var state := State.PLAIN:
	set(v):
		state = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		set_process(selected)
		queue_redraw()
var zoom := 1.18  ## portrait scale inside the disc
var focus := Vector2(0.0, 0.06)  ## shifts the portrait (share of the diameter): the head stays in view
var badge := true
var ring_override := Color(0, 0, 0, 0)
var _t := 0.0


static func make(tex: Texture2D, px: float, st := State.PLAIN) -> Medallion:
	var m := Medallion.new()
	m.texture = tex
	m.state = st
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _ready() -> void:
	set_process(selected)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _ring_colors() -> Array:
	if ring_override.a > 0.0:
		return [ring_override.lightened(0.3), ring_override, ring_override.darkened(0.4)]
	match state:
		State.BEATEN:
			return [Pal.GOLD_HI, Pal.GOLD, Pal.GOLD_LO]
		State.OPEN, State.CURRENT:
			return [Pal.LEAF_HI, Pal.LEAF, Pal.LEAF_LO]
		State.LOCKED:
			return [Pal.STONE_HI, Pal.STONE, Pal.STONE_LO]
	return [Pal.WOOD_HI, Pal.WOOD, Pal.WOOD_LO]


func _draw() -> void:
	var d := minf(size.x, size.y)
	if d < 4.0:
		return
	var c := size * 0.5
	var r := d * 0.5
	var ow := maxf(3.0, d * 0.035)
	var ring_w := maxf(4.0, d * 0.07)
	var cols := _ring_colors()
	if selected:
		var k := 0.5 + 0.5 * sin(_t * 3.2) if not Pal.reduced_motion() else 1.0
		var g: Color = Pal.GOLD_HI if state != State.LOCKED else Pal.CREAM
		for i in 6:
			var gr := r + d * (0.02 + 0.025 * i) * (0.8 + 0.4 * k)
			draw_circle(c, gr, Pal.with_alpha(g, 0.11 * (1.0 - i / 6.0)), true, -1.0, true)
	# shadow, outline, ring with a light top
	draw_circle(c + Vector2(0, d * 0.04), r, Pal.with_alpha(Pal.SHADOW, 0.5), true, -1.0, true)
	draw_circle(c, r, Pal.OUTLINE, true, -1.0, true)
	draw_circle(c, r - ow, cols[2], true, -1.0, true)
	draw_circle(c - Vector2(0, ring_w * 0.22), r - ow - ring_w * 0.18, cols[1], true, -1.0, true)
	draw_arc(c, r - ow - ring_w * 0.35, PI * 1.12, PI * 1.88, 24, Pal.with_alpha(cols[0], 0.9), ring_w * 0.32, true)
	var inner := r - ow - ring_w
	draw_circle(c, inner + ow * 0.6, Pal.OUTLINE, true, -1.0, true)
	# background disc
	var bg_top := Color("3f6b3a")
	var bg_bot := Color("1f3a24")
	if state == State.LOCKED:
		bg_top = Color("4a4740")
		bg_bot = Color("26241f")
	elif state == State.BEATEN:
		bg_top = Color("8a6a2e")
		bg_bot = Color("4a3414")
	_disc(c, inner, bg_top, bg_bot)
	if texture:
		var pts := _circle_pts(c, inner, 56)
		var side := inner * 2.0 * zoom
		var img := Rect2(c - Vector2(side, side) * 0.5 + focus * inner * 2.0, Vector2(side, side))
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - img.position) / img.size)
		var mod := Color.WHITE if state != State.LOCKED else Color(0.1, 0.09, 0.08, 0.92)
		var cols_p := PackedColorArray()
		cols_p.resize(pts.size())
		cols_p.fill(mod)
		draw_polygon(pts, cols_p, uvs, texture)
	# inner shade at the top and a gloss
	draw_arc(c, inner - inner * 0.06, PI * 1.05, PI * 1.95, 32, Pal.with_alpha(Pal.OUTLINE, 0.35), inner * 0.12, true)
	draw_arc(c, inner * 0.82, PI * 1.2, PI * 1.55, 16, Color(1, 1, 1, 0.22), inner * 0.07, true)
	if badge and d >= 80.0:
		var bname := ""
		var bcol := Pal.CREAM
		var bbg := Pal.WOOD
		match state:
			State.BEATEN:
				bname = "star"
				bcol = Pal.GOLD_HI
				bbg = Pal.GOLD_LO
			State.LOCKED:
				bname = "lock"
				bcol = Pal.CREAM
				bbg = Pal.STONE_LO
			State.CURRENT:
				bname = "swords"
				bcol = Pal.CREAM
				bbg = Pal.LEAF_LO
		if bname != "":
			var br := d * 0.17
			var bc := c + Vector2(r * 0.68, r * 0.68)
			draw_circle(bc, br + ow, Pal.OUTLINE, true, -1.0, true)
			draw_circle(bc, br, bbg, true, -1.0, true)
			Icon.paint(self, bname, Rect2(bc - Vector2(br, br) * 0.78, Vector2(br, br) * 1.56), bcol, Pal.OUTLINE, Pal.GOLD, 9.0)


func _disc(c: Vector2, r: float, top: Color, bottom: Color) -> void:
	var pts := _circle_pts(c, r, 48)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - (c.y - r)) / (2.0 * r), 0.0, 1.0)))
	draw_polygon(pts, cols)


static func _circle_pts(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
