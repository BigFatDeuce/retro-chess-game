shader_type canvas_item;
// The ground around the board, drawn in one piece with an exact perspective per pixel (no seams between
// pieces of geometry). The library's painted ground is repeated at its own scale; a second, turned and
// scaled copy blended through soft noise, and a slow brightness variation, hide the repetition.

uniform sampler2D tex : repeat_enable, filter_linear_mipmap;
uniform float horizon;
uniform float proj_c;
uniform float k;
uniform float square;
uniform float cx;
uniform float rep = 5.0;
uniform float variation = 1.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

// smooth variation from sums of sines: continuous everywhere (a hash-based value noise lost precision on the
// mobile renderer and drew sharp lines across the ground)
float wave(vec2 p) {
	float a = sin(p.x * 0.37 + 1.3 * sin(p.y * 0.23));
	float b = sin(p.y * 0.29 + 1.7 * sin(p.x * 0.17 + 0.8));
	float c = sin((p.x + p.y) * 0.13 + 2.1);
	return clamp(0.5 + 0.2 * (a + b + c), 0.0, 1.0);
}

void fragment() {
	float s = max((lp.y - horizon) / proj_c, 0.02);
	float v = (1.0 / s - 1.0) / k;
	float u = (lp.x - cx) / (square * s) + 4.0;
	vec2 b = vec2(u, -v);
	vec4 a = texture(tex, b / rep);
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec4 a2 = texture(tex, (r * b) / (rep * 1.37) + vec2(0.31, 0.57));
	float n = wave(b);
	vec3 col = mix(a.rgb, a2.rgb, smoothstep(0.3, 0.7, n) * variation);
	float n2 = wave(b * 0.45 + vec2(7.0, 3.0));
	col *= mix(1.0, mix(0.9, 1.07, n2), variation);
	COLOR = vec4(col, 1.0);
}
