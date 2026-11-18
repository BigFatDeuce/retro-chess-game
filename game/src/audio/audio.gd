extends Node
## Music (crossfaded, one track per context: menu, board, victory, defeat), a looping ambience per board and
## pooled sound effects. Sounds come from the local library (tools/build_audio.py): animation cues
## (`sound:<name>`) are resolved through data/sfx_map.json, game sounds through data/sounds.json.
## Volumes live on the buses (Music, Sfx, Ambient) so a settings slider never restarts anything.

const SFX_DIR := "res://assets/gen/audio/sfx/%s.mp3"
const MUSIC_DIR := "res://assets/gen/audio/music/%s.ogg"
const FADE := 1.6
const VOICES := 24
const SAME_GAP_MS := 70  ## the same sound is not started twice within this time
const SAME_MAX := 2  ## voices playing the same sound at most

var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _track := ""
var _fade: Tween
var _ambient: AudioStreamPlayer
var _ambient_key := ""
var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _last: Dictionary = {}
var _map: Dictionary = {}  ## sound name -> fx file
var _sounds: Dictionary = {}  ## data/sounds.json
var _music_db: Dictionary = {}  ## data/music.json
var muted_cues := false  ## tests: silence without changing volumes


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "Sfx", "Ambient"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -6.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), -4.0)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambient"
	add_child(_ambient)
	_ambient.finished.connect(_on_ambient_finished)
	for i in VOICES:
		var s := AudioStreamPlayer.new()
		s.bus = "Sfx"
		add_child(s)
		_pool.append(s)
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_map.json"))
	if m is Dictionary:
		for k in (m["map"] as Dictionary):
			_map[String(k).to_lower()] = m["map"][k]
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sounds.json"))
	if s is Dictionary:
		_sounds = s
	var mu: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/music.json"))
	if mu is Dictionary:
		_music_db = mu


# ---------------------------------------------------------------- music

var _picked: Dictionary = {}  ## context -> track drawn for this launch (a context listing several tracks)


## The track of a context: a list is drawn from once per launch (the title screen changes from one launch to the
## next, then keeps its tune).
func _track_of(context: String) -> String:
	var v: Variant = _music_db.get("contexts", {}).get(context, "")
	if v is Array:
		if not _picked.has(context):
			_picked[context] = String((v as Array).pick_random()) if not (v as Array).is_empty() else ""
		return _picked[context]
	return String(v)


## Plays the track of a context of data/music.json (crossfade; the same track keeps going).
func music(context: String) -> void:
	var id := _track_of(context)
	var path := MUSIC_DIR % id
	if id == "" or not ResourceLoader.exists(path):
		return
	if id == _track and _music[_active].playing:
		return
	_track = id
	var stream := load(path) as AudioStreamOggVorbis
	if stream:
		stream.loop = context != "victory" and context != "defeat"
	if _fade and _fade.is_valid():
		_fade.kill()
	var old := _music[_active]
	_active = 1 - _active
	var new := _music[_active]
	new.stop()
	new.stream = stream
	# victory and defeat open on their jingle: no fade-in that would swallow it
	var jingle := context == "victory" or context == "defeat"
	new.volume_db = 0.0 if jingle else -40.0
	new.play()
	_fade = create_tween().set_parallel(true)
	if not jingle:
		_fade.tween_property(new, "volume_db", 0.0, FADE)
	if old.playing:
		_fade.tween_property(old, "volume_db", -80.0, FADE)
	_fade.chain().tween_callback(func() -> void:
		if old != _music[_active]:
			old.stop())


func stop_music() -> void:
	_track = ""
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	for p in _music:
		if p.playing:
			_fade.tween_property(p, "volume_db", -80.0, FADE)


# ---------------------------------------------------------------- ambience

## Looping ambience of a board (data/sounds.json "ambient"); the library clips are short, so each loop
## restarts after a short random pause to avoid a mechanical repetition.
func ambient(board: String) -> void:
	_ambient_key = board
	var a: Dictionary = _sounds.get("ambient", {}).get(board, {})
	var stream := _stream(String(a.get("sound", "")))
	if stream == null:
		_ambient.stop()
		return
	_ambient.stream = stream
	_ambient.volume_db = float(a.get("db", -10.0))
	_ambient.play()


func _on_ambient_finished() -> void:
	var key := _ambient_key
	await get_tree().create_timer(randf_range(1.5, 5.0)).timeout
	if key == _ambient_key and _ambient.stream:
		_ambient.pitch_scale = randf_range(0.95, 1.05)
		_ambient.play()


# ---------------------------------------------------------------- effects

## A game sound of data/sounds.json ("game.check", "ui.click", "steps.heavy").
func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	var parts := key.split(".")
	if parts.size() != 2:
		return
	var v: Variant = _sounds.get(parts[0], {}).get(parts[1])
	if v is Array:
		v = (v as Array).pick_random()
	if v is String:
		sfx(v, volume_db, pitch)


## An animation cue (`sound:<name>` without the prefix): the creature's own attack, hit and death sounds.
func cue(name: String, volume_db := 0.0) -> void:
	if muted_cues:
		return
	sfx(name, volume_db, randf_range(0.97, 1.03))


func sfx(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _stream(name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	var id := stream.resource_path
	if now - int(_last.get(id, -1000)) < SAME_GAP_MS:
		return
	var same := 0
	for p in _pool:
		if p.playing and p.stream == stream:
			same += 1
	if same >= SAME_MAX:
		return
	_last[id] = now
	var player := _free_voice()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _free_voice() -> AudioStreamPlayer:
	var oldest := _pool[0]
	for p in _pool:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func file_of(name: String) -> String:
	var n := name.strip_edges().to_lower().replace(" ", "_").trim_suffix(".mp3")
	if n.begins_with("fx_") or ResourceLoader.exists(SFX_DIR % n):
		return n
	return String(_map.get(n, ""))


func _stream(name: String) -> AudioStream:
	if name == "":
		return null
	if _cache.has(name):
		return _cache[name]
	var f := file_of(name)
	var path := SFX_DIR % f
	var st: AudioStream = load(path) if f != "" and ResourceLoader.exists(path) else null
	_cache[name] = st
	return st
