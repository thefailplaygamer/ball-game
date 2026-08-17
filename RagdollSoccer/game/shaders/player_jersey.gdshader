shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Trikot-Stoff: Muster + Farben (siehe JerseyData.Pattern) mit feinem
// Webmuster und angedeuteter Saum-Naht statt einer flachen Einheitsfarbe.

uniform int pattern_mode = 0;
uniform vec4 color_a : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float weave_scale = 60.0;
uniform float weave_strength : hint_range(0.0, 0.4) = 0.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

vec3 pattern_color(vec2 uv) {
	if (pattern_mode == 1) { // horizontale Streifen
		float band = mod(floor(uv.y * 10.0), 2.0);
		return mix(color_a.rgb, color_b.rgb, band);
	} else if (pattern_mode == 2) { // vertikale Streifen
		float band = mod(floor(uv.x * 10.0), 2.0);
		return mix(color_a.rgb, color_b.rgb, band);
	} else if (pattern_mode == 3) { // Halbiert
		return uv.x < 0.5 ? color_a.rgb : color_b.rgb;
	} else if (pattern_mode == 4) { // Farbblöcke (Drittel)
		float band = step(0.33, uv.x) - step(0.66, uv.x);
		return mix(color_a.rgb, color_b.rgb, band);
	} else if (pattern_mode == 5) { // Dreifarbige Ringel
		float band = mod(floor(uv.y * 9.0), 3.0);
		return band < 1.0 ? color_a.rgb : (band < 2.0 ? color_b.rgb : color_c.rgb);
	} else if (pattern_mode == 6) { // Diagonale Schärpe
		float diag = uv.x + uv.y;
		float sash = smoothstep(0.85, 0.95, 1.0 - abs(fract(diag * 1.4) - 0.5) * 2.0);
		return mix(color_a.rgb, color_b.rgb, sash);
	} else if (pattern_mode == 7) { // Schachbrett
		float cx = mod(floor(uv.x * 8.0), 2.0);
		float cy = mod(floor(uv.y * 8.0), 2.0);
		float check = mod(cx + cy, 2.0);
		return mix(color_a.rgb, color_b.rgb, check);
	} else if (pattern_mode == 8) { // Nadelstreifen
		float line = step(0.92, fract(uv.x * 22.0));
		return mix(color_a.rgb, color_b.rgb, line);
	} else if (pattern_mode == 9) { // Vertikaler Farbverlauf
		return mix(color_a.rgb, color_b.rgb, uv.y);
	} else if (pattern_mode == 10) { // Radialer Farbverlauf
		float d = distance(uv, vec2(0.5));
		return mix(color_a.rgb, color_b.rgb, clamp(d * 1.6, 0.0, 1.0));
	} else if (pattern_mode == 11) { // Diagonaler Farbverlauf
		return mix(color_a.rgb, color_b.rgb, clamp((uv.x + uv.y) * 0.5, 0.0, 1.0));
	} else if (pattern_mode == 12) { // Scharfer Dual-Verlauf
		float t = clamp((uv.x - uv.y + 1.0) * 0.5, 0.0, 1.0);
		t = smoothstep(0.3, 0.7, t);
		return mix(color_a.rgb, color_b.rgb, t);
	} else if (pattern_mode == 13) { // Regenbogen
		float t = fract(uv.x * 0.6 + uv.y * 0.4);
		return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
	} else if (pattern_mode == 14) { // Hologramm (animiert)
		float t = fract(uv.x * 0.5 + uv.y * 0.5 + TIME * 0.15);
		vec3 col = 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
		return mix(col, vec3(1.0), 0.15);
	} else if (pattern_mode == 15) { // Tarnmuster
		float n1 = value_noise(uv * 9.0);
		float n2 = value_noise(uv * 17.0 + vec2(5.2, 1.3));
		float blotch = n1 * 0.6 + n2 * 0.4;
		vec3 col = mix(color_a.rgb, color_b.rgb, step(0.42, blotch));
		col = mix(col, color_c.rgb, step(0.68, blotch));
		return col;
	} else if (pattern_mode == 16) { // Flammen (animiert)
		float n = value_noise(uv * vec2(5.0, 3.0) - vec2(0.0, TIME * 0.6));
		float rise = clamp(1.0 - uv.y + n * 0.35, 0.0, 1.0);
		vec3 col = mix(color_c.rgb, color_a.rgb, smoothstep(0.2, 0.6, rise));
		col = mix(col, color_b.rgb, smoothstep(0.6, 0.95, rise));
		return col;
	}
	return color_a.rgb; // 0: einfarbig
}

void fragment() {
	vec2 weave_uv = UV * weave_scale;
	float weave = hash(floor(weave_uv)) * 0.5 + hash(floor(weave_uv) + vec2(0.5, 0.5)) * 0.5;

	vec3 base_color = pattern_color(UV);
	vec3 base = base_color * (1.0 - weave_strength * 0.5 + weave * weave_strength);

	// Leichte horizontale Saum-/Nahtlinien fuer mehr Stoff-Charakter.
	float seam = smoothstep(0.0, 0.02, abs(fract(UV.y * 3.0) - 0.5) - 0.47);
	base = mix(base, base * 0.72, seam * 0.5);

	ALBEDO = base;
	ROUGHNESS = 0.7 + weave * 0.2;
	METALLIC = pattern_mode == 14 ? 0.35 : 0.0;
}
