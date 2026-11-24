extends Node
## The note of the first boards (o1..o3, not o4) and the sets' buttons at the bottom right: they swap the pieces.
## Run: godot --path game res://tests/tip_test.tscn -- <out.png>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://tip.png"
	Settings.values["pieces_tip"] = true  # not saved
	Settings.values["piece_set"] = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var ok := true
	for id in ["o1", "o2", "o3", "o4"]:
		main.play(id, "white")
		await get_tree().create_timer(0.3).timeout
		var shown: bool = main.hud._tip != null and is_instance_valid(main.hud._tip)
		print(id, " ", main.game.board_key, " note: ", shown)
		ok = ok and shown == (id != "o4")
	main.play("o1", "white")
	await get_tree().create_timer(1.6).timeout
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(out)
	print("shot ", out)
	var buttons: Array = main.hud._sets.get_children()
	ok = ok and buttons.size() == 3  # the three sets, bottom right
	buttons[2].emit_signal("pressed")  # the player picks the third set
	await get_tree().create_timer(1.5).timeout
	var piece: Node = main.game.pieces.values()[0]
	print("set ", Settings.get_value("piece_set"), " atlas ", piece.sprite.atlas.meta.get("set", ""))
	ok = ok and Settings.get_value("piece_set") == "staunton" and not bool(Settings.get_value("pieces_tip"))
	ok = ok and piece.sprite.atlas.meta.get("set", "") == "staunton"
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_staunton.png"))
	Settings.values["piece_set"] = ""  # the test leaves the player's settings as they were
	Settings.values["pieces_tip"] = true
	Settings.save()
	# back to the creatures: the name of the piece under the mouse, then the views
	Settings.values["piece_set"] = "staunton"  # still the third set (the lines above reset the value only)
	buttons[0].emit_signal("pressed")
	await get_tree().create_timer(1.0).timeout
	var sq: int = main.game.pieces.keys()[0]
	var pc: Piece = main.game.pieces[sq]
	main.game.board.hover = sq
	await get_tree().create_timer(0.8).timeout
	print("tip ", main.hud._ptip.visible, " ", main.hud._ptip_name.text, " / ", main.hud._ptip_role.text)
	ok = ok and main.hud._ptip.visible and main.hud._ptip_name.text == Lang.t(String(pc.def["name"]))
	main.hud.next_view()
	main.hud.next_view()
	print("view tilt ", main.game.camera.target_tilt)
	ok = ok and is_equal_approx(main.game.camera.target_tilt, 1.0)
	Settings.values["piece_set"] = ""
	Settings.save()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
