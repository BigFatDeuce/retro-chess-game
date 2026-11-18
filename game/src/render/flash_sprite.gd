class_name FlashSprite
extends Node2D
## Plays animations baked from the vector symbols of the local library.
## The node origin is the symbol origin (a creature's feet, an effect's impact point).
## "_R" drawings face the viewer turned right (south-east), "_L" drawings show the back turned left
## (north-west); mirroring gives the two other diagonals.

signal frame_event(tag: String)
signal finished(anim: String)

var atlas: Atlas
var anim := ""
var frame := 0
var playing := false
var loop := false
var speed := 1.0
var sound_db := 0.0  ## volume of the clip's own sound cues (sound:<name>)
var sounds := true  ## false: the cues are only emitted, not played (ambient creatures far away)
var flip_h := false:
	set(v):
		flip_h = v
		queue_redraw()
var flash := 0.0:  ## white flash amount (hit), decays
	set(v):
		flash = v
		_apply_colour()
var tint := Color(1, 1, 1, 0):  ## colour overlay (rgb, strength in a)
	set(v):
		tint = v
		_apply_colour()

var _frames: Array = []
var _events: Dictionary = {}
var _t := 0.0


## Suffix of the drawing for a direction on screen: the back ("L") only when the move clearly points away.
static func facing_suffix(v: Vector2, bias := 0.35) -> String:
	return "L" if v.y < -absf(v.x) * bias else "R"


## Mirroring that makes a drawing with this suffix face `v`: R is mirrored toward the west, L toward the east.
static func facing_flip(v: Vector2, suffix: String) -> bool:
	return v.x > 0.0 if suffix == "L" else v.x < 0.0


func set_atlas(a: Atlas) -> void:
	atlas = a
	anim = ""
	_frames = []
	queue_redraw()


## Plays `base` drawn toward `v`, falling back to the "_R" drawing when the clip has no "_L".
func play_facing(base: String, v: Vector2, restart := true) -> bool:
	var suffix := facing_suffix(v)
	if suffix == "L" and (atlas == null or not atlas.has(base + "_L")):
		suffix = "R"
	if absf(v.x) > 0.01 or suffix == "L":
		flip_h = facing_flip(v, suffix)
	return play(base + "_" + suffix, restart)


## Plays `key`. Returns false when the atlas has no such animation.
func play(key: String, restart := true, force_loop: Variant = null) -> bool:
	if atlas == null or not atlas.has(key):
		return false
	if key == anim and playing and not restart:
		return true
	anim = key
	var a: Dictionary = atlas.anims[key]
	_frames = a["frames"]
	_events = a["events"]
	loop = a["loop"] if force_loop == null else bool(force_loop)
	frame = 0
	_t = 0.0
	playing = true
	_emit_events(0)
	queue_redraw()
	return true


## Jumps to a random frame of the animation playing (idle loops out of step with each other).
func seek_random() -> void:
	if _frames.size() > 1:
		frame = randi() % _frames.size()
		queue_redraw()


func has_anim(key: String) -> bool:
	return atlas != null and atlas.has(key)


func stop_on_last() -> void:
	if not _frames.is_empty():
		frame = _frames.size() - 1
	playing = false
	queue_redraw()


## Seconds left before the current animation ends (0 when looping or stopped).
func time_left() -> float:
	if not playing or loop or _frames.is_empty():
		return 0.0
	return (_frames.size() - frame - _t) / (atlas.fps * speed)


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 4.0)
	if not playing or _frames.is_empty():
		return
	_t += delta * atlas.fps * speed
	while _t >= 1.0 and playing:
		_t -= 1.0
		var nf := frame + 1
		if nf >= _frames.size():
			if loop:
				nf = 0
			else:
				playing = false
				finished.emit(anim)
				break
		frame = nf
		_emit_events(frame)
		queue_redraw()


func _emit_events(fi: int) -> void:
	var key := str(fi)
	if _events.has(key):
		for tag in _events[key]:
			var s := String(tag)
			if sounds and s.begins_with("sound:"):
				Audio.cue(s.substr(6), sound_db)
			frame_event.emit(s)


func _apply_colour() -> void:
	if flash <= 0.0 and tint.a <= 0.0:
		self_modulate = Color.WHITE
		return
	var m := Color.WHITE.lerp(Color(tint.r, tint.g, tint.b), clampf(tint.a, 0.0, 1.0))
	var f := 1.0 + flash * 1.6
	self_modulate = Color(m.r * f, m.g * f, m.b * f, 1.0)


func _draw() -> void:
	draw_current(self)


## Bounds of the current frame in this node's coordinates (feet at the origin).
func local_rect() -> Rect2:
	if _frames.is_empty():
		return Rect2()
	var f: Dictionary = _frames[frame]
	var inv := 1.0 / atlas.density
	var rect: Rect2 = f["rect"]
	var origin: Vector2 = f["origin"]
	var r := Rect2(-origin * inv, rect.size * inv)
	if flip_h:
		r.position.x = -r.end.x
	return r


## Draws the current frame onto `ci` (from ci's own _draw): the see-through ghost of a hidden piece uses it.
func draw_current(ci: CanvasItem, offset := Vector2.ZERO) -> void:
	if _frames.is_empty():
		return
	var f: Dictionary = _frames[frame]
	var tex: Texture2D = atlas.page(int(f["page"]))
	var inv := 1.0 / atlas.density
	var rect: Rect2 = f["rect"]
	var origin: Vector2 = f["origin"]
	if f.has("xform"):
		# a still picture animated by moving it (classic pieces): flip, then the frame's own move, then the density
		var m := Transform2D(0.0, Vector2(-1.0 if flip_h else 1.0, 1.0), 0.0, offset) * (f["xform"] as Transform2D) 			* Transform2D(0.0, Vector2(inv, inv), 0.0, Vector2.ZERO)
		ci.draw_set_transform_matrix(m)
	else:
		ci.draw_set_transform(offset, 0.0, Vector2(-inv if flip_h else inv, inv))
	ci.draw_texture_rect_region(tex, Rect2(-origin, rect.size), rect)
