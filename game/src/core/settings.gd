extends Node
## Player settings, saved in user://settings.cfg and applied at once: volumes (on the audio buses), animation
## speed, see-through pieces, life around the board, display (full screen, window size, vertical sync, frame
## rate cap) and accessibility (fewer interface animations).

signal changed(key: String)

const PATH := "user://settings.cfg"
const VERSION := 3  ## 2: images / s capped by default (60, 30 on phones), power saving; 3: browser at the screen's own resolution by default
const BACKGROUND_FPS := 12  ## images / s while the window is in the background (power saving)
const DEFAULTS := {
	"music": 0.7,  ## 0..1
	"sfx": 0.85,
	"ambient": 0.7,
	"anim_speed": 1.0,  ## 0.75 slow, 1 normal, 1.5 fast
	"see_through": true,
	"piece_set": "",  ## the chess pieces: "" the creatures, "classic" Bonta against Brâkmar, "staunton" (Atlas.PIECE_SETS)
	"pieces_tip": true,  ## the note offering them on the first boards (until the player uses its switch)
	"ambient_life": true,
	"fullscreen": false,
	"window_size": "1600x900",  ## windowed size on desktop
	"cursor_size": 1.0,  ## the glove cursor (Glove): 0.75 small .. 1.6 very large
	"vsync": true,
	"max_fps": 60,  ## 0 = no cap (the screen's rate with vsync); FPS_CHOICES, the same on computers and phones
	"power_save": true,  ## fewer frames while nothing moves on screen and while the game is in the background
	"check_updates": true,  ## look for a new version at launch (Windows, Android)
	"language": "",  ## "fr" / "en"; "" = French
	"reduce_motion": false,  ## interface transitions and pulses kept to a minimum
	"web_resolution": 0,  ## browser: height of the picture drawn, in pixels (WEB_RESOLUTIONS); 0 = the screen's own
	"performance": false,  ## browser: performance mode for modest machines (see PERFORMANCE)
	"perf_backup": {},  ## the settings the performance mode changed, given back when it is turned off
}
const WEB_RESOLUTIONS := [0, 720, 900, 1080, 1440, 2160]  ## browser; 0 = Auto: the screen's own pixels (up to 2160)
## Performance mode: what it sets (given back when it is turned off). On top of it: the picture drawn at 720p at
## most, no edge smoothing (MSAA), and a plainer ground around the board.
const PERFORMANCE := {"ambient_life": false, "see_through": false, "reduce_motion": true}
const PERF_HEIGHT := 720
const FPS_CHOICES := [30, 60, 90, 120, 144, 0]  ## images / s offered in the settings (0 = no cap)
const WINDOW_SIZES := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]  ## shown as 720p…2160p

var values: Dictionary = DEFAULTS.duplicate()
var _started := false  ## false while the saved settings are first applied


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in DEFAULTS:
			values[k] = cf.get_value("settings", k, DEFAULTS[k])
		if int(cf.get_value("meta", "version", 1)) < 2:
			values["max_fps"] = DEFAULTS["max_fps"]  # was "no cap" by default: the game drew as fast as it could
		if bool(cf.get_value("settings", "classic_pieces", false)) and not cf.has_section_key("settings", "piece_set"):
			values["piece_set"] = "classic"  # before the third set: a switch, creatures or Bonta against Brâkmar
		if int(cf.get_value("meta", "version", 1)) < 3:
			values["web_resolution"] = 0  # was 1080p by default: blurred on larger screens
	if String(values["language"]) == "":
		values["language"] = Lang.resolve("")
	Lang.apply(String(values["language"]))
	# the audio buses exist once the Audio autoload is ready (it comes first)
	_apply_all.call_deferred()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	if values.get(key) == v:
		return
	values[key] = v
	_apply(key)
	save()
	changed.emit(key)


func save() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.set_value("meta", "version", VERSION)
	cf.save(PATH)


func _apply_all() -> void:
	for k in values:
		_apply(k)
	_started = true


func _apply(key: String) -> void:
	match key:
		"language":
			Lang.apply(String(values[key]))
		"piece_set":
			Atlas.piece_set = String(values[key]) if String(values[key]) in Atlas.PIECE_SETS else ""
		"web_resolution":
			_apply_web_height()
		"performance":
			var on := bool(values[key])
			if _started:
				_performance_preset(on)
			# edge smoothing of the 2D drawings: the costliest part for a modest graphics chip
			var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
			if not on:
				msaa = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0)) as Viewport.MSAA
			get_tree().root.msaa_2d = msaa
			_apply_web_height()
		"music", "sfx", "ambient":
			var bus := {"music": "Music", "sfx": "Sfx", "ambient": "Ambient"}[key] as String
			var i := AudioServer.get_bus_index(bus)
			if i >= 0:
				var lin := clampf(float(values[key]), 0.0, 1.0)
				AudioServer.set_bus_mute(i, lin <= 0.001)
				# the buses keep their own mix offset (Audio sets them); the slider scales around it
				AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.001)) + _base_db(bus))
		"fullscreen":
			if OS.has_feature("mobile"):
				return
			# browser: full screen needs a gesture of the player (F11, the switch); never at start-up
			if OS.has_feature("web") and not _started:
				values[key] = false
				return
			var full := bool(values[key])
			var mode := DisplayServer.window_get_mode()
			var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if full != is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
				if not full:
					_apply("window_size")
			if not full:
				_window_frame()
		"window_size":
			if OS.has_feature("mobile") or OS.has_feature("web") or bool(values["fullscreen"]):
				return
			# a size given on the command line (tests, captures) wins: at start-up, the window is only resized
			# when it opened at the project's default size
			if DisplayServer.get_name() == "headless":
				return
			if not _started and DisplayServer.window_get_size() != Vector2i(1600, 900):
				return
			var parts := String(values[key]).split("x")
			if parts.size() != 2:
				return
			var want := Vector2i(int(parts[0]), int(parts[1]))
			# never larger than the screen the window is on
			var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
			want = Vector2i(mini(want.x, usable.x), mini(want.y, usable.y))
			if DisplayServer.window_get_size() != want:
				DisplayServer.window_set_size(want)
				var at := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
				DisplayServer.window_set_position(at.position + (at.size - want) / 2)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values[key]) else DisplayServer.VSYNC_DISABLED)
		"max_fps", "power_save":
			_apply_fps()


## Turning the performance mode on sets PERFORMANCE and remembers the values it replaced; turning it off gives
## them back (unless the player changed them in between).
## Windowed on a computer: always the system frame with its buttons (close, minimise, maximise) and a resizable
## window; only full screen goes without.
func _window_frame() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)


## F11: full screen on and off (computers and browsers: the page keeps the key for itself, so the game does it).
func _input(event: InputEvent) -> void:
	if OS.has_feature("mobile"):
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F11:
		set_value("fullscreen", not _is_full())
		get_viewport().set_input_as_handled()


func _is_full() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


var _full_check := 0.0


## Browser: the player may leave full screen with Escape (the page does it): the setting follows.
func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_full_check -= delta
	if _full_check > 0.0:
		return
	_full_check = 0.5
	if bool(values["fullscreen"]) != _is_full():
		values["fullscreen"] = _is_full()
		changed.emit("fullscreen")


func _performance_preset(on: bool) -> void:
	if on:
		var backup := {}
		for k in PERFORMANCE:
			backup[k] = values[k]
		values["perf_backup"] = backup
		for k in PERFORMANCE:
			set_value(k, PERFORMANCE[k])
	else:
		var backup: Dictionary = values.get("perf_backup", {})
		for k in backup:
			if values.get(k) == PERFORMANCE.get(k):
				set_value(k, backup[k])
		values["perf_backup"] = {}
		save()


func performance() -> bool:
	return bool(values.get("performance", false))


## Browser: the height of the picture the game draws (the page scales it to the window). The page's own script
## (export_game.py, DPR_SHIM) lowers the device pixel ratio the engine sees until the picture fits.
func _apply_web_height() -> void:
	if not OS.has_feature("web"):
		return
	var h := int(values["web_resolution"])
	if h <= 0:
		h = 2160  # Auto: never above the screen's own pixels (the page's shim caps at them)
	if bool(values["performance"]):
		h = mini(h, PERF_HEIGHT)
	JavaScriptBridge.eval("window.rcSetHeight && window.rcSetHeight(%d)" % clampi(h, 360, 2160))


var _background := false  ## the window has lost the focus / is minimised


## Images / s: the setting, or BACKGROUND_FPS in the background when power saving is on.
func _apply_fps() -> void:
	var fps := int(values["max_fps"])
	if _background and bool(values["power_save"]):
		fps = BACKGROUND_FPS if fps == 0 else mini(fps, BACKGROUND_FPS)
	Engine.max_fps = fps


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_background = true
			_apply_fps()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_background = false
			_apply_fps()


func _base_db(bus: String) -> float:
	return {"Music": -6.0, "Ambient": -4.0}.get(bus, 0.0)
