class_name Atlas
extends RefCounted
## Animation atlas baked by tools/build_pieces.py (format of tools/build/atlas.py).
## Each frame: page index, source rect, origin (feet / impact point) inside the rect.

static var _cache: Dictionary = {}
## Sprite set: "" = 4K (density 1.5), "_1x" = one texel per pixel at 2560x1440 (see choose_set).
static var sprite_set := "_1x"


## Picks the set from the size the game is drawn at: the 4K set only when the screen is clearly larger than
## the 2560x1440 layout (shrinking it 1.5x blurs and shimmers). A build may ship one set only.
static func choose_set(render_size: Vector2) -> void:
	var px := minf(render_size.x / 2560.0, render_size.y / 1440.0)
	var want := "" if px > 1.2 else "_1x"
	if not FileAccess.file_exists("res://assets/gen/pieces%s/white_king.json" % want):
		want = "_1x" if want == "" else ""
	if want != sprite_set:
		_cache.clear()
	sprite_set = want


## Classic Staunton pieces (tools/build_classic.py) instead of the creatures (Settings "classic_pieces").
static var classic := false


static func piece_path(side: String, role: String) -> String:
	if classic:
		var dir := "classic" + sprite_set
		if not FileAccess.file_exists("res://assets/gen/%s/white_king.json" % dir):
			dir = "classic_1x" if sprite_set == "" else "classic"
		return "res://assets/gen/%s/%s_%s.json" % [dir, side, role]
	return "res://assets/gen/pieces%s/%s_%s.json" % [sprite_set, side, role]


static func critter_path(key: String) -> String:
	return "res://assets/gen/critters%s/%s.json" % [sprite_set, key]


static func fx_path(fx_id: int) -> String:
	return "res://assets/gen/fx%s/fx%d.json" % [sprite_set, fx_id]

var name: String
var fps := 60.0
var density := 1.0  ## texels per layout pixel (1.5 = sharp up to 4K)
var pages: Array[Texture2D] = []  ## null until needed: use page(i)
var page_paths: PackedStringArray = []
const RESTING := ["static_R", "walk_R", "static_L", "walk_L"]  ## loaded with the atlas; the rest on demand
var anims: Dictionary = {}  ## key -> {frames: Array[Dictionary], events: Dictionary, loop: bool}
var meta: Dictionary = {}


## Loads once, then shares the atlas between every node that shows it.
static func get_atlas(json_path: String) -> Atlas:
	if _cache.has(json_path):
		return _cache[json_path]
	var a := load_from(json_path)
	if a != null:
		_cache[json_path] = a
	return a


static func load_from(json_path: String) -> Atlas:
	var text := FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		push_error("Atlas introuvable : %s" % json_path)
		return null
	var data: Dictionary = JSON.parse_string(text)
	var a := Atlas.new()
	a.name = json_path.get_file().get_basename()
	a.meta = data
	a.fps = float(data.get("fps", 60.0))
	# "page_scale": pages shrunk after baking (lighter sets); frame coordinates are scaled here
	var ps := float(data.get("page_scale", 1.0))
	a.density = float(data.get("density", 1.0)) * ps
	var dir := json_path.get_base_dir()
	for p in data["pages"]:
		a.page_paths.append(dir.path_join(p))
		a.pages.append(null)
	for key in data["anims"]:
		var src: Dictionary = data["anims"][key]
		var frames: Array[Dictionary] = []
		for f in src["frames"]:
			var r: Array = f["r"]
			var o: Array = f["o"]
			var fr := {
				"page": int(f["p"]),
				"rect": Rect2(r[0] * ps, r[1] * ps, r[2] * ps, r[3] * ps),
				"origin": Vector2(o[0], o[1]) * ps,
			}
			# "t": the frame is the picture moved about the feet: [degrees, scale x, scale y, dx, dy] (layout px)
			if f.has("t"):
				var t: Array = f["t"]
				fr["xform"] = Transform2D(deg_to_rad(float(t[0])), Vector2(float(t[1]), float(t[2])), 0.0, Vector2(float(t[3]), float(t[4])))
			frames.append(fr)
		a.anims[key] = {"frames": frames, "events": src.get("events", {}), "loop": bool(src.get("loop", false))}
	# only the pages of the resting and walking poses are loaded now: attacks, hits and deaths (most of the
	# pages, and of the video memory) come when a piece first moves (prefetch) or plays them
	for key in RESTING:
		if a.anims.has(key):
			for f: Dictionary in a.anims[key]["frames"]:
				a.page(int(f["page"]))
	return a


## Page i, loaded the first time it is asked for (waiting for a background load started by prefetch()).
func page(i: int) -> Texture2D:
	if pages[i] == null:
		var path := page_paths[i]
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			pages[i] = ResourceLoader.load_threaded_get(path) as Texture2D
		if pages[i] == null:
			pages[i] = load(path)
	return pages[i]


## Starts loading the pages not loaded yet in the background (a piece about to move: its attack follows).
func prefetch() -> void:
	for i in pages.size():
		if pages[i] == null and ResourceLoader.load_threaded_get_status(page_paths[i]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(page_paths[i])


func has(key: String) -> bool:
	return anims.has(key)


func frame_count(key: String) -> int:
	return anims[key]["frames"].size() if anims.has(key) else 0


## Seconds an animation lasts at the atlas frame rate.
func duration(key: String) -> float:
	return frame_count(key) / fps


## First frame carrying an event whose tag starts with prefix, or -1.
func first_event(key: String, prefix: String) -> int:
	if not anims.has(key):
		return -1
	var best := -1
	var ev: Dictionary = anims[key]["events"]
	for fi in ev:
		for tag in ev[fi]:
			if String(tag).begins_with(prefix):
				var n := int(fi)
				if best < 0 or n < best:
					best = n
	return best


## Highest point drawn by an animation's first frame, above the origin (layout px): where heads are.
func top_of(key: String) -> float:
	if not anims.has(key) or anims[key]["frames"].is_empty():
		return 0.0
	var f: Dictionary = anims[key]["frames"][0]
	return f["origin"].y / density
