extends Node
## Resource probe: runs the game a few seconds (title, then a game against the first opponent) and prints
## frame time, CPU-side process time, object counts and memory (static, textures, video).
## Run: godot --path game res://tests/perf_probe.tscn

var main: Node


func _ready() -> void:
	main = load("res://src/main.gd").new()
	add_child(main)
	await get_tree().create_timer(6.0).timeout
	_report("title")
	main.play("o1", "white")
	await get_tree().create_timer(6.0).timeout
	_report("game")
	_atlases()
	get_tree().quit()


func _report(tag: String) -> void:
	var P := Performance
	print("%s: fps %d, process %.2f ms, nodes %d, objects %d, static %.0f MB, textures %.0f MB, video %.0f MB, draw calls %d" % [
		tag, P.get_monitor(P.TIME_FPS), P.get_monitor(P.TIME_PROCESS) * 1000.0, P.get_monitor(P.OBJECT_NODE_COUNT),
		P.get_monitor(P.OBJECT_COUNT), P.get_monitor(P.MEMORY_STATIC) / 1048576.0,
		P.get_monitor(P.RENDER_TEXTURE_MEM_USED) / 1048576.0, P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576.0,
		P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


## Video memory by atlas (loaded pages): what the textures are spent on.
func _atlases() -> void:
	var total := 0.0
	for k: String in Atlas._cache:
		var a: Atlas = Atlas._cache[k]
		var mb := 0.0
		var n := 0
		for p in a.pages:
			if p:
				n += 1
				mb += p.get_width() * p.get_height() * 4.0 / 1048576.0
		total += mb
		print("  %s: %d / %d pages, %.0f MB (uncompressed)" % [k.get_file(), n, a.pages.size(), mb])
	print("  atlases total %.0f MB" % total)
