shader_type canvas_item;

// Inventar-/Kisten-Icon eines Trikots.
//
// Statt eines flachen Farbquadrats wird hier eine echte Trikot-Silhouette
// (Rumpf + Aermel + Halsausschnitt) per Signed-Distance-Field gezeichnet und
// das Muster hineingeclippt. Der Vorteil gegenueber dem frueheren
// handgezeichneten Control: exakt dasselbe Muster wie am 3D-Spieler (gleiche
// Bibliothek), animierte Muster laufen ohne Zusatzcode, und Rahmen/Aura
// kosten keine zusaetzlichen Draw-Calls.

#include "res://shaders/jersey_patterns.gdshaderinc"

uniform int pattern_mode = 0;
uniform vec4 color_a : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 rarity_color : source_color = vec4(0.7, 0.72, 0.75, 1.0);
uniform vec4 bg_color : source_color = vec4(0.05, 0.055, 0.07, 1.0);
// Wie stark das Trikot die Kachel hinter sich einfaerbt (steigt mit der Stufe).
uniform float rarity_glow : hint_range(0.0, 1.0) = 0.0;
// > 0.5 = die Aura pulsiert zusaetzlich (legendaer).
uniform float glow_pulse : hint_range(0.0, 1.0) = 0.0;
uniform bool locked = false;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - (b - vec2(r));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

// Halsausschnitt separat, damit der Kragen als eigener Ring gezeichnet werden
// kann.
float neck_sdf(vec2 uv) {
	vec2 p = (uv - vec2(0.5, 0.285)) / vec2(1.0, 0.82);
	return length(p) - 0.088;
}

float shirt_sdf(vec2 uv) {
	vec2 p = uv - vec2(0.5, 0.0);

	// Rumpf: leicht taillierte, unten abgerundete Box.
	float torso = sd_round_box(p - vec2(0.0, 0.605), vec2(0.19, 0.3), 0.04);

	// Aermel: an |x| gespiegelt, nach aussen-unten gekippt.
	vec2 q = vec2(abs(p.x), p.y) - vec2(0.285, 0.375);
	float c = cos(0.36);
	float s = sin(0.36);
	q = mat2(vec2(c, -s), vec2(s, c)) * q;
	float sleeve = sd_round_box(q, vec2(0.115, 0.088), 0.035);

	return max(min(torso, sleeve), -neck_sdf(uv));
}

void fragment() {
	vec2 uv = UV;

	// Kachel mit abgerundeten Ecken; ausserhalb bleibt alles transparent.
	float tile = sd_round_box(uv - vec2(0.5), vec2(0.5), 0.09);
	float tile_aa = max(fwidth(tile), 0.0015);
	float tile_mask = 1.0 - smoothstep(-tile_aa, tile_aa, tile);

	float d = shirt_sdf(uv);
	float aa = max(fwidth(d), 0.0015);

	vec3 col = bg_color.rgb;

	// Aura in Seltenheitsfarbe hinter dem Trikot.
	if (!locked && rarity_glow > 0.0) {
		float pulse = glow_pulse > 0.5 ? 0.7 + 0.3 * sin(TIME * 2.1) : 1.0;
		float aura = exp(-max(d, 0.0) * 15.0) * rarity_glow * pulse;
		col = mix(col, rarity_color.rgb, clamp(aura, 0.0, 0.8));
	}

	vec3 shirt;
	if (locked) {
		shirt = vec3(0.135, 0.145, 0.165);
	} else {
		float emit = 0.0;
		shirt = jersey_pattern(pattern_mode, uv, color_a.rgb, color_b.rgb, color_c.rgb, TIME, emit);
		shirt *= 1.0 + emit * 0.5;

		// Stoff-Plastik: Raender abdunkeln, Brustmitte leicht anheben.
		float rim = smoothstep(-0.006, -0.055, d);
		shirt *= mix(0.6, 1.0, rim);
		shirt *= 1.0 + 0.12 * (1.0 - smoothstep(0.0, 0.4, length(uv - vec2(0.5, 0.46))));

		// Saum am unteren Rumpfabschluss.
		float hem = smoothstep(0.008, 0.0, abs(uv.y - 0.845)) * step(abs(uv.x - 0.5), 0.19);
		shirt = mix(shirt, shirt * 0.68, hem * 0.85);

		// Kragenbund.
		float collar = smoothstep(0.022, 0.0, abs(neck_sdf(uv)));
		shirt = mix(shirt, shirt * 0.55 + vec3(0.06), collar * 0.9);
	}

	float shirt_mask = 1.0 - smoothstep(-aa, aa, d);
	col = mix(col, shirt, shirt_mask);

	// Dunkle Kontur, damit helle Trikots sich vom Hintergrund abheben.
	float outline = 1.0 - smoothstep(0.003, 0.003 + aa * 1.5, abs(d));
	col = mix(col, vec3(0.03, 0.03, 0.045), outline * 0.8);

	// Rahmen in Seltenheitsfarbe entlang der Kachelkante.
	float inner = sd_round_box(uv - vec2(0.5), vec2(0.5 - 0.032), 0.06);
	float frame = tile_mask * smoothstep(-tile_aa, tile_aa, inner);
	vec3 frame_col = locked ? vec3(0.26, 0.27, 0.31) : rarity_color.rgb;
	col = mix(col, frame_col, frame);

	COLOR = vec4(col, tile_mask);
}
