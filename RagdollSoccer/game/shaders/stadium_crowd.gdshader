shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Tribuenenrang: die UV kommen aus dem prozedural gebauten Bowl-Mesh und sind
// KEINE 0..1-Koordinaten:
//   UV.x = Strecke entlang der Tribuene in Metern
//   UV.y = Rangnummer, dabei ist [i, i+0.5] die senkrechte Stufenwange
//          (dort sitzen die Leute) und [i+0.5, i+1] die waagerechte Trittstufe.
// Daraus wird pro Sitzplatz eine Zelle abgeleitet und darin je nach Zufall ein
// Zuschauer, ein leerer Schalensitz oder ein Treppenaufgang gezeichnet.

uniform vec3 concrete_color : source_color = vec3(0.17, 0.17, 0.19);
uniform vec3 seat_color_a : source_color = vec3(0.55, 0.12, 0.12);
uniform vec3 seat_color_b : source_color = vec3(0.12, 0.2, 0.5);
uniform float seat_pitch = 0.5;
uniform float fill_ratio : hint_range(0.0, 1.0) = 0.86;
uniform float aisle_every = 22.0;
uniform float aisle_width = 1.2;
uniform float motion : hint_range(0.0, 1.0) = 1.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.5;
// Vereinsfarben, damit die Kurven farblich zu den Teams passen.
uniform vec3 team_a_color : source_color = vec3(0.85, 0.2, 0.2);
uniform vec3 team_b_color : source_color = vec3(0.2, 0.4, 0.9);
uniform float team_split = 0.0;

float chash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec3 chash3(vec2 p) {
	return vec3(chash(p), chash(p + 17.3), chash(p + 41.7));
}

void fragment() {
	float u = UV.x;
	float v = UV.y;

	float seat = floor(u / seat_pitch);
	float row = floor(v);
	float fu = fract(u / seat_pitch);
	float fv = fract(v);

	vec2 cell = vec2(seat, row);
	vec3 rnd = chash3(cell);

	// Treppenaufgaenge: dort keine Sitze, nur Beton.
	float aisle_pos = mod(u, aisle_every);
	float is_aisle = step(aisle_pos, aisle_width);

	vec3 col = concrete_color * (0.82 + chash(cell * 3.1) * 0.36);
	float emit = 0.0;
	float rough = 0.9;

	if (is_aisle < 0.5) {
		// Heimkurve/Gaestekurve gehen weich ineinander ueber statt an einer
		// harten Kante umzuschlagen — eine echte Tribuene ist nie sauber geteilt.
		float side = clamp(sin(u * 0.055 + team_split) * 1.6 + chash(cell * 1.7) * 0.7 - 0.35, 0.0, 1.0);
		vec3 seat_col = mix(seat_color_a, seat_color_b, side);
		seat_col *= 0.75 + rnd.z * 0.5;

		if (fv < 0.5) {
			// --- Stufenwange: hier sitzt/steht das Publikum ---
			float body_v = fv / 0.5;
			// Leichtes Auf und Ab, jeder Zuschauer mit eigenem Takt.
			float bob = sin(TIME * (1.1 + rnd.y * 1.6) + rnd.x * 30.0) * 0.06 * motion;
			float occupied = step(1.0 - fill_ratio, rnd.x);

			// Schultern schmaler als der Sitz, dazu etwas Streuung — sonst
			// entsteht ein lueckenloser Farbteppich statt einzelner Koepfe.
			float half_w = 0.2 + rnd.z * 0.08;
			float cx = 0.5 + (rnd.y - 0.5) * 0.12;
			float torso = step(cx - half_w, fu) * step(fu, cx + half_w) * step(0.1 + bob, body_v);
			float head = 1.0 - step(0.115, length(vec2((fu - cx) * 1.25, body_v - (0.76 + bob))));
			float person = clamp(torso + head, 0.0, 1.0) * occupied;

			// Kleidung: nur eine Minderheit traegt wirklich Vereinsfarben, der
			// Rest steckt in Alltagstoenen. Alles bewusst entsaettigt, sonst
			// leuchtet die Tribuene aus der Distanz wie eine Neonwand.
			vec3 team_col = mix(team_a_color, team_b_color, step(0.5, side));
			vec3 shirt = team_col;
			if (rnd.y > 0.42) {
				// Alltagskleidung: Grau-, Beige- und Blautoene.
				vec3 casual = vec3(0.3 + rnd.z * 0.45, 0.3 + rnd.z * 0.4, 0.32 + rnd.z * 0.42);
				casual = mix(casual, vec3(0.45, 0.36, 0.28), step(0.75, rnd.z));
				shirt = casual;
			}
			// Restsaettigung kappen und abdunkeln (Tribuenen liegen im Schatten).
			float lum = dot(shirt, vec3(0.299, 0.587, 0.114));
			shirt = mix(vec3(lum), shirt, 0.62) * (0.42 + rnd.z * 0.4);
			vec3 skin = vec3(0.55, 0.4, 0.31) * (0.5 + rnd.z * 0.6);

			vec3 body_col = mix(shirt, skin, head);
			col = mix(mix(col, seat_col * 0.7, 0.85), body_col, person);

			// Kamerablitze im Publikum.
			float flash_seed = chash(cell + floor(TIME * 3.0) * 13.7);
			float flash = step(0.9985 - flash_amount * 0.004, flash_seed) * occupied;
			emit = flash * 6.0;
			col = mix(col, vec3(1.0), flash * 0.8);
			rough = mix(0.85, 0.65, person);
		} else {
			// --- Trittstufe: Sitzflaeche + Beton ---
			float tread_v = (fv - 0.5) / 0.5;
			float seat_shape = step(0.12, fu) * step(fu, 0.88) * step(0.1, tread_v) * step(tread_v, 0.72);
			col = mix(col * 0.85, seat_col * 0.6, seat_shape);
			rough = mix(0.92, 0.55, seat_shape);
		}
	}

	ALBEDO = col;
	EMISSION = vec3(1.0, 0.97, 0.9) * emit;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
