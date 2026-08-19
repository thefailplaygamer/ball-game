shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Haut fuer Kopf, Hals und Haende. Statt einer flachen Farbflaeche mit
// Rauschkorn: feine Poren, ein warmer Rotstich in den duenneren Partien
// (Wangen, Nase, Ohren) und ein leichter Talgglanz auf den erhabenen Stellen.
// Die UV kommen aus dem Loft-Mesh (UV.x laeuft um den Kopf, UV.y von oben nach
// unten), dadurch sitzt die Wangenroete auch wirklich seitlich.

uniform vec4 skin_tone : source_color = vec4(0.87, 0.68, 0.56, 1.0);
uniform vec4 blush_tone : source_color = vec4(0.78, 0.42, 0.36, 1.0);
uniform float pore_scale = 180.0;
uniform float pore_strength : hint_range(0.0, 0.3) = 0.06;
uniform float blush_strength : hint_range(0.0, 1.0) = 0.35;
uniform float sheen : hint_range(0.0, 1.0) = 0.3;

float shash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float snoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(shash(i), shash(i + vec2(1.0, 0.0)), f.x),
		mix(shash(i + vec2(0.0, 1.0)), shash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void fragment() {
	// Poren: zwei Frequenzen, damit es aus der Naehe nicht wie Rauschen flimmert.
	float pores = snoise2(UV * pore_scale) * 0.65 + snoise2(UV * pore_scale * 2.7) * 0.35;
	float blotch = snoise2(UV * 9.0);

	// Wangen/Ohren liegen seitlich, also bei UV.x rund um 0.25 und 0.75.
	float side = abs(sin(UV.x * 6.2831));
	float cheek = smoothstep(0.55, 1.0, side) * smoothstep(0.25, 0.6, UV.y);
	float blush = clamp(cheek * 0.7 + blotch * 0.4, 0.0, 1.0) * blush_strength;

	vec3 col = mix(skin_tone.rgb, blush_tone.rgb, blush);
	col *= 0.94 + pores * 0.12;
	// Nach unten hin (Kinn, Hals) minimal abgedunkelt, das gibt Tiefe.
	col *= mix(1.04, 0.9, clamp(UV.y, 0.0, 1.0));

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.62 - pores * sheen * 0.35, 0.15, 1.0);
	SPECULAR = 0.35 + sheen * 0.2;
	METALLIC = 0.0;
}
