extends Node
## Castling by clicks: king then rook (both sides, both colours), and king then its landing square.
## Run: godot --headless --path game res://tests/castle_click_test.tscn

var game: ChessGame


func _ready() -> void:
	game = ChessGame.new()
	game.two_humans = true
	add_child(game)
	game.new_game(ChessPosition.WHITE, {}, "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1")
	await get_tree().create_timer(0.5).timeout
	var ok := true
	ok = await _castle(4, 7, "e1g1") and ok      # white: king, then h1 rook
	ok = await _castle(60, 56, "e8c8") and ok    # black: king, then a8 rook
	game.new_game(ChessPosition.WHITE, {}, "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1")
	await get_tree().create_timer(0.5).timeout
	ok = await _castle(4, 2, "e1c1") and ok      # white: king, then c1 (the classic way)
	print("CASTLE_TEST ", "OK" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)


func _castle(king: int, target: int, want: String) -> bool:
	game._on_square_clicked(king)
	var marked: bool = target in game.board.targets
	game._on_square_clicked(target)
	for i in 300:
		if not game.busy:
			break
		await get_tree().process_frame
	await get_tree().process_frame
	var last := game.uci_moves[game.uci_moves.size() - 1] if not game.uci_moves.is_empty() else ""
	print("%s : marqué %s, joué %s" % [want, marked, last])
	return marked and last == want
