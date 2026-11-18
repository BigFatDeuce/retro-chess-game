class_name AmbientLife
extends Node2D
## Life around the board, per theme (data/boards.json "ambient" and "critters"):
## - critters: small library creatures wandering off the board (Critter, in the pieces' y-sorted layer);
## - butterflies fluttering in loops, now and then crossing the board, with their shadow on the ground;
## - pollen motes drifting with the wind, falling leaves from the trees behind, fireflies, cloud shadows.
## The air things are drawn here, above the pieces, in layout space; positions live in board coordinates
## (u, v, height) so the perspective stays right.

const WING_COLORS := [Color("fff3d6"), Color("ffd447"), Color("ff9fc9"), Color("9fd4ff"), Color("ffb347")]
const LEAF_COLORS := [Color("8fbf3a"), Color("c9a23a"), Color("b8682c"), Color("a4c64a")]
const WIND := Vector2(0.10, -0.02)  ## squares per second

var board: BoardView
var layer: Node2D
var enabled := true

var _critters: Array[Critter] = []
var _butterflies: Array = []  ## {p: Vector3 (u, v, h), t: Vector3, ph, col, spd}
var _pollen: Array = []  ## {p: Vector3, ph, size}
var _leaves: Array = []  ## {p: Vector3, vel: Vector3, rot, spin, col, life}
var _flies: Array = []  ## fireflies {p: Vector3, ph}
var _clouds: Array = []  ## {p: Vector2 (u, v), r}
var _leaf_rate := 0.0
var _leaf_in := 3.0
var _t := 0.0
var _cloud_alpha := 0.0
var _tree_spots: Array[Vector2] = []
var _soft: Texture2D  ## radial falloff (cloud shadows): a smooth gradient, never stacked rings


func _init() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_soft = gt


func get_critters() -> Array[Critter]:
	return _critters.filter(func(c): return is_instance_valid(c))


func setup(p_board: BoardView, p_layer: Node2D) -> void:
	board = p_board
	layer = p_layer
	z_index = 10


func load_theme(key: String) -> void:
	for c in _critters:
		if is_instance_valid(c):
			c.queue_free()
	_critters.clear()
	_butterflies.clear()
	_pollen.clear()
	_leaves.clear()
	_flies.clear()
	_clouds.clear()
	var boards: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boards.json"))
	var b: Dictionary = boards.get("boards", {}).get(key, {})
	var amb: Dictionary = b.get("ambient", {})
	# critters
	var cdefs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/critters.json")).get("critters", {})
	var cc: Dictionary = b.get("critters", {})
	var pool: Array = cc.get("pool", [])
	for i in int(cc.get("count", 0)):
		if pool.is_empty():
			break
		var k := String(pool[i % pool.size()])
		if not cdefs.has(k):
			continue
		var c := Critter.new()
		if c.setup(board, k, cdefs[k]):
			layer.add_child(c)
			_critters.append(c)
	# trees behind the board drop the leaves
	_tree_spots.clear()
	for o in board.obstacles:
		if o.z > 0.35:
			_tree_spots.append(Vector2(o.x, o.y))
	for i in int(amb.get("butterflies", 0)):
		var p := _air_point()
		_butterflies.append({"p": p, "t": _air_point(), "ph": randf() * TAU, "col": WING_COLORS.pick_random(),
			"spd": randf_range(0.7, 1.1)})
	for i in int(amb.get("pollen", 0)):
		_pollen.append({"p": Vector3(randf_range(-4, 12), randf_range(-1, 12), randf_range(0.1, 1.6)),
			"ph": randf() * TAU, "size": randf_range(2.0, 4.2)})
	for i in int(amb.get("fireflies", 0)):
		_flies.append({"p": Vector3(randf_range(-3, 11), randf_range(-0.5, 11), randf_range(0.2, 1.2)),
			"ph": randf() * TAU})
	_leaf_rate = float(amb.get("leaves", 0))
	_cloud_alpha = float(amb.get("clouds", 0.0))
	if _cloud_alpha > 0.0:
		for i in 3:
			_clouds.append({"p": Vector2(randf_range(-8, 14), randf_range(-1, 11)), "r": randf_range(3.0, 5.0)})


## A point in the air around the board (mostly off it, sometimes over it).
func _air_point() -> Vector3:
	var u := randf_range(-2.5, 10.5)
	var v := randf_range(-0.2, 10.5)
	if randf() < 0.7 and u > -0.6 and u < 8.6 and v < 8.6:
		u = -1.8 if randf() < 0.5 else 9.8
	return Vector3(u, v, randf_range(0.5, 1.5))


func _screen(p: Vector3) -> Vector2:
	var g := board.project(p.x, p.y)
	return g - Vector2(0, p.z * BoardView.SQUARE * 0.55 * board.scale_at(p.y))


func _process(delta: float) -> void:
	visible = enabled
	if not enabled or board == null:
		return
	_t += delta
	for b in _butterflies:
		var p: Vector3 = b["p"]
		var t: Vector3 = b["t"]
		var to := t - p
		if Vector2(to.x, to.y).length() < 0.25 or randf() < delta * 0.08:
			b["t"] = _air_point()
		var d := Vector2(to.x, to.y).normalized()
		# fluttering: a wobble across the path and up and down
		var wob: Vector2 = Vector2(-d.y, d.x) * sin(_t * 3.1 + float(b["ph"])) * 0.6
		var step: Vector2 = (d + wob) * 0.55 * float(b["spd"]) * delta
		p.x += step.x
		p.y += step.y
		p.z = clampf(p.z + (t.z - p.z) * delta * 0.6 + sin(_t * 5.3 + b["ph"]) * delta * 0.5, 0.25, 1.8)
		b["p"] = p
	for m in _pollen:
		var p: Vector3 = m["p"]
		p.x += (WIND.x + sin(_t * 0.6 + m["ph"]) * 0.05) * delta
		p.y += (WIND.y + cos(_t * 0.5 + m["ph"]) * 0.03) * delta
		p.z += sin(_t * 0.8 + m["ph"]) * 0.04 * delta
		if p.x > 12.0:
			p.x = -4.0
		if p.y < -1.0:
			p.y = 12.0
		m["p"] = p
	for f in _flies:
		var p: Vector3 = f["p"]
		p.x += sin(_t * 0.7 + f["ph"] * 3.0) * 0.12 * delta
		p.y += cos(_t * 0.5 + f["ph"] * 2.0) * 0.10 * delta
		p.z = 0.7 + sin(_t * 0.9 + f["ph"]) * 0.4
		f["p"] = p
	if _leaf_rate > 0.0 and not _tree_spots.is_empty():
		_leaf_in -= delta
		if _leaf_in <= 0.0:
			_leaf_in = randf_range(3.0, 7.0) / _leaf_rate
			var s: Vector2 = _tree_spots.pick_random()
			_leaves.append({"p": Vector3(s.x + randf_range(-0.4, 0.4), s.y, randf_range(1.6, 2.4)),
				"vel": Vector3(randf_range(0.15, 0.35), randf_range(-0.25, -0.05), -randf_range(0.28, 0.4)),
				"rot": randf() * TAU, "spin": randf_range(-3.0, 3.0), "col": LEAF_COLORS.pick_random(), "life": 0.0})
	for l in _leaves:
		var p: Vector3 = l["p"]
		var vel: Vector3 = l["vel"]
		l["life"] += delta
		if p.z > 0.0:
			p += vel * delta + Vector3(sin(_t * 2.0 + l["rot"]) * 0.25 * delta, 0, 0)
			l["rot"] += l["spin"] * delta
		p.z = maxf(p.z, 0.0)
		l["p"] = p
	_leaves = _leaves.filter(func(l): return l["life"] < 14.0)
	for c in _clouds:
		var p: Vector2 = c["p"]
		p += Vector2(0.18, -0.03) * delta
		if p.x > 16.0:
			p = Vector2(-9.0, randf_range(-1, 11))
		c["p"] = p
	queue_redraw()


func _draw() -> void:
	if board == null:
		return
	# cloud shadows: very soft dark patches drifting over the whole scene
	for c in _clouds:
		var g := board.project(c["p"].x, c["p"].y)
		var s := board.scale_at(c["p"].y)
		var r: float = c["r"] * BoardView.SQUARE * s
		draw_texture_rect(_soft, Rect2(g - Vector2(r, r * 0.45), Vector2(r * 2.0, r * 0.9)), false,
			Color(0.04, 0.07, 0.14, _cloud_alpha * 0.2))
	for m in _pollen:
		var p := _screen(m["p"])
		var a := 0.35 + 0.25 * sin(_t * 1.7 + m["ph"])
		var sz: float = m["size"] * board.scale_at(m["p"].y)
		draw_circle(p, sz * 1.9, Color(1.0, 0.97, 0.8, a * 0.25))
		draw_circle(p, sz, Color(1.0, 0.98, 0.85, a))
	for l in _leaves:
		_draw_leaf(l)
	for f in _flies:
		var p := _screen(f["p"])
		var a := clampf(0.5 + 0.5 * sin(_t * 2.3 + f["ph"] * 5.0), 0.0, 1.0)
		var s := board.scale_at(f["p"].y)
		draw_circle(p, 16.0 * s, Color(0.85, 1.0, 0.45, a * 0.12))
		draw_circle(p, 7.0 * s, Color(0.9, 1.0, 0.5, a * 0.35))
		draw_circle(p, 3.0 * s, Color(1.0, 1.0, 0.8, a))
	for b in _butterflies:
		_draw_butterfly(b)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, r.y / maxf(r.x, 0.001)))
	draw_circle(Vector2.ZERO, r.x, col)
	draw_set_transform(Vector2.ZERO)


func _draw_leaf(l: Dictionary) -> void:
	var p3: Vector3 = l["p"]
	var p := _screen(p3)
	var s := board.scale_at(p3.y) * 1.25
	var fade := clampf((14.0 - float(l["life"])) / 3.0, 0.0, 1.0)
	var col: Color = l["col"]
	col.a = 0.9 * fade
	var rot: float = l["rot"]
	var flat := absf(cos(rot * 1.3)) * 0.7 + 0.3  # tumbling: the leaf turns edge-on and back
	draw_set_transform(p, rot, Vector2(s, s * flat))
	draw_colored_polygon(PackedVector2Array([Vector2(-11, 0), Vector2(-3, -5), Vector2(9, -3), Vector2(12, 0),
		Vector2(9, 3), Vector2(-3, 5)]), col)
	draw_line(Vector2(-11, 0), Vector2(11, 0), col.darkened(0.35), 1.2)
	draw_set_transform(Vector2.ZERO)


func _draw_butterfly(b: Dictionary) -> void:
	var p3: Vector3 = b["p"]
	var s := board.scale_at(p3.y) * 2.5
	var g := board.project(p3.x, p3.y)
	# shadow on the ground
	_ellipse(g, Vector2(9.0 * s, 3.5 * s), Color(0, 0, 0, 0.12))
	var p := _screen(p3)
	var flap := absf(sin(_t * 16.0 * float(b["spd"]) + float(b["ph"])))
	var col: Color = b["col"]
	var edge := col.darkened(0.45)
	var w := lerpf(0.2, 1.0, flap)  # wing span as the wings beat
	var tgt: Vector3 = b["t"]
	var face := -1.0 if tgt.x < p3.x else 1.0
	draw_set_transform(p, 0.0, Vector2(s * face, s))
	for side in [-1.0, 1.0]:
		var up := PackedVector2Array([Vector2(0, 0), Vector2(side * 9.0 * w, -10.0), Vector2(side * 12.0 * w, -4.0),
			Vector2(side * 3.0 * w, 1.0)])
		var low := PackedVector2Array([Vector2(0, 1), Vector2(side * 8.0 * w, 3.0), Vector2(side * 6.0 * w, 8.0),
			Vector2(side * 1.5 * w, 4.0)])
		draw_colored_polygon(up, col)
		draw_colored_polygon(low, col.darkened(0.1))
		draw_polyline(up + PackedVector2Array([up[0]]), edge, 1.0)
	draw_line(Vector2(0, -3), Vector2(0, 5), Color(0.2, 0.15, 0.1), 2.0)
	draw_set_transform(Vector2.ZERO)
