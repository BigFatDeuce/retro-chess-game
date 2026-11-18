class_name Piece
extends Node2D
## One chess piece on the board: its creature (FlashSprite) standing on a base of its side's colour
## (ivory / obsidian), so the side reads at a glance whatever the creature looks like.
## The node sits on the creature's feet; BoardView gives its perspective scale.

const BASE_RX := 66.0  ## base radius across, front-row layout px
const BASE_RY := 38.0

var side := "white"  ## "white" | "black"
var role := "pawn"
var def: Dictionary = {}
var sprite: FlashSprite
var square := -1
var ghost: PieceGhost  ## see-through copy drawn above everything while another piece hides this one
var hidden_amount := 0.0  ## 0..1, set by the game from the overlap with the pieces in front
var base_alpha := 1.0:
	set(v):
		base_alpha = v
		queue_redraw()


func setup(p_side: String, p_role: String, p_def: Dictionary) -> void:
	side = p_side
	role = p_role
	def = p_def
	name = "%s_%s" % [side, role]
	sprite = FlashSprite.new()
	add_child(sprite)
	sprite.set_atlas(Atlas.get_atlas(Atlas.piece_path(side, role)))
	if sprite.atlas and sprite.atlas.meta.get("classic", false):
		sprite.sound_db = -6.0  # a hop at every step: kept soft
	ghost = PieceGhost.new()
	ghost.piece = self
	add_child(ghost)
	idle()


## The way a piece looks while it waits: turned toward the other army, face visible.
## The controller sets it: white looks right and black left, swapped when the board is turned for black.
var home_right := true


func home_dir() -> Vector2:
	return Vector2(1 if home_right else -1, 0.2)


func idle() -> void:
	if not sprite.play_facing("static", home_dir(), true):
		sprite.play("static_R")
	if sprite.atlas and sprite.atlas.meta.get("classic", false):
		sprite.seek_random()  # the classic pieces breathe, each at its own pace


## Plays an animation toward `dir` and waits until it ends (never longer than `cap` seconds).
func play_and_wait(base: String, dir: Vector2, cap := 6.0) -> void:
	if not sprite.play_facing(base, dir):
		return
	var t := 0.0
	while sprite.playing and t < cap:
		await get_tree().process_frame
		t += get_process_delta_time()


func move_anim() -> String:
	return "walk" if sprite.has_anim("walk_R") else "run"


func attack(kind: String) -> Dictionary:
	var atks: Dictionary = def.get("attacks", {})
	if kind == "ranged" and atks.has("ranged"):
		return atks["ranged"]
	return atks.get("melee", {})


func has_ranged() -> bool:
	return def.get("attacks", {}).has("ranged")


## Height of the creature above its feet (layout px, before the perspective scale).
func body_height() -> float:
	var a := sprite.atlas
	if a == null or not a.has("static_R"):
		return 80.0
	var f: Dictionary = a.anims["static_R"]["frames"][0]
	return f["origin"].y / a.density


## This piece's body on the layer (layout px), for the hidden-piece test.
func body_rect() -> Rect2:
	var r := sprite.local_rect()
	return Rect2(position + (r.position + sprite.position) * scale, r.size * scale)


func _process(delta: float) -> void:
	var want := 0.55 if hidden_amount > 0.0 else 0.0
	if want == 0.0 and not ghost.visible:
		return  # nothing to fade, nothing to draw
	ghost.modulate.a = move_toward(ghost.modulate.a, want, delta * 3.0)
	ghost.visible = ghost.modulate.a > 0.01
	if ghost.visible:
		ghost.queue_redraw()


## A discreet mark of the side under the creature: a soft contact shadow and a thin ring of the side's colour
## (ivory / obsidian) lying on the ground. The creatures themselves already differ in colour between sides.
func ring_color() -> Color:
	return Color("fff4dc") if side == "white" else Color("2b1f3a")


func ring_points() -> PackedVector2Array:
	var r := _ellipse(BASE_RX, BASE_RY, 0.0)
	r.append(r[0])
	return r


func _draw() -> void:
	var ring := ring_color()
	var glow := Color("ffffff") if side == "white" else Color("8f78b8")
	var a := base_alpha
	# soft shadow: three stacked ellipses, darker at the centre
	for k in 3:
		var f := 1.0 - k * 0.22
		draw_colored_polygon(_ellipse(BASE_RX * f, BASE_RY * f, 0.0), Color(0, 0, 0, 0.13 * a))
	var r := _ellipse(BASE_RX, BASE_RY, 0.0)
	r.append(r[0])
	draw_polyline(r, Color(glow.r, glow.g, glow.b, 0.35 * a), 7.0, true)
	draw_polyline(r, Color(ring.r, ring.g, ring.b, 0.85 * a), 3.0, true)


func _ellipse(rx: float, ry: float, dy: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		pts.append(Vector2(cos(t) * rx, sin(t) * ry + dy))
	return pts
