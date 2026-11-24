extends Node
## Glove cursor: the hand follows the game (point, open over a piece of the side to move, closing into a fist
## when it is selected) and its size follows the setting. godot --path game res://tests/glove_test.tscn

var ok := true


func _ready() -> void:
	var game := ChessGame.new()
	add_child(game)
	game.two_humans = true
	game.new_game(ChessPosition.WHITE, {}, ChessPosition.START_FEN)
	await get_tree().create_timer(0.8).timeout
	game.board.hover = 36  # e5, empty
	await _frames(10)
	_check(Glove._shown == "point", "case vide : index")
	game.board.hover = 12  # e2, a white pawn
	await _frames(10)
	_check(Glove._shown == "open", "pièce à jouer : main ouverte")
	var seen: Array[String] = []
	game._on_square_clicked(12)
	for i in 30:
		await get_tree().process_frame
		if seen.is_empty() or seen.back() != Glove._shown:
			seen.append(Glove._shown)
	print("  prise : ", " → ".join(seen))
	_check(seen == ["grab1", "grab2", "fist"], "la main se referme en 3 étapes")
	game._on_square_clicked(28)
	await _frames(30)
	_check(Glove._shown == "point", "coup joué : retour à l'index")
	var s0: int = Glove._size
	Settings.set_value("cursor_size", 1.6)
	await _frames(2)
	print("  taille ", s0, " → ", Glove._size)
	_check(Glove._size > s0, "taille du curseur agrandie")
	Settings.set_value("cursor_size", 1.0)
	print("GLOVE_TEST ", "OK" if ok else "FAILED")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  ÉCHEC ") + what)
	ok = ok and c
