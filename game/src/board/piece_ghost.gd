class_name PieceGhost
extends Node2D
## See-through copy of a piece, drawn above the other pieces while one of them stands in front of it
## (a pawn behind a Craqueleur): the hidden creature and its ring stay readable. Same frame as the piece,
## faded by its alpha (Piece._process).

var piece: Piece


func _ready() -> void:
	z_as_relative = false
	z_index = 4
	modulate.a = 0.0
	visible = false


func _draw() -> void:
	if piece == null or piece.sprite == null:
		return
	var ring := piece.ring_color()
	draw_polyline(piece.ring_points(), Color(ring.r, ring.g, ring.b, 0.9), 3.0, true)
	piece.sprite.draw_current(self, piece.sprite.position)
