class_name MainMenu
extends CanvasLayer

const DISCORD_URL := "https://discord.gg/N8f62M2eaK"  ## the community: the other retro games, news, bugs, ideas
const DISCORD_COLOR := Color("7983f5")  ## Discord's blurple, a little lighter to read on the dark buttons
## The menus, over the living board: title (logo, resume, play, next challenge, profile), "Le Chemin des
## Champions" (the ten opponents on a trail, a large card for the one chosen, its board shown behind),
## free play, online games (create a room and share its code, or join one), profiles (choose, create, edit,
## delete) and settings (SettingsPanel). Built from the design system in
## src/ui/kit. No chess here: the menu asks main.gd to start games through its signals.

signal play_requested(opponent_id: String, side: String)
signal resume_requested
signal duel_requested
signal free_requested(elo: int, board: String, side: String)
signal preview_board(key: String)
signal quit_requested

const CARD_W := 1040.0

var game: ChessGame  ## to frame the board behind the menus
var boards: Dictionary = {}  ## data/boards.json "boards"
var _root: Control
var _screen: Control
var _screen_name := ""
var _sel_opp := ""
var _side := "white"
var _card: VBoxContainer
var _nodes: Dictionary = {}  ## opponent id -> path node button
var _trail: Control
var _edit_id := ""  ## profile being edited ("" = new)
var _edit_avatar := ""
var _overlay: Control  ## settings or a dialog over the current screen
var _free_elo := 1200  ## free play: strength and board chosen
var _free_board := "prairie"
var online: OnlineClient:  ## set by main.gd: the online screen opens rooms through it
	set(v):
		online = v
		online.room_changed.connect(_on_net_room)
		online.failed.connect(_on_net_failed)
var _net_board := "prairie"  ## online game: board and colour the host picks
var _net_side := "random"
var _net_status: Label  ## the online screen's line of state (connecting, errors)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var b: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/boards.json"))
	boards = b.get("boards", {}) if b is Dictionary else {}
	_root = Ui.full_rect(Control.new())
	_root.theme = UiTheme.ensure()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(Ui.vignette(0.7))
	_root.add_child(_motes())
	_side = String(Profiles.current().get("last_side", "white"))
	Updater.found.connect(func(_i: Dictionary) -> void:
		if _screen_name == "title" and is_instance_valid(_screen):
			_update_plate())
	show_screen("title")


func show_screen(name: String) -> void:
	if _screen:
		_screen.queue_free()
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_screen_name = name
	_screen = Ui.full_rect(Control.new())
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_screen)
	if game and game.camera:
		game.camera.frame_offset = Vector2.ZERO
	match name:
		"title":
			_build_title()
		"opponents":
			_build_opponents()
		"profiles":
			_build_profiles()
		"profile_edit":
			_build_profile_edit()
		"settings":
			_open_settings()
		"free":
			_build_free()
		"online":
			_build_online()
	Ui.fade_in(_screen, 0.0, Pal.T_FAST)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_instance_valid(_overlay):
		return
	if event.is_action_pressed("ui_cancel"):
		match _screen_name:
			"opponents", "profiles", "free":
				Audio.play("ui.click")
				show_screen("title")
			"online":
				Audio.play("ui.click")
				_leave_online()
			"profile_edit":
				show_screen("profiles")
		get_viewport().set_input_as_handled()


## Golden dust drifting up over the whole screen.
func _motes() -> CPUParticles2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.7, 1))
	g.set_color(1, Color(1, 0.85, 0.4, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	var p := CPUParticles2D.new()
	p.texture = gt
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = Vector2(1280, 760)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1700, 820)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.1
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 0.55))
	fade.add_point(0.8, Color(1, 1, 1, 0.45))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p


## A button that holds any content (the profile chip, the profile cards).
func _content_button(content: Control, variation := "DarkButton") -> FxButton:
	var b := FxButton.make("", variation)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in content.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.hold(content)
	return b


func _opp_state(id: String) -> Medallion.State:
	if Profiles.is_beaten(id):
		return Medallion.State.BEATEN
	if not Profiles.is_unlocked(id):
		return Medallion.State.LOCKED
	return Medallion.State.CURRENT if id == Profiles.next_challenge() else Medallion.State.OPEN


func _board_name(o: Dictionary) -> String:
	return Lang.t(String(boards.get(o.get("board", ""), {}).get("name", "")))


# --- title ---------------------------------------------------------------------------------------------------------

func _build_title() -> void:
	var col := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	_screen.add_child(col)
	Ui.anchor_at(col, Vector2(0.5, 0.5))
	var logo := TextureRect.new()
	logo.texture = load("res://assets/brand/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var saved := Profiles.saved_game()
	# a smaller logo when the resume button takes its place in the column
	logo.custom_minimum_size = Vector2(900, 604) if saved.is_empty() else Vector2(760, 510)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo)
	LogoFx.attach(logo)  # light sweeps, glints, twinkles, a burst of sparks on arrival (the logo itself stays still)
	var buttons := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(buttons)
	var first: FxButton
	if not saved.is_empty():
		var opp_id := String(saved.get("opp", ""))
		var who := "Partie à deux" if opp_id == "" else String(Profiles.opponent(opp_id).get("name", ""))
		if opp_id == FreePlay.ID:
			who = Lang.t("Adversaire libre") + "  ·  " + Lang.f("≈ %d Elo", [int(saved.get("elo", 0))])
		var n := (saved.get("moves", []) as Array).size()
		var res := FxButton.make("Reprendre la partie", "GoldButton", "play", Vector2(760, 116))
		res.tooltip_text = Lang.f("%s · coup %d", [Lang.t(who), n / 2 + 1])
		res.pressed.connect(func() -> void: resume_requested.emit())
		buttons.add_child(res)
		var sub := Ui.label(Lang.f("%s  ·  coup %d", [Lang.t(who), n / 2 + 1]), "Hud", Pal.FS_SMALL)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buttons.add_child(sub)
		first = res
	var play := FxButton.make("Jouer", "LeafButton", "swords", Vector2(760, 132))
	play.add_theme_font_size_override("font_size", 58)
	play.set_icon_name("swords", 70.0)
	play.pulse = saved.is_empty()
	play.pressed.connect(func() -> void:
		_sel_opp = Profiles.next_challenge()
		show_screen("opponents"))
	buttons.add_child(play)
	if first == null:
		first = play
	buttons.add_child(_next_plate())
	# free play (any board, any strength) and online games, side by side under the path
	var modes := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	buttons.add_child(modes)
	var free := FxButton.make("Partie libre", "GoldButton", "target", Vector2(372, 108))
	free.tooltip_text = "Choisis le plateau et la force de ton adversaire"
	free.pressed.connect(func() -> void: show_screen("free"))
	modes.add_child(free)
	var net := FxButton.make("En ligne", "GoldButton", "users", Vector2(372, 108))
	net.tooltip_text = "Affronte un ami à distance avec un code à partager"
	net.pressed.connect(func() -> void: show_screen("online"))
	modes.add_child(net)
	var row := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	buttons.add_child(row)
	var duel := FxButton.make("À deux", "Button", "users", Vector2(300, 104))
	duel.tooltip_text = "Deux joueurs sur le même écran"
	duel.pressed.connect(func() -> void: duel_requested.emit())
	row.add_child(duel)
	var st := FxButton.make("Réglages", "Button", "gear", Vector2(330, 104))
	st.pressed.connect(func() -> void: show_screen("settings"))
	row.add_child(st)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var q := FxButton.make("", "DarkButton", "door", Vector2(104, 104))
		q.tooltip_text = "Quitter le jeu"
		q.pressed.connect(func() -> void:
			_overlay = Ui.confirm(self, "Quitter ?", "Ta progression est enregistrée.", "Quitter",
				func() -> void: quit_requested.emit(), "EmberButton", "door"))
		row.add_child(q)
	_profile_chip()
	# the community's Discord, bottom right over the version: the other retro games, news, bugs to report, ideas
	var discord := FxButton.make("Discord", "DarkButton", "chat", Vector2(0, 96))
	discord.icon_color = DISCORD_COLOR
	discord.set_icon_name("chat", 52.0)
	discord.tooltip_text = "Rejoindre le Discord : les autres jeux rétro, les nouvelles, les bugs à signaler, les idées"
	discord.pressed.connect(func() -> void: OS.shell_open(DISCORD_URL))
	_screen.add_child(discord)
	Ui.anchor_at(discord, Vector2(1.0, 1.0), Vector2(1.0, 1.0))
	discord.offset_right = -Pal.EDGE
	discord.offset_bottom = -Pal.EDGE - 56
	discord.offset_top = -Pal.EDGE - 56
	if not Updater.info.is_empty():
		_update_plate()
	# the credits and thanks, bottom left over the Ankama line (as the Discord, bottom right)
	var credits := FxButton.make("Crédits", "DarkButton", "info", Vector2(0, 96))
	credits.set_icon_name("info", 52.0)
	credits.tooltip_text = "Crédits, remerciements et liens"
	credits.pressed.connect(_open_credits)
	_screen.add_child(credits)
	Ui.anchor_at(credits, Vector2(0.0, 1.0), Vector2(0.0, 1.0))
	credits.offset_left = Pal.EDGE
	credits.offset_bottom = -Pal.EDGE - 56
	credits.offset_top = -Pal.EDGE - 56
	var credit := Ui.label("Créatures, décors, sons et musiques : Dofus Retro, © Ankama", "Dim", Pal.FS_TINY)
	credit.add_theme_color_override("font_outline_color", Pal.with_alpha(Pal.OUTLINE, 0.8))
	credit.add_theme_constant_override("outline_size", 8)
	_screen.add_child(credit)
	Ui.anchor_at(credit, Vector2(0.0, 1.0), Vector2(0.0, 1.0))
	credit.offset_left = Pal.EDGE
	credit.offset_top = -Pal.EDGE
	credit.offset_bottom = -Pal.EDGE
	var ver := Ui.label("v" + String(ProjectSettings.get_setting("application/config/version", "")), "Dim", Pal.FS_TINY)
	ver.add_theme_constant_override("outline_size", 8)
	_screen.add_child(ver)
	Ui.anchor_at(ver, Vector2(1.0, 1.0), Vector2(1.0, 1.0))
	ver.offset_right = -Pal.EDGE
	ver.offset_bottom = -Pal.EDGE
	ver.offset_left = -Pal.EDGE
	ver.offset_top = -Pal.EDGE
	Ui.pop_in(logo, 0.0, 0.8)
	Ui.stagger(buttons.get_children(), 0.06, 0.15)
	first.grab_focus.call_deferred()


## Under the play button: who comes next, with a portrait.
func _next_plate() -> Control:
	var id := Profiles.next_challenge()
	var o := Profiles.opponent(id)
	var p := Ui.panel("Plate")
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := Ui.hbox(Pal.S3)
	p.add_child(h)
	if o.is_empty():
		return p
	h.add_child(Medallion.make(UiKit.avatar_texture(String(o.get("avatar", "tofu"))), 96, _opp_state(id)))
	var v := Ui.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	h.add_child(v)
	var all_done := Profiles.beaten_count() >= Profiles.opponents.size()
	v.add_child(Ui.label("Tous les champions sont vaincus !" if all_done else "Prochain défi", "Dim", Pal.FS_SMALL))
	v.add_child(Ui.label(String(o["name"]), "", Pal.FS_BODY))
	v.add_child(Ui.label("%s  ·  %s" % [_board_name(o), UiKit.elo_text(o)], "Dim", Pal.FS_TINY))
	return p


## A newer version exists: top right of the title, with its button.
func _update_plate() -> void:
	if _screen.has_node("Update"):
		return
	var p := Ui.panel("Plate")
	p.name = "Update"
	_screen.add_child(p)
	Ui.anchor_at(p, Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	p.offset_right = -Pal.EDGE
	p.offset_top = Pal.EDGE
	var h := Ui.hbox(Pal.S2)
	p.add_child(h)
	h.add_child(Icon.make("sparkle", 56, Pal.GOLD_HI))
	var v := Ui.vbox(2)
	h.add_child(v)
	v.add_child(Ui.label("Nouvelle version", "", Pal.FS_SMALL))
	v.add_child(Ui.label(String(Updater.info.get("version", "")), "Dim", Pal.FS_TINY))
	var b := FxButton.make("Mettre à jour", "GoldButton", "refresh", Vector2(0, 88))
	b.pressed.connect(_update_dialog)
	h.add_child(b)
	Ui.slide_in(p, Vector2(60, 0), 0.4)


## What the new version brings, then the download (progress) and the install.
func _update_dialog() -> void:
	var host := CanvasLayer.new()
	host.layer = 60
	add_child(host)
	_overlay = Ui.full_rect(Control.new())
	host.add_child(_overlay)
	_overlay.theme = UiTheme.ensure()
	_overlay.add_child(Ui.veil(0.6, true))
	var panel := Ui.panel()
	_overlay.add_child(panel)
	Ui.anchor_at(panel, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S3)
	panel.add_child(v)
	v.add_child(Ui.title(Lang.f("Version %s", [String(Updater.info.get("version", ""))])))
	var notes := String(Updater.info.get("notes", "")).strip_edges()
	if notes.length() > 700:
		notes = notes.substr(0, 700) + "…"
	if notes != "":
		v.add_child(Ui.para(notes, 1200, "Dim"))
	var mb := int(Updater.info.get("size", 0)) / 1048576.0
	var how := "Le jeu va se fermer, installer la mise à jour et se relancer tout seul." if OS.has_feature("windows") \
		else "Le programme d'installation d'Android va s'ouvrir : confirme l'installation." if OS.has_feature("android") \
		else "La page de téléchargement va s'ouvrir dans ton navigateur."
	v.add_child(Ui.para(Lang.t(how) + ("  (%.0f Mo)" % mb if mb > 0 else ""), 1200, "Hud"))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(1200, 30)
	bar.max_value = 1.0
	bar.visible = false
	v.add_child(bar)
	var msg := Ui.label("", "Dim", Pal.FS_SMALL)
	v.add_child(msg)
	var row := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(row)
	var later := FxButton.make("Plus tard", "Button", "close", Vector2(340, 104))
	var go := FxButton.make("Installer", "LeafButton", "check", Vector2(400, 104))
	row.add_child(later)
	row.add_child(go)
	var close := func() -> void:
		if not Updater.busy:
			host.queue_free()
			_overlay = null
	later.pressed.connect(close)
	var esc: Node = preload("res://src/ui/kit/esc_catcher.gd").new()
	esc.set("on_cancel", close)
	_overlay.add_child(esc)
	var on_progress := func(r: float) -> void:
		bar.value = r
		msg.text = Lang.f("Téléchargement… %d %%", [roundi(r * 100.0)])
	var on_failed := func(m: String) -> void:
		msg.text = m
		bar.visible = false
		go.disabled = false
		later.disabled = false
	var on_installing := func() -> void:
		bar.value = 1.0
		msg.text = Lang.t("Installation… le jeu va redémarrer.")
	Updater.progress.connect(on_progress)
	Updater.failed.connect(on_failed)
	Updater.installing.connect(on_installing)
	host.tree_exiting.connect(func() -> void:
		Updater.progress.disconnect(on_progress)
		Updater.failed.disconnect(on_failed)
		Updater.installing.disconnect(on_installing))
	go.pressed.connect(func() -> void:
		if not Updater.self_installs():
			Updater.install()
			close.call()
			return
		go.disabled = true
		later.disabled = true
		bar.visible = true
		msg.text = Lang.t("Téléchargement…")
		Updater.install())
	Ui.pop_in(panel)
	go.grab_focus.call_deferred()


## The current profile, top left: portrait, name, progress; opens the profiles.
func _profile_chip() -> void:
	var p := Profiles.current()
	var h := Ui.hbox(Pal.S3)
	h.add_child(Medallion.make(UiKit.avatar_texture(String(p.get("avatar", Profiles.default_avatar()))), 112))
	var v := Ui.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	h.add_child(v)
	v.add_child(Ui.label(String(p.get("name", "")), "H2", 44))
	var pb := ProgressBar.new()
	pb.max_value = Profiles.opponents.size()
	pb.value = Profiles.beaten_count()
	pb.custom_minimum_size = Vector2(320, 22)
	v.add_child(pb)
	v.add_child(Ui.label(Lang.f("%d / %d champions vaincus", [Profiles.beaten_count(), Profiles.opponents.size()]), "Dim", Pal.FS_TINY))
	var b := _content_button(h, "DarkButton")
	b.tooltip_text = "Changer de profil"
	b.pressed.connect(func() -> void: show_screen("profiles"))
	_screen.add_child(b)
	b.position = Vector2(Pal.EDGE, Pal.EDGE)
	Ui.slide_in(b, Vector2(-60, 0), 0.2)


# --- le chemin des champions ---------------------------------------------------------------------------------------

func _build_opponents() -> void:
	var back := FxButton.make("", "IconButton", "back", Vector2(112, 112))
	back.tooltip_text = "Retour"
	back.pressed.connect(func() -> void: show_screen("title"))
	_screen.add_child(back)
	back.position = Vector2(Pal.EDGE, Pal.EDGE)
	var banner := Banner.make("Le Chemin des Champions", Pal.FS_H2 + 6)
	_screen.add_child(banner)
	Ui.anchor_at(banner, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	banner.offset_top = Pal.EDGE
	# progress, top right
	var prog := Ui.panel("Plate")
	_screen.add_child(prog)
	Ui.anchor_at(prog, Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	prog.offset_right = -Pal.EDGE
	prog.offset_top = Pal.EDGE
	var ph := Ui.hbox(Pal.S2)
	prog.add_child(ph)
	ph.add_child(Icon.make("trophy", 56, Pal.GOLD_HI))
	var pv := Ui.vbox(2)
	ph.add_child(pv)
	pv.add_child(Ui.label(Lang.f("%d / %d vaincus", [Profiles.beaten_count(), Profiles.opponents.size()]), "", Pal.FS_SMALL))
	var pb := ProgressBar.new()
	pb.max_value = Profiles.opponents.size()
	pb.value = Profiles.beaten_count()
	pb.custom_minimum_size = Vector2(260, 20)
	pv.add_child(pb)
	# the card
	var card := Ui.panel()
	_screen.add_child(card)
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = Pal.EDGE
	card.offset_right = Pal.EDGE + CARD_W
	card.offset_top = 176
	card.offset_bottom = -318
	_card = Ui.vbox(Pal.S2)
	card.add_child(_card)
	# a dark band under the trail, so it reads over the board
	var band := TextureRect.new()
	var bg := Gradient.new()
	bg.set_color(0, Color(0.03, 0.02, 0.01, 0.0))
	bg.set_color(1, Color(0.03, 0.02, 0.01, 0.78))
	var bgt := GradientTexture2D.new()
	bgt.gradient = bg
	bgt.fill_from = Vector2(0, 0)
	bgt.fill_to = Vector2(0, 1)
	bgt.width = 8
	bgt.height = 128
	band.texture = bgt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(band)
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 1.0
	band.anchor_bottom = 1.0
	band.offset_top = -360
	# the trail
	_trail = Control.new()
	_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_trail)
	_trail.anchor_left = 0.0
	_trail.anchor_right = 1.0
	_trail.anchor_top = 1.0
	_trail.anchor_bottom = 1.0
	_trail.offset_top = -306
	_trail.offset_bottom = -12
	_trail.draw.connect(_draw_trail)
	_trail.resized.connect(_layout_trail)
	_nodes.clear()
	var prev: Control
	for i in Profiles.opponents.size():
		var o: Dictionary = Profiles.opponents[i]
		var n := _path_node(i, o)
		_trail.add_child(n)
		_nodes[o["id"]] = n
		if prev:
			prev.focus_neighbor_right = n.get_path()
			n.focus_neighbor_left = prev.get_path()
		prev = n
	_layout_trail.call_deferred()
	if _sel_opp == "":
		_sel_opp = Profiles.next_challenge()
	_select_opponent(_sel_opp, false)
	Ui.slide_in(card, Vector2(-80, 0), 0.0)
	Ui.slide_in(_trail, Vector2(0, 80), 0.08)
	(_nodes[_sel_opp] as Control).grab_focus.call_deferred()


func _path_node(i: int, o: Dictionary) -> Button:
	var id := String(o["id"])
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 236)
	b.size = b.custom_minimum_size
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.tooltip_text = "%d. %s — %s" % [i + 1, Lang.t(String(o["name"])), _board_name(o)]
	var m := Medallion.make(UiKit.avatar_texture(String(o.get("avatar", "tofu"))), 150, _opp_state(id))
	m.position = Vector2(10, 4)
	m.size = Vector2(150, 150)
	m.pivot_offset = Vector2(75, 75)
	m.name = "Medallion"
	b.add_child(m)
	var num := Ui.label("%d" % (i + 1), "Hud", 40)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.position = Vector2(0, 160)
	num.size = Vector2(170, 44)
	b.add_child(num)
	var bn := Ui.label(_board_name(o), "Hud", Pal.FS_TINY - 2, Pal.DIM)
	bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bn.add_theme_constant_override("outline_size", 7)
	bn.position = Vector2(-20, 200)
	bn.size = Vector2(210, 34)
	b.add_child(bn)
	b.pressed.connect(func() -> void:
		Audio.play("ui.click")
		if _sel_opp == id:
			var go := _card.find_child("Play", true, false) as Control
			if go:
				go.grab_focus()
		else:
			_select_opponent(id))
	b.focus_entered.connect(func() -> void:
		if _sel_opp != id:
			_select_opponent(id))
	b.mouse_entered.connect(func() -> void:
		Audio.play("ui.hover", -16.0)
		if not Pal.reduced_motion():
			m.create_tween().tween_property(m, "scale", Vector2.ONE * (1.18 if _sel_opp == id else 1.08), 0.12))
	b.mouse_exited.connect(func() -> void:
		m.create_tween().tween_property(m, "scale", Vector2.ONE * (1.15 if _sel_opp == id else 1.0), 0.15))
	return b


func _layout_trail() -> void:
	if _trail == null:
		return
	var w := _trail.size.x
	var n := Profiles.opponents.size()
	var margin := 150.0
	for i in n:
		var b: Control = _nodes[Profiles.opponents[i]["id"]]
		var x := lerpf(margin, w - margin, float(i) / maxf(n - 1, 1))
		var y := 50.0 + sin(i * 1.3) * 26.0
		b.position = Vector2(x - b.size.x * 0.5, y)
	_trail.queue_redraw()


func _draw_trail() -> void:
	var n := Profiles.opponents.size()
	var pts: Array[Vector2] = []
	for i in n:
		var b: Control = _nodes[Profiles.opponents[i]["id"]]
		pts.append(b.position + Vector2(b.size.x * 0.5, 79))
	for i in n - 1:
		var a := pts[i]
		var c := pts[i + 1]
		var next_id := String(Profiles.opponents[i + 1]["id"])
		var done := Profiles.is_beaten(String(Profiles.opponents[i]["id"]))
		var open := Profiles.is_unlocked(next_id)
		var dir := (c - a).normalized()
		a += dir * 82.0
		c -= dir * 82.0
		if done and Profiles.is_beaten(next_id):
			_trail.draw_line(a, c, Pal.OUTLINE, 18.0, true)
			_trail.draw_line(a, c, Pal.GOLD, 9.0, true)
		else:
			var col := Pal.LEAF_HI if open else Pal.STONE_HI
			var length := a.distance_to(c)
			var steps := int(length / 30.0)
			for k in steps + 1:
				var p := a.lerp(c, float(k) / maxf(steps, 1))
				_trail.draw_circle(p, 9.0, Pal.OUTLINE, true, -1.0, true)
				_trail.draw_circle(p, 5.5, col, true, -1.0, true)


func _select_opponent(id: String, animate := true) -> void:
	_sel_opp = id
	var o := Profiles.opponent(id)
	if o.is_empty():
		return
	for k in _nodes:
		var m := (_nodes[k] as Control).get_node("Medallion") as Medallion
		m.selected = k == id
		var s := 1.15 if k == id else 1.0
		if Pal.reduced_motion():
			m.scale = Vector2.ONE * s
		else:
			m.create_tween().tween_property(m, "scale", Vector2.ONE * s, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	preview_board.emit(String(o.get("board", "prairie")))
	if game and game.camera:
		game.camera.frame_offset = Vector2(-430, 70)
	_fill_card(o)
	if animate:
		Ui.stagger(_card.get_children(), 0.03)


func _fill_card(o: Dictionary) -> void:
	for c in _card.get_children():
		c.queue_free()
	var id := String(o["id"])
	var i := Profiles.index_of(id)
	var open := Profiles.is_unlocked(id)
	var beaten := Profiles.is_beaten(id)
	var accent := Color(String(boards.get(o.get("board", ""), {}).get("accent", "8fd14a")))
	# heading: number, name, intro
	var head := Ui.hbox(Pal.S3)
	_card.add_child(head)
	head.add_child(_number_disc(i + 1, accent))
	var hv := Ui.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nm := Ui.title(String(o["name"]), 58)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(820, 0)
	hv.add_child(nm)
	hv.add_child(Ui.para(String(o.get("intro", "")), 820, "Dim", Pal.FS_SMALL))
	# the illustration on a halo of the board's colour
	var art := Control.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size = Vector2(0, 260)
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(art)
	var halo := Ui.full_rect(TextureRect.new())
	halo.texture = _halo(accent if open else Pal.STONE)
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(halo)
	var pic := Ui.full_rect(TextureRect.new())
	pic.texture = _art_texture(String(o.get("avatar", "tofu")))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.offset_top = 16
	pic.offset_bottom = -16
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not open:
		pic.modulate = Color(0.12, 0.1, 0.09, 0.95)
	art.add_child(pic)
	if not Pal.reduced_motion():
		pic.resized.connect(func() -> void: pic.pivot_offset = pic.size * Vector2(0.5, 1.0))
		var tw := pic.create_tween().set_loops()
		tw.tween_property(pic, "scale", Vector2(1.0, 1.025), 1.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pic, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE)
	if beaten:
		var seal := _seal("Vaincu", Pal.GOLD_HI, "star")
		art.add_child(seal)
		Ui.anchor_at(seal, Vector2(1.0, 0.0), Vector2(1.0, 0.0))
		seal.offset_right = -Pal.S2
		seal.offset_top = Pal.S2
	if not open:
		var lock := Ui.vbox(Pal.S2, BoxContainer.ALIGNMENT_CENTER)
		art.add_child(lock)
		Ui.anchor_at(lock, Vector2(0.5, 0.5))
		var li := Icon.make("lock", 130, Pal.CREAM)
		li.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lock.add_child(li)
		var prev_name := String(Profiles.opponents[i - 1]["name"]) if i > 0 else ""
		var why := Ui.para(Lang.f("Bats « %s » pour ouvrir ce chemin.", [Lang.t(prev_name)]), 760, "Hud", Pal.FS_BODY)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.add_child(why)
	# facts
	var facts := Ui.hbox(Pal.S2)
	_card.add_child(facts)
	facts.add_child(_fact("map", _board_name(o), accent))
	facts.add_child(_fact("crown", UiKit.elo_text(o), Pal.GOLD_HI))
	var r := Profiles.record(id)
	facts.add_child(_fact("trophy", Lang.f("%d V · %d D · %d N", [r["w"], r["l"], r["d"]]), Pal.CREAM))
	# colour and play
	var row := Ui.hbox(Pal.S2)
	_card.add_child(row)
	row.add_child(Ui.label("Tu joues", "", Pal.FS_SMALL + 2))
	var g := ButtonGroup.new()
	for s in [["white", "Blancs"], ["black", "Noirs"], ["random", "Hasard"]]:
		var cb := FxButton.make(s[1], "ChipButton", "", Vector2(0, 84))
		if s[0] == "black":
			cb.icon_color = Color("2b2622")
			cb.icon_line = Pal.CREAM
		cb.set_icon_name("dice" if s[0] == "random" else "pawn", 46.0)
		cb.toggle_mode = true
		cb.button_group = g
		cb.button_pressed = _side == s[0]
		cb.disabled = not open
		var key: String = s[0]
		cb.pressed.connect(func() -> void: _side = key)
		row.add_child(cb)
	var go := FxButton.make("Affronter" if open else "Verrouillé", "LeafButton" if open else "Button", "swords" if open else "lock", Vector2(0, 116))
	go.name = "Play"
	go.disabled = not open
	go.pulse = open and not beaten
	go.add_theme_font_size_override("font_size", 50)
	go.pressed.connect(func() -> void:
		var side := _side
		if side == "random":
			side = "white" if randf() < 0.5 else "black"
		play_requested.emit(id, side))
	_card.add_child(go)


# --- free play -----------------------------------------------------------------------------------------------------

func _build_free() -> void:
	var saved_choice: Dictionary = Profiles.current().get("free", {})
	_free_elo = clampi(int(saved_choice.get("elo", _free_elo)), FreePlay.MIN_ELO, FreePlay.MAX_ELO)
	_free_board = String(saved_choice.get("board", _free_board))
	if not boards.has(_free_board):
		_free_board = "prairie"
	var back := FxButton.make("", "IconButton", "back", Vector2(112, 112))
	back.tooltip_text = "Retour"
	back.pressed.connect(func() -> void: show_screen("title"))
	_screen.add_child(back)
	back.position = Vector2(Pal.EDGE, Pal.EDGE)
	var banner := Banner.make("Partie libre", Pal.FS_H2 + 6)
	_screen.add_child(banner)
	Ui.anchor_at(banner, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	banner.offset_top = Pal.EDGE
	var card := Ui.panel()
	_screen.add_child(card)
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = Pal.EDGE
	card.offset_right = Pal.EDGE + CARD_W
	card.offset_top = 176
	card.offset_bottom = -Pal.EDGE
	var v := Ui.vbox(Pal.S2)
	card.add_child(v)
	# the board: the ten, shown behind the card as they are picked
	v.add_child(_free_head("map", "Plateau"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var bg := ButtonGroup.new()
	var first: Control
	for o: Dictionary in Profiles.opponents:
		var key := String(o.get("board", ""))
		if not boards.has(key):
			continue
		var b := FxButton.make(_board_name(o), "ChipButton", "", Vector2((CARD_W - 120) / 3.0, 66))
		b.toggle_mode = true
		b.button_group = bg
		b.button_pressed = key == _free_board
		b.icon_color = Color(String(boards[key].get("accent", "f0c040")))
		b.set_icon_name("map", 40.0)
		b.pressed.connect(func() -> void:
			_free_board = key
			preview_board.emit(key)
			_store_free())
		grid.add_child(b)
		if b.button_pressed:
			first = b
	# the strength
	v.add_child(_free_head("crown", "Force de l'adversaire"))
	var sh := Ui.hbox(Pal.S3)
	v.add_child(sh)
	var med := Medallion.make(UiKit.avatar_texture(String(FreePlay.nearest(_free_elo).get("avatar", "tofu"))), 112, Medallion.State.BEATEN)
	med.badge = false
	sh.add_child(med)
	var sv := Ui.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	sh.add_child(sv)
	var elo_l := Ui.title("", Pal.FS_H2 + 6)
	sv.add_child(elo_l)
	var desc := Ui.label("", "Dim", Pal.FS_SMALL)
	sv.add_child(desc)
	var srow := Ui.hbox(Pal.S2)
	v.add_child(srow)
	var minus := FxButton.make("−", "IconButton", "", Vector2(88, 88))
	minus.add_theme_font_size_override("font_size", 56)
	var slider := HSlider.new()
	slider.min_value = FreePlay.MIN_ELO
	slider.max_value = FreePlay.MAX_ELO
	slider.step = FreePlay.STEP
	slider.value = _free_elo
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plus := FxButton.make("+", "IconButton", "", Vector2(88, 88))
	plus.add_theme_font_size_override("font_size", 56)
	srow.add_child(minus)
	srow.add_child(slider)
	srow.add_child(plus)
	var show_elo := func(e: int) -> void:
		elo_l.text = Lang.f("≈ %d Elo", [e])
		desc.text = _free_level_text(e)
		med.texture = UiKit.avatar_texture(String(FreePlay.nearest(e).get("avatar", "tofu")))
	show_elo.call(_free_elo)
	slider.value_changed.connect(func(x: float) -> void:
		_free_elo = int(x)
		show_elo.call(_free_elo)
		_store_free())
	minus.pressed.connect(func() -> void: slider.value -= FreePlay.STEP)
	plus.pressed.connect(func() -> void: slider.value += FreePlay.STEP)
	# colour and play
	var row := Ui.hbox(Pal.S2)
	v.add_child(row)
	row.add_child(Ui.label("Tu joues", "", Pal.FS_SMALL + 2))
	var g := ButtonGroup.new()
	for s in [["white", "Blancs"], ["black", "Noirs"], ["random", "Hasard"]]:
		var cb := FxButton.make(s[1], "ChipButton", "", Vector2(0, 84))
		if s[0] == "black":
			cb.icon_color = Color("2b2622")
			cb.icon_line = Pal.CREAM
		cb.set_icon_name("dice" if s[0] == "random" else "pawn", 46.0)
		cb.toggle_mode = true
		cb.button_group = g
		cb.button_pressed = _side == s[0]
		var key: String = s[0]
		cb.pressed.connect(func() -> void: _side = key)
		row.add_child(cb)
	var go := FxButton.make("Jouer", "LeafButton", "swords", Vector2(0, 116))
	go.name = "Play"
	go.pulse = true
	go.add_theme_font_size_override("font_size", 50)
	go.pressed.connect(func() -> void:
		var side := _side
		if side == "random":
			side = "white" if randf() < 0.5 else "black"
		free_requested.emit(_free_elo, _free_board, side))
	v.add_child(go)
	preview_board.emit(_free_board)
	if game and game.camera:
		game.camera.frame_offset = Vector2(-430, 70)
	Ui.slide_in(card, Vector2(-80, 0), 0.0)
	(first if first else go).grab_focus.call_deferred()


# --- online games --------------------------------------------------------------------------------------------------

func _leave_online() -> void:
	if online:
		online.leave()
	show_screen("title")


## Create a room (board, colour) and share its code, or join a friend's room with theirs.
func _build_online() -> void:
	var saved_choice: Dictionary = Profiles.current().get("online", {})
	_net_board = String(saved_choice.get("board", _net_board))
	_net_side = String(saved_choice.get("side", _net_side))
	if not boards.has(_net_board):
		_net_board = "prairie"
	var back := FxButton.make("", "IconButton", "back", Vector2(112, 112))
	back.tooltip_text = "Retour"
	back.pressed.connect(_leave_online)
	_screen.add_child(back)
	back.position = Vector2(Pal.EDGE, Pal.EDGE)
	var banner := Banner.make("Partie en ligne", Pal.FS_H2 + 6)
	_screen.add_child(banner)
	Ui.anchor_at(banner, Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	banner.offset_top = Pal.EDGE
	var card := Ui.panel()
	_screen.add_child(card)
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = Pal.EDGE
	card.offset_right = Pal.EDGE + CARD_W
	card.offset_top = 176
	card.offset_bottom = -Pal.EDGE
	var v := Ui.vbox(Pal.S2)
	card.add_child(v)
	# create: the board and the colour, then the code to share
	v.add_child(_free_head("crown", "Créer une partie"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var bg := ButtonGroup.new()
	var first: Control
	for o: Dictionary in Profiles.opponents:
		var key := String(o.get("board", ""))
		if not boards.has(key):
			continue
		var b := FxButton.make(_board_name(o), "ChipButton", "", Vector2((CARD_W - 120) / 3.0, 62))
		b.toggle_mode = true
		b.button_group = bg
		b.button_pressed = key == _net_board
		b.icon_color = Color(String(boards[key].get("accent", "f0c040")))
		b.set_icon_name("map", 38.0)
		b.pressed.connect(func() -> void:
			_net_board = key
			preview_board.emit(key)
			_store_online())
		grid.add_child(b)
		if b.button_pressed:
			first = b
	var row := Ui.hbox(Pal.S2)
	v.add_child(row)
	row.add_child(Ui.label("Tu joues", "", Pal.FS_SMALL + 2))
	var g := ButtonGroup.new()
	for s in [["white", "Blancs"], ["black", "Noirs"], ["random", "Hasard"]]:
		var cb := FxButton.make(s[1], "ChipButton", "", Vector2(0, 80))
		if s[0] == "black":
			cb.icon_color = Color("2b2622")
			cb.icon_line = Pal.CREAM
		cb.set_icon_name("dice" if s[0] == "random" else "pawn", 44.0)
		cb.toggle_mode = true
		cb.button_group = g
		cb.button_pressed = _net_side == s[0]
		var key: String = s[0]
		cb.pressed.connect(func() -> void:
			_net_side = key
			_store_online())
		row.add_child(cb)
	var create := FxButton.make("Créer la partie", "LeafButton", "users", Vector2(0, 108))
	create.add_theme_font_size_override("font_size", 44)
	create.pressed.connect(func() -> void:
		_set_net_status("Connexion au serveur…")
		online.host(_net_side, _net_board))
	v.add_child(create)
	v.add_child(Ui.separator(CARD_W - 80))
	# join: the friend's code
	v.add_child(_free_head("swords", "Rejoindre une partie"))
	var jr := Ui.hbox(Pal.S2)
	v.add_child(jr)
	var field := LineEdit.new()
	field.placeholder_text = "CODE"
	field.max_length = OnlineClient.CODE_LEN
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(440, 104)
	field.add_theme_font_size_override("font_size", 60)
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jr.add_child(field)
	var join := FxButton.make("Rejoindre", "GoldButton", "play", Vector2(0, 104))
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.disabled = true
	jr.add_child(join)
	field.text_changed.connect(func(t: String) -> void:
		var c := OnlineClient.clean_code(t)
		if c != t:
			var at := field.caret_column
			field.text = c
			field.caret_column = mini(at, c.length())
		join.disabled = c.length() != OnlineClient.CODE_LEN)
	var go_join := func() -> void:
		if field.text.length() == OnlineClient.CODE_LEN:
			_set_net_status("Connexion au serveur…")
			online.join(field.text)
	join.pressed.connect(go_join)
	field.text_submitted.connect(func(_t: String) -> void: go_join.call())
	_net_status = Ui.para("", CARD_W - 80, "Dim", Pal.FS_SMALL)
	v.add_child(_net_status)
	_set_net_status("Ton ami te donne le code de sa partie : saisis-le ici. Pas de limite de temps entre les coups.")
	preview_board.emit(_net_board)
	if game and game.camera:
		game.camera.frame_offset = Vector2(-430, 70)
	Ui.slide_in(card, Vector2(-80, 0), 0.0)
	(first if first else create).grab_focus.call_deferred()


func _set_net_status(text: String, error := false) -> void:
	if _net_status == null or not is_instance_valid(_net_status):
		return
	_net_status.text = Lang.t(text)
	if error:
		_net_status.add_theme_color_override("font_color", Pal.EMBER_HI)
	else:
		_net_status.remove_theme_color_override("font_color")


func _store_online() -> void:
	var p := Profiles.current()
	p["online"] = {"board": _net_board, "side": _net_side}
	Profiles.save()


## The room opened: the code to share while the friend is awaited (the game starts by itself when they come).
func _on_net_room(info: Dictionary) -> void:
	if _screen_name != "online" or not visible or String(info.get("state", "")) != "waiting":
		return
	if is_instance_valid(_overlay):
		return
	var code := String(info.get("code", ""))
	_overlay = Ui.full_rect(Control.new())
	_root.add_child(_overlay)
	_overlay.add_child(Ui.veil(0.55))
	var p := Ui.panel()
	_overlay.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(980, 0)
	p.add_child(v)
	var t := Ui.title("Ta partie est prête")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var hint := Ui.para("Envoie ce code à ton adversaire : la partie commence dès qu'il le saisit dans « En ligne ».", 900, "", Pal.FS_BODY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var big := Ui.title(" ".join(code.split("")), 150, Color(1.0, 0.95, 0.6), Color(0.97, 0.6, 0.12))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var wait := Ui.label("En attente de ton adversaire…", "Dim", Pal.FS_BODY)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wait)
	var row := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(row)
	var copy := FxButton.make("Copier le code", "GoldButton", "scroll", Vector2(440, 108))
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		Ui.toast(_root, Lang.t("Code copié"), "check"))
	row.add_child(copy)
	var cancel := FxButton.make("Annuler", "DarkButton", "back", Vector2(340, 108))
	cancel.pressed.connect(func() -> void:
		online.leave()
		_overlay.queue_free()
		_overlay = null
		_set_net_status(""))
	row.add_child(cancel)
	Ui.pop_in(p)
	copy.grab_focus.call_deferred()


func _on_net_failed(why: String) -> void:
	if _screen_name != "online" or not visible:
		return
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
	var text: String = {
		"not_found": "Aucune partie avec ce code : vérifie-le auprès de ton ami.",
		"full": "Cette partie a déjà ses deux joueurs.",
		"version": "Ta version du jeu et celle du serveur ne correspondent pas : mets le jeu à jour.",
		"network": "Impossible de joindre le serveur : vérifie ta connexion à Internet.",
	}.get(why, "La connexion a échoué.")
	_set_net_status(text, true)


func _free_head(icon: String, text: String) -> Control:
	var h := Ui.hbox(Pal.S2)
	h.add_child(Icon.make(icon, 46, Pal.GOLD_HI))
	h.add_child(Ui.label(text, "H2", 38))
	return h


## What a strength means: the champion it matches, else a level of play.
func _free_level_text(elo: int) -> String:
	var n := FreePlay.nearest(elo)
	if not n.is_empty() and absi(int(n["elo"]) - elo) <= 25:
		return Lang.f("La force de « %s »", [Lang.t(String(n["name"]))])
	var tier := "Maître"
	for t in [[700, "Débutant"], [1100, "Amateur"], [1500, "Joueur de club"], [1900, "Joueur confirmé"], [2300, "Expert"]]:
		if elo < int(t[0]):
			tier = String(t[1])
			break
	return Lang.t(tier)


func _store_free() -> void:
	var p := Profiles.current()
	p["free"] = {"elo": _free_elo, "board": _free_board}
	Profiles.save()


func _number_disc(n: int, accent: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(112, 112)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var ctr := c.size * 0.5
		c.draw_circle(ctr + Vector2(0, 5), 54, Pal.with_alpha(Pal.SHADOW, 0.5), true, -1.0, true)
		c.draw_circle(ctr, 54, Pal.OUTLINE, true, -1.0, true)
		c.draw_circle(ctr, 48, accent.darkened(0.35), true, -1.0, true)
		c.draw_circle(ctr - Vector2(0, 3), 44, accent, true, -1.0, true)
		var f := UiTheme.display
		var s := str(n)
		var fs := 62
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := ctr + Vector2(-w * 0.5, fs * 0.36)
		c.draw_string_outline(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Pal.OUTLINE)
		c.draw_string(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Pal.CREAM))
	return c


func _fact(icon: String, text: String, col: Color) -> Control:
	var p := Ui.panel("Plate")
	p.add_theme_stylebox_override("panel", PlankBox.plate(0.7).with({"shadow": 0.0, "rim": 0.0}).margins(Pal.S2, 6))
	var h := Ui.hbox(Pal.S1)
	p.add_child(h)
	h.add_child(Icon.make(icon, 40, col))
	h.add_child(Ui.label(text, "", Pal.FS_TINY + 2))
	return p


func _seal(text: String, col: Color, icon: String) -> Control:
	var p := Ui.panel("Plate")
	var h := Ui.hbox(Pal.S1)
	p.add_child(h)
	h.add_child(Icon.make(icon, 44, col))
	h.add_child(Ui.label(text, "", Pal.FS_SMALL, col))
	p.rotation = deg_to_rad(4.0)
	return p


func _halo(col: Color) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.2), 0.55))
	g.add_point(0.45, Color(col, 0.22))
	g.set_color(g.get_point_count() - 1, Color(col, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.62)
	gt.fill_to = Vector2(0.98, 0.62)
	gt.width = 256
	gt.height = 256
	return gt


## The creature's large illustration (tools/build_portraits.py --art), else its portrait.
static func _art_texture(id: String) -> Texture2D:
	var p := "res://assets/gen/art/%s.png" % id
	if ResourceLoader.exists(p):
		return load(p)
	return UiKit.avatar_texture(id)


# --- profiles ------------------------------------------------------------------------------------------------------

func _build_profiles() -> void:
	_screen.add_child(Ui.veil(0.35, false))
	var p := Ui.panel()
	_screen.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S4)
	v.custom_minimum_size = Vector2(1560, 0)
	p.add_child(v)
	var head := Ui.hbox(Pal.S3)
	v.add_child(head)
	head.add_child(Icon.make("users", 76, Pal.GOLD_HI))
	head.add_child(Ui.title("Profils"))
	head.add_child(Ui.spacer(0, 0, true))
	head.add_child(Ui.label("Chaque profil garde sa progression et sa partie en cours.", "Dim", Pal.FS_SMALL))
	v.add_child(Ui.separator(1560))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Pal.S3)
	grid.add_theme_constant_override("v_separation", Pal.S3)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var first: Control
	for prof in Profiles.all():
		var card := _profile_card(prof)
		grid.add_child(card)
		if String(prof["id"]) == Profiles.current_id():
			first = card
	if Profiles.all().size() < 8:
		var nv := Ui.vbox(Pal.S2, BoxContainer.ALIGNMENT_CENTER)
		nv.custom_minimum_size = Vector2(330, 300)
		var pi := Icon.make("plus", 110, Pal.LEAF_HI)
		pi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		nv.add_child(pi)
		var nl := Ui.label("Nouveau profil", "H2", 40)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nv.add_child(nl)
		var nb := _content_button(nv, "DarkButton")
		nb.pressed.connect(func() -> void:
			_edit_id = ""
			_edit_avatar = Profiles.avatars.pick_random()
			show_screen("profile_edit"))
		grid.add_child(nb)
	var bar := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(bar)
	var back := FxButton.make("Retour", "DarkButton", "back", Vector2(360, 104))
	back.pressed.connect(func() -> void: show_screen("title"))
	bar.add_child(back)
	var ed := FxButton.make("Modifier", "Button", "pencil", Vector2(360, 104))
	ed.pressed.connect(func() -> void:
		_edit_id = Profiles.current_id()
		_edit_avatar = String(Profiles.current().get("avatar", Profiles.default_avatar()))
		show_screen("profile_edit"))
	bar.add_child(ed)
	var del := FxButton.make("Supprimer", "EmberButton", "trash", Vector2(380, 104))
	del.pressed.connect(func() -> void:
		var cur := Profiles.current()
		_overlay = Ui.confirm(self, Lang.f("Supprimer « %s » ?", [Lang.t(String(cur.get("name", "")))]),
			Lang.f("Sa progression (%d champions vaincus) et sa partie en cours seront effacées. C'est définitif.", [Profiles.beaten_count()]),
			"Supprimer", func() -> void:
				Profiles.remove(String(cur["id"]))
				show_screen("profiles"), "EmberButton", "trash"))
	bar.add_child(del)
	Ui.pop_in(p)
	if first:
		first.grab_focus.call_deferred()


func _profile_card(prof: Dictionary) -> FxButton:
	var id := String(prof["id"])
	var cur := id == Profiles.current_id()
	var v := Ui.vbox(Pal.S1, BoxContainer.ALIGNMENT_CENTER)
	v.custom_minimum_size = Vector2(330, 300)
	var m := Medallion.make(UiKit.avatar_texture(String(prof.get("avatar", Profiles.default_avatar()))), 160,
		Medallion.State.BEATEN if cur else Medallion.State.PLAIN)
	m.badge = false
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(m)
	var nl := Ui.label(String(prof.get("name", "")), "H2", 40)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size = Vector2(320, 0)
	v.add_child(nl)
	var n := (prof.get("beaten", []) as Array).size()
	var st := Ui.label((Lang.t("Actif  ·  ") if cur else "") + Lang.f("%d / %d vaincus", [n, Profiles.opponents.size()]), "Dim", Pal.FS_TINY + 2)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cur:
		st.add_theme_color_override("font_color", Pal.GOLD_HI)
	v.add_child(st)
	var b := _content_button(v, "Button" if cur else "DarkButton")
	b.pressed.connect(func() -> void:
		Profiles.select(id)
		_side = String(Profiles.current().get("last_side", "white"))
		show_screen("profiles"))
	return b


func _build_profile_edit() -> void:
	_screen.add_child(Ui.veil(0.35, false))
	var prof: Dictionary = Profiles.data["profiles"].get(_edit_id, {})
	var p := Ui.panel()
	_screen.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S4)
	p.add_child(v)
	var head := Ui.hbox(Pal.S3)
	v.add_child(head)
	head.add_child(Icon.make("pencil" if _edit_id != "" else "plus", 70, Pal.GOLD_HI))
	head.add_child(Ui.title("Nouveau profil" if _edit_id == "" else "Modifier le profil"))
	var body := Ui.hbox(Pal.S5)
	v.add_child(body)
	# left: the chosen portrait, large, and the name
	var left := Ui.vbox(Pal.S3, BoxContainer.ALIGNMENT_CENTER)
	left.custom_minimum_size = Vector2(560, 0)
	body.add_child(left)
	var big := Medallion.make(UiKit.avatar_texture(_edit_avatar), 340, Medallion.State.BEATEN)
	big.badge = false
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(big)
	left.add_child(Ui.label("Nom", "Dim"))
	var name_edit := LineEdit.new()
	name_edit.text = String(prof.get("name", ""))
	name_edit.placeholder_text = "Aventurier"
	name_edit.max_length = Profiles.MAX_NAME
	name_edit.custom_minimum_size = Vector2(560, 0)
	left.add_child(name_edit)
	# right: the portraits
	var right := Ui.vbox(Pal.S2)
	body.add_child(right)
	right.add_child(Ui.label("Choisis ton personnage", "H2", 42))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", Pal.S2)
	grid.add_theme_constant_override("v_separation", Pal.S2)
	right.add_child(grid)
	var meds: Dictionary = {}
	for a: String in Profiles.avatars:
		var b := Button.new()
		b.custom_minimum_size = Vector2(148, 148)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for stn in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		var m := Medallion.make(UiKit.avatar_texture(a), 140, Medallion.State.BEATEN if a == _edit_avatar else Medallion.State.PLAIN)
		m.badge = false
		m.selected = a == _edit_avatar
		m.position = Vector2(4, 4)
		m.size = Vector2(140, 140)
		b.add_child(m)
		meds[a] = m
		var key: String = a
		var pick := func() -> void:
			_edit_avatar = key
			big.texture = UiKit.avatar_texture(key)
			for k in meds:
				(meds[k] as Medallion).selected = k == key
				(meds[k] as Medallion).state = Medallion.State.BEATEN if k == key else Medallion.State.PLAIN
			if not Pal.reduced_motion():
				big.pivot_offset = big.size * 0.5
				big.scale = Vector2.ONE * 0.9
				big.create_tween().tween_property(big, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		b.pressed.connect(func() -> void:
			Audio.play("ui.click")
			pick.call())
		b.mouse_entered.connect(func() -> void: Audio.play("ui.hover", -16.0))
		b.focus_entered.connect(func() -> void: m.ring_override = Pal.GOLD_HI)
		b.focus_exited.connect(func() -> void: m.ring_override = Color(0, 0, 0, 0))
		grid.add_child(b)
	var bar := Ui.hbox(Pal.S3, BoxContainer.ALIGNMENT_END)
	v.add_child(bar)
	var back := FxButton.make("Annuler", "DarkButton", "close", Vector2(340, 104))
	back.pressed.connect(func() -> void: show_screen("profiles"))
	bar.add_child(back)
	var ok := FxButton.make("Créer" if _edit_id == "" else "Enregistrer", "LeafButton", "check", Vector2(420, 104))
	ok.pressed.connect(func() -> void:
		if _edit_id == "":
			Profiles.create(name_edit.text, _edit_avatar)
		else:
			Profiles.update(_edit_id, {"name": name_edit.text, "avatar": _edit_avatar})
		show_screen("profiles"))
	bar.add_child(ok)
	name_edit.text_submitted.connect(func(_t: String) -> void: ok.pressed.emit())
	Ui.pop_in(p)
	if not Pal.touch():
		name_edit.grab_focus.call_deferred()


# --- settings ------------------------------------------------------------------------------------------------------

## Who made what the game is built on, with thanks and links; a free fan game, made for no money.
const CREDITS := [
	["Dofus Retro, © Ankama", "Les créatures, les décors, les sons et les musiques viennent de Dofus Retro. Merci à Ankama et à ses artistes pour ce monde qui nous accompagne depuis des années.", "https://www.dofus-retro.com/"],
	["Stockfish", "Le moteur d'échecs libre (GPLv3) qui calcule les coups des adversaires. Merci à ses nombreux contributeurs.", "https://stockfishchess.org/"],
	["Lichess", "Sa base de parties ouverte (domaine public) a servi de référence pour régler les erreurs des adversaires. Merci pour ce site libre et gratuit.", "https://database.lichess.org/"],
	["Godot Engine", "Le moteur de jeu libre (MIT) avec lequel Retro Chess est fait.", "https://godotengine.org/"],
	["Fredoka et Nunito", "Les polices du jeu (SIL Open Font License).", "https://fonts.google.com/"],
	["Retro Chess", "Le code du jeu est ouvert : réutilisable librement en citant ses auteurs.", "https://github.com/BigFatDeuce/retro-chess-game"],
]


func _open_credits() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var root := Ui.full_rect(Control.new())
	root.theme = UiTheme.ensure()
	layer.add_child(root)
	var close := func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	var v := Ui.veil(0.6)
	v.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close.call())
	root.add_child(v)
	var p := Ui.panel()
	root.add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var box := Ui.vbox(Pal.S3)
	p.add_child(box)
	var t := Ui.title("Crédits et remerciements", Pal.FS_H2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var intro := Ui.para("Retro Chess est un jeu de fan gratuit, fait par passion, sans aucun but commercial, et non affilié à Ankama.", 1300, "", Pal.FS_SMALL)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(intro)
	for c: Array in CREDITS:
		var row := Ui.hbox(Pal.S3)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var txt := Ui.vbox(2)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(Ui.label(c[0], "", Pal.FS_BODY, Pal.GOLD_HI))
		txt.add_child(Ui.para(c[1], 1000, "Dim", Pal.FS_TINY))
		row.add_child(txt)
		var url: String = c[2]
		var go := FxButton.make("Visiter", "DarkButton", "chevron_r", Vector2(250, 80))
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.tooltip_text = url
		go.pressed.connect(func() -> void: OS.shell_open(url))
		row.add_child(go)
		box.add_child(row)
	var ok := FxButton.make("Fermer", "DarkButton", "close", Vector2(380, 100))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close)
	box.add_child(ok)
	root.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			close.call())
	Ui.pop_in(p)
	ok.grab_focus.call_deferred()


func _open_settings() -> void:
	var sp := SettingsPanel.new()
	_screen.add_child(sp)
	sp.closed.connect(func() -> void: show_screen("title"))
