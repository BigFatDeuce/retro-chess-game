extends Node
## The design system on one sheet (buttons in every variation and state, icons, medallions, banner, titles,
## fields, panels), captured for review. Run: godot --path game res://tests/ui_kit_test.tscn -- <out.png>

var out := "user://ui_kit.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		out = args[0]
	RenderingServer.set_default_clear_color(Color("47613c"))
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Ui.full_rect(Control.new())
	root.theme = UiTheme.ensure()
	layer.add_child(root)
	var bg := Ui.full_rect(ColorRect.new())
	bg.color = Color("3d5a34")
	root.add_child(bg)
	var margin := MarginContainer.new()
	Ui.full_rect(margin)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 40)
	root.add_child(margin)
	var cols := Ui.hbox(Pal.S5)
	margin.add_child(cols)

	# column 1: buttons
	var c1 := Ui.vbox(Pal.S3)
	cols.add_child(c1)
	c1.add_child(Banner.make("Le Chemin"))
	for v in [["Jouer", "LeafButton", "play"], ["Réglages", "Button", "gear"], ["Abandonner", "EmberButton", "flag"],
			["Récompense", "GoldButton", "trophy"], ["Retour", "DarkButton", "back"], ["Sans icône", "Button", ""]]:
		c1.add_child(FxButton.make(v[0], v[1], v[2], Vector2(520, 104)))
	var dis := FxButton.make("Verrouillé", "Button", "lock", Vector2(520, 104))
	dis.disabled = true
	c1.add_child(dis)
	var row := Ui.hbox(Pal.S2)
	c1.add_child(row)
	for n in ["pause", "gear", "eye", "scroll", "home", "target"]:
		row.add_child(FxButton.make("", "IconButton", n, Vector2(112, 112)))
	var chips := Ui.hbox(Pal.S2)
	c1.add_child(chips)
	var g := ButtonGroup.new()
	for n in ["Lentes", "Normales", "Rapides"]:
		var b := FxButton.make(n, "ChipButton", "", Vector2(0, 80))
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = n == "Normales"
		chips.add_child(b)

	# column 2: panel with text, fields, medallions
	var p := Ui.panel()
	cols.add_child(p)
	var c2 := Ui.vbox(Pal.S3)
	c2.custom_minimum_size = Vector2(760, 0)
	p.add_child(c2)
	var t := Ui.title("Victoire !", Pal.FS_TITLE)
	c2.add_child(t)
	c2.add_child(Ui.label("Le Gardien des Prairies", "H2"))
	c2.add_child(Ui.para("Texte courant en Nunito : bats l'adversaire pour ouvrir le plateau suivant. ≈ 400 Elo (estimé).", 740))
	c2.add_child(Ui.label("Texte secondaire, plus discret", "Dim"))
	c2.add_child(Ui.separator(740))
	var meds := Ui.hbox(Pal.S3)
	c2.add_child(meds)
	var st := [Medallion.State.BEATEN, Medallion.State.CURRENT, Medallion.State.OPEN, Medallion.State.LOCKED, Medallion.State.PLAIN]
	var ids := ["piou_bleu", "bouftou", "crabe", "black_knight", "white_pawn"]
	for i in 5:
		var m := Medallion.make(UiKit.avatar_texture(ids[i]), 132, st[i])
		m.selected = i == 1
		meds.add_child(m)
	var le := LineEdit.new()
	le.text = "Aventurier"
	le.custom_minimum_size = Vector2(740, 0)
	c2.add_child(le)
	var sl := HSlider.new()
	sl.value = 70
	sl.custom_minimum_size = Vector2(740, 58)
	c2.add_child(sl)
	var sw_row := Ui.hbox(Pal.S3)
	c2.add_child(sw_row)
	var sw1 := CheckButton.new()
	sw1.button_pressed = true
	sw_row.add_child(sw1)
	sw_row.add_child(CheckButton.new())
	var pb := ProgressBar.new()
	pb.value = 30
	pb.custom_minimum_size = Vector2(740, 30)
	c2.add_child(pb)

	# column 3: icons, plate, parchment
	var c3 := Ui.vbox(Pal.S3)
	cols.add_child(c3)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	c3.add_child(grid)
	for n in Icon.NAMES:
		grid.add_child(Icon.make(n, 64))
	var plate := Ui.panel("Plate")
	c3.add_child(plate)
	var ph := Ui.hbox(Pal.S2)
	plate.add_child(ph)
	ph.add_child(Medallion.make(UiKit.avatar_texture("tofu"), 110, Medallion.State.PLAIN))
	var pv := Ui.vbox(0)
	ph.add_child(pv)
	pv.add_child(Ui.label("La Glaneuse", "Hud"))
	pv.add_child(Ui.label("≈ 850 Elo · estimé", "Dim"))
	var parch := Ui.panel("Parchment")
	c3.add_child(parch)
	var pc := Ui.vbox(4)
	parch.add_child(pc)
	pc.add_child(Ui.label("1.  e4      e5", "Ink"))
	pc.add_child(Ui.label("2.  Cf3    Cc6", "Ink"))
	pc.add_child(Ui.label("Historique des coups", "InkDim"))
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("UI KIT SHOT ", img.get_size())
	get_tree().quit()
