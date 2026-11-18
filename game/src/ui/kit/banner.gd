@tool
class_name Banner
extends Container
## A wooden plank with notched ends, like the logo's sign: the screen titles sit on it. Its single child
## (a label) is centred; the plank grows around it.

var plank_top := Pal.WOOD_HI
var plank_bottom := Pal.WOOD_LO
var pad := Vector2(110, 26)
var notch := 34.0


static func make(text: String, size := Pal.FS_H2, gold := true) -> Banner:
	var b := Banner.new()
	var l := Ui.title(text, size) if gold else Ui.label(text, "H2", size)
	b.add_child(l)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and c.visible:
			m = m.max(c.get_combined_minimum_size())
	return m + pad * 2.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			if c is Control:
				var ms: Vector2 = c.get_combined_minimum_size()
				fit_child_in_rect(c, Rect2((size - ms) * 0.5 - Vector2(0, 2), ms))


func _shape(r: Rect2) -> PackedVector2Array:
	var n := minf(notch, r.size.y * 0.45)
	var mid := r.position.y + r.size.y * 0.5
	return PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x - n, mid), r.end,
		Vector2(r.position.x, r.end.y), Vector2(r.position.x + n, mid)])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ow := Pal.OUTLINE_W
	# shadow
	var sh := _shape(Rect2(r.position + Vector2(0, 10), r.size))
	draw_colored_polygon(sh, Pal.with_alpha(Pal.SHADOW, 0.4))
	draw_colored_polygon(_shape(r), Pal.OUTLINE)
	var inner := r.grow(-ow)
	var pts := _shape(inner)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(plank_top.lerp(plank_bottom, (p.y - inner.position.y) / inner.size.y))
	draw_polygon(pts, cols)
	# wood grain: a few long darker strokes
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 4:
		var y := inner.position.y + inner.size.y * (0.22 + 0.19 * i)
		var x0 := inner.position.x + notch + rng.randf() * 60.0
		var x1 := inner.end.x - notch - rng.randf() * 60.0
		draw_line(Vector2(x0, y), Vector2(x1, y + rng.randf_range(-3, 3)), Pal.with_alpha(Pal.WOOD_LO, 0.45), 2.5, true)
	# light top edge
	draw_line(inner.position + Vector2(8, 3), Vector2(inner.end.x - 8, inner.position.y + 3), Color(1, 0.95, 0.8, 0.45), 3.0, true)
	# rivets near the ends
	var ry := inner.position.y + inner.size.y * 0.5
	for x in [inner.position.x + notch + 26.0, inner.end.x - notch - 26.0]:
		PlankBox._rivet(get_canvas_item(), Vector2(x, ry), 9.0)
