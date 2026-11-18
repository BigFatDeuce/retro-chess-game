// Title letters: a vertical gradient over the fill (gold like the logo's "RETRO"), a light band that sweeps
// across now and then, the outline and the shadow left as they are. The label's fill colour must be white:
// this is how the fill is told apart from the outline pass.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(1.0, 0.9, 0.42, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.97, 0.56, 0.1, 1.0);
uniform float y_top = 0.0;  // local px where the gradient starts and ends (set from the label's size)
uniform float y_bottom = 100.0;
uniform float shine = -1.0;  // position of the sweep, 0..1 across the label; < 0 = none
uniform float width = 400.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float is_fill = step(0.97, min(c.r, min(c.g, c.b)));
	float t = clamp((local_pos.y - y_top) / max(y_bottom - y_top, 1.0), 0.0, 1.0);
	vec3 g = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, t));
	// a soft highlight in the upper third
	g += vec3(0.12) * (1.0 - smoothstep(0.15, 0.45, t));
	if (shine >= 0.0) {
		float x = (local_pos.x + (local_pos.y - y_top) * 0.45) / max(width, 1.0);
		float band = 1.0 - smoothstep(0.0, 0.06, abs(x - shine * 1.4 + 0.2));
		g = mix(g, vec3(1.0, 0.99, 0.92), band * 0.75);
	}
	COLOR.rgb = mix(c.rgb, g, is_fill);
}
