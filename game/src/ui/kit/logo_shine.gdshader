shader_type canvas_item;
// A band of light sweeping diagonally across a picture (the title logo), on its opaque pixels only.

uniform float shine = -1.0;  // sweep progress 0..1; < 0: no band
uniform float width = 0.11;
uniform vec4 band_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);

void fragment() {
	vec4 c = COLOR;
	if (shine >= 0.0) {
		float x = UV.x + (1.0 - UV.y) * 0.5;
		float p = mix(-0.35, 1.85, shine);
		float b = smoothstep(width, 0.0, abs(x - p));
		// a thin bright core inside a wider soft band
		b = b * 0.55 + smoothstep(width * 0.25, 0.0, abs(x - p)) * 0.45;
		c.rgb += band_color.rgb * b * 0.6 * c.a;
	}
	COLOR = c;
}
