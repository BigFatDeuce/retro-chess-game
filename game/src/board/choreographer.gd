class_name Choreographer
extends Node
## Stages a move on the board: walks, the knight's leap, castling, captures with the attacker's real attack
## (melee, charge, projectile, beam or effect on the target), the victim's hit and death, promotion.
## It only animates: the controller applies the move to ChessPosition afterwards and checks that the board
## matches the position (never the other way round). Every wait has a time cap, so a missing animation event
## can never stall a game.

const WALK_SPEED := 2.4  ## squares per second
const RUN_SPEED := 3.6
const APPROACH := 0.6  ## a melee attacker stops this far (squares) from its victim

var board: BoardView
var layer: Node2D  ## y-sorted layer holding the pieces and the effects
var speed := 1.0  ## animation speed multiplier (settings)
var enabled := true  ## false: moves are instant

var _fx_specs: Dictionary = {}


func setup(p_board: BoardView, p_layer: Node2D, fx_specs: Dictionary) -> void:
	board = p_board
	layer = p_layer
	_fx_specs = fx_specs


# --- geometry -------------------------------------------------------------------------------------------------------

func uv_of(sq: int) -> Vector2:
	var c := board.cell_of(sq)
	return Vector2(c.x + 0.5, c.y + 0.5)


func place(p: Piece, uv: Vector2) -> void:
	p.position = board.project(uv.x, uv.y)
	p.scale = Vector2.ONE * board.scale_at(uv.y) * BoardView.PIECE_K


func place_on(p: Piece, sq: int) -> void:
	p.square = sq
	place(p, uv_of(sq))


func screen_dir(a: Vector2, b: Vector2) -> Vector2:
	return board.project(b.x, b.y) - board.project(a.x, a.y)


func _uv_of_piece(p: Piece) -> Vector2:
	var b := board.unproject(p.position)
	return b


func _wait(t: float) -> void:
	if t > 0.0:
		await get_tree().create_timer(t / speed, false).timeout


## Waits until the sprite emits an event starting with one of `prefixes`, or until `fallback` seconds passed
## (the animation's own timing when it carries no cue). Returns as soon as either happens.
func _wait_event(sprite: FlashSprite, prefixes: Array, fallback: float) -> void:
	var state := {"hit": false}
	var cb := func(tag: String) -> void:
		for pf in prefixes:
			if tag.begins_with(pf):
				state["hit"] = true
	sprite.frame_event.connect(cb)
	var t := 0.0
	while not state["hit"] and t < fallback:
		await get_tree().process_frame
		if not is_instance_valid(sprite):
			return  # the game was left during the staging
		t += get_process_delta_time() * speed
	sprite.frame_event.disconnect(cb)


## Moment of an animation where the blow lands: its first sound cue (the gesture) or its "impact" marker,
## else 45 % of its length.
func _strike_time(sprite: FlashSprite, key: String) -> float:
	var a := sprite.atlas
	if a == null or not a.has(key):
		return 0.3
	var f := a.first_event(key, "impact")
	if f < 0:
		f = a.first_event(key, "sound")
	if f <= 0:
		f = int(a.frame_count(key) * 0.45)
	return f / a.fps


func _wait_anim(p: Piece, cap := 5.0) -> void:
	var t := 0.0
	while is_instance_valid(p) and p.sprite.playing and t < cap:
		await get_tree().process_frame
		t += get_process_delta_time() * speed


# --- travel ---------------------------------------------------------------------------------------------------------

## Walks (or runs) a piece in a straight line across the board, keeping the perspective scale.
func travel(p: Piece, to_uv: Vector2, run := false) -> void:
	var from_uv := _uv_of_piece(p)
	var dist := from_uv.distance_to(to_uv)
	if dist < 0.01:
		return
	var anim := p.move_anim()
	var dir := screen_dir(from_uv, to_uv)
	# running is only drawn facing the viewer: a piece moving away walks
	if run and p.sprite.has_anim("run_" + FlashSprite.facing_suffix(dir)):
		anim = "run"
	p.sprite.play_facing(anim, dir, false)
	var dur := dist / (RUN_SPEED if run else WALK_SPEED)
	dur = minf(dur, 1.8)
	# footsteps, unless the walk clip carries its own step sounds
	var steps := _steps_of(p, p.sprite.anim)
	var step_gap := 0.2 if run else 0.29
	var next_step := 0.05
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		if not is_instance_valid(p):
			return
		t += get_process_delta_time() * speed
		place(p, from_uv.lerp(to_uv, clampf(t / dur, 0.0, 1.0)))
		if steps != "" and t >= next_step:
			next_step += step_gap
			Audio.play(steps, -7.0, randf_range(0.92, 1.08))
	place(p, to_uv)


## Footstep sound of a piece (data/sounds.json "steps"): pieces.json "steps", else by size; "" when the walk
## clip already makes its own sound.
func _steps_of(p: Piece, key: String) -> String:
	if p.sprite.atlas and p.sprite.atlas.first_event(key, "sound") >= 0:
		return ""
	var w := String(p.def.get("steps", ""))
	if w == "":
		w = {"pawn": "small", "rook": "heavy", "bishop": "small"}.get(p.role, "normal")
	return "steps." + w


## The knight's leap: a jump in an arc over the other pieces.
func leap(p: Piece, to_uv: Vector2) -> void:
	var from_uv := _uv_of_piece(p)
	Audio.play("game.leap", -3.0)
	p.sprite.play_facing(p.move_anim(), screen_dir(from_uv, to_uv), false)
	var dur := 0.75
	var t := 0.0
	p.z_index = 1
	while t < dur:
		await get_tree().process_frame
		if not is_instance_valid(p):
			return
		t += get_process_delta_time() * speed
		var k := clampf(t / dur, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		place(p, from_uv.lerp(to_uv, e))
		p.position.y -= sin(k * PI) * 110.0 * p.scale.y
	p.z_index = 0
	place(p, to_uv)
	Audio.play("game.land", -4.0)


# --- the move -------------------------------------------------------------------------------------------------------

## `info`: mover, from, to, captured (Piece or null), captured_sq, rook (Piece or null), rook_to, promo_role, knight
func play_move(info: Dictionary) -> void:
	var mover: Piece = info["mover"]
	# the attack, hit and death pages load in the background while the piece walks
	for p: Variant in [mover, info.get("captured")]:
		if p is Piece and is_instance_valid(p) and (p as Piece).sprite.atlas:
			(p as Piece).sprite.atlas.prefetch()
	var to_uv := uv_of(info["to"])
	if not enabled:
		if info.get("captured"):
			(info["captured"] as Piece).queue_free()
		place_on(mover, info["to"])
		if info.get("rook"):
			place_on(info["rook"], info["rook_to"])
		return
	var captured: Piece = info.get("captured")
	if captured:
		await _capture(mover, captured, info)
	elif info.get("rook"):
		var rook: Piece = info["rook"]
		Audio.play("game.castle", -4.0)
		travel(rook, uv_of(info["rook_to"]))
		await travel(mover, to_uv)
		await _wait(0.15)
		rook.square = info["rook_to"]
		rook.idle()
	elif info.get("knight"):
		await leap(mover, to_uv)
	else:
		var d := _uv_of_piece(mover).distance_to(to_uv)
		await travel(mover, to_uv, d > 2.5)
	mover.square = info["to"]
	mover.idle()


func _capture(att: Piece, vic: Piece, info: Dictionary) -> void:
	var a_uv := _uv_of_piece(att)
	var v_uv := uv_of(info["captured_sq"])
	var dist := a_uv.distance_to(v_uv)
	var ranged := dist > 1.6 and att.has_ranged()
	var atk := att.attack("ranged" if ranged else "melee")
	var mode := String(atk.get("mode", ""))
	var anim := String(atk.get("anim", "anim0"))
	if not ranged and not info.get("knight"):
		# walk up to the victim, stopping in front of it
		var stop := v_uv + (a_uv - v_uv).normalized() * APPROACH
		if a_uv.distance_to(stop) > 0.05:
			await travel(att, stop, dist > 2.5)
	elif not ranged and info.get("knight"):
		var stop := v_uv + (a_uv - v_uv).normalized() * APPROACH
		await leap(att, stop)
	a_uv = _uv_of_piece(att)
	var dir := screen_dir(a_uv, v_uv)
	vic.sprite.play_facing("static", -dir)
	if mode == "charge":
		await _charge(att, anim, v_uv, dir)
		_victim_hit(vic, dir)
	else:
		att.sprite.play_facing(anim, dir)
		var key := att.sprite.anim
		if ranged and atk.get("fx") != null:
			await _wait(_strike_time(att.sprite, key))
			await _spell(att, vic, int(atk["fx"]), String(atk.get("mode", "")), a_uv, v_uv)
		else:
			await _wait_event(att.sprite, ["impact", "sound"], _strike_time(att.sprite, key))
		_victim_hit(vic, dir)
	await _wait_anim(att, 4.0)
	await _wait(0.12)
	# the attacker takes the square while the victim falls
	await travel(att, uv_of(info["to"]))


## Estocade: the warrior lunges, closing the distance by the time the blade lands.
func _charge(att: Piece, anim: String, v_uv: Vector2, dir: Vector2) -> void:
	var a_uv := _uv_of_piece(att)
	var stop := v_uv + (a_uv - v_uv).normalized() * APPROACH
	att.sprite.play_facing(anim, dir)
	var hit_t := maxf(0.25, _strike_time(att.sprite, att.sprite.anim))
	var t := 0.0
	while t < hit_t:
		await get_tree().process_frame
		if not is_instance_valid(att):
			return
		t += get_process_delta_time() * speed
		var k := clampf(t / hit_t, 0.0, 1.0)
		place(att, a_uv.lerp(stop, k * k))
	place(att, stop)


func _victim_hit(vic: Piece, dir: Vector2) -> void:
	_victim_die(vic, dir)


func _victim_die(vic: Piece, dir: Vector2) -> void:
	vic.sprite.flash = 1.0
	vic.sprite.play_facing("hit", -dir)
	if vic.sprite.atlas and vic.sprite.atlas.first_event(vic.sprite.anim, "sound") < 0:
		Audio.sfx("hit_defaut", -2.0)
	await _wait(minf(0.45, vic.sprite.time_left()))
	if not is_instance_valid(vic):
		return
	vic.sprite.play_facing("die", -dir)
	var tw := create_tween()
	tw.tween_property(vic, "base_alpha", 0.0, 0.5 / speed)
	await _wait_anim(vic, 2.5)
	if not is_instance_valid(vic):
		return
	var tw2 := create_tween()
	tw2.tween_property(vic, "modulate:a", 0.0, 0.35 / speed)
	await tw2.finished
	if is_instance_valid(vic):
		vic.queue_free()


# --- spell effects --------------------------------------------------------------------------------------------------

func _fx_sprite(fx_id: int) -> FlashSprite:
	var at := Atlas.get_atlas(Atlas.fx_path(fx_id))
	if at == null:
		return null
	var s := FlashSprite.new()
	s.set_atlas(at)
	layer.add_child(s)
	return s


## Body point of a piece (a fraction of its height above its feet), in layer coordinates.
func _body(p: Piece, frac: float) -> Vector2:
	return p.position + Vector2(0, -p.body_height() * frac * p.scale.y)


## Plays the spell's own effect clip from the attacker to the victim; returns when it strikes.
func _spell(att: Piece, vic: Piece, fx_id: int, mode: String, a_uv: Vector2, v_uv: Vector2) -> void:
	if mode == "":
		mode = String(_fx_specs.get(str(fx_id), {}).get("mode", "at_target"))
	var s := _fx_sprite(fx_id)
	if s == null:
		return
	var vs := board.scale_at(v_uv.y) * BoardView.PIECE_K
	match mode:
		"at_target":
			s.position = vic.position + Vector2(0, 1)
			s.scale = Vector2.ONE * vs
			s.play("play")
			s.finished.connect(func(_a): s.queue_free())
			await _wait_event(s, ["impact"], _strike_time(s, "play"))
		"beam":
			var from := _body(att, 0.45)
			var to := _body(vic, 0.4)
			var ref := float(s.atlas.meta.get("fx", {}).get("ref_dist", 300.0))
			s.position = from
			s.rotation = (to - from).angle()
			var as_ := board.scale_at(a_uv.y) * BoardView.PIECE_K
			s.scale = Vector2(from.distance_to(to) / ref, as_)
			s.z_index = 2
			s.play("play")
			s.finished.connect(func(_a): s.queue_free())
			await _wait_event(s, ["impact"], _strike_time(s, "play"))
		"arc":
			var from := _body(att, 0.6)
			var to := _body(vic, 0.35)
			s.play("flight")
			s.z_index = 2
			var dur := clampf(from.distance_to(to) / 900.0, 0.35, 0.8)
			var t := 0.0
			while t < dur:
				await get_tree().process_frame
				if not is_instance_valid(s):
					return
				t += get_process_delta_time() * speed
				var k := clampf(t / dur, 0.0, 1.0)
				s.position = from.lerp(to, k) + Vector2(0, -sin(k * PI) * 160.0 * vs)
				s.scale = Vector2.ONE * lerpf(board.scale_at(a_uv.y) * BoardView.PIECE_K, vs, k)
				s.rotation += get_process_delta_time() * 9.0
			s.rotation = 0.0
			s.position = vic.position
			s.z_index = 0
			if not s.play("impact"):
				s.queue_free()
			else:
				s.finished.connect(func(_a): s.queue_free())


# --- moments --------------------------------------------------------------------------------------------------------

## A promoted pawn turns into its new piece in a flash of light.
func promote(old: Piece, new_piece: Piece) -> void:
	new_piece.modulate.a = 0.0
	if not enabled:
		old.queue_free()
		new_piece.modulate.a = 1.0
		return
	var hl := String(old.def.get("highlight", ""))
	if hl != "":
		old.sprite.play_facing(hl, old.home_dir())
	old.sprite.flash = 1.0
	Audio.play("game.promote")
	await _wait(0.35)
	var tw := create_tween().set_parallel()
	tw.tween_property(old, "modulate:a", 0.0, 0.3 / speed)
	tw.tween_property(new_piece, "modulate:a", 1.0, 0.3 / speed)
	new_piece.sprite.flash = 1.0
	await tw.finished
	old.queue_free()
	var hl2 := String(new_piece.def.get("highlight", ""))
	if hl2 != "":
		await new_piece.play_and_wait(hl2, new_piece.home_dir(), 3.0)
	new_piece.idle()


## The king in check rears up (its highlight animation).
func check(king: Piece) -> void:
	if not enabled or king == null:
		return
	king.sprite.flash = 0.6
	Audio.play("game.check", -3.0)
	var hl := String(king.def.get("highlight", ""))
	if hl != "":
		await king.play_and_wait(hl, king.home_dir(), 3.0)
	king.idle()


## Mate: the winning king triumphs, the mated king is struck down.
func mate(winner: Piece, loser: Piece) -> void:
	Audio.play("game.mate")
	if winner:
		var hl := String(winner.def.get("highlight", ""))
		if hl != "" and enabled:
			winner.sprite.play_facing(hl, winner.home_dir())
	if loser and enabled:
		loser.sprite.flash = 1.0
		await loser.play_and_wait("hit", loser.home_dir(), 1.5)
		await loser.play_and_wait("die", loser.home_dir(), 3.0)
		loser.sprite.stop_on_last()
