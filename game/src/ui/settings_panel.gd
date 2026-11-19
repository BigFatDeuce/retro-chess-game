class_name SettingsPanel
extends Control
## The settings, in four tabs (sound, game, display, accessibility). Every change applies and saves at once
## (Settings). Opened from the title screen and from the pause menu; `closed` when the player leaves.

signal closed

const TABS := [["sound", "Son", "sound"], ["game", "Jeu", "swords"], ["display", "Affichage", "eye"],
	["access", "Accessibilité", "info"]]

var _tab := "sound"
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	Ui.full_rect(self)
	# a new language: the sentences put together in code are rebuilt (the rest translates itself)
	Settings.changed.connect(func(k: String) -> void:
		if (k == "language" or k == "fullscreen") and is_inside_tree():
			_show.call_deferred(_tab))
	theme = UiTheme.ensure()
	add_child(Ui.veil(0.5))
	var p := Ui.panel()
	add_child(p)
	Ui.anchor_at(p, Vector2(0.5, 0.5))
	var v := Ui.vbox(Pal.S4)
	v.custom_minimum_size = Vector2(1500, 860)
	p.add_child(v)
	var head := Ui.hbox(Pal.S4)
	v.add_child(head)
	head.add_child(Icon.make("gear", 76, Pal.GOLD_HI))
	head.add_child(Ui.title("Réglages", Pal.FS_TITLE))
	head.add_child(Ui.spacer(0, 0, true))
	var tabs := Ui.hbox(Pal.S2)
	head.add_child(tabs)
	var g := ButtonGroup.new()
	for t in TABS:
		var b := FxButton.make(t[1], "ChipButton", t[2], Vector2(0, 84))
		b.icon_px = 40.0
		b.set_icon_name(t[2], 40.0)
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = t[0] == _tab
		var key: String = t[0]
		b.pressed.connect(func() -> void: _show(key))
		tabs.add_child(b)
		_tab_buttons[key] = b
	v.add_child(Ui.separator(1500))
	_content = Ui.vbox(Pal.S4)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_content)
	var back := FxButton.make("Retour", "DarkButton", "back", Vector2(400, 104))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)
	_show(_tab)
	Ui.pop_in(p)
	(_tab_buttons[_tab] as Button).grab_focus.call_deferred()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	# shoulder buttons / Q-E switch tabs
	elif event.is_action_pressed("ui_page_up") or event.is_action_pressed("ui_page_down"):
		var keys := TABS.map(func(t): return t[0])
		var i := keys.find(_tab) + (1 if event.is_action_pressed("ui_page_down") else -1)
		var key: String = keys[wrapi(i, 0, keys.size())]
		(_tab_buttons[key] as Button).button_pressed = true
		_show(key)
		get_viewport().set_input_as_handled()


func _show(tab: String) -> void:
	_tab = tab
	for c in _content.get_children():
		c.queue_free()
	match tab:
		"sound":
			_slider("music", "music", "Musique")
			_slider("sfx", "sound", "Bruitages")
			_slider("ambient", "leaf", "Ambiance de la nature")
		"game":
			var langs: Array = []
			for l in Lang.LANGS:
				langs.append([l[0], l[1]])
			_choice("language", "scroll", "Langue", langs)
			if Updater.supported():
				_switch("check_updates", "refresh", Lang.f("Chercher les mises à jour au lancement (version %s)", [Updater.version()]))
			_choice("anim_speed", "hourglass", "Vitesse des créatures", [[0.75, "Lente"], [1.0, "Normale"], [1.5, "Rapide"]])
			_row("pawn", "Pièces", Ui.piece_set_picker(54.0))
			_switch("see_through", "eye", Lang.t("Pièces cachées en transparence") + ("" if Pal.touch() else "  (F1)"))
			_switch("ambient_life", "leaf", "Vie autour du plateau (créatures, papillons)")
		"display":
			if not OS.has_feature("mobile"):
				_switch("fullscreen", "target", Lang.t("Plein écran") + "  (F11)")
			if not OS.has_feature("mobile") and not OS.has_feature("web"):
				var sizes: Array = []
				for s in Settings.WINDOW_SIZES:
					sizes.append([s, s.get_slice("x", 1) + "p"])
				_choice("window_size", "map", "Taille de la fenêtre", sizes)
			if not OS.has_feature("mobile"):
				_choice("cursor_size", "target", "Taille du curseur", [[0.75, "Petit"], [1.0, "Normal"], [1.3, "Grand"],
					[1.6, "Très grand"]])
			_switch("vsync", "refresh", "Synchronisation verticale")
			# on computers and phones alike: many phones show 90 or 120 images / s
			var fps: Array = []
			for n: int in Settings.FPS_CHOICES:
				fps.append([n, str(n) if n > 0 else "Sans limite"])
			_choice("max_fps", "hourglass", "Images par seconde", fps)
			_switch("power_save", "leaf", "Économie d'énergie en arrière-plan")
			if OS.has_feature("web"):
				var res: Array = []
				for h: int in Settings.WEB_RESOLUTIONS:
					res.append([h, Lang.t("Auto") if h == 0 else "%dp" % h])
				_choice("web_resolution", "map", "Résolution", res)
				_switch("performance", "sparkle", "Mode performance (machines peu puissantes)")
				_content.add_child(Ui.para(Lang.t("Auto dessine le jeu à la résolution de ton écran. Le mode performance le dessine en 720p au plus, ") +
					Lang.t("sans la vie autour du plateau ni la transparence des pièces, avec moins d'animations dans l'interface."), 1380, "Dim"))
		"access":
			_switch("reduce_motion", "sparkle", "Réduire les animations de l'interface")
			_switch("see_through", "eye", "Pièces cachées en transparence")
			var note := Ui.para(Lang.t("Les déplacements et attaques des créatures gardent leur vitesse réglée dans « Jeu ». ") +
				Lang.t("Au clavier : flèches et Entrée ; à la manette : croix et A ; Échap ou B pour revenir."), 1380, "Dim")
			_content.add_child(note)
	Ui.stagger(_content.get_children(), 0.035)


func _row(icon: String, text: String, ctrl: Control) -> void:
	var h := Ui.hbox(Pal.S4)
	h.custom_minimum_size = Vector2(0, 96)
	var ic := Icon.make(icon, 58, Pal.GOLD_HI)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := Ui.label(text, "", Pal.FS_BODY + 2)
	l.custom_minimum_size = Vector2(700, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctrl)
	_content.add_child(h)


func _slider(key: String, icon: String, text: String) -> void:
	var h := Ui.hbox(Pal.S3)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(520, 60)
	var pct := Ui.label("%d %%" % roundi(s.value * 100.0), "Dim", Pal.FS_BODY)
	pct.custom_minimum_size = Vector2(120, 0)
	s.value_changed.connect(func(x: float) -> void:
		Settings.set_value(key, x)
		pct.text = "%d %%" % roundi(x * 100.0))
	s.drag_ended.connect(func(_c: bool) -> void:
		if key == "sfx":
			Audio.play("game.select"))
	h.add_child(s)
	h.add_child(pct)
	_row(icon, text, h)


func _switch(key: String, icon: String, text: String) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_value(key))
	cb.toggled.connect(func(on: bool) -> void:
		Audio.play("ui.click")
		Settings.set_value(key, on)
		if key == "performance":
			_show.call_deferred(_tab))  # the switches it turned are shown as they now are
	_row(icon, text, cb)


func _choice(key: String, icon: String, text: String, options: Array) -> void:
	var h: Container = Ui.hbox(Pal.S2)
	if options.size() > 4:  # the languages: two rows of chips
		h = GridContainer.new()
		(h as GridContainer).columns = 3
		h.add_theme_constant_override("h_separation", Pal.S2)
		h.add_theme_constant_override("v_separation", Pal.S2)
	var g := ButtonGroup.new()
	var cur: Variant = Settings.get_value(key)
	for o in options:
		var b := FxButton.make(String(o[1]), "ChipButton", "", Vector2(0, 80))
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = (cur is float and o[0] is float and is_equal_approx(cur, o[0])) or str(cur) == str(o[0])
		var val: Variant = o[0]
		b.pressed.connect(func() -> void: Settings.set_value(key, val))
		h.add_child(b)
	_row(icon, text, h)
