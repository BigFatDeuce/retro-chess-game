extends Node
## Window frame: F11 goes full screen and back; windowed, the system frame (close, minimise, maximise) stays.
## godot --path game res://tests/window_test.tscn

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var ok := true
	var start_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	print("  départ : ", "plein écran" if start_full else "fenêtré")
	if not start_full:
		ok = _frame("au lancement") and ok
	for i in 2:
		var ev := InputEventKey.new()
		ev.keycode = KEY_F11
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.8).timeout
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		print("  F11 n°%d : %s" % [i + 1, "plein écran" if full else "fenêtré"])
		ok = ok and full == ((i == 0) != start_full)
		if not full:
			ok = _frame("en fenêtre") and ok
	print("WINDOW_TEST ", "OK" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)


func _frame(when: String) -> bool:
	var b := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	var r := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED)
	print("  %s : cadre %s, redimensionnable %s" % [when, "non" if b else "oui", "non" if r else "oui"])
	return not b and not r
