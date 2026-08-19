shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Sichtbeton fuer Dach, Traeger und Aussenhaut: Fugenraster der Schalungs-
// platten, Regenschlieren und feines Korn. UV in Metern (aus dem Bowl-Sweep).

uniform vec3 base_color : source_color = vec3(0.2, 0.2, 0.22);
uniform vec3 stain_color : source_color = vec3(0.11, 0.11, 0.12);
uniform float panel_size = 2.4;
uniform float joint_width = 0.035;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float stain_strength : hint_range(0.0, 1.0) = 0.45;
uniform float uv_scale = 1.0;

float khash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float knoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(khash(i), khash(i + vec2(1.0, 0.0)), f.x),
		mix(khash(i + vec2(0.0, 1.0)), khash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float kfbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * knoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec2 cell = uv / panel_size;
	vec2 f = abs(fract(cell) - 0.5);
	float joint = 1.0 - smoothstep(0.5 - joint_width * 2.0, 0.5 - joint_width, max(f.x, f.y));

	vec3 col = base_color * (0.85 + khash(floor(cell)) * 0.3);
	col *= 1.0 + (kfbm(uv * 6.0) - 0.5) * grain_strength;

	// Senkrechte Regenschlieren.
	float streak = kfbm(vec2(uv.x * 3.0, uv.y * 0.35));
	streak = smoothstep(0.5, 0.85, streak) * smoothstep(0.0, 3.0, uv.y);
	col = mix(col, stain_color, streak * stain_strength);

	col = mix(col, col * 0.62, joint);

	ALBEDO = col;
	ROUGHNESS = clamp(0.86 - joint * 0.15, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
