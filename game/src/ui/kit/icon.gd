@tool
class_name Icon
extends Control
## The interface's icons, drawn in code like the rest (sharp at any size): flat shapes in a light colour with
## the thick dark brown outline of the logo and the creatures. Each icon is a list of primitives in a 100 x 100
## box: ["poly", pts], ["circle", c, r], ["line", a, b, w], ["arc", c, r, from, to, w], ["rect", Rect2, radius].
## A primitive may end with "dark" (drawn in the outline colour: holes, pupils, pips) or "accent".

@export var icon := "play":
	set(v):
		icon = v
		queue_redraw()
@export var color := Pal.CREAM:
	set(v):
		color = v
		queue_redraw()
@export var accent := Pal.GOLD
@export var outline := Pal.OUTLINE
@export var outline_px := 7.0  ## in the 100-unit box

const NAMES := ["play", "pause", "gear", "user", "users", "trophy", "lock", "unlock", "flag", "home", "back",
	"close", "check", "star", "crown", "swords", "eye", "eye_off", "music", "sound", "mute", "refresh", "target",
	"dice", "scroll", "door", "chevron_l", "chevron_r", "plus", "pencil", "trash", "hourglass", "info", "swap",
	"sparkle", "shield", "leaf", "question", "map", "skull", "handshake", "pawn"]


static func make(name: String, px: float, col := Pal.CREAM) -> Icon:
	var i := Icon.new()
	i.icon = name
	i.color = col
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	paint(self, icon, Rect2(Vector2.ZERO, size), color, outline, accent, outline_px)


## Draws an icon into `rect` (centred square) of any canvas item.
static func paint(ci: CanvasItem, name: String, rect: Rect2, col: Color, line := Pal.OUTLINE, acc := Pal.GOLD, ow_units := 7.0) -> void:
	var side := minf(rect.size.x, rect.size.y)
	if side <= 1.0:
		return
	var k := side / 100.0
	var o := rect.position + (rect.size - Vector2(side, side)) * 0.5
	var prims := shapes(name)
	for pass_i in 2:
		for p in prims:
			_prim(ci, p, pass_i, k, o, col, line, acc, ow_units * k)


static func _prim(ci: CanvasItem, p: Array, pass_i: int, k: float, o: Vector2, fill: Color, line: Color, acc: Color, ow: float) -> void:
	var kind: String = p[0]
	var tag: String = p[-1] if p.size() > 1 and p[-1] is String and p[-1] in ["dark", "accent"] else ""
	var col := fill
	if tag == "dark":
		col = line
	elif tag == "accent":
		col = acc
	if pass_i == 0:
		if tag == "dark":
			return  # drawn over the fill in the second pass only
		col = line
	match kind:
		"poly":
			var pts := PackedVector2Array()
			for v in p[1]:
				pts.append(o + v * k)
			if pass_i == 0:
				var closed := pts.duplicate()
				closed.append(pts[0])
				ci.draw_polyline(closed, col, ow * 2.0, true)
				for v in pts:
					ci.draw_circle(v, ow, col, true, -1.0, true)
			ci.draw_colored_polygon(pts, col)
		"circle":
			ci.draw_circle(o + p[1] * k, p[2] * k + (ow if pass_i == 0 else 0.0), col, true, -1.0, true)
		"line":
			var w: float = p[3] * k + (ow * 2.0 if pass_i == 0 else 0.0)
			var a: Vector2 = o + p[1] * k
			var b: Vector2 = o + p[2] * k
			ci.draw_line(a, b, col, w, true)
			ci.draw_circle(a, w * 0.5, col, true, -1.0, true)
			ci.draw_circle(b, w * 0.5, col, true, -1.0, true)
		"arc":
			var w2: float = p[5] * k + (ow * 2.0 if pass_i == 0 else 0.0)
			var c: Vector2 = o + p[1] * k
			var r: float = p[2] * k
			ci.draw_arc(c, r, p[3], p[4], 40, col, w2, true)
			for ang in [p[3], p[4]]:
				ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * r, w2 * 0.5, col, true, -1.0, true)
		"rect":
			var rr: Rect2 = p[1]
			var r2 := Rect2(o + rr.position * k, rr.size * k)
			var rad: float = p[2] * k
			if pass_i == 0:
				r2 = r2.grow(ow)
				rad += ow
			ci.draw_colored_polygon(PlankBox.rr_points(r2, rad), col)


## The primitives of an icon.
static func shapes(name: String) -> Array:
	match name:
		"play":
			return [["poly", [Vector2(32, 18), Vector2(84, 50), Vector2(32, 82)]]]
		"pause":
			return [["rect", Rect2(24, 18, 18, 64), 5.0], ["rect", Rect2(58, 18, 18, 64), 5.0]]
		"gear":
			var g: Array = []
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var c := Vector2(50, 50)
				g.append(["poly", [c + d * 26 + n * 9, c + d * 42 + n * 7, c + d * 42 - n * 7, c + d * 26 - n * 9]])
			g.append(["circle", Vector2(50, 50), 29.0])
			g.append(["circle", Vector2(50, 50), 11.0, "dark"])
			return g
		"user":
			return [["circle", Vector2(50, 33), 19.0], ["poly", _half_disc(Vector2(50, 90), 34.0, 14)]]
		"users":
			return [["circle", Vector2(66, 32), 15.0], ["poly", _half_disc(Vector2(66, 82), 26.0, 12)],
				["circle", Vector2(36, 38), 17.0], ["poly", _half_disc(Vector2(36, 90), 30.0, 12)]]
		"trophy":
			return [["arc", Vector2(24, 36), 12.0, PI * 0.5, PI * 1.5, 7.0], ["arc", Vector2(76, 36), 12.0, -PI * 0.5, PI * 0.5, 7.0],
				["poly", [Vector2(26, 18), Vector2(74, 18), Vector2(70, 46), Vector2(58, 60), Vector2(42, 60), Vector2(30, 46)]],
				["rect", Rect2(44, 58, 12, 14), 2.0], ["rect", Rect2(30, 72, 40, 12), 4.0]]
		"lock":
			return [["arc", Vector2(50, 42), 17.0, PI, TAU, 10.0], ["rect", Rect2(24, 42, 52, 42), 9.0],
				["circle", Vector2(50, 58), 6.0, "dark"], ["rect", Rect2(47, 60, 6, 13), 2.0, "dark"]]
		"unlock":
			return [["arc", Vector2(66, 30), 16.0, PI, TAU, 10.0], ["line", Vector2(82, 30), Vector2(82, 40), 10.0],
				["rect", Rect2(16, 42, 52, 42), 9.0], ["circle", Vector2(42, 58), 6.0, "dark"], ["rect", Rect2(39, 60, 6, 13), 2.0, "dark"]]
		"flag":
			return [["line", Vector2(26, 14), Vector2(26, 88), 7.0],
				["poly", [Vector2(30, 16), Vector2(82, 26), Vector2(68, 38), Vector2(82, 52), Vector2(30, 52)]]]
		"home":
			return [["poly", [Vector2(50, 14), Vector2(88, 48), Vector2(78, 48), Vector2(78, 86), Vector2(22, 86), Vector2(22, 48), Vector2(12, 48)]],
				["rect", Rect2(42, 60, 16, 26), 3.0, "dark"]]
		"back":
			return [["poly", [Vector2(14, 50), Vector2(48, 18), Vector2(48, 36), Vector2(86, 36), Vector2(86, 64), Vector2(48, 64), Vector2(48, 82)]]]
		"close":
			return [["line", Vector2(26, 26), Vector2(74, 74), 13.0], ["line", Vector2(74, 26), Vector2(26, 74), 13.0]]
		"check":
			return [["line", Vector2(20, 52), Vector2(42, 74), 13.0], ["line", Vector2(42, 74), Vector2(82, 28), 13.0]]
		"star":
			return [["poly", _star(Vector2(50, 53), 40.0, 17.0, 5)]]
		"sparkle":
			return [["poly", _star(Vector2(50, 50), 42.0, 11.0, 4)]]
		"crown":
			return [["poly", [Vector2(14, 30), Vector2(32, 50), Vector2(50, 20), Vector2(68, 50), Vector2(86, 30), Vector2(80, 76), Vector2(20, 76)]],
				["circle", Vector2(50, 60), 6.0, "accent"]]
		"swords":
			return [["line", Vector2(20, 20), Vector2(76, 76), 8.0], ["line", Vector2(80, 20), Vector2(24, 76), 8.0],
				["line", Vector2(60, 76), Vector2(80, 56), 7.0], ["line", Vector2(40, 76), Vector2(20, 56), 7.0]]
		"eye":
			return [["poly", _almond()], ["circle", Vector2(50, 50), 14.0, "dark"], ["circle", Vector2(45, 45), 4.0]]
		"eye_off":
			return [["poly", _almond()], ["circle", Vector2(50, 50), 14.0, "dark"], ["line", Vector2(20, 20), Vector2(80, 80), 9.0]]
		"music":
			return [["line", Vector2(44, 72), Vector2(44, 20), 7.0], ["poly", [Vector2(44, 16), Vector2(76, 26), Vector2(76, 42), Vector2(44, 32)]],
				["circle", Vector2(32, 74), 14.0]]
		"sound":
			return [["poly", [Vector2(14, 38), Vector2(32, 38), Vector2(54, 18), Vector2(54, 82), Vector2(32, 62), Vector2(14, 62)]],
				["arc", Vector2(56, 50), 16.0, -PI * 0.3, PI * 0.3, 7.0], ["arc", Vector2(56, 50), 30.0, -PI * 0.3, PI * 0.3, 7.0]]
		"mute":
			return [["poly", [Vector2(10, 38), Vector2(28, 38), Vector2(50, 18), Vector2(50, 82), Vector2(28, 62), Vector2(10, 62)]],
				["line", Vector2(64, 36), Vector2(88, 64), 8.0], ["line", Vector2(88, 36), Vector2(64, 64), 8.0]]
		"refresh":
			return [["arc", Vector2(50, 52), 28.0, -PI * 0.35, PI * 1.45, 10.0],
				["poly", [Vector2(62, 14), Vector2(86, 30), Vector2(60, 42)]]]
		"target":
			return [["arc", Vector2(50, 50), 28.0, 0.0, TAU, 8.0], ["circle", Vector2(50, 50), 8.0],
				["line", Vector2(50, 8), Vector2(50, 22), 7.0], ["line", Vector2(50, 78), Vector2(50, 92), 7.0],
				["line", Vector2(8, 50), Vector2(22, 50), 7.0], ["line", Vector2(78, 50), Vector2(92, 50), 7.0]]
		"dice":
			var d: Array = [["rect", Rect2(16, 16, 68, 68), 14.0]]
			for v in [Vector2(34, 34), Vector2(66, 34), Vector2(50, 50), Vector2(34, 66), Vector2(66, 66)]:
				d.append(["circle", v, 6.5, "dark"])
			return d
		"scroll":
			return [["rect", Rect2(22, 14, 56, 72), 8.0], ["line", Vector2(34, 32), Vector2(66, 32), 6.0, "dark"],
				["line", Vector2(34, 50), Vector2(66, 50), 6.0, "dark"], ["line", Vector2(34, 68), Vector2(56, 68), 6.0, "dark"]]
		"door":
			return [["rect", Rect2(16, 12, 44, 76), 6.0], ["circle", Vector2(50, 52), 4.5, "dark"],
				["poly", [Vector2(62, 38), Vector2(76, 38), Vector2(76, 26), Vector2(94, 50), Vector2(76, 74), Vector2(76, 62), Vector2(62, 62)]]]
		"chevron_l":
			return [["line", Vector2(62, 18), Vector2(32, 50), 13.0], ["line", Vector2(32, 50), Vector2(62, 82), 13.0]]
		"chevron_r":
			return [["line", Vector2(38, 18), Vector2(68, 50), 13.0], ["line", Vector2(68, 50), Vector2(38, 82), 13.0]]
		"plus":
			return [["line", Vector2(50, 18), Vector2(50, 82), 14.0], ["line", Vector2(18, 50), Vector2(82, 50), 14.0]]
		"pencil":
			return [["poly", [Vector2(66, 14), Vector2(86, 34), Vector2(38, 82), Vector2(16, 86), Vector2(20, 62)]],
				["line", Vector2(58, 24), Vector2(76, 42), 4.0, "dark"]]
		"trash":
			return [["rect", Rect2(16, 20, 68, 12), 4.0], ["rect", Rect2(40, 12, 20, 10), 3.0],
				["poly", [Vector2(22, 34), Vector2(78, 34), Vector2(72, 88), Vector2(28, 88)]],
				["line", Vector2(42, 46), Vector2(42, 76), 5.0, "dark"], ["line", Vector2(58, 46), Vector2(58, 76), 5.0, "dark"]]
		"hourglass":
			return [["rect", Rect2(20, 12, 60, 10), 4.0], ["rect", Rect2(20, 78, 60, 10), 4.0],
				["poly", [Vector2(26, 22), Vector2(74, 22), Vector2(54, 50), Vector2(74, 78), Vector2(26, 78), Vector2(46, 50)]],
				["poly", [Vector2(36, 72), Vector2(64, 72), Vector2(50, 58)], "accent"]]
		"chat":  # a speech bubble with three dots (the community's Discord)
			return [["rect", Rect2(12, 18, 76, 54), 18.0], ["poly", [Vector2(26, 66), Vector2(46, 66), Vector2(22, 88)]],
				["circle", Vector2(32, 45), 6.5, "dark"], ["circle", Vector2(50, 45), 6.5, "dark"], ["circle", Vector2(68, 45), 6.5, "dark"]]
		"info":
			return [["circle", Vector2(50, 50), 38.0], ["circle", Vector2(50, 30), 6.0, "dark"], ["rect", Rect2(44, 42, 12, 32), 4.0, "dark"]]
		"question":
			return [["circle", Vector2(50, 50), 38.0], ["arc", Vector2(50, 40), 12.0, PI, TAU + PI * 0.4, 8.0, "dark"],
				["circle", Vector2(50, 72), 5.5, "dark"]]
		"swap":
			return [["poly", [Vector2(14, 36), Vector2(36, 14), Vector2(36, 28), Vector2(84, 28), Vector2(84, 44), Vector2(36, 44), Vector2(36, 58)]],
				["poly", [Vector2(86, 64), Vector2(64, 86), Vector2(64, 72), Vector2(16, 72), Vector2(16, 56), Vector2(64, 56), Vector2(64, 42)]]]
		"shield":
			return [["poly", [Vector2(50, 10), Vector2(84, 22), Vector2(80, 56), Vector2(50, 90), Vector2(20, 56), Vector2(16, 22)]],
				["poly", [Vector2(50, 22), Vector2(72, 30), Vector2(69, 54), Vector2(50, 76)], "accent"]]
		"leaf":
			return [["poly", [Vector2(16, 84), Vector2(20, 46), Vector2(44, 20), Vector2(86, 14), Vector2(80, 56), Vector2(54, 80)]],
				["line", Vector2(24, 76), Vector2(66, 34), 5.0, "dark"]]
		"map":
			return [["poly", [Vector2(10, 22), Vector2(36, 12), Vector2(64, 22), Vector2(90, 12), Vector2(90, 78), Vector2(64, 88), Vector2(36, 78), Vector2(10, 88)]],
				["line", Vector2(36, 14), Vector2(36, 78), 4.0, "dark"], ["line", Vector2(64, 22), Vector2(64, 86), 4.0, "dark"]]
		"skull":
			return [["circle", Vector2(50, 44), 32.0], ["rect", Rect2(32, 58, 36, 28), 8.0],
				["circle", Vector2(38, 46), 9.0, "dark"], ["circle", Vector2(62, 46), 9.0, "dark"],
				["line", Vector2(44, 76), Vector2(44, 84), 4.0, "dark"], ["line", Vector2(56, 76), Vector2(56, 84), 4.0, "dark"]]
		"pawn":
			return [["circle", Vector2(50, 27), 14.0], ["poly", [Vector2(41, 41), Vector2(59, 41), Vector2(63, 49), Vector2(57, 51),
				Vector2(65, 74), Vector2(35, 74), Vector2(43, 51), Vector2(37, 49)]], ["rect", Rect2(25, 74, 50, 13), 5.0]]
		"handshake":
			return [["poly", [Vector2(8, 40), Vector2(30, 30), Vector2(54, 44), Vector2(60, 60), Vector2(44, 74), Vector2(24, 66), Vector2(8, 62)]],
				["poly", [Vector2(92, 40), Vector2(70, 30), Vector2(46, 38), Vector2(40, 50), Vector2(52, 56), Vector2(62, 50), Vector2(76, 66), Vector2(92, 62)]]]
	return [["circle", Vector2(50, 50), 30.0]]


static func _half_disc(c: Vector2, r: float, n: int) -> Array:
	var pts: Array = []
	for i in n + 1:
		var a := PI + PI * i / n
		pts.append(c + Vector2(cos(a), sin(a) * 1.05) * r)
	return pts


static func _star(c: Vector2, r_out: float, r_in: float, points: int) -> Array:
	var pts: Array = []
	for i in points * 2:
		var a := -PI * 0.5 + PI * i / points
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _almond() -> Array:
	var pts: Array = []
	for i in 13:
		var t := float(i) / 12.0
		pts.append(Vector2(10 + 80 * t, 50 - sin(t * PI) * 30))
	for i in range(11, 0, -1):
		var t := float(i) / 12.0
		pts.append(Vector2(10 + 80 * t, 50 + sin(t * PI) * 30))
	return pts
