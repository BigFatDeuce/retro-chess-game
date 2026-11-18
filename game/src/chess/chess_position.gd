class_name ChessPosition
extends RefCounted
## Complete rules of international chess: legal move generation, make/unmake, check, mate,
## stalemate, castling, en passant, promotion, repetition, fifty-move rule, insufficient material,
## FEN import/export with validation, SAN and UCI notation.
##
## Board: 64 squares, a1 = 0, h1 = 7, a8 = 56. Piece codes: type | colour << 3 (0 = empty).
## Moves are packed ints: from | to << 6 | promo << 12 | flags << 16.

enum { EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6 }
enum { WHITE = 0, BLACK = 1 }
const FLAG_CAPTURE := 1
const FLAG_EP := 2
const FLAG_CASTLE := 4
const FLAG_DOUBLE := 8
const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8
const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const PIECE_CHARS := ".pnbrqk"

const KNIGHT_D := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_D := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const BISHOP_D := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const ROOK_D := [[1, 0], [-1, 0], [0, 1], [0, -1]]

# Precomputed target lists (filled once).
static var _knight_targets: Array = []
static var _king_targets: Array = []
static var _rays: Array = []  # _rays[sq][dir 0..7] -> PackedInt32Array, dirs 0-3 rook, 4-7 bishop
static var _zobrist_piece: PackedInt64Array
static var _zobrist_side: int
static var _zobrist_castle: PackedInt64Array
static var _zobrist_ep: PackedInt64Array
static var _ready := false

var board := PackedInt32Array()
var side := WHITE
var castling := 0
var ep_square := -1
var halfmove := 0
var fullmove := 1
var king_sq := PackedInt32Array([4, 60])
var hash := 0
var _undo: Array = []  # [move, captured, castling, ep, halfmove, hash]
var _hash_history: PackedInt64Array = PackedInt64Array()


static func _init_tables() -> void:
	if _ready:
		return
	_ready = true
	for sq in 64:
		var f := sq % 8
		var r := sq / 8
		var kn := PackedInt32Array()
		for d in KNIGHT_D:
			var nf: int = f + d[0]
			var nr: int = r + d[1]
			if nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
				kn.append(nr * 8 + nf)
		_knight_targets.append(kn)
		var kg := PackedInt32Array()
		for d in KING_D:
			var nf: int = f + d[0]
			var nr: int = r + d[1]
			if nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
				kg.append(nr * 8 + nf)
		_king_targets.append(kg)
		var rays := []
		for d in ROOK_D + BISHOP_D:
			var ray := PackedInt32Array()
			var nf: int = f + d[0]
			var nr: int = r + d[1]
			while nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
				ray.append(nr * 8 + nf)
				nf += d[0]
				nr += d[1]
			rays.append(ray)
		_rays.append(rays)
	# Deterministic Zobrist keys (fixed seed: hashes are stable between runs).
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EC7E55
	_zobrist_piece = PackedInt64Array()
	_zobrist_piece.resize(16 * 64)
	for i in 16 * 64:
		_zobrist_piece[i] = _rand64(rng)
	_zobrist_side = _rand64(rng)
	_zobrist_castle = PackedInt64Array()
	_zobrist_castle.resize(16)
	for i in 16:
		_zobrist_castle[i] = _rand64(rng)
	_zobrist_ep = PackedInt64Array()
	_zobrist_ep.resize(8)
	for i in 8:
		_zobrist_ep[i] = _rand64(rng)


static func _rand64(rng: RandomNumberGenerator) -> int:
	return (rng.randi() << 32) ^ rng.randi()


func _init(fen: String = START_FEN) -> void:
	_init_tables()
	var err := set_fen(fen)
	if err != "":
		push_error("ChessPosition: invalid FEN (%s): %s" % [err, fen])
		set_fen(START_FEN)


# ------------------------------------------------------------------ helpers
static func piece_type(p: int) -> int:
	return p & 7


static func piece_color(p: int) -> int:
	return p >> 3


static func make_piece(t: int, c: int) -> int:
	return t | (c << 3)


static func move_from(m: int) -> int:
	return m & 63


static func move_to(m: int) -> int:
	return (m >> 6) & 63


static func move_promo(m: int) -> int:
	return (m >> 12) & 7


static func move_flags(m: int) -> int:
	return (m >> 16) & 15


static func encode(from: int, to: int, promo: int = 0, flags: int = 0) -> int:
	return from | (to << 6) | (promo << 12) | (flags << 16)


static func sq_name(sq: int) -> String:
	return "abcdefgh"[sq % 8] + str(sq / 8 + 1)


static func sq_from_name(s: String) -> int:
	if s.length() != 2:
		return -1
	var f := "abcdefgh".find(s[0])
	var r := "12345678".find(s[1])
	if f < 0 or r < 0:
		return -1
	return r * 8 + f


func duplicate_position() -> ChessPosition:
	var p := ChessPosition.new(get_fen())
	p._hash_history = _hash_history.duplicate()
	return p


# ------------------------------------------------------------------ FEN
## Loads a FEN; returns "" on success or a description of why the position is illegal.
func set_fen(fen: String) -> String:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 4:
		return "champs manquants"
	var b := PackedInt32Array()
	b.resize(64)
	var rows := parts[0].split("/")
	if rows.size() != 8:
		return "8 rangées attendues"
	for i in 8:
		var r := 7 - i
		var f := 0
		for ch in rows[i]:
			if ch.is_valid_int():
				f += int(ch)
			else:
				var lower := ch.to_lower()
				var t := PIECE_CHARS.find(lower)
				if t <= 0 or f > 7:
					return "pièce inconnue '%s'" % ch
				b[r * 8 + f] = make_piece(t, WHITE if ch != lower else BLACK)
				f += 1
		if f != 8:
			return "rangée %d incomplète" % (r + 1)
	var s := WHITE if parts[1] == "w" else (BLACK if parts[1] == "b" else -1)
	if s < 0:
		return "trait invalide"
	var c := 0
	if parts[2] != "-":
		for ch in parts[2]:
			match ch:
				"K": c |= CASTLE_WK
				"Q": c |= CASTLE_WQ
				"k": c |= CASTLE_BK
				"q": c |= CASTLE_BQ
				_: return "roques invalides"
	var ep := -1
	if parts[3] != "-":
		ep = sq_from_name(parts[3])
		if ep < 0:
			return "case en passant invalide"
	board = b
	side = s
	castling = c
	ep_square = ep
	halfmove = int(parts[4]) if parts.size() > 4 else 0
	fullmove = int(parts[5]) if parts.size() > 5 else 1
	_undo.clear()
	var err := _validate()
	if err != "":
		return err
	hash = compute_hash()
	_hash_history = PackedInt64Array([hash])
	return ""


func _validate() -> String:
	var kings := [0, 0]
	var counts := [[0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]]
	for sq in 64:
		var p := board[sq]
		if p == EMPTY:
			continue
		var t := piece_type(p)
		var col := piece_color(p)
		counts[col][t] += 1
		if t == KING:
			kings[col] += 1
			king_sq[col] = sq
		if t == PAWN and (sq < 8 or sq >= 56):
			return "pion sur la première ou la dernière rangée"
	if kings[0] != 1 or kings[1] != 1:
		return "chaque camp doit avoir exactement un roi"
	for col in 2:
		if counts[col][PAWN] > 8:
			return "plus de 8 pions"
		var extra := maxi(0, counts[col][QUEEN] - 1) + maxi(0, counts[col][ROOK] - 2) \
			+ maxi(0, counts[col][BISHOP] - 2) + maxi(0, counts[col][KNIGHT] - 2)
		if counts[col][PAWN] + extra > 8:
			return "trop de pièces promues"
	var kd := absi(king_sq[0] % 8 - king_sq[1] % 8) + 0
	if maxi(kd, absi(king_sq[0] / 8 - king_sq[1] / 8)) <= 1:
		return "rois adjacents"
	if is_square_attacked(king_sq[1 - side], side):
		return "le camp qui n'a pas le trait est en échec"
	# Castling rights need king and rook on their original squares.
	if castling & CASTLE_WK and (board[4] != make_piece(KING, WHITE) or board[7] != make_piece(ROOK, WHITE)):
		castling &= ~CASTLE_WK
	if castling & CASTLE_WQ and (board[4] != make_piece(KING, WHITE) or board[0] != make_piece(ROOK, WHITE)):
		castling &= ~CASTLE_WQ
	if castling & CASTLE_BK and (board[60] != make_piece(KING, BLACK) or board[63] != make_piece(ROOK, BLACK)):
		castling &= ~CASTLE_BK
	if castling & CASTLE_BQ and (board[60] != make_piece(KING, BLACK) or board[56] != make_piece(ROOK, BLACK)):
		castling &= ~CASTLE_BQ
	if ep_square >= 0:
		var expect_rank := 5 if side == WHITE else 2
		var pawn_sq := ep_square - 8 if side == WHITE else ep_square + 8
		if ep_square / 8 != expect_rank or board[pawn_sq] != make_piece(PAWN, 1 - side) or board[ep_square] != EMPTY:
			ep_square = -1
	return ""


func get_fen() -> String:
	var out := ""
	for r in range(7, -1, -1):
		var empty := 0
		for f in 8:
			var p := board[r * 8 + f]
			if p == EMPTY:
				empty += 1
				continue
			if empty:
				out += str(empty)
				empty = 0
			var ch: String = PIECE_CHARS[piece_type(p)]
			out += ch.to_upper() if piece_color(p) == WHITE else ch
		if empty:
			out += str(empty)
		if r > 0:
			out += "/"
	var cs := ""
	if castling & CASTLE_WK: cs += "K"
	if castling & CASTLE_WQ: cs += "Q"
	if castling & CASTLE_BK: cs += "k"
	if castling & CASTLE_BQ: cs += "q"
	if cs == "":
		cs = "-"
	return "%s %s %s %s %d %d" % [out, "w" if side == WHITE else "b", cs,
		sq_name(ep_square) if ep_square >= 0 else "-", halfmove, fullmove]


func compute_hash() -> int:
	var h := 0
	for sq in 64:
		if board[sq] != EMPTY:
			h ^= _zobrist_piece[board[sq] * 64 + sq]
	if side == BLACK:
		h ^= _zobrist_side
	h ^= _zobrist_castle[castling]
	if ep_square >= 0 and _ep_capturable():
		h ^= _zobrist_ep[ep_square % 8]
	return h


## En passant only counts for repetition when a pawn could actually capture.
func _ep_capturable() -> bool:
	var pawn := make_piece(PAWN, side)
	var f := ep_square % 8
	var r := ep_square / 8 + (-1 if side == WHITE else 1)
	for df in [-1, 1]:
		var nf: int = f + df
		if nf >= 0 and nf < 8 and board[r * 8 + nf] == pawn:
			return true
	return false


# ------------------------------------------------------------------ attacks
func is_square_attacked(sq: int, by: int) -> bool:
	var f := sq % 8
	var r := sq / 8
	# pawns
	var pr := r - 1 if by == WHITE else r + 1
	if pr >= 0 and pr < 8:
		var pawn := make_piece(PAWN, by)
		if f > 0 and board[pr * 8 + f - 1] == pawn:
			return true
		if f < 7 and board[pr * 8 + f + 1] == pawn:
			return true
	var kn := make_piece(KNIGHT, by)
	for t in _knight_targets[sq]:
		if board[t] == kn:
			return true
	var kg := make_piece(KING, by)
	for t in _king_targets[sq]:
		if board[t] == kg:
			return true
	var rq := make_piece(ROOK, by)
	var bq := make_piece(BISHOP, by)
	var qq := make_piece(QUEEN, by)
	var rays: Array = _rays[sq]
	for d in 8:
		var slider := rq if d < 4 else bq
		for t in rays[d]:
			var p := board[t]
			if p != EMPTY:
				if p == slider or p == qq:
					return true
				break
	return false


func in_check(color: int = -1) -> bool:
	if color < 0:
		color = side
	return is_square_attacked(king_sq[color], 1 - color)


# ------------------------------------------------------------------ move generation
func pseudo_moves() -> PackedInt32Array:
	var moves := PackedInt32Array()
	var us := side
	var them := 1 - us
	for sq in 64:
		var p := board[sq]
		if p == EMPTY or piece_color(p) != us:
			continue
		match piece_type(p):
			PAWN:
				_pawn_moves(sq, us, moves)
			KNIGHT:
				for t in _knight_targets[sq]:
					var q := board[t]
					if q == EMPTY:
						moves.append(encode(sq, t))
					elif piece_color(q) == them:
						moves.append(encode(sq, t, 0, FLAG_CAPTURE))
			KING:
				for t in _king_targets[sq]:
					var q := board[t]
					if q == EMPTY:
						moves.append(encode(sq, t))
					elif piece_color(q) == them:
						moves.append(encode(sq, t, 0, FLAG_CAPTURE))
				_castle_moves(sq, us, moves)
			var t_:
				var d0 := 0 if t_ != BISHOP else 4
				var d1 := 8 if t_ == QUEEN else d0 + 4
				var rays: Array = _rays[sq]
				for d in range(d0, d1):
					for t in rays[d]:
						var q := board[t]
						if q == EMPTY:
							moves.append(encode(sq, t))
						else:
							if piece_color(q) == them:
								moves.append(encode(sq, t, 0, FLAG_CAPTURE))
							break
	return moves


func _pawn_moves(sq: int, us: int, moves: PackedInt32Array) -> void:
	var dir := 8 if us == WHITE else -8
	var start_rank := 1 if us == WHITE else 6
	var promo_rank := 7 if us == WHITE else 0
	var f := sq % 8
	var one := sq + dir
	if board[one] == EMPTY:
		_add_pawn(sq, one, 0, promo_rank, moves)
		if sq / 8 == start_rank and board[one + dir] == EMPTY:
			moves.append(encode(sq, one + dir, 0, FLAG_DOUBLE))
	for df in [-1, 1]:
		var nf: int = f + df
		if nf < 0 or nf > 7:
			continue
		var t: int = one + df
		var q := board[t]
		if q != EMPTY and piece_color(q) != us:
			_add_pawn(sq, t, FLAG_CAPTURE, promo_rank, moves)
		elif t == ep_square:
			moves.append(encode(sq, t, 0, FLAG_CAPTURE | FLAG_EP))


func _add_pawn(from: int, to: int, flags: int, promo_rank: int, moves: PackedInt32Array) -> void:
	if to / 8 == promo_rank:
		for pt in [QUEEN, ROOK, BISHOP, KNIGHT]:
			moves.append(encode(from, to, pt, flags))
	else:
		moves.append(encode(from, to, 0, flags))


func _castle_moves(ksq: int, us: int, moves: PackedInt32Array) -> void:
	var them := 1 - us
	if us == WHITE and ksq == 4:
		if castling & CASTLE_WK and board[5] == EMPTY and board[6] == EMPTY \
				and not is_square_attacked(4, them) and not is_square_attacked(5, them) and not is_square_attacked(6, them):
			moves.append(encode(4, 6, 0, FLAG_CASTLE))
		if castling & CASTLE_WQ and board[3] == EMPTY and board[2] == EMPTY and board[1] == EMPTY \
				and not is_square_attacked(4, them) and not is_square_attacked(3, them) and not is_square_attacked(2, them):
			moves.append(encode(4, 2, 0, FLAG_CASTLE))
	elif us == BLACK and ksq == 60:
		if castling & CASTLE_BK and board[61] == EMPTY and board[62] == EMPTY \
				and not is_square_attacked(60, them) and not is_square_attacked(61, them) and not is_square_attacked(62, them):
			moves.append(encode(60, 62, 0, FLAG_CASTLE))
		if castling & CASTLE_BQ and board[59] == EMPTY and board[58] == EMPTY and board[57] == EMPTY \
				and not is_square_attacked(60, them) and not is_square_attacked(59, them) and not is_square_attacked(58, them):
			moves.append(encode(60, 58, 0, FLAG_CASTLE))


func legal_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	var us := side
	for m in pseudo_moves():
		make_move(m)
		if not is_square_attacked(king_sq[us], 1 - us):
			out.append(m)
		unmake_move()
	return out


func legal_moves_from(sq: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for m in legal_moves():
		if move_from(m) == sq:
			out.append(m)
	return out


# ------------------------------------------------------------------ make / unmake
const _CASTLE_MASK := {0: ~CASTLE_WQ, 4: ~(CASTLE_WK | CASTLE_WQ), 7: ~CASTLE_WK,
	56: ~CASTLE_BQ, 60: ~(CASTLE_BK | CASTLE_BQ), 63: ~CASTLE_BK}


func make_move(m: int) -> void:
	var from := move_from(m)
	var to := move_to(m)
	var flags := move_flags(m)
	var promo := move_promo(m)
	var p := board[from]
	var captured := board[to]
	var cap_sq := to
	if flags & FLAG_EP:
		cap_sq = to - 8 if side == WHITE else to + 8
		captured = board[cap_sq]
	_undo.append([m, captured, castling, ep_square, halfmove, hash])
	var h := hash
	if ep_square >= 0 and _ep_capturable():
		h ^= _zobrist_ep[ep_square % 8]
	h ^= _zobrist_castle[castling]
	if captured != EMPTY:
		board[cap_sq] = EMPTY
		h ^= _zobrist_piece[captured * 64 + cap_sq]
	board[from] = EMPTY
	h ^= _zobrist_piece[p * 64 + from]
	var placed := p if promo == 0 else make_piece(promo, side)
	board[to] = placed
	h ^= _zobrist_piece[placed * 64 + to]
	if piece_type(p) == KING:
		king_sq[side] = to
		if flags & FLAG_CASTLE:
			var rf := to + 1 if to > from else to - 2
			var rt := to - 1 if to > from else to + 1
			var rook := board[rf]
			board[rf] = EMPTY
			board[rt] = rook
			h ^= _zobrist_piece[rook * 64 + rf] ^ _zobrist_piece[rook * 64 + rt]
	castling &= _CASTLE_MASK.get(from, ~0) & _CASTLE_MASK.get(to, ~0)
	h ^= _zobrist_castle[castling]
	ep_square = (from + to) / 2 if flags & FLAG_DOUBLE else -1
	halfmove = 0 if (piece_type(p) == PAWN or captured != EMPTY) else halfmove + 1
	if side == BLACK:
		fullmove += 1
	side = 1 - side
	h ^= _zobrist_side
	if ep_square >= 0 and _ep_capturable():
		h ^= _zobrist_ep[ep_square % 8]
	hash = h
	_hash_history.append(h)


func unmake_move() -> void:
	var u: Array = _undo.pop_back()
	var m: int = u[0]
	var captured: int = u[1]
	_hash_history.resize(_hash_history.size() - 1)
	side = 1 - side
	if side == BLACK:
		fullmove -= 1
	var from := move_from(m)
	var to := move_to(m)
	var flags := move_flags(m)
	var p := board[to]
	if move_promo(m) != 0:
		p = make_piece(PAWN, side)
	board[from] = p
	board[to] = EMPTY
	if flags & FLAG_EP:
		board[to - 8 if side == WHITE else to + 8] = captured
	else:
		board[to] = captured
	if piece_type(p) == KING:
		king_sq[side] = from
		if flags & FLAG_CASTLE:
			var rf := to + 1 if to > from else to - 2
			var rt := to - 1 if to > from else to + 1
			board[rf] = board[rt]
			board[rt] = EMPTY
	castling = u[2]
	ep_square = u[3]
	halfmove = u[4]
	hash = u[5]


func ply_count() -> int:
	return _undo.size()


func last_move() -> int:
	return _undo.back()[0] if _undo.size() else -1


func captured_piece_of_last_move() -> int:
	return _undo.back()[1] if _undo.size() else EMPTY


# ------------------------------------------------------------------ game state
enum Result { ONGOING, CHECKMATE, STALEMATE, REPETITION, FIFTY_MOVES, INSUFFICIENT_MATERIAL }


func repetition_count() -> int:
	var n := 0
	# only positions since the last irreversible move can repeat
	var start := maxi(0, _hash_history.size() - 1 - halfmove)
	for i in range(start, _hash_history.size()):
		if _hash_history[i] == hash:
			n += 1
	return n


func insufficient_material() -> bool:
	var minors := []  # [type, colour, square colour]
	for sq in 64:
		var p := board[sq]
		if p == EMPTY:
			continue
		var t := piece_type(p)
		if t == KING:
			continue
		if t == PAWN or t == ROOK or t == QUEEN:
			return false
		minors.append([t, piece_color(p), (sq % 8 + sq / 8) % 2])
	if minors.size() <= 1:
		return true  # K v K, K+B v K, K+N v K
	# only bishops, all on the same square colour (any side): no mate possible
	var col := -1
	for mn in minors:
		if mn[0] != BISHOP:
			return false
		if col < 0:
			col = mn[2]
		elif mn[2] != col:
			return false
	return true


## Game status for the side to move. Draws are automatic (threefold repetition, 50 moves).
func result() -> int:
	if legal_moves().is_empty():
		return Result.CHECKMATE if in_check() else Result.STALEMATE
	if insufficient_material():
		return Result.INSUFFICIENT_MATERIAL
	if halfmove >= 100:
		return Result.FIFTY_MOVES
	if repetition_count() >= 3:
		return Result.REPETITION
	return Result.ONGOING


# ------------------------------------------------------------------ notation
func move_to_uci(m: int) -> String:
	var s := sq_name(move_from(m)) + sq_name(move_to(m))
	if move_promo(m):
		s += PIECE_CHARS[move_promo(m)]
	return s


## Finds the legal move matching a UCI string ("e2e4", "e7e8q"); -1 if none.
func move_from_uci(uci: String) -> int:
	if uci.length() < 4:
		return -1
	var from := sq_from_name(uci.substr(0, 2))
	var to := sq_from_name(uci.substr(2, 2))
	var promo := PIECE_CHARS.find(uci[4]) if uci.length() > 4 else 0
	for m in legal_moves():
		if move_from(m) == from and move_to(m) == to and move_promo(m) == promo:
			return m
	return -1


func move_to_san(m: int) -> String:
	var from := move_from(m)
	var to := move_to(m)
	var t := piece_type(board[from])
	var s := ""
	if move_flags(m) & FLAG_CASTLE:
		s = "O-O" if to > from else "O-O-O"
	else:
		var cap := move_flags(m) & FLAG_CAPTURE != 0
		if t == PAWN:
			if cap:
				s = "abcdefgh"[from % 8] + "x"
			s += sq_name(to)
			if move_promo(m):
				s += "=" + "NBRQ"[move_promo(m) - 2]
		else:
			s = "NBRQK"[t - 2]
			var same_file := false
			var same_rank := false
			var ambiguous := false
			for o in legal_moves():
				if o != m and move_to(o) == to and piece_type(board[move_from(o)]) == t:
					ambiguous = true
					if move_from(o) % 8 == from % 8:
						same_file = true
					if move_from(o) / 8 == from / 8:
						same_rank = true
			if ambiguous:
				if not same_file:
					s += "abcdefgh"[from % 8]
				elif not same_rank:
					s += str(from / 8 + 1)
				else:
					s += sq_name(from)
			if cap:
				s += "x"
			s += sq_name(to)
	make_move(m)
	if in_check():
		s += "#" if legal_moves().is_empty() else "+"
	unmake_move()
	return s


# ------------------------------------------------------------------ testing
func perft(depth: int) -> int:
	if depth == 0:
		return 1
	var n := 0
	var us := side
	for m in pseudo_moves():
		make_move(m)
		if not is_square_attacked(king_sq[us], 1 - us):
			n += 1 if depth == 1 else perft(depth - 1)
		unmake_move()
	return n
