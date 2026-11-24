extends Node
## Online game, two players in one process: two complete games (scenes/main.tscn) talk through the room server.
## Run a local server first (npx wrangler@4 dev -c tools/build/cloudflare/wrangler.jsonc --port 8787), then:
## godot --headless --path game res://tests/online_test.tscn -- --online-url ws://127.0.0.1:8787/api
## Covers: create + join by code, moves both ways, mate, rematch (colours swapped), a dropped line caught up,
## resignation.

var a: Node  ## the host
var b: Node  ## the guest
var ok := true


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	a = scene.instantiate()
	b = scene.instantiate()
	add_child(a)
	add_child(b)
	await get_tree().process_frame
	for m in [a, b]:
		m.game.choreo.enabled = false  # instant moves: the test is about the line, not the staging
	a.online.host("white", "forest")
	await _until(func() -> bool: return a.online.code.length() == 6, "code reçu")
	print("code : ", a.online.code)
	b.online.join(a.online.code.to_lower())
	await _until(func() -> bool: return a.net_game == 1 and b.net_game == 1, "partie lancée des deux côtés")
	_check(a.side == "white" and b.side == "black", "couleurs : hôte blanc, invité noir")
	_check(b.game.board_key == "forest", "plateau de l'hôte chez l'invité")
	# scholar's mate: e4 e5 Qh5 Nc6 Bc4 Nf6 Qxf7#
	var plan := [[a, 12, 28], [b, 52, 36], [a, 3, 39], [b, 57, 42], [a, 5, 26], [b, 62, 45], [a, 39, 53]]
	for i in plan.size():
		var who: Node = plan[i][0]
		await _click(who, plan[i][1], plan[i][2])
		await _until(func() -> bool: return a.game.uci_moves.size() == i + 1 and b.game.uci_moves.size() == i + 1, "coup %d reçu" % (i + 1))
	await _until(func() -> bool: return a.game.over and b.game.over, "mat des deux côtés")
	_check(" ".join(a.game.uci_moves) == " ".join(b.game.uci_moves), "mêmes coups des deux côtés")
	# rematch: both ask, colours swap
	a._restart()
	await get_tree().create_timer(0.3).timeout
	_check(a.net_game == 1, "pas de revanche tant qu'un seul la demande")
	b._restart()
	await _until(func() -> bool: return a.net_game == 2 and b.net_game == 2, "revanche lancée")
	_check(a.side == "black" and b.side == "white", "couleurs échangées")
	for m in [a, b]:
		m.game.choreo.enabled = false
	# the host's line drops; the guest plays meanwhile; the host comes back and catches up
	a.online.line_changed.connect(func(up: bool) -> void: print("  ligne hôte : ", "rétablie" if up else "coupée", " à ", Time.get_ticks_msec()))
	print("  coupure à ", Time.get_ticks_msec())
	a.online._ws.close()
	await get_tree().create_timer(0.5).timeout
	await _click(b, 12, 28)
	var t0 := Time.get_ticks_msec()
	await _until(func() -> bool: return a.game.uci_moves.size() == 1, "coup rattrapé après la reconnexion", 10.0)
	print("  rattrapage en %d ms" % (Time.get_ticks_msec() - t0))
	await _click(a, 52, 36)
	await _until(func() -> bool: return b.game.uci_moves.size() == 2, "coup après reconnexion reçu")
	# the guest resigns
	b.hud.resign_requested.emit()
	await _until(func() -> bool: return a.game.over, "abandon reçu")
	print("ONLINE_TEST ", "OK" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)


func _click(m: Node, from: int, to: int) -> void:
	await _until(func() -> bool: return not m.game.busy and m.game.is_human_turn() and not m.game.over, "tour du joueur")
	m.game._on_square_clicked(from)
	m.game._on_square_clicked(to)


func _until(cond: Callable, what: String, limit := 6.0) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(cond.call(), what)


func _check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  ÉCHEC ") + what)
	if not c:
		ok = false
