extends Node
## The settings' "game" tab with the three sets of pieces: sizes, and a pick changes the setting. Headless.

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var keep: Variant = Settings.values["piece_set"]
	print("saved set: ", keep, " atlas: ", Atlas.piece_set)
	var sp := SettingsPanel.new()
	add_child(sp)
	await get_tree().process_frame
	sp._show("game")
	await get_tree().create_timer(0.5).timeout
	var p: Control = sp.get_child(1)
	print("panel ", p.size, " screen 2560x1440")
	var buttons: Array = sp.find_children("*", "FxButton", true, false).filter(func(b: FxButton) -> bool: return b.button_group != null and b.get_child_count() > 0 and b.tooltip_text in ["Créatures", "Bonta / Brâkmar", "Classiques", "Creatures", "Classic"])
	print("set buttons ", buttons.size(), " ", buttons.map(func(b: FxButton) -> Vector2: return b.size))
	buttons[2].emit_signal("pressed")
	var ok: bool = buttons.size() == 3 and Settings.values["piece_set"] == "staunton" and p.size.x <= 2560 and p.size.y <= 1440
	Settings.values["piece_set"] = keep
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
