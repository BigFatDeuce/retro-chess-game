extends SceneTree
## Rules regression tests: perft counts against published values + special cases.
## Run: godot --headless --path game -s tests/test_rules.gd

var failures := 0

func check(name: String, got, want) -> void:
	if got == want:
		print("  ok   ", name)
	else:
		failures += 1
		print("  FAIL ", name, " : obtenu ", got, ", attendu ", want)

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("perft")
	var cases := [
		["start", ChessPosition.START_FEN, [20, 400, 8902, 197281]],
		["kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862]],
		["pos3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238, 674624]],
		["pos4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]],
		["pos5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379]],
		["pos6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079, 89890]],
	]
	for c in cases:
		var p := ChessPosition.new(c[1])
		for d in c[2].size():
			check("%s d%d" % [c[0], d + 1], p.perft(d + 1), c[2][d])
		check("%s fen aller-retour" % c[0], p.get_fen(), ChessPosition.new(c[1]).get_fen())
	print("cas particuliers")
	var p := ChessPosition.new("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
	var m := p.move_from_uci("a1a8")
	check("SAN mat du couloir", p.move_to_san(m), "Ra8#")
	p.make_move(m)
	check("mat", p.result(), ChessPosition.Result.CHECKMATE)
	p = ChessPosition.new("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	check("pat", p.result(), ChessPosition.Result.STALEMATE)
	p = ChessPosition.new("8/8/4k3/8/8/2B5/4K3/8 w - - 0 1")
	check("matériel insuffisant K+F", p.result(), ChessPosition.Result.INSUFFICIENT_MATERIAL)
	p = ChessPosition.new("8/8/4k3/8/8/2N5/4K3/8 w - - 99 80")
	p.make_move(p.move_from_uci("c3d5"))
	check("matériel insuffisant prioritaire", p.result(), ChessPosition.Result.INSUFFICIENT_MATERIAL)
	p = ChessPosition.new("8/8/4k3/8/8/2R5/4K3/8 w - - 99 80")
	p.make_move(p.move_from_uci("c3c4"))
	check("50 coups", p.result(), ChessPosition.Result.FIFTY_MOVES)
	p = ChessPosition.new()
	for u in ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"]:
		p.make_move(p.move_from_uci(u))
	check("triple répétition", p.result(), ChessPosition.Result.REPETITION)
	p = ChessPosition.new("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
	m = p.move_from_uci("e5f6")
	check("prise en passant SAN", p.move_to_san(m), "exf6")
	p.make_move(m)
	check("prise en passant retire le pion", p.board[ChessPosition.sq_from_name("f5")], 0)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	check("roque SAN", p.move_to_san(p.move_from_uci("e1c1")), "O-O-O")
	p = ChessPosition.new("r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1")
	check("roque interdit en échec... (f2 attaque e1)", p.move_from_uci("e1g1"), -1)
	p = ChessPosition.new("8/P7/8/8/8/8/8/k6K w - - 0 1")
	check("4 promotions", p.legal_moves_from(ChessPosition.sq_from_name("a7")).size(), 4)
	check("promotion cavalier SAN", p.move_to_san(p.move_from_uci("a7a8n")), "a8=N")
	print("promotion et dames multiples")
	# promoting to a queen is allowed while the original queen is still on the board (FIDE 3.7.e)
	p = ChessPosition.new("4k3/P7/8/8/8/8/8/3QK3 w - - 0 1")
	m = p.move_from_uci("a7a8q")
	check("promotion en dame avec la dame encore en jeu", m >= 0, true)
	p.make_move(m)
	var queens := 0
	for sq in 64:
		if p.board[sq] == ChessPosition.make_piece(ChessPosition.QUEEN, ChessPosition.WHITE):
			queens += 1
	check("deux dames blanches", queens, 2)
	check("la nouvelle dame donne échec", p.in_check(), true)
	p = ChessPosition.new("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
	check("sous-promotion tour", p.move_from_uci("a7a8r") >= 0, true)
	check("pas de promotion en roi", p.move_from_uci("a7a8k"), -1)
	check("pion sans promotion interdit sur la dernière rangée", p.move_from_uci("a7a8"), -1)
	p = ChessPosition.new("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1")
	check("promotion en prenant", p.move_to_san(p.move_from_uci("a7b8q")), "axb8=Q+")
	p = ChessPosition.new("4k3/8/8/8/8/8/p7/4K3 b - - 0 1")
	check("promotion noire", p.move_from_uci("a2a1q") >= 0, true)
	print("roque")
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	check("petit roque permis", p.move_from_uci("e1g1") >= 0, true)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K1rR w KQkq - 0 1")
	check("roque en passant par une case attaquée (f1 par g1)", p.move_from_uci("e1g1"), -1)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	p = ChessPosition.new("1r2k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
	check("grand roque permis si seule b1 est attaquée", p.move_from_uci("e1c1") >= 0, true)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	p.make_move(p.move_from_uci("h1h2"))
	p.make_move(p.move_from_uci("a8a7"))
	p.make_move(p.move_from_uci("h2h1"))
	p.make_move(p.move_from_uci("a7a8"))
	check("tour revenue : plus de petit roque", p.move_from_uci("e1g1"), -1)
	check("autre côté toujours permis", p.move_from_uci("e1c1") >= 0, true)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	p.make_move(p.move_from_uci("a1a8"))
	check("tour prise : les noirs perdent le grand roque", p.move_from_uci("e8c8"), -1)
	p = ChessPosition.new("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1")
	check("roque bloqué par une pièce", p.move_from_uci("e1c1"), -1)
	print("prise en passant")
	p = ChessPosition.new("8/8/8/KPp4r/8/8/8/7k w - c6 0 1")
	check("prise en passant interdite si elle découvre le roi", p.move_from_uci("b5c6"), -1)
	p = ChessPosition.new("4k3/8/8/2pP4/8/8/8/4K3 w - c6 0 1")
	check("prise en passant juste après le double pas", p.move_from_uci("d5c6") >= 0, true)
	p = ChessPosition.new("4k3/2p5/8/3P4/8/8/8/4K3 b - - 0 1")
	p.make_move(p.move_from_uci("c7c5"))
	p.make_move(p.move_from_uci("e1e2"))
	p.make_move(p.move_from_uci("e8e7"))
	check("prise en passant plus possible un coup après", p.move_from_uci("d5c6"), -1)
	print("échec")
	p = ChessPosition.new("4k3/8/8/8/8/8/2n5/R3K3 w Q - 0 1")
	check("le cavalier c2 met le roi en échec", p.in_check(), true)
	check("roi en échec : seuls les coups qui parent", Array(p.legal_moves()).all(func(mm):
		var q := p.duplicate_position()
		q.make_move(mm)
		return not q.in_check(ChessPosition.WHITE)), true)
	check("pas de roque en échec", p.move_from_uci("e1c1"), -1)
	p = ChessPosition.new("4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1")
	check("pièce clouée ne peut pas quitter la ligne", p.move_from_uci("e2d3"), -1)
	print("positions illégales")
	var bad := {"deux rois blancs": "K6K/8/8/8/8/8/8/k7 w - - 0 1", "pion rangée 1": "k7/8/8/8/8/8/8/K3P3 w - - 0 1",
		"camp sans trait en échec": "k7/8/8/8/8/8/8/K6r b - - 0 1", "rois adjacents": "8/8/8/3kK3/8/8/8/8 w - - 0 1"}
	for k in bad:
		check(k, ChessPosition.new().set_fen(bad[k]) != "", true)
	print("%d échec(s) en %d ms" % [failures, Time.get_ticks_msec() - t0])
	quit(1 if failures else 0)
