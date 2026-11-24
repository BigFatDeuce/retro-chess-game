extends Node
## End of an online game against a profile character: the full figure (art/npc_<gfx>.png), never the bust.
## Run: godot --path game --resolution 1280x720 res://tests/result_art_test.tscn -- <out.png> [npc_<gfx>]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://result_art.png"
	var avatar := args[1] if args.size() > 1 else "npc_9036"
	var m: Node = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await get_tree().process_frame
	m.net_game = 1
	m.net_opp = {"name": "Ami", "avatar": avatar, "remote": true, "board": "prairie"}
	m.side = "white"
	m._start()
	await get_tree().create_timer(1.0).timeout
	m.hud.show_result({"result": -1, "winner": 1, "human_won": false, "resigned": true, "moves": 2}, false)
	await get_tree().create_timer(2.5).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("RESULT_ART saved")
	get_tree().quit()
