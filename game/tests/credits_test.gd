extends Node
## Opens the credits from the title screen and takes a picture. Run: godot --path game res://tests/credits_test.tscn -- <out.png>


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	var menu := main.find_children("*", "MainMenu", true, false)
	(menu[0] if not menu.is_empty() else main.get("menu"))._open_credits()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("CREDITS OK")
	get_tree().quit()
