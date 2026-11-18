class_name LogoFx
extends Control
## The title logo's effects, laid over a TextureRect (full rect child): a band of light sweeping across it now
## and then, star glints popping on its letters and leaves, twinkles drifting up around it, and a burst of
## sparks when it appears. With "Réduire les animations": the logo alone, still.

const SHADER := preload("res://src/ui/kit/logo_shine.gdshader")
const GLINT_EVERY := 0.28  ## s between two glints
const GLINT_LIFE := 0.75
const SHINE_EVERY := 5.5  ## s between two sweeps

var logo: TextureRect
var _spots: PackedVector2Array = []  ## opaque points of the picture (0..1), where glints may appear
var _glints: Array[Dictionary] = []  ## {"p": uv, "t": age, "s": size, "r": spin}
var _next_glint := 0.6
var _mat: ShaderMaterial
var _sweep: Tween
var _twinkle: CPUParticles2D

static var _star: Texture2D


## A soft four-pointed star, white (tinted by the particles / draw colour).
static func star_texture() -> Texture2D:
	if _star:
		return _star
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var dx := absf(x - c) / c
			var dy := absf(y - c) / c
			var core := clampf(1.0 - Vector2(dx, dy).length() * 2.2, 0.0, 1.0)
			var arms := maxf(pow(clampf(1.0 - dx, 0.0, 1.0), 1.5) * clampf(1.0 - dy * 5.0, 0.0, 1.0),
				pow(clampf(1.0 - dy, 0.0, 1.0), 1.5) * clampf(1.0 - dx * 5.0, 0.0, 1.0))
			var a := clampf(maxf(core, arms) + core * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star = ImageTexture.create_from_image(img)
	return _star


static func attach(p_logo: TextureRect) -> LogoFx:
	var fx := LogoFx.new()
	fx.logo = p_logo
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	p_logo.add_child(fx)
	return fx


func _ready() -> void:
	if Pal.reduced_motion() or logo == null or logo.texture == null:
		set_process(false)
		return
	# glints and sparks add light (they brighten what is under them instead of covering it)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	logo.material = _mat
	_find_spots()
	var halo := _halo()
	logo.add_child(halo)
	logo.move_child(halo, 0)
	var rays := _rays()
	logo.add_child(rays)
	logo.move_child(rays, 0)
	logo.add_child(_twinkles())
	get_tree().create_timer(0.35).timeout.connect(_burst)  # once the logo has popped in and has its size
	_sweep = create_tween().set_loops()
	_sweep.tween_interval(1.2)
	_sweep.tween_method(func(v: float) -> void: _mat.set_shader_parameter("shine", v), 0.0, 1.0, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sweep.tween_callback(func() -> void: _mat.set_shader_parameter("shine", -1.0))
	_sweep.tween_interval(SHINE_EVERY)


## Where the picture is drawn inside the TextureRect (kept aspect, centred).
func _pic_rect() -> Rect2:
	var ts := logo.texture.get_size()
	var k := minf(size.x / ts.x, size.y / ts.y)
	var s := ts * k
	return Rect2((size - s) * 0.5, s)


func _find_spots() -> void:
	var img := logo.texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tries := 0
	while _spots.size() < 220 and tries < 6000:
		tries += 1
		var u := rng.randf_range(0.08, 0.92)
		var v := rng.randf_range(0.05, 0.9)
		var c := img.get_pixel(int(u * (w - 1)), int(v * (h - 1)))
		# on bright, opaque parts (letters' highlights, flowers, leaves), not on the dark outline
		if c.a > 0.95 and c.get_luminance() > 0.55:
			_spots.append(Vector2(u, v))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_next_glint -= delta
	if _next_glint <= 0.0 and not _spots.is_empty():
		_next_glint = GLINT_EVERY * randf_range(0.6, 1.5)
		_glints.append({"p": _spots[randi() % _spots.size()], "t": 0.0, "s": randf_range(70.0, 130.0),
			"r": randf_range(-1.0, 1.0)})
	for g in _glints:
		g["t"] = float(g["t"]) + delta
	_glints = _glints.filter(func(g: Dictionary) -> bool: return float(g["t"]) < GLINT_LIFE)
	if not _glints.is_empty():
		queue_redraw()


func _draw() -> void:
	if _glints.is_empty():
		return
	var pr := _pic_rect()
	var tex := star_texture()
	for g in _glints:
		var k := float(g["t"]) / GLINT_LIFE
		var s := float(g["s"]) * sin(k * PI)
		var p: Vector2 = pr.position + (g["p"] as Vector2) * pr.size
		draw_set_transform(p, float(g["r"]) + k * 1.2, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 0.97, 0.85, 0.95))
		draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.18, Vector2(s, s) * 0.36), false, Color(1, 1, 1, 1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A warm glow behind the logo.
func _halo() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.86, 0.45, 0.6))
	g.set_color(1, Color(1.0, 0.7, 0.3, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var h := TextureRect.new()
	h.texture = gt
	h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.show_behind_parent = true
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = -380
	h.offset_right = 380
	h.offset_top = -280
	h.offset_bottom = 280
	return h


## Slow rays of light turning behind the logo (redrawn 20 times a second, not every frame).
func _rays() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.show_behind_parent = true
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var t0 := Time.get_ticks_msec()
	c.draw.connect(func() -> void:
		var ctr := c.size * Vector2(0.5, 0.5)
		var r := c.size.x * 0.95
		var spin := (Time.get_ticks_msec() - t0) / 1000.0 * 0.06
		for i in 12:
			var a := spin + TAU * i / 12.0
			var w := 0.07 + 0.03 * sin(i * 1.7)
			var pts := PackedVector2Array([ctr, ctr + Vector2(cos(a - w), sin(a - w) * 0.75) * r,
				ctr + Vector2(cos(a + w), sin(a + w) * 0.75) * r])
			c.draw_polygon(pts, PackedColorArray([Color(1.0, 0.9, 0.55, 0.3), Color(1.0, 0.9, 0.55, 0.0),
				Color(1.0, 0.9, 0.55, 0.0)])))
	var tick := Timer.new()
	tick.wait_time = 0.05
	tick.autostart = true
	tick.timeout.connect(c.queue_redraw)
	c.add_child(tick)
	return c


## Small stars drifting up around the logo, twinkling as they go.
func _twinkles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = star_texture()
	p.amount = 40
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 50.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.0))
	sc.add_point(Vector2(0.2, 1.0))
	sc.add_point(Vector2(0.5, 0.35))
	sc.add_point(Vector2(0.75, 0.9))
	sc.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(1.0, 0.8, 0.4, 0.0))
	p.color_ramp = g
	p.material = material
	_twinkle = p
	# methods, not lambdas: a call still pending when the screen is replaced is dropped with this node
	logo.resized.connect(_place_twinkles)
	_place_twinkles.call_deferred()
	return p


func _place_twinkles() -> void:
	if is_instance_valid(_twinkle) and is_instance_valid(logo):
		_twinkle.position = logo.size * 0.5
		_twinkle.emission_rect_extents = logo.size * Vector2(0.48, 0.42)


## Sparks thrown out once as the logo lands.
func _burst() -> void:
	var p := CPUParticles2D.new()
	p.texture = star_texture()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 40
	p.lifetime = 1.3
	p.position = logo.size * Vector2(0.5, 0.55)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = logo.size.x * 0.22
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 620.0
	p.damping_min = 120.0
	p.damping_max = 240.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.8, 1.0))
	g.set_color(1, Color(1.0, 0.65, 0.2, 0.0))
	p.color_ramp = g
	p.material = material
	logo.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
