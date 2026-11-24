extends Node
## Headless: in every language, does the text stay on screen? Shows the title screen, each settings tab and a game's
## HUD, and lists the visible controls that stick out of the window or of their panel. Run:
## godot --headless --path game res://tests/lang_fit_test.tscn


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(root: Node, what: String) -> int:
	var vp := get_viewport().get_visible_rect().grow(2)
	var bad := 0
	for c: Control in root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or c.size == Vector2.ZERO:
			continue
		if not (c is Label or c is Button):
			continue
		var r := c.get_global_rect()
		if not vp.encloses(r):
			bad += 1
			print("  HORS ÉCRAN ", what, " ", c.get_class(), " ", r, " « ", c.get("text"), " »")
	return bad


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	var total := 0
	for l in Lang.LANGS:
		Settings.values["language"] = l[0]
		Lang.apply(l[0])
		await _frames(10)
		var bad := await _check(main, "menu")
		var sp := SettingsPanel.new()
		add_child(sp)
		for t in SettingsPanel.TABS:
			sp._show(t[0])
			await _frames(6)
			var p: Control = sp.get_child(1)
			print(l[0], " ", t[0], " panneau ", p.size)
			if p.size.x > 1840.0:  # the window is 1920 wide
				bad += 1
				print("  PANNEAU TROP LARGE ", l[0], " ", t[0])
			bad += await _check(sp, t[0])
		sp.queue_free()
		await _frames(2)
		print("LANG ", l[0], " : ", bad)
		total += bad
	Settings.values["pieces_tip"] = true
	for l in Lang.LANGS:
		Lang.apply(l[0])
		main.play("o1", "white")
		await _frames(40)
		var bad := await _check(main.hud, "hud")
		print("HUD ", l[0], " : ", bad, "  gauche ", main.hud._left.size, " droite ", main.hud._right.size)
		total += bad
	print("LANG_FIT ", "OK" if total == 0 else "%d DÉBORDEMENTS" % total)
	get_tree().quit()
