class_name GameHud
extends CanvasLayer
## In-game interface, kept in the free corners so the board is never covered: the two players' plates
## (portrait, name, strength, captured creatures, whose turn), the turn banner (check in red), the actions
## (pause, see-through, recentre, history), the move list, the pause menu with confirmations, the promotion
## choice and the end of game screen (victory, defeat, draw; the next board unlocked). No chess logic here: it
## reads the game's position and history, and asks for actions through its signals.
## Every landscape shape keeps the same corners (the board's width is fixed by the layout, extra room goes to
## the bands above and below it); under 1.2:1 the move list folds behind its button.

signal restart_requested
signal menu_requested
signal resign_requested
signal next_requested
signal path_requested  ## back to "Le Chemin des Champions" (or to the free play choices after a free game)

const VALUES := {ChessPosition.PAWN: 1, ChessPosition.KNIGHT: 3, ChessPosition.BISHOP: 3, ChessPosition.ROOK: 5, ChessPosition.QUEEN: 9}
const START_COUNT := {ChessPosition.PAWN: 8, ChessPosition.KNIGHT: 2, ChessPosition.BISHOP: 2, ChessPosition.ROOK: 2, ChessPosition.QUEEN: 1}

var game: ChessGame
var opponent: Dictionary = {}  ## data/opponents.json entry; {} = two players
var _root: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _plates: Array[Control] = [null, null]  ## by colour: WHITE, BLACK
var _banner: PanelContainer
var _banner_label: Label
var _banner_icon: Icon
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _history_scroll: ScrollContainer
var _actions: HBoxContainer
var _pause: Control
var _promo: Control
var _result: Control
var _think_t := 0.0
var _notice: PanelContainer  ## online games: the line or the friend dropped out (under the turn banner)
var _notice_label: Label
var _rematch_label: Label  ## online games: the rematch asked / waited for, on the result screen
var _wide := true


func setup(p_game: ChessGame, _a := "", _b := "") -> void:
	game = p_game
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Ui.full_rect(Control.new())
	_root.theme = UiTheme.ensure()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_left = Ui.vbox(Pal.S3)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_left)
	_right = Ui.vbox(Pal.S3)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_right)
	# actions
	_actions = Ui.hbox(Pal.S2, BoxContainer.ALIGNMENT_END)
	_right.add_child(_actions)
	var px := 104.0 if Pal.touch() else 80.0
	var acts := [["pause", "Pause (Échap)", show_pause], ["eye", "Transparence des pièces cachées (F1)", func() -> void: game.set_see_through(not game.see_through)],
		["target", "Recentrer la vue (Origine) · clic droit glissé vers le haut : se lever pour voir le plateau", func() -> void:
			_view_i = 0
			game.camera.reset()],
		["map", "Changer de vue : assis, penché, debout… (V)", next_view], ["scroll", "Historique des coups (H)", toggle_history]]
	for a in acts:
		var b := FxButton.make("", "IconButton", a[0], Vector2(px, px))
		b.tooltip_text = a[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(a[2])
		_actions.add_child(b)
	# the sets of pieces, at the bottom right
	_sets = Ui.piece_set_picker(40.0, Callable(), false, true)  # a column: the board's corner leaves little width
	_sets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in _sets.get_children():
		b.focus_mode = Control.FOCUS_NONE
	_root.add_child(_sets)
	# the name of the piece under the mouse
	_ptip = Ui.panel("Plate")
	_ptip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ptip.visible = false
	_ptip.z_index = 5
	var pv := Ui.vbox(2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ptip.add_child(pv)
	_ptip_name = Ui.label("", "", Pal.FS_SMALL)
	_ptip_name.add_theme_color_override("font_color", Pal.GOLD_HI)
	pv.add_child(_ptip_name)
	_ptip_role = Ui.label("", "", Pal.FS_SMALL - 6)
	pv.add_child(_ptip_role)
	_root.add_child(_ptip)
	# history
	_history_panel = Ui.panel("Parchment")
	_history_panel.custom_minimum_size = Vector2(420, 0)
	_right.add_child(_history_panel)
	var hv := Ui.vbox(Pal.S1)
	_history_panel.add_child(hv)
	var hh := Ui.hbox(Pal.S2)
	hv.add_child(hh)
	var hi := Icon.make("scroll", 40, Pal.PARCHMENT)
	hh.add_child(hi)
	hh.add_child(Ui.label("Coups joués", "Ink", Pal.FS_SMALL + 2))
	_history_scroll = ScrollContainer.new()
	_history_scroll.custom_minimum_size = Vector2(0, HISTORY_H)
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hv.add_child(_history_scroll)
	_history_list = Ui.vbox(2)
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.add_child(_history_list)
	# turn banner
	_banner = Ui.panel("Plate")
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	Ui.anchor_at(_banner, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	_banner.offset_top = Pal.EDGE - 8
	var bh := Ui.hbox(Pal.S2)
	_banner.add_child(bh)
	_banner_icon = Icon.make("swords", 48, Pal.GOLD_HI)
	bh.add_child(_banner_icon)
	_banner_label = Ui.label("", "", Pal.FS_BODY + 4)
	bh.add_child(_banner_label)
	# online notice, under the banner
	_notice = Ui.panel("Plate")
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	_root.add_child(_notice)
	Ui.anchor_at(_notice, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	_notice.offset_top = Pal.EDGE + 112
	var nh := Ui.hbox(Pal.S2)
	_notice.add_child(nh)
	nh.add_child(Icon.make("refresh", 40, Pal.EMBER_HI))
	_notice_label = Ui.label("", "", Pal.FS_SMALL + 2)
	nh.add_child(_notice_label)
	game.see_through_changed.connect(func(on: bool) -> void:
		Ui.toast(_root, Lang.t("Transparence activée" if on else "Transparence désactivée"), "eye_off" if not on else "eye"))
	game.turn_changed.connect(_on_turn)
	game.promotion_needed.connect(show_promotion)
	game.move_made.connect(_on_move)
	get_viewport().size_changed.connect(_relayout)
	_relayout.call_deferred()


## Online games: a line under the turn banner ("" hides it).
func notice(text: String) -> void:
	if _notice == null:
		return
	_notice_label.text = Lang.t(text) if text != "" else ""
	_notice.visible = text != ""
	if _notice.visible:
		Ui.pop_in(_notice, 0.0, 0.9)


## Online games: the rematch asked by the friend, or waited for, shown on the result screen.
func rematch_note(text: String) -> void:
	if _rematch_label and is_instance_valid(_rematch_label):
		_rematch_label.text = text
		_rematch_label.visible = true


func remote() -> bool:
	return bool(opponent.get("remote", false))


## Wide screens: plates in a column on the left, actions and history on the right. Narrower ones (4:3,
## portrait tablets): the plates go to the top-left and bottom-left bands, the history is folded.
func _relayout() -> void:
	if _root == null:
		return
	var s := _root.get_viewport_rect().size
	_wide = s.x / s.y >= 1.2  # the game is played in landscape; below that, the history folds away
	_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left.position = Vector2(Pal.EDGE, Pal.EDGE)
	_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.offset_right = -Pal.EDGE
	_right.offset_top = Pal.EDGE
	_right.offset_left = -Pal.EDGE - _right.get_combined_minimum_size().x
	_history_panel.visible = _wide and bool(_history_panel.get_meta("open", true))
	var m := _sets.get_combined_minimum_size()
	_sets.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_sets.offset_right = -Pal.EDGE
	_sets.offset_bottom = -Pal.EDGE
	_sets.offset_left = -Pal.EDGE - m.x
	_sets.offset_top = -Pal.EDGE - m.y


## The views, from seated to standing (the "map" button and V cycle through them): [name, tilt, zoom].
const VIEWS := [["Vue assise", 0.0, 1.0], ["Penché sur le plateau", 0.45, 1.12], ["Debout", 1.0, 1.0],
	["Debout, de près", 0.7, 1.3]]
var _view_i := 0
var _sets: BoxContainer  ## the three sets of pieces, bottom right
var _ptip: PanelContainer  ## the name of the piece under the mouse
var _ptip_name: Label
var _ptip_role: Label
var _ptip_sq := -1
var _ptip_t := 0.0
const PTIP_DELAY := 0.45  ## s the mouse rests on a piece before its name shows
const ROLE_NAMES := {
	"white": {"king": "Roi blanc", "queen": "Dame blanche", "rook": "Tour blanche", "bishop": "Fou blanc",
		"knight": "Cavalier blanc", "pawn": "Pion blanc"},
	"black": {"king": "Roi noir", "queen": "Dame noire", "rook": "Tour noire", "bishop": "Fou noir",
		"knight": "Cavalier noir", "pawn": "Pion noir"}}


func next_view() -> void:
	_view_i = (_view_i + 1) % VIEWS.size()
	var v: Array = VIEWS[_view_i]
	game.camera.target_tilt = float(v[1])
	game.camera.target_zoom = float(v[2])
	game.camera.target_pos = BoardCamera.HOME
	Ui.toast(_root, Lang.t(String(v[0])), "map", 1.0)


## The piece under the mouse, named after a short rest (the creature's own name, then its chess role).
func _update_piece_tip(delta: float) -> void:
	if _ptip == null or Pal.touch():
		return
	var sq := -1
	var b := game.board
	if visible and b and b.input_enabled and not (_pause and is_instance_valid(_pause)) and get_viewport().gui_get_hovered_control() == null:
		sq = b.hover
	var p: Piece = game.pieces.get(sq) if sq >= 0 else null
	if p == null or not is_instance_valid(p):
		_ptip.visible = false
		_ptip_sq = -1
		return
	if sq != _ptip_sq:
		_ptip_sq = sq
		_ptip_t = 0.0
		_ptip.visible = false
	_ptip_t += delta
	if _ptip_t < PTIP_DELAY:
		return
	var role := Lang.t(String(ROLE_NAMES[p.side][p.role]))
	var nm := "" if Atlas.still_pieces() else String(p.def.get("name", ""))
	_ptip_name.text = nm if nm != "" else role
	_ptip_role.text = role
	_ptip_role.visible = nm != ""
	_ptip.reset_size()
	var vs := _root.get_viewport_rect().size
	var at := _root.get_local_mouse_position() + Vector2(30, 34)
	at.x = minf(at.x, vs.x - _ptip.size.x - 8)
	at.y = minf(at.y, vs.y - _ptip.size.y - 8)
	_ptip.position = at
	_ptip.visible = true

const HISTORY_H := 340.0  ## the moves list's height (it scrolls); shorter while the note of the first boards shows
const HISTORY_H_TIP := 150.0
var _tip: PanelContainer  ## the first boards: "not fond of the monsters?" with the three sets of pieces


func _close_tip() -> void:
	if _tip and is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
	_history_scroll.custom_minimum_size.y = HISTORY_H


## The first boards of the ladder: a small note at the top right offering the other sets of pieces instead of the
## creatures: it points at the sets' buttons at the bottom right (a cross closes it). Once a set is picked, it is
## never shown again.
func pieces_tip(show: bool) -> void:
	_close_tip()
	if not show or not bool(Settings.get_value("pieces_tip")):
		return
	_tip = Ui.panel("Plate")
	_tip.custom_minimum_size = Vector2(0, 0)
	_right.add_child(_tip)
	_right.move_child(_tip, 1)  # under the action buttons
	var v := Ui.vbox(Pal.S1)
	_tip.add_child(v)
	var h := Ui.hbox(Pal.S2)
	v.add_child(h)
	var txt := Ui.label("Pas fan des monstres ? Change de pièces en bas à droite.", "", Pal.FS_SMALL - 4)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(280, 0)  # a fixed width: the column stays as wide as the history
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	var x := FxButton.make("", "IconButton", "close", Vector2(56, 56))
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = Lang.t("Fermer")
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(func() -> void:
		Audio.play("ui.click")
		_close_tip()
		_relayout.call_deferred())
	h.add_child(x)
	_history_scroll.custom_minimum_size.y = HISTORY_H_TIP  # the note's room, so the column stays off the board
	_relayout.call_deferred()
	get_tree().process_frame.connect(_relayout, CONNECT_ONE_SHOT)  # once the wrapped text has its height
	Ui.pop_in(_tip, 0.6, 0.9)


func toggle_history() -> void:
	var open := not _history_panel.visible
	_history_panel.set_meta("open", open)
	_history_panel.visible = open
	if open:
		Ui.pop_in(_history_panel, 0.0, 0.94)
		_scroll_history_end()


# --- players ----------------------------------------------------------------------------------------------------------

## Who plays: an opponent of the ladder ({} = two players on one screen).
func set_players(p_opponent: Dictionary) -> void:
	opponent = p_opponent
	for c in _left.get_children():
		c.queue_free()
	var human := game.human_side
	var prof := Profiles.current()
	var top_side := 1 - human if not game.two_humans else ChessPosition.BLACK
	var bottom_side := 1 - top_side
	var top: Control
	var bottom: Control
	if game.two_humans:
		top = _plate(Profiles.other_avatar(String(prof.get("avatar", ""))), "Joueur 2", "Les noirs", ChessPosition.BLACK)
		bottom = _plate(String(prof.get("avatar", Profiles.default_avatar())), String(prof.get("name", "Joueur 1")), "Les blancs", ChessPosition.WHITE)
	else:
		var sub := Lang.t("Joueur en ligne") if remote() else UiKit.elo_text(opponent)
		top = _plate(String(opponent.get("avatar", "tofu")), String(opponent.get("name", "")), sub, top_side)
		bottom = _plate(String(prof.get("avatar", Profiles.default_avatar())), String(prof.get("name", "")),
			"Les blancs" if bottom_side == ChessPosition.WHITE else "Les noirs", bottom_side)
	_plates[top_side] = top
	_plates[bottom_side] = bottom
	_left.add_child(top)
	var vs := Ui.label("contre", "Dim", Pal.FS_TINY)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.add_theme_constant_override("outline_size", 8)
	vs.add_theme_color_override("font_outline_color", Pal.OUTLINE)
	_left.add_child(vs)
	_left.add_child(bottom)
	_rebuild_history()
	_on_turn(game.pos.side)
	Ui.slide_in(_left, Vector2(-70, 0))
	Ui.slide_in(_right, Vector2(70, 0))


func _plate(avatar: String, title: String, sub: String, side: int) -> Control:
	var p := Ui.panel("Plate")
	p.custom_minimum_size = Vector2(430, 0)  # compact: clear of the board's frame
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := Ui.hbox(Pal.S2)
	p.add_child(h)
	var m := Medallion.make(UiKit.avatar_texture(avatar), 92)
	m.badge = false
	m.name = "Medallion"
	h.add_child(m)
	var v := Ui.vbox(2, BoxContainer.ALIGNMENT_CENTER)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := Ui.label(title, "H2", 30 if title.length() <= 18 else 26)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.max_lines_visible = 2
	t.custom_minimum_size = Vector2(290, 0)
	v.add_child(t)
	var sr := Ui.hbox(Pal.S1)
	v.add_child(sr)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.draw.connect(func() -> void:
		dot.draw_circle(Vector2(13, 13), 12.0, Pal.OUTLINE, true, -1.0, true)
		dot.draw_circle(Vector2(13, 13), 8.5, Pal.CREAM if side == ChessPosition.WHITE else Color("2a2622"), true, -1.0, true))
	sr.add_child(dot)
	sr.add_child(Ui.label(sub, "Dim", Pal.FS_TINY + 2))
	var caps := Ui.hbox(-14)
	caps.name = "Captures"
	caps.custom_minimum_size = Vector2(0, 36)
	v.add_child(caps)
	var think := Ui.label("", "Small", Pal.FS_TINY + 2, Pal.GOLD_HI)
	think.name = "Think"
	think.visible = false
	v.add_child(think)
	p.set_meta("side", side)
	return p


## The creatures each side has taken, with the material balance.
func _refresh_captures() -> void:
	if game == null:
		return
	var count := [{}, {}]
	for sq in 64:
		var pc := game.pos.board[sq]
		if pc == ChessPosition.EMPTY:
			continue
		var c := ChessPosition.piece_color(pc)
		var t := ChessPosition.piece_type(pc)
		count[c][t] = int(count[c].get(t, 0)) + 1
	var material := [0, 0]
	for c in 2:
		for t in VALUES:
			material[c] += VALUES[t] * int(count[c].get(t, 0))
	for side in 2:
		var plate := _plates[side]
		if plate == null:
			continue
		var row := plate.find_child("Captures", true, false) as HBoxContainer
		for ch in row.get_children():
			ch.queue_free()
		var other := 1 - side
		var other_name := "white" if other == ChessPosition.WHITE else "black"
		for t in [ChessPosition.QUEEN, ChessPosition.ROOK, ChessPosition.BISHOP, ChessPosition.KNIGHT, ChessPosition.PAWN]:
			var lost := maxi(0, int(START_COUNT[t]) - int(count[other].get(t, 0)))
			for i in lost:
				var tr := TextureRect.new()
				tr.texture = UiKit.avatar_texture("%s_%s" % [other_name, ChessGame.PIECE_ROLES[t]])
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = Vector2(44, 44)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(tr)
		var diff: int = material[side] - material[other]
		if diff > 0:
			row.add_child(Ui.spacer(22, 0))
			row.add_child(Ui.label("+%d" % diff, "Small", Pal.FS_SMALL, Pal.GOLD_HI))


# --- turn, history -----------------------------------------------------------------------------------------------------

func _on_turn(side: int) -> void:
	var check := game.pos.in_check()
	var text := ""
	var icon := "swords"
	var who := Lang.t(String(opponent.get("name", "L'adversaire")))
	if game.two_humans:
		text = "Aux blancs de jouer" if side == ChessPosition.WHITE else "Aux noirs de jouer"
	elif game.is_human_turn():
		text = "À toi de jouer"
	elif remote():
		text = Lang.f("Au tour de %s", [String(opponent.get("name", ""))])
		icon = "hourglass"
	else:
		text = Lang.f("%s réfléchit", [who])
		icon = "hourglass"
	if check:
		text = (Lang.t("Échec !  ") + Lang.t(text)) if game.is_human_turn() or game.two_humans else "Échec !"
		icon = "shield"
	_set_banner(text, icon, check)
	for s in 2:
		var p := _plates[s]
		if p == null:
			continue
		var on := s == side
		var sb := PlankBox.plate().with({"glow": Pal.with_alpha(Pal.EMBER_HI if (on and check) else Pal.GOLD_HI, 0.75) if on else Color(0, 0, 0, 0),
			"glow_size": 14.0 if on else 0.0, "rim_top": Pal.GOLD_HI if on else Pal.WOOD_HI, "rim_bottom": Pal.GOLD_LO if on else Pal.WOOD_LO}).margins(Pal.S3, Pal.S2)
		p.add_theme_stylebox_override("panel", sb)
		(p.find_child("Medallion", true, false) as Medallion).selected = on
		var think := p.find_child("Think", true, false) as Label
		think.text = ""
		think.visible = on and not game.is_human_turn() and not game.two_humans
	_refresh_captures()


func _set_banner(text: String, icon: String, danger: bool) -> void:
	_banner_label.text = text
	_banner_icon.icon = icon
	_banner_icon.color = Pal.CREAM if danger else Pal.GOLD_HI
	var sb := PlankBox.plate(0.92).margins(Pal.S4, Pal.S1 + 4)
	if danger:
		sb = sb.with({"fill_top": Color(0.55, 0.13, 0.08, 0.95), "fill_bottom": Color(0.32, 0.06, 0.03, 0.95),
			"rim_top": Pal.EMBER_HI, "rim_bottom": Pal.EMBER_LO, "glow": Pal.with_alpha(Pal.EMBER_HI, 0.6), "glow_size": 16.0}).margins(Pal.S4, Pal.S1 + 4)
	_banner.add_theme_stylebox_override("panel", sb)
	if not Pal.reduced_motion():
		_banner.pivot_offset = _banner.size * 0.5
		var tw := _banner.create_tween()
		if danger:
			for i in 4:
				tw.tween_property(_banner, "rotation", deg_to_rad(2.5 if i % 2 == 0 else -2.5), 0.05)
			tw.tween_property(_banner, "rotation", 0.0, 0.05)
		else:
			_banner.scale = Vector2(0.94, 0.94)
			tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if game:
		_update_piece_tip(delta)
	if game == null or game.over or game.is_human_turn():
		return
	_think_t += delta
	var dots := ".".repeat(1 + int(_think_t * 2.5) % 3)
	var p := _plates[game.pos.side]
	if p:
		var think := p.find_child("Think", true, false) as Label
		var txt := Lang.t("réfléchit") + dots
		if think and think.text != txt:
			think.text = txt  # only when the dots change: a new text lays the plate out again


func _on_move(_san: String) -> void:
	_rebuild_history()


func _rebuild_history() -> void:
	for c in _history_list.get_children():
		c.queue_free()
	var sans := game.san_moves
	var first_black := game.start_fen.split(" ").size() > 1 and game.start_fen.split(" ")[1] == "b"
	var items: Array = Array(sans)
	if first_black:
		items.push_front("…")
	var n := (items.size() + 1) / 2
	for i in n:
		var row := Ui.hbox(Pal.S2)
		var last := i == n - 1
		var num := Ui.label("%d." % (i + 1), "InkDim", Pal.FS_SMALL)
		num.custom_minimum_size = Vector2(68, 0)
		row.add_child(num)
		for k in 2:
			var idx := i * 2 + k
			var t := String(items[idx]) if idx < items.size() else ""
			var l := Ui.label(_fr_san(t), "Ink", Pal.FS_SMALL + 2)
			l.custom_minimum_size = Vector2(160, 0)
			if last and idx == items.size() - 1:
				l.add_theme_color_override("font_color", Pal.EMBER_LO)
			row.add_child(l)
		_history_list.add_child(row)
	if n == 0:
		_history_list.add_child(Ui.label("La partie commence.", "InkDim", Pal.FS_SMALL))
	_scroll_history_end()


func _scroll_history_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_history_scroll):
		_history_scroll.scroll_vertical = int(_history_scroll.get_v_scroll_bar().max_value)


## Algebraic notation with the French piece letters (R, D, T, F, C).
static func _fr_san(s: String) -> String:
	if s.is_empty() or s == "…" or Lang.is_en():
		return s
	var map := {"K": "R", "Q": "D", "R": "T", "B": "F", "N": "C"}
	var out := ""
	for i in s.length():
		var ch := s[i]
		if map.has(ch) and (i == 0 or s[i - 1] == "="):
			out += map[ch]
		else:
			out += ch
	return out


# --- pause ---------------------------------------------------------------------------------------------------------

func show_pause() -> void:
	if (_result and _result.visible) or (_pause and is_instance_valid(_pause)):
		return
	if not remote():
		get_tree().paused = true  # online, the friend's moves keep coming: nothing stops
	_pause = Ui.full_rect(Control.new())
	_root.add_child(_pause)
	_pause.add_child(Ui.veil(0.55))
	var p := Ui.panel()
	_pause.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(700, 0)
	p.add_child(v)
	var t := Ui.title("Pause")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := Lang.t("Partie à deux") if game.two_humans else Lang.f("Contre %s", [Lang.t(String(opponent.get("name", "")))])
	var il := Ui.label(Lang.f("%s  ·  coup %d", [info, game.san_moves.size() / 2 + 1]), "Dim")
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(il)
	v.add_child(Ui.separator(700))
	var resume := FxButton.make("Reprendre", "LeafButton", "play", Vector2(700, 112))
	resume.pressed.connect(hide_pause)
	v.add_child(resume)
	var st := FxButton.make("Réglages", "Button", "gear", Vector2(700, 104))
	st.pressed.connect(func() -> void:
		var sp := SettingsPanel.new()
		_root.add_child(sp))
	v.add_child(st)
	if not remote():
		var rs := FxButton.make("Recommencer", "Button", "refresh", Vector2(700, 104))
		rs.pressed.connect(func() -> void:
			Ui.confirm(self, "Recommencer ?", "La partie en cours sera perdue et une nouvelle commencera sur ce plateau.",
				"Recommencer", func() -> void:
					hide_pause()
					restart_requested.emit(), "Button", "refresh"))
		v.add_child(rs)
	if not game.over:
		var rg := FxButton.make("Abandonner", "EmberButton", "flag", Vector2(700, 104))
		rg.pressed.connect(func() -> void:
			var msg := "La partie comptera comme une défaite." if not game.two_humans else "Le camp qui a le trait perd la partie."
			if remote():
				msg = "Ton adversaire gagnera la partie."
			Ui.confirm(self, "Abandonner ?", msg, "Abandonner", func() -> void:
				hide_pause()
				resign_requested.emit(), "EmberButton", "flag"))
		v.add_child(rg)
	var mn := FxButton.make("Menu principal", "DarkButton", "home", Vector2(700, 104))
	mn.tooltip_text = "La partie est sauvegardée : tu pourras la reprendre depuis le titre."
	if remote() and not game.over:
		mn.tooltip_text = "Quitter la partie en ligne compte comme un abandon."
		mn.pressed.connect(func() -> void:
			Ui.confirm(self, "Quitter la partie ?", "Quitter la partie en ligne compte comme un abandon.", "Quitter",
				func() -> void:
					hide_pause()
					menu_requested.emit(), "EmberButton", "door"))
	else:
		mn.pressed.connect(func() -> void:
			hide_pause()
			menu_requested.emit())
	v.add_child(mn)
	var note := Ui.label("La partie est sauvegardée à chaque coup." if not remote() else "Partie en ligne : sans limite de temps entre les coups.", "Dim", Pal.FS_TINY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	Ui.pop_in(p)
	Ui.fade_in(_pause, 0.0, Pal.T_FAST)
	resume.grab_focus.call_deferred()


func hide_pause() -> void:
	if _pause and is_instance_valid(_pause):
		_pause.queue_free()
	_pause = null
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _promo and is_instance_valid(_promo):
			_close_promo()
		elif _pause and is_instance_valid(_pause):
			hide_pause()
		elif not (_result and _result.visible):
			show_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		toggle_history()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		next_view()
		get_viewport().set_input_as_handled()


# --- promotion ------------------------------------------------------------------------------------------------------

## Four creatures to choose from (keys D, T, F, C as well).
func show_promotion(moves: Array) -> void:
	_close_promo()
	_promo = Ui.full_rect(Control.new())
	_root.add_child(_promo)
	_promo.add_child(Ui.veil(0.5))
	var p := Ui.panel()
	_promo.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	p.add_child(v)
	var t := Ui.title("Promotion")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := Ui.label("Ton pion a traversé le plateau : choisis sa nouvelle forme.", "Dim")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(row)
	var side := "white" if game.pos.side == ChessPosition.WHITE else "black"
	var order := [ChessPosition.QUEEN, ChessPosition.ROOK, ChessPosition.BISHOP, ChessPosition.KNIGHT]
	var keys := {ChessPosition.QUEEN: "Q", ChessPosition.ROOK: "R", ChessPosition.BISHOP: "B", ChessPosition.KNIGHT: "N"} if Lang.is_en() else {ChessPosition.QUEEN: "D", ChessPosition.ROOK: "T", ChessPosition.BISHOP: "F", ChessPosition.KNIGHT: "C"}
	var first: Control
	for pt in order:
		for m in moves:
			if ChessPosition.move_promo(m) != pt:
				continue
			var role: String = ChessGame.PIECE_ROLES[pt]
			var cv := Ui.vbox(Pal.S1, BoxContainer.ALIGNMENT_CENTER)
			cv.custom_minimum_size = Vector2(250, 300)
			var med := Medallion.make(UiKit.avatar_texture("%s_%s" % [side, role]), 200, Medallion.State.BEATEN if pt == ChessPosition.QUEEN else Medallion.State.PLAIN)
			med.badge = false
			med.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cv.add_child(med)
			var nl := Ui.label("%s  (%s)" % [Lang.t(_role_fr(role)), keys[pt]] if not Pal.touch() else _role_fr(role), "H2", 40)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(nl)
			var b := _card_button(cv, "GoldButton" if pt == ChessPosition.QUEEN else "DarkButton")
			var mv: int = m
			b.set_meta("key", keys[pt])
			b.pressed.connect(func() -> void:
				_close_promo()
				game.play_move(mv))
			row.add_child(b)
			if first == null:
				first = b
	var cancel := FxButton.make("Annuler", "DarkButton", "close", Vector2(340, 96))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_close_promo)
	v.add_child(cancel)
	Ui.pop_in(p)
	if first:
		first.grab_focus.call_deferred()
	_promo.set_process_unhandled_key_input(true)
	_promo.gui_input.connect(func(_e: InputEvent) -> void: pass)
	var keyer := Node.new()
	keyer.set_script(preload("res://src/ui/kit/key_catcher.gd"))
	keyer.set("buttons", row.get_children())
	_promo.add_child(keyer)


func _close_promo() -> void:
	if _promo and is_instance_valid(_promo):
		_promo.queue_free()
	_promo = null


func _card_button(content: Control, variation: String) -> FxButton:
	var b := FxButton.make("", variation)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in content.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)
	var fit := func() -> void:
		var sb := b.get_theme_stylebox("normal")
		b.custom_minimum_size = content.get_combined_minimum_size() + Vector2(sb.content_margin_left + sb.content_margin_right, sb.content_margin_top + sb.content_margin_bottom)
		content.position = Vector2(sb.content_margin_left, sb.content_margin_top)
		content.size = b.size - Vector2(sb.content_margin_left + sb.content_margin_right, sb.content_margin_top + sb.content_margin_bottom)
	b.resized.connect(fit)
	fit.call_deferred()
	return b


static func _role_fr(role: String) -> String:
	return {"queen": "Dame", "rook": "Tour", "bishop": "Fou", "knight": "Cavalier", "king": "Roi", "pawn": "Pion"}[role]


# --- end of game ----------------------------------------------------------------------------------------------------

## r: the game's result ({"result", "winner", "human_won", "resigned", "moves"}), plus "unlocked" (opponent
## id opened by this win) when there is one.
func show_result(r: Dictionary, can_continue := false) -> void:
	hide_result()
	hide_pause()
	_close_promo()
	_result = Ui.full_rect(Control.new())
	_root.add_child(_result)
	var winner := int(r.get("winner", -1))
	var won := bool(r.get("human_won", false))
	var kind := "draw"
	if winner >= 0:
		kind = "win" if (won or game.two_humans) else "loss"
	var veil := Ui.veil(0.62)
	_result.add_child(veil)
	if kind == "win":
		_result.add_child(_rays(Pal.GOLD_HI, 0.15))
		_result.add_child(_confetti())
	elif kind == "loss":
		_result.add_child(_rays(Color("7a8aa8"), 0.09))
	var col := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	_result.add_child(col)
	Ui.anchor_at(col, Vector2(0.5, 0.5))
	# title
	var title := "Victoire !"
	var tc := [Color(1.0, 0.92, 0.45), Color(0.97, 0.56, 0.1)]
	if game.two_humans and winner >= 0:
		title = "Les blancs gagnent !" if winner == ChessPosition.WHITE else "Les noirs gagnent !"
	elif kind == "loss":
		title = "Défaite"
		tc = [Color(1.0, 0.62, 0.48), Color(0.72, 0.16, 0.1)]
	elif kind == "draw":
		title = "Partie nulle"
		tc = [Color(0.98, 0.95, 0.86), Color(0.68, 0.64, 0.56)]
	var tl := Ui.title(title, Pal.FS_HUGE, tc[0], tc[1])
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tl)
	var reason: String = {
		ChessPosition.Result.CHECKMATE: "Échec et mat",
		ChessPosition.Result.STALEMATE: "Pat : plus aucun coup légal",
		ChessPosition.Result.REPETITION: "Triple répétition",
		ChessPosition.Result.FIFTY_MOVES: "Règle des 50 coups",
		ChessPosition.Result.INSUFFICIENT_MATERIAL: "Matériel insuffisant",
	}.get(r.get("result", -1), "Abandon" if r.get("resigned", false) else "")
	if r.get("opponent_resigned", false):
		reason = "Ton adversaire a abandonné"
	var sub := Ui.label(Lang.f("%s  ·  %d coups", [Lang.t(reason), (int(r.get("moves", 0)) + 1) / 2]), "Hud", Pal.FS_BODY + 2, Pal.CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	# the opponent's illustration with a stamp
	if not game.two_humans and not opponent.is_empty():
		var art := Control.new()
		art.custom_minimum_size = Vector2(760, 470)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
		var pic := Ui.full_rect(TextureRect.new())
		pic.texture = MainMenu._art_texture(String(opponent.get("avatar", "tofu")))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(pic)
		if kind == "win":
			pic.modulate = Color(0.85, 0.85, 0.85)
		var stamp_text: String = {"win": "Vaincu !", "loss": "Invaincu", "draw": "Égalité"}[kind]
		var stamp := Ui.panel("Plate")
		var sh := Ui.hbox(Pal.S1)
		stamp.add_child(sh)
		sh.add_child(Icon.make(String({"win": "star", "loss": "shield", "draw": "handshake"}[kind]), 52, Pal.GOLD_HI if kind == "win" else Pal.CREAM))
		sh.add_child(Ui.label(stamp_text, "H2", 46, Pal.GOLD_HI if kind == "win" else Pal.CREAM))
		art.add_child(stamp)
		Ui.anchor_at(stamp, Vector2(0.78, 0.2))
		stamp.rotation = deg_to_rad(-8.0)
		if not Pal.reduced_motion():
			stamp.scale = Vector2.ONE * 2.2
			stamp.modulate.a = 0.0
			var st := stamp.create_tween().set_parallel()
			st.tween_property(stamp, "scale", Vector2.ONE, 0.35).set_delay(0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			st.tween_property(stamp, "modulate:a", 1.0, 0.15).set_delay(0.6)
			stamp.resized.connect(func() -> void: stamp.pivot_offset = stamp.size * 0.5)
	# the board this win opened
	var unlocked := String(r.get("unlocked", ""))
	if unlocked != "":
		col.add_child(_unlock_plate(unlocked))
	elif kind == "win" and not game.two_humans and not opponent.get("free", false) \
			and Profiles.beaten_count() >= Profiles.opponents.size():
		var champ := Ui.label("Tous les champions sont vaincus. Bravo !", "H2", 44, Pal.GOLD_HI)
		champ.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(champ)
	# what next
	var bar := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(bar)
	var first: FxButton
	if can_continue:
		var nx := FxButton.make("Adversaire suivant", "LeafButton", "swords", Vector2(560, 116))
		nx.pulse = true
		nx.pressed.connect(func() -> void: next_requested.emit())
		bar.add_child(nx)
		first = nx
	var again := FxButton.make("Rejouer" if kind != "loss" and not remote() else "Revanche", "Button" if can_continue else "LeafButton", "refresh", Vector2(400, 116))
	if remote():
		# online: the rematch starts when both players ask for it (colours swapped)
		_rematch_label = Ui.label("", "Hud", Pal.FS_BODY, Pal.GOLD_HI)
		_rematch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rematch_label.visible = false
		col.add_child(_rematch_label)
		col.move_child(_rematch_label, bar.get_index())
		again.pressed.connect(func() -> void:
			again.disabled = true
			restart_requested.emit())
	else:
		again.pressed.connect(func() -> void:
			hide_result()
			restart_requested.emit())
	bar.add_child(again)
	if first == null:
		first = again
	if not game.two_humans and not remote():
		var free := bool(opponent.get("free", false))
		var path := FxButton.make("Partie libre" if free else "Le Chemin", "Button", "target" if free else "map", Vector2(380, 116))
		path.pressed.connect(func() -> void: path_requested.emit())
		bar.add_child(path)
	var mn := FxButton.make("", "DarkButton", "home", Vector2(116, 116))
	mn.tooltip_text = "Menu principal"
	mn.pressed.connect(func() -> void: menu_requested.emit())
	bar.add_child(mn)
	Ui.fade_in(veil, 0.0, Pal.T_SLOW)
	Ui.pop_in(tl, 0.1, 0.5)
	Ui.shine(tl, 2.5)
	Ui.stagger(col.get_children().slice(1), 0.12, 0.35)
	first.grab_focus.call_deferred()


## "Nouveau chemin ouvert": the next opponent's medallion goes from locked to open.
func _unlock_plate(id: String) -> Control:
	var o := Profiles.opponent(id)
	var p := Ui.panel()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := Ui.hbox(Pal.S4)
	p.add_child(h)
	var m := Medallion.make(UiKit.avatar_texture(String(o.get("avatar", "tofu"))), 168, Medallion.State.LOCKED)
	h.add_child(m)
	var v := Ui.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	h.add_child(v)
	var head := Ui.hbox(Pal.S1)
	v.add_child(head)
	head.add_child(Icon.make("unlock", 48, Pal.LEAF_HI))
	head.add_child(Ui.title("Nouveau chemin ouvert !", 50, Color(0.8, 1.0, 0.55), Color(0.36, 0.72, 0.16)))
	var b: Dictionary = {}
	var bv: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/boards.json"))
	if bv is Dictionary:
		b = bv.get("boards", {}).get(o.get("board", ""), {})
	v.add_child(Ui.label(String(o.get("name", "")), "H2", 42))
	v.add_child(Ui.label("%s  ·  %s" % [Lang.t(String(b.get("name", ""))), UiKit.elo_text(o)], "Dim"))
	# the lock opens after a beat
	var t := create_tween()
	t.tween_interval(Pal.dur(1.3))
	t.tween_callback(func() -> void:
		m.state = Medallion.State.CURRENT
		m.selected = true
		Audio.play("game.promote", -6.0)
		if not Pal.reduced_motion():
			m.pivot_offset = m.size * 0.5
			var pt := m.create_tween()
			pt.tween_property(m, "scale", Vector2.ONE * 1.25, 0.15)
			pt.tween_property(m, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return p


## Slowly turning light rays behind the title.
func _rays(col: Color, alpha := 0.22) -> Control:
	var c := Ui.full_rect(Control.new())
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t0 := Time.get_ticks_msec()
	c.draw.connect(func() -> void:
		var ctr := c.size * Vector2(0.5, 0.36)
		var r := c.size.length()
		var spin := 0.0 if Pal.reduced_motion() else (Time.get_ticks_msec() - t0) / 1000.0 * 0.08
		for i in 14:
			var a := spin + TAU * i / 14.0
			var w := 0.09
			var pts := PackedVector2Array([ctr, ctr + Vector2(cos(a - w), sin(a - w)) * r, ctr + Vector2(cos(a + w), sin(a + w)) * r])
			c.draw_polygon(pts, PackedColorArray([Color(col, alpha), Color(col, 0.0), Color(col, 0.0)])))
	var tick := Timer.new()
	tick.wait_time = 1.0 / 30.0
	tick.autostart = true
	tick.timeout.connect(c.queue_redraw)
	c.add_child(tick)
	return c


func _confetti() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var img := Image.create(14, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	p.texture = ImageTexture.create_from_image(img)
	p.amount = 140 if not Pal.reduced_motion() else 30
	p.lifetime = 4.5
	p.position = Vector2(_root.size.x * 0.5, -40)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_root.size.x * 0.5, 20)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Pal.GOLD_HI)
	g.set_color(1, Pal.EMBER_HI)
	g.add_point(0.25, Pal.LEAF_HI)
	g.add_point(0.5, Pal.SKY_HI)
	g.add_point(0.75, Pal.CREAM)
	p.color_initial_ramp = g
	return p


func hide_result() -> void:
	if _result and is_instance_valid(_result):
		_result.queue_free()
	_result = null
