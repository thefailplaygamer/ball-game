shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Kompletter Rasen: Maehstreifen, Grasstruktur, Abnutzung und saemtliche
// Spielfeldmarkierungen werden aus der WELT-Position berechnet (nicht aus UV),
// damit die Linien exakt an den Toren (x = +/- goal_line_x) und Seitenwaenden
// (z = +/- touch_line_z) sitzen, egal wie der Boden-Quader skaliert ist.
// Die Masse sind die FIFA-Proportionen (105 x 68 m) auf die Arena heruntergerechnet.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_dark : source_color = vec3(0.09, 0.27, 0.09);
uniform vec3 grass_light : source_color = vec3(0.16, 0.42, 0.14);
uniform vec3 line_color : source_color = vec3(0.93, 0.95, 0.93);
uniform vec3 soil_color : source_color = vec3(0.16, 0.11, 0.07);

uniform float goal_line_x = 14.0;
uniform float touch_line_z = 9.3;
uniform float line_half_width = 0.045;

// Aus 105x68 heruntergerechnete Standardmasse.
uniform float penalty_depth = 4.4;    // 16.5 m
uniform float penalty_half_z = 5.55;  // 40.32 m breit
uniform float goal_box_depth = 1.47;  // 5.5 m
uniform float goal_box_half_z = 2.52; // 18.32 m breit
uniform float penalty_spot_x = 11.06; // 11 m vor der Torlinie
uniform float circle_radius = 2.44;   // 9.15 m
uniform float corner_radius = 0.32;

uniform float mow_width = 1.75;
uniform float mow_contrast : hint_range(0.0, 0.5) = 0.16;
uniform float grass_detail : hint_range(0.0, 1.0) = 0.55;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;
varying float top_face;

float phash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float pnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(phash(i), phash(i + vec2(1.0, 0.0)), f.x),
		mix(phash(i + vec2(0.0, 1.0)), phash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * pnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Ein Streifen der Breite 2*half um `center`, weich ueber `aa` ausgeblendet.
float band(float v, float center, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(v - center));
}

// 1 innerhalb [lo, hi].
float span(float v, float lo, float hi, float aa) {
	return smoothstep(lo - aa, lo + aa, v) * (1.0 - smoothstep(hi - aa, hi + aa, v));
}

// Kreisring (Linie) bzw. gefuellte Scheibe.
float ring(vec2 p, vec2 c, float r, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(length(p - c) - r));
}

float disc(vec2 p, vec2 c, float r, float aa) {
	return 1.0 - smoothstep(r - aa, r + aa, length(p - c));
}

// Alle Markierungen einer Spielfeldhaelfte (s = +1 Ost, s = -1 West).
float half_markings(vec2 p, float s, float hw, float aa) {
	float m = 0.0;
	float gl = s * goal_line_x;
	float pen_front = s * (goal_line_x - penalty_depth);
	float box_front = s * (goal_line_x - goal_box_depth);
	float lo_pen = min(pen_front, gl);
	float hi_pen = max(pen_front, gl);
	float lo_box = min(box_front, gl);
	float hi_box = max(box_front, gl);

	// Strafraum
	m = max(m, band(p.x, pen_front, hw, aa) * span(p.y, -penalty_half_z - hw, penalty_half_z + hw, aa));
	m = max(m, band(abs(p.y), penalty_half_z, hw, aa) * span(p.x, lo_pen - hw, hi_pen + hw, aa));
	// Torraum
	m = max(m, band(p.x, box_front, hw, aa) * span(p.y, -goal_box_half_z - hw, goal_box_half_z + hw, aa));
	m = max(m, band(abs(p.y), goal_box_half_z, hw, aa) * span(p.x, lo_box - hw, hi_box + hw, aa));
	// Elfmeterpunkt
	m = max(m, disc(p, vec2(s * penalty_spot_x, 0.0), hw * 1.7, aa));
	// Teilkreis am Strafraum: nur der Teil ausserhalb des Strafraums.
	float outside = s > 0.0
		? (1.0 - smoothstep(pen_front - aa, pen_front + aa, p.x))
		: smoothstep(pen_front - aa, pen_front + aa, p.x);
	m = max(m, ring(p, vec2(s * penalty_spot_x, 0.0), circle_radius, hw, aa) * outside);
	// Eckviertelkreise
	m = max(m, ring(p, vec2(gl, touch_line_z), corner_radius, hw, aa));
	m = max(m, ring(p, vec2(gl, -touch_line_z), corner_radius, hw, aa));
	return m;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	top_face = step(0.7, NORMAL.y);
}

void fragment() {
	vec2 p = world_pos.xz;
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.6 + 0.0015;
	float hw = line_half_width;

	// --- Grasgrund ----------------------------------------------------------
	// Maehstreifen: benachbarte Bahnen sind in Gegenrichtung gewalzt und
	// reflektieren dadurch unterschiedlich hell.
	float stripe = mod(floor((p.x + goal_line_x) / mow_width), 2.0);
	// Die Bahngrenze leicht ausfransen, damit sie nicht wie ein Lineal wirkt.
	float stripe_edge = fbm(p * 3.0) - 0.5;
	float stripe_mix = clamp(stripe + stripe_edge * 0.25, 0.0, 1.0);

	float patch = fbm(p * 0.55);
	vec3 grass = mix(grass_dark, grass_light, clamp(patch * 0.75 + stripe_mix * 0.45, 0.0, 1.0));
	grass *= 1.0 + (stripe_mix - 0.5) * mow_contrast;

	// Feine Halmstruktur aus der Foto-Textur, bewusst nur als Kontrast-Modulation
	// (nicht als Farbe), sonst kippt der Rasen ins Gelbliche.
	vec3 tex = texture(grass_tex, p * 0.55).rgb;
	float tex_lum = dot(tex, vec3(0.299, 0.587, 0.114));
	grass *= 1.0 + (tex_lum - 0.5) * grass_detail;
	// Zusaetzliches Hochfrequenz-Rauschen fuer Nahsicht.
	float blades = pnoise(p * 42.0);
	grass *= 1.0 + (blades - 0.5) * 0.18;

	// Abnutzung: kahle Stellen vor den Toren und rund um den Anstosspunkt.
	float wear = 0.0;
	wear = max(wear, smoothstep(3.4, 1.2, length(vec2(abs(p.x) - goal_line_x, p.y))));
	wear = max(wear, smoothstep(1.9, 0.5, length(p)) * 0.7);
	wear *= 0.55 + fbm(p * 2.2) * 0.7;
	grass = mix(grass, mix(grass, vec3(0.24, 0.26, 0.14), 0.55), clamp(wear, 0.0, 1.0) * wear_strength);

	// --- Markierungen -------------------------------------------------------
	float in_field = span(p.x, -goal_line_x - hw, goal_line_x + hw, aa)
		* span(p.y, -touch_line_z - hw, touch_line_z + hw, aa);

	float lines = 0.0;
	lines = max(lines, band(abs(p.y), touch_line_z, hw, aa) * span(p.x, -goal_line_x - hw, goal_line_x + hw, aa));
	lines = max(lines, band(abs(p.x), goal_line_x, hw, aa) * span(p.y, -touch_line_z - hw, touch_line_z + hw, aa));
	lines = max(lines, band(p.x, 0.0, hw, aa) * span(p.y, -touch_line_z - hw, touch_line_z + hw, aa));
	lines = max(lines, ring(p, vec2(0.0), circle_radius, hw, aa));
	lines = max(lines, disc(p, vec2(0.0), hw * 1.7, aa));
	lines = max(lines, half_markings(p, 1.0, hw, aa) * in_field);
	lines = max(lines, half_markings(p, -1.0, hw, aa) * in_field);
	lines *= in_field;

	// Kalklinien sind nie perfekt deckend.
	float line_wear = 0.82 + fbm(p * 8.0) * 0.28;
	vec3 albedo = mix(grass, line_color * line_wear, lines);

	// Seitenflaechen des Bodenquaders sind Erdreich, kein Rasen.
	albedo = mix(soil_color * (0.7 + fbm(p * 6.0) * 0.6), albedo, top_face);

	// --- Oberflaeche --------------------------------------------------------
	// Grasrichtung pro Maehbahn kippen -> sichtbarer Streifeneffekt im Glanz.
	float dir = mix(-1.0, 1.0, stripe_mix);
	vec3 n = normalize(vec3((blades - 0.5) * 0.35, 2.0, dir * 0.28 + (pnoise(p * 17.0) - 0.5) * 0.4));
	NORMAL = mix(NORMAL, normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz), top_face * 0.65);

	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, mix(0.78, 0.62, lines), top_face);
	SPECULAR = mix(0.2, 0.35, top_face);
	METALLIC = 0.0;
}
