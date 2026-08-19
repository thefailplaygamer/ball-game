shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Echter Fussball statt zufaelliger Voronoi-Flecken: das klassische
// Telstar-Muster ist ein abgestumpftes Ikosaeder aus 12 Fuenfecken und
// 20 Sechsecken. Beides laesst sich exakt rekonstruieren, weil
//   * die 12 Fuenfeck-Mittelpunkte genau die Ecken eines Ikosaeders sind und
//   * die 20 Sechseck-Mittelpunkte genau dessen Flaechenmitten (= Dodekaeder-Ecken).
// Fuer jeden Punkt auf der Kugel wird das naechstliegende dieser 32 Zentren
// gesucht (Kugel-Voronoi) -> daraus ergeben sich automatisch die korrekten
// Panel-Formen. Der Abstand zum zweitnaechsten Zentrum liefert gratis die Naht.

uniform vec3 white_color : source_color = vec3(0.94, 0.94, 0.91);
uniform vec3 black_color : source_color = vec3(0.07, 0.07, 0.08);
uniform vec3 seam_color : source_color = vec3(0.35, 0.34, 0.33);
// Breite der eingelassenen Naht zwischen zwei Panels.
uniform float seam_width : hint_range(0.002, 0.08) = 0.022;
// Wie stark sich jedes Panel nach aussen woelbt (Kissen-Effekt am aufgepumpten Ball).
uniform float panel_bulge : hint_range(0.0, 1.5) = 0.55;
// Sichtbare Steppnaehte entlang der Panelkanten.
uniform float stitch_density = 190.0;
uniform float stitch_strength : hint_range(0.0, 1.0) = 0.45;
uniform float grain_scale = 220.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.28;
uniform float scuff_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 obj_pos;
varying vec3 obj_normal;

const float PHI = 1.6180339887;
const float IPHI = 0.6180339887;

// Ikosaeder-Ecken -> Mittelpunkte der 12 schwarzen Fuenfecke.
const vec3 PENTA[12] = vec3[12](
	vec3(0.0, 1.0, PHI), vec3(0.0, 1.0, -PHI), vec3(0.0, -1.0, PHI), vec3(0.0, -1.0, -PHI),
	vec3(1.0, PHI, 0.0), vec3(1.0, -PHI, 0.0), vec3(-1.0, PHI, 0.0), vec3(-1.0, -PHI, 0.0),
	vec3(PHI, 0.0, 1.0), vec3(-PHI, 0.0, 1.0), vec3(PHI, 0.0, -1.0), vec3(-PHI, 0.0, -1.0)
);

// Dodekaeder-Ecken -> Mittelpunkte der 20 weissen Sechsecke.
const vec3 HEXA[20] = vec3[20](
	vec3(1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, 1.0), vec3(1.0, -1.0, -1.0),
	vec3(-1.0, 1.0, 1.0), vec3(-1.0, 1.0, -1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, -1.0, -1.0),
	vec3(0.0, IPHI, PHI), vec3(0.0, IPHI, -PHI), vec3(0.0, -IPHI, PHI), vec3(0.0, -IPHI, -PHI),
	vec3(IPHI, PHI, 0.0), vec3(IPHI, -PHI, 0.0), vec3(-IPHI, PHI, 0.0), vec3(-IPHI, -PHI, 0.0),
	vec3(PHI, 0.0, IPHI), vec3(PHI, 0.0, -IPHI), vec3(-PHI, 0.0, IPHI), vec3(-PHI, 0.0, -IPHI)
);

float bhash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float bnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = bhash(i + vec3(0.0, 0.0, 0.0));
	float n100 = bhash(i + vec3(1.0, 0.0, 0.0));
	float n010 = bhash(i + vec3(0.0, 1.0, 0.0));
	float n110 = bhash(i + vec3(1.0, 1.0, 0.0));
	float n001 = bhash(i + vec3(0.0, 0.0, 1.0));
	float n101 = bhash(i + vec3(1.0, 0.0, 1.0));
	float n011 = bhash(i + vec3(0.0, 1.0, 1.0));
	float n111 = bhash(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

void vertex() {
	obj_pos = normalize(VERTEX);
	obj_normal = NORMAL;
}

void fragment() {
	vec3 p = normalize(obj_pos);

	// Kugel-Voronoi ueber alle 32 Panel-Zentren: bester und zweitbester Treffer.
	float d1 = -2.0;
	float d2 = -2.0;
	vec3 c1 = vec3(0.0, 1.0, 0.0);
	float pent = 0.0;
	for (int i = 0; i < 12; i++) {
		vec3 c = normalize(PENTA[i]);
		float d = dot(p, c);
		if (d > d1) {
			d2 = d1;
			d1 = d;
			c1 = c;
			pent = 1.0;
		} else if (d > d2) {
			d2 = d;
		}
	}
	for (int i = 0; i < 20; i++) {
		vec3 c = normalize(HEXA[i]);
		float d = dot(p, c);
		if (d > d1) {
			d2 = d1;
			d1 = d;
			c1 = c;
			pent = 0.0;
		} else if (d > d2) {
			d2 = d;
		}
	}

	// Abstand zur Panelkante (0 = genau auf der Naht).
	float edge = d1 - d2;

	// --- Naht + Steppnaht ---------------------------------------------------
	float groove = 1.0 - smoothstep(seam_width * 0.35, seam_width, edge);
	// Richtung entlang der Naht, damit die Steppstiche mitlaufen statt zu flimmern.
	vec3 to_center = c1 - p * dot(c1, p);
	float tan_len = length(to_center);
	vec3 tang = tan_len > 0.0001 ? to_center / tan_len : vec3(0.0, 0.0, 1.0);
	vec3 along = normalize(cross(p, tang));
	float stitch_phase = dot(along, vec3(12.9898, 78.233, 37.719)) + dot(p, vec3(41.3, 27.9, 63.1)) * stitch_density;
	float stitch_band = 1.0 - smoothstep(seam_width * 1.1, seam_width * 2.4, edge);
	stitch_band *= smoothstep(seam_width * 0.9, seam_width * 1.3, edge);
	float stitch = stitch_band * step(0.55, fract(stitch_phase * 0.5)) * stitch_strength;

	// --- Panelfarbe ---------------------------------------------------------
	vec3 panel = mix(white_color, black_color, pent);
	// Leichte Helligkeitsvariation pro Panel, damit die Kugel nicht wie
	// eingefaerbtes Plastik wirkt.
	float panel_var = bhash(c1 * 17.0) * 0.06 - 0.03;
	panel *= 1.0 + panel_var;

	// Lederkorn.
	float grain = bnoise(p * grain_scale);
	panel *= 1.0 + (grain - 0.5) * grain_strength * 0.35;

	// Gebrauchsspuren: grossflaeckige, leicht mattere Schrammen.
	float scuff = bnoise(p * 9.0);
	scuff = smoothstep(0.62, 0.95, scuff);

	vec3 albedo = mix(panel, seam_color * mix(vec3(1.0), panel, 0.5), groove);
	albedo = mix(albedo, albedo * 1.35 + 0.06, stitch);
	albedo = mix(albedo, albedo * 0.88, scuff * scuff_strength);

	// --- Normale: Panels woelben sich, Naht liegt tief -----------------------
	// Nahe der Kante kippt die Normale vom Panelmittelpunkt weg (Kissenform),
	// direkt in der Rille kippt sie zurueck -> sichtbar eingelassene Naht.
	float bulge = smoothstep(0.0, seam_width * 6.0, edge);
	float n_amount = (1.0 - bulge) * panel_bulge - groove * panel_bulge * 1.6;
	vec3 n_obj = normalize(p - tang * n_amount);
	// Feines Korn zusaetzlich in die Normale, sonst wirkt das Leder zu glatt.
	vec3 grain_offset = vec3(
		bnoise(p * grain_scale + vec3(11.0, 0.0, 0.0)),
		bnoise(p * grain_scale + vec3(0.0, 23.0, 0.0)),
		bnoise(p * grain_scale + vec3(0.0, 0.0, 31.0))) - 0.5;
	n_obj = normalize(n_obj + grain_offset * grain_strength * 0.12);

	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_obj, 0.0)).xyz);

	ALBEDO = albedo;
	ROUGHNESS = clamp(base_roughness + groove * 0.4 + scuff * 0.3 + grain * 0.12, 0.05, 1.0);
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
