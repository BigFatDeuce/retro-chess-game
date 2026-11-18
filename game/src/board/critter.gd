class_name Critter
extends Node2D
## A small creature of the local library living around the board (data/critters.json): it wanders off the
## board, stops, plays its idle emote now and then and goes on. A scared one (Tofu) runs off when a piece
## passes close by. It never steps on the board and keeps clear of the standing decor.
## Works in the board's display coordinates (u across, v in depth, as BoardView.project).

const BOARD_CLEAR := 0.75  ## squares kept between a critter and the board's frame
const SCARE_DIST := 2.0  ## squares: a piece moving this close sends a scared critter running

var board: BoardView
var def: Dictionary = {}
var sprite: FlashSprite
var uv := Vector2.ZERO
var behaviour := "wander"

var _speed := 0.5
var _target := Vector2.ZERO
var _state := "idle"
var _wait := 0.0
var _check := 0.0
var _seen: Dictionary = {}  ## piece instance id -> last position (only a moving piece is frightening)


func setup(p_board: BoardView, key: String, p_def: Dictionary) -> bool:
	board = p_board
	def = p_def
	behaviour = String(def.get("behaviour", "wander"))
	_speed = float(def.get("speed", 0.5))
	var at := Atlas.get_atlas(Atlas.critter_path(key))
	if at == null:
		return false
	sprite = FlashSprite.new()
	sprite.sounds = false  # their clips chirp on every step: far too busy next to the game
	sprite.set_atlas(at)
	add_child(sprite)
	name = key
	return true


func _ready() -> void:
	uv = free_point()
	_place()
	board.view_changed.connect(_place)  # the view tilts: a critter at rest stays on its spot of ground
	_wait = randf_range(0.0, 3.0)
	sprite.play_facing("static", Vector2(randf_range(-1, 1), 0.3))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.16))
	draw_circle(Vector2.ZERO, 17.0, Color(0, 0, 0, 0.12))


# --- where it may go -------------------------------------------------------------------------------------------------

## Half-width (squares) of what the screen shows at depth v, minus a margin.
func _half_view(v: float) -> float:
	return 1280.0 / (BoardView.SQUARE * board.scale_at(v)) - 0.5


func allowed(p: Vector2) -> bool:
	var e := BoardView.BORDER + BOARD_CLEAR
	if p.x > -e and p.x < 8.0 + e and p.y > -e and p.y < 8.0 + e:
		return false
	if p.y < -0.35 or p.y > 11.5 or absf(p.x - 4.0) > _half_view(p.y):
		return false
	for o in board.obstacles:
		if Vector2(o.x, o.y).distance_to(p) < o.z:
			return false
	return true


func free_point() -> Vector2:
	for i in 60:
		var side := randi() % 3
		var p: Vector2
		match side:
			0:
				p = Vector2(randf_range(-3.5, -BoardView.BORDER - BOARD_CLEAR), randf_range(-0.3, 9.5))
			1:
				p = Vector2(randf_range(8.0 + BoardView.BORDER + BOARD_CLEAR, 11.5), randf_range(-0.3, 9.5))
			_:
				p = Vector2(randf_range(-2.5, 10.5), randf_range(8.0 + BoardView.BORDER + BOARD_CLEAR, 10.8))
		if allowed(p):
			return p
	return Vector2(-1.8, 2.0)


## A point a short walk away, on the same side of the board, with a clear straight path.
func _next_point(max_dist: float) -> Vector2:
	for i in 30:
		var a := randf() * TAU
		var p := uv + Vector2(cos(a), sin(a) * 0.8) * randf_range(0.6, max_dist)
		if allowed(p) and _clear_path(uv, p):
			return p
	return uv


func _clear_path(a: Vector2, b: Vector2) -> bool:
	for i in range(1, 6):
		if not allowed(a.lerp(b, i / 6.0)):
			return false
	return true


# --- life ------------------------------------------------------------------------------------------------------------

func _place() -> void:
	position = board.project(uv.x, uv.y)
	scale = Vector2.ONE * board.scale_at(uv.y)


func _process(delta: float) -> void:
	if board == null:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		if behaviour == "scared" and _state != "flee":
			_watch_pieces()
	match _state:
		"idle":
			_wait -= delta
			if _wait <= 0.0:
				_choose()
		"emote":
			if not sprite.playing:
				_rest()
		"walk", "flee":
			var sp := _speed * (2.6 if _state == "flee" else 1.0) * delta
			var to := _target - uv
			if to.length() <= sp:
				uv = _target
				_place()
				_rest()
			else:
				uv += to.normalized() * sp
				_place()


func _choose() -> void:
	var r := randf()
	if r < 0.25 and sprite.has_anim("bonus_R"):
		_state = "emote"
		sprite.play_facing("bonus", Vector2(-1.0 if sprite.flip_h else 1.0, 0.3))
		return
	var dist := 1.4 if behaviour == "graze" else 2.4
	_walk_to(_next_point(dist), false)


func _walk_to(p: Vector2, flee: bool) -> void:
	if p.distance_to(uv) < 0.05:
		_rest()
		return
	_target = p
	_state = "flee" if flee else "walk"
	var dir := board.project(p.x, p.y) - board.project(uv.x, uv.y)
	sprite.play_facing("run" if flee and sprite.has_anim("run_R") else "walk", dir, false)


func _rest() -> void:
	_state = "idle"
	_wait = randf_range(1.5, 6.0) * (1.8 if behaviour == "graze" else 1.0)
	sprite.play_facing("static", Vector2(-1.0 if sprite.flip_h else 1.0, 0.3))


func _watch_pieces() -> void:
	var layer := get_parent()
	for n in layer.get_children():
		if n is Piece and is_instance_valid(n):
			var pp := (n as Piece).position
			var id := n.get_instance_id()
			var moved := _seen.has(id) and (_seen[id] as Vector2).distance_to(pp) > 2.0
			_seen[id] = pp
			var puv := board.unproject(pp)
			if moved and puv.distance_to(uv) < SCARE_DIST:
				var away := (uv - puv).normalized()
				var p := uv + away * 2.0
				if allowed(p) and _clear_path(uv, p):
					_walk_to(p, true)
				return
