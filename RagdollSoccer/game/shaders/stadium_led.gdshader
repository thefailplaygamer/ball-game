shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Umlaufende LED-Bandenwerbung: durchlaufende Farbbloecke mit angedeuteten
// Schriftzuegen, sichtbarem Pixelraster und Eigenleuchten. UV.x in Metern,
// UV.y von 0 (Unterkante) bis 1 (Oberkante) der Bande.

uniform vec3 color_a : source_color = vec3(0.95, 0.3, 0.12);
uniform vec3 color_b : source_color = vec3(0.15, 0.5, 0.95);
uniform vec3 color_c : source_color = vec3(0.98, 0.8, 0.15);
uniform float scroll_speed = 1.6;
uniform float board_length = 9.0;
uniform float pixel_pitch = 0.045;
uniform float emission_strength = 2.2;
uniform float frame_height : hint_range(0.0, 0.5) = 0.13;

float lhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float u = UV.x - TIME * scroll_speed;
	float v = clamp(UV.y, 0.0, 1.0);

	// Rahmen oben/unten: dunkles Alu-Profil.
	float frame = clamp(step(v, frame_height) + step(1.0 - frame_height, v), 0.0, 1.0);

	float board = floor(u / board_length);
	float bu = fract(u / board_length);
	float r = lhash(vec2(board, 3.0));

	vec3 bg = r < 0.34 ? color_a : (r < 0.67 ? color_b : color_c);
	bg *= 0.35 + lhash(vec2(board, 7.0)) * 0.35;

	// Angedeutete Schrift: unterschiedlich breite Bloecke auf mittlerer Hoehe.
	float text = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float start = 0.16 + fi * 0.095 + lhash(vec2(board, fi)) * 0.02;
		float w = 0.03 + lhash(vec2(board, fi + 20.0)) * 0.045;
		text += step(start, bu) * step(bu, start + w);
	}
	text *= step(0.36, v) * step(v, 0.72);
	text = clamp(text, 0.0, 1.0);

	vec3 fg = mix(vec3(0.98), bg * 2.6 + 0.3, lhash(vec2(board, 11.0)));
	vec3 col = mix(bg, fg, text);

	// Pixelraster der LED-Module.
	vec2 px = fract(vec2(UV.x, UV.y) / pixel_pitch);
	float grid = smoothstep(0.0, 0.25, min(px.x, px.y)) * smoothstep(0.0, 0.25, min(1.0 - px.x, 1.0 - px.y));
	col *= 0.55 + grid * 0.55;

	vec3 frame_col = vec3(0.09, 0.09, 0.11);
	ALBEDO = mix(col, frame_col, frame);
	EMISSION = col * emission_strength * (1.0 - frame);
	ROUGHNESS = mix(0.35, 0.55, frame);
	METALLIC = mix(0.0, 0.7, frame);
}
