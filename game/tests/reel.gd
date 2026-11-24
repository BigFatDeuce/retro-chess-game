extends Node
## Showreel for the README, short: the title screen, then four boards with the three piece sets (creatures, Bonta
## against Brâkmar, classic), the tilted view, and a mate with the victory screen. One PNG per frame. The player's
## profiles and settings are changed: back them up first.
## godot --path game --resolution 1280x720 --fixed-fps 8 --audio-driver Dummy res://tests/reel.tscn -- <out_dir>

const FPS := 8
## [opponent, piece set, moves (both sides), tilt the view after the moves]
const GAMES := [
	["o1", "", ["e2e4", "d7d5", "e4d5", "d8d5", "b1c3"], true],
	["o6", "staunton", ["d2d4", "d7d5", "c2c4", "d5c4"], false],
	["o9", "classic", ["e2e4", "c7c5", "g1f3", "b8c6"], false],
	["o8", "", ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"], false],
]
var main: Node
var out_dir := ""
var rec := false
var n := 0


func _ready() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.set_value("piece_set", "")
	Settings.set_value("pieces_tip", false)
	Settings.set_value("language", "en")  # the README is in English
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.5)
	rec = true
	await _wait(2.0)
	main.menu.show_screen("opponents")
	await _wait(1.5)
	for g: Array in GAMES:
		rec = false
		Settings.set_value("piece_set", g[1])
		main.play(String(g[0]), "white")
		main.game.two_humans = true  # the reel plays both sides (the opponent's card stays on screen)
		await _wait(0.6)
		main.game.camera._zoom_at(1.15, Vector2(1280, 820))
		await _wait(1.0)
		rec = true
		await _wait(0.3)
		for i in g[2].size():
			if g == GAMES[-1] and i == g[2].size() - 1:
				main.game.two_humans = false  # the mate: a win against the champion, with its screen
			main.game.play_move(main.game.pos.move_from_uci(g[2][i]))
			while main.game.busy:
				await get_tree().process_frame
			await _wait(0.1)
		if g[3]:
			await _tilt(0.0, 1.0)  # as with the right mouse button, slowly enough for a film
			await _wait(0.8)
			await _tilt(1.0, 0.0)
			await _wait(0.6)
		await _wait(0.4)
	await _wait(3.0)  # the victory screen
	print("REEL frames ", n)
	get_tree().quit()


## Moves the camera's tilt target step by step (the camera eases the view after it, the pieces follow).
func _tilt(a: float, b: float) -> void:
	var steps := int(1.6 * FPS)
	for i in steps + 1:
		main.game.camera.target_tilt = lerpf(a, b, smoothstep(0.0, 1.0, float(i) / steps))
		await get_tree().process_frame


func _wait(s: float) -> void:
	for i in int(s * FPS):
		await get_tree().process_frame


func _process(_d: float) -> void:
	if rec:
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("f%04d.png" % n))
		n += 1
