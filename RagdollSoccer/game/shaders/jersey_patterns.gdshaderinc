// Gemeinsame Trikot-Muster-Bibliothek.
//
// Wird von BEIDEN Trikot-Shadern eingebunden, damit ein Muster nur an einer
// Stelle existiert und die 2D-Inventar-Vorschau garantiert genauso aussieht
// wie der Stoff am 3D-Spieler:
//   - shaders/player_jersey.gdshader (spatial, Spielermodell)
//   - shaders/jersey_icon.gdshader   (canvas_item, Inventar-/Kisten-Icon)
//
// WICHTIG: Die Modus-Nummern muessen exakt mit JerseyData.Pattern in
// scripts/jersey_data.gd uebereinstimmen. Die Reihenfolge ist nach
// Seltenheit sortiert (0-3 Gewoehnlich ... 21-25 Legendaer), damit die
// Shader ueber einfache Bereichsvergleiche entscheiden koennen, wie
// glaenzend/animiert ein Trikot ist.

// ── Rausch-Helfer ────────────────────────────────────────────────────────

float jhash11(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 jhash22(vec2 p) {
	vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(q) * 43758.5453123);
}

float jnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = jhash11(i);
	float b = jhash11(i + vec2(1.0, 0.0));
	float c = jhash11(i + vec2(0.0, 1.0));
	float d = jhash11(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float jfbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * jnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

// x = Abstand zur naechsten Zelle, y = zur zweitnaechsten (y-x ~ Kantennaehe),
// z = Zufallswert der Zelle (fuer Farbe pro Facette).
vec3 jvoronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = p - n;
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = jhash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = jhash11(n + g);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Wabenraster: xy = Position innerhalb der Zelle, zw = Zellen-Index.
const vec2 JHEX_S = vec2(1.0, 1.7320508);

vec4 jhex(vec2 p) {
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / JHEX_S.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * JHEX_S, p - (hc.zw + 0.5) * JHEX_S);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + vec2(0.5));
}

// 0 in der Zellmitte, 0.5 auf der Wabenkante.
float jhex_edge(vec2 h) {
	return max(dot(abs(h), JHEX_S * 0.5), abs(h.x));
}

// ── Muster ───────────────────────────────────────────────────────────────
//
// t  = TIME (bei statischen Mustern egal)
// emit = wieviel das Muster an dieser Stelle leuchten soll (0 = gar nicht).
//        Der 3D-Shader macht daraus EMISSION, das Icon hellt damit auf.

vec3 jersey_pattern(int mode, vec2 uv, vec3 ca, vec3 cb, vec3 cc, float t, out float emit) {
	emit = 0.0;

	// ═══ GEWOEHNLICH: schlicht, aber sauber verarbeitet ═══

	if (mode == 0) { // Einfarbig
		return ca;
	}

	if (mode == 1) { // Ton-in-Ton-Streifen: breite Bahnen, kaum Kontrast
		float x = uv.x * 6.0;
		vec3 col = mix(ca, cb, step(0.5, fract(x)));
		float seam = smoothstep(0.47, 0.5, abs(fract(x) - 0.5));
		return col * (1.0 - seam * 0.07);
	}

	if (mode == 2) { // Melange: feine Faserspreckel wie meliertes Garn
		float n = jnoise(uv * 130.0) * 0.55 + jnoise(uv * 51.0 + 3.7) * 0.45;
		return mix(ca, cb, smoothstep(0.3, 0.8, n) * 0.8);
	}

	if (mode == 3) { // Brustband mit schmalen Zierlinien
		float band = smoothstep(0.405, 0.42, uv.y) - smoothstep(0.555, 0.57, uv.y);
		float trim = (smoothstep(0.375, 0.385, uv.y) - smoothstep(0.392, 0.402, uv.y))
			+ (smoothstep(0.575, 0.585, uv.y) - smoothstep(0.592, 0.602, uv.y));
		vec3 col = mix(ca, cb, clamp(band, 0.0, 1.0));
		return mix(col, cb * 0.65, clamp(trim, 0.0, 1.0));
	}

	// ═══ UNGEWOEHNLICH: klassische Vereinsmuster, klarer Zweifarb-Kontrast ═══

	if (mode == 4) { // Senkrechte Streifen
		float x = uv.x * 9.0;
		vec3 col = mix(ca, cb, step(0.5, fract(x)));
		float edge = smoothstep(0.45, 0.5, abs(fract(x) - 0.5));
		return col * (1.0 - edge * 0.13);
	}

	if (mode == 5) { // Waagerechte Ringel
		float y = uv.y * 8.0;
		vec3 col = mix(ca, cb, step(0.5, fract(y)));
		float edge = smoothstep(0.45, 0.5, abs(fract(y) - 0.5));
		return col * (1.0 - edge * 0.13);
	}

	if (mode == 6) { // Senkrecht halbiert, mit Trennlinie
		vec3 col = mix(ca, cb, smoothstep(0.494, 0.506, uv.x));
		float line = smoothstep(0.014, 0.0, abs(uv.x - 0.5));
		return mix(col, cc, line);
	}

	if (mode == 7) { // Doppelte Nadelstreifen
		float f = fract(uv.x * 13.0);
		float l1 = smoothstep(0.055, 0.0, abs(f - 0.28));
		float l2 = smoothstep(0.055, 0.0, abs(f - 0.44));
		return mix(ca, cb, clamp(l1 + l2, 0.0, 1.0) * 0.92);
	}

	if (mode == 8) { // Diagonale Schaerpe mit Kontrastkante
		float d = abs(uv.x + uv.y - 1.0);
		float sash = smoothstep(0.2, 0.165, d);
		float edge = clamp(smoothstep(0.255, 0.22, d) - sash, 0.0, 1.0);
		vec3 col = mix(ca, cc, edge);
		return mix(col, cb, sash);
	}

	if (mode == 9) { // Feines Karo (Vichy): drei Helligkeiten aus zwei Farben
		float sx = step(0.5, fract(uv.x * 11.0));
		float sy = step(0.5, fract(uv.y * 11.0));
		float lvl = sx + sy;
		vec3 mid = mix(ca, cb, 0.45);
		return lvl < 0.5 ? cb : (lvl < 1.5 ? mid : ca);
	}

	// ═══ SELTEN: geometrisch, dreifarbig, auffaellig ═══

	if (mode == 10) { // Chevron: gestapelte Pfeilspitzen
		float v = uv.y * 5.0 + abs(fract(uv.x * 2.0) - 0.5) * 2.4;
		vec3 col = mix(ca, cb, step(0.5, fract(v)));
		float f = fract(v * 2.0);
		float line = smoothstep(0.09, 0.0, min(f, 1.0 - f));
		return mix(col, cc, line * 0.85);
	}

	if (mode == 11) { // Argyle: Rautenmuster mit gekreuzten Ziernaehten
		vec2 g = vec2(uv.x * 4.0, uv.y * 3.2);
		vec2 f = fract(g) - 0.5;
		float d = abs(f.x) + abs(f.y);
		float parity = mod(floor(g.x) + floor(g.y), 2.0);
		vec3 inner = mix(cb, ca, parity);
		vec3 outer = mix(ca, cb, parity) * 0.72;
		vec3 col = mix(outer, inner, smoothstep(0.52, 0.48, d));
		float lx = abs(fract(g.x + g.y) - 0.5);
		float ly = abs(fract(g.x - g.y) - 0.5);
		float lines = smoothstep(0.44, 0.5, max(lx, ly));
		return mix(col, cc, lines * 0.9);
	}

	if (mode == 12) { // Waben mit leuchtenden Kanten
		vec4 h = jhex(uv * 6.5);
		float ed = jhex_edge(h.xy);
		float rnd = jhash11(h.zw);
		vec3 col = mix(ca, ca * 1.45, step(0.5, rnd));
		float edge = smoothstep(0.4, 0.47, ed);
		col = mix(col, cb, edge);
		float fill = smoothstep(0.4, 0.3, ed) * step(0.84, rnd);
		col = mix(col, cc, fill * 0.85);
		emit = edge * 0.15 + fill * 0.2;
		return col;
	}

	if (mode == 13) { // Splitterglas: facettierte Bruchstuecke
		vec3 v = jvoronoi(uv * 6.5);
		float edge = smoothstep(0.0, 0.085, v.y - v.x);
		vec3 col = mix(ca, cb, v.z);
		col *= 0.72 + 0.55 * smoothstep(0.0, 0.55, v.x);
		col = mix(cc, col, edge);
		emit = (1.0 - edge) * 0.25;
		return col;
	}

	if (mode == 14) { // Digitaltarn: gepixelte Flecken
		vec2 q = floor(uv * 28.0) / 28.0;
		float n = jnoise(q * 6.5) * 0.6 + jnoise(q * 14.0 + 4.3) * 0.4;
		vec3 col = mix(ca, cb, step(0.44, n));
		return mix(col, cc, step(0.67, n));
	}

	if (mode == 15) { // Tigerstreifen: breite, wellig verzogene Baender
		// Der Rausch wird ueber die Hoehe staerker gestreckt als ueber die
		// Breite, dadurch bleiben die Baender senkrecht und wellen sich nur.
		float warp = jnoise(uv * vec2(1.6, 3.4)) * 0.75 + jnoise(uv * vec2(3.2, 7.0) + 2.7) * 0.18;
		float s = sin((uv.x * 3.2 + warp) * 6.28318);
		float stripe = smoothstep(0.42, 0.72, abs(s));
		vec3 col = mix(cb, ca, stripe);
		return mix(col, cc, smoothstep(0.8, 1.0, stripe) * 0.4);
	}

	// ═══ EPISCH: Verlaeufe + Leuchten + dezente Bewegung ═══

	if (mode == 16) { // Sonnenuntergang: Sonnenscheibe ueber ziehenden Wolkenbaendern
		vec3 col = mix(cc, ca, smoothstep(0.06, 0.5, uv.y));
		col = mix(col, cb, smoothstep(0.5, 0.96, uv.y));
		float horizon = 0.5 + sin(t * 0.3) * 0.015;
		float sd = length((uv - vec2(0.5, horizon)) / vec2(1.0, 1.25));
		float halo = smoothstep(0.42, 0.0, sd);
		float disc = smoothstep(0.115, 0.085, sd);
		col = mix(col, cc, halo * 0.45);
		col = mix(col, vec3(1.0, 0.95, 0.75), disc * 0.85);
		// Wolkenbaender ziehen langsam durch und schneiden die Sonne an.
		float band = sin(uv.y * 34.0 + sin(t * 0.35) * 1.8);
		float cloud = smoothstep(0.55, 0.95, band)
			* smoothstep(0.28, 0.45, uv.y) * smoothstep(1.0, 0.7, uv.y);
		col = mix(col, cb * 0.5, cloud * 0.7);
		emit = disc * 1.1 + halo * 0.35 + 0.08;
		return col;
	}

	if (mode == 17) { // Nebula: treibende Gasschwaden mit funkelnden Sternen
		vec2 p = uv * 3.0 + vec2(t * 0.018, -t * 0.013);
		float n = jfbm(p);
		float n2 = jfbm(p * 2.1 + 7.3);
		vec3 col = mix(cc * 0.3, ca, smoothstep(0.22, 0.78, n));
		col = mix(col, cb, smoothstep(0.48, 0.95, n2) * 0.85);
		col = mix(col, cc, smoothstep(0.7, 1.0, n * n2 * 1.6) * 0.6);
		vec2 sc = floor(uv * 70.0);
		float sr = jhash11(sc);
		float tw = 0.5 + 0.5 * sin(t * 1.1 + sr * 40.0);
		float star = step(0.984, sr) * (0.35 + 0.65 * tw);
		col += vec3(star);
		emit = 0.18 + star * 1.6;
		return col;
	}

	if (mode == 18) { // Schaltkreis: Leiterbahnen mit wanderndem Energiepuls
		vec2 g = uv * vec2(10.0, 13.0);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float r = jhash11(cell);
		float r2 = jhash11(cell + vec2(17.3, 5.1));
		// Waagerechte und senkrechte Bahnen ueberlagern sich, damit das Netz
		// zusammenhaengend wirkt statt aus losen Strichen zu bestehen.
		float hline = smoothstep(0.07, 0.028, abs(f.y - 0.5)) * step(0.25, r);
		float vline = smoothstep(0.07, 0.028, abs(f.x - 0.5)) * step(0.45, r2);
		float trace = clamp(hline + vline, 0.0, 1.0);
		float node = smoothstep(0.16, 0.09, length(f - vec2(0.5))) * step(0.78, r2);
		float pulse = 0.5 + 0.5 * sin(t * 1.7 - uv.y * 10.0 + r * 6.28);
		vec3 col = cc;
		col = mix(col, ca * (0.55 + 0.65 * pulse), trace);
		col = mix(col, cb, node);
		emit = trace * pulse * 0.7 + node * 0.9;
		return col;
	}

	if (mode == 19) { // Frostbruch: Eiskristall-Risse mit langsamem Schimmer
		vec3 v = jvoronoi(uv * 5.0 + jfbm(uv * 3.0) * 0.45);
		float crack = smoothstep(0.11, 0.0, v.y - v.x);
		vec3 col = mix(cb, ca, smoothstep(0.0, 0.65, v.x));
		col = mix(col, cc, crack);
		float sweep = smoothstep(0.93, 1.0, sin((uv.x + uv.y * 0.7) * 3.4 - t * 0.55));
		col += cc * sweep * 0.16;
		emit = crack * 0.35 + sweep * 0.25;
		return col;
	}

	if (mode == 20) { // Magmakern: dunkle Kruste, gluehende Spalten, Pulsieren
		vec2 p = uv * 4.0;
		float crust = jfbm(p * 1.6);
		vec3 v = jvoronoi(p + jfbm(p) * 0.55);
		float crack = smoothstep(0.15, 0.0, v.y - v.x);
		float breath = 0.6 + 0.4 * sin(t * 0.9 + v.z * 6.28);
		float hot = crack * breath;
		vec3 col = mix(cc * 0.55, cc * 1.5, crust);
		col = mix(col, ca, hot);
		col = mix(col, cb, smoothstep(0.55, 1.0, hot));
		emit = hot * 1.5;
		return col;
	}

	// ═══ LEGENDAER: voll animiert, sollen sofort ins Auge springen ═══

	if (mode == 21) { // Prisma: rotierendes Spektrum mit Brechungswellen
		vec2 p = uv - 0.5;
		float rad = length(p);
		float ang = atan(p.y, p.x);
		float k = ang / 6.28318 + rad * 1.5 - t * 0.17;
		k += sin(rad * 20.0 - t * 1.5) * 0.05;
		vec3 col = 0.5 + 0.5 * cos(6.28318 * (k + vec3(0.0, 0.33, 0.67)));
		col = pow(col, vec3(0.8));
		float band = smoothstep(0.9, 1.0, sin((uv.x + uv.y) * 13.0 - t * 3.0));
		col += vec3(band) * 0.55;
		emit = 0.5 + band * 0.9;
		return col;
	}

	if (mode == 22) { // Hologramm: Beugungsgitter + durchwandernder Glanzbalken
		float grate = sin(uv.x * 95.0 + sin(uv.y * 15.0) * 3.0);
		float k = uv.x * 0.7 + uv.y * 0.9 + t * 0.26 + grate * 0.018;
		vec3 col = 0.5 + 0.5 * cos(6.28318 * (k + vec3(0.0, 0.33, 0.67)));
		col = mix(col, vec3(1.0), 0.2);
		float sweep = fract(t * 0.33);
		float d = abs(fract(uv.x * 0.5 + uv.y * 0.5 - sweep + 0.5) - 0.5);
		float bar = smoothstep(0.055, 0.0, d);
		col += vec3(1.0) * bar * 0.9;
		emit = 0.3 + bar * 1.3;
		return col;
	}

	if (mode == 23) { // Flammenbrand: aufsteigendes Feuer mit stiebenden Funken
		// Das Feuer sitzt am Saum und leckt nach oben: unten weissglut, oben
		// verlaufen die Zungen in dunklen Rauch. Der Rausch scrollt mit +t
		// nach oben, sonst wuerden die Flammen fallen.
		vec2 p = uv * vec2(3.4, 2.2);
		p.y += t * 0.95;
		float n = jfbm(p);
		float n2 = jfbm(p * 2.7 + vec2(5.2, 0.0));
		float flame = clamp((uv.y - 0.28) * 1.45 + (n - 0.5) * 1.7 + (n2 - 0.5) * 0.9, 0.0, 1.0);
		vec3 col = cc;
		col = mix(col, ca * 0.4, smoothstep(0.02, 0.2, flame));
		col = mix(col, ca, smoothstep(0.22, 0.52, flame));
		col = mix(col, cb, smoothstep(0.58, 0.88, flame));
		col = mix(col, vec3(1.0), smoothstep(0.92, 1.0, flame) * 0.5);
		vec2 sc = floor(uv * vec2(34.0, 46.0) + vec2(0.0, t * 8.0));
		float spark = step(0.988, jhash11(sc)) * smoothstep(0.95, 0.1, uv.y);
		col += cb * spark * 1.7;
		emit = smoothstep(0.15, 0.85, flame) * 1.05 + spark * 2.0;
		return col;
	}

	if (mode == 24) { // Cybergitter: scrollendes Neonraster, Scanpuls, Datenstroeme
		vec2 g = uv * vec2(10.0, 14.0);
		g.y += t * 1.15;
		vec2 f = abs(fract(g) - 0.5);
		float grid = smoothstep(0.43, 0.5, max(f.x, f.y));
		vec3 col = cc;
		col = mix(col, ca, grid * 0.9);
		float scan = smoothstep(0.9, 1.0, sin(uv.y * 6.0 - t * 2.2));
		col += ca * scan * 0.5;
		// Datenstroeme: schmale Spalten, in denen kurze Zeichenketten nach
		// unten fallen — die Spalte bleibt schmaler als eine Rasterzelle,
		// sonst werden daraus grobe Kloetze.
		float col_id = floor(uv.x * 15.0);
		float speed = 0.55 + jhash11(vec2(col_id, 3.0)) * 1.5;
		float head = fract(uv.y + t * speed + jhash11(vec2(col_id, 7.0)));
		float streak = smoothstep(0.72, 1.0, head);
		float row = floor(uv.y * 52.0 - t * speed * 52.0);
		float glyph = step(0.55, jhash11(vec2(col_id, row)));
		float col_w = smoothstep(0.38, 0.24, abs(fract(uv.x * 15.0) - 0.5));
		float data = streak * glyph * col_w;
		col += cb * data * 1.5;
		emit = grid * 0.75 + scan * 0.8 + data * 1.8;
		return col;
	}

	if (mode == 25) { // Galaxie: rotierende Spiralarme um einen gleissenden Kern
		vec2 p = uv - 0.5;
		float r = length(p) * 2.0;
		float a = atan(p.y, p.x) + r * 3.4 - t * 0.32;
		float arms = 0.5 + 0.5 * sin(a * 2.0);
		arms *= smoothstep(1.3, 0.05, r);
		float dust = jfbm(vec2(cos(a), sin(a)) * 2.2 + r * 3.0 - t * 0.05);
		vec3 col = cc;
		col = mix(col, ca, arms * (0.5 + 0.5 * dust));
		col = mix(col, cb, smoothstep(0.5, 1.0, arms * dust) * 0.9);
		float core = smoothstep(0.34, 0.0, r);
		col = mix(col, vec3(1.0, 0.95, 0.86), core * 0.92);
		vec2 sc = floor(uv * 80.0);
		float sr = jhash11(sc);
		float tw = 0.5 + 0.5 * sin(t * 2.0 + sr * 60.0);
		float star = step(0.982, sr) * (0.3 + 0.7 * tw);
		col += vec3(star);
		emit = core * 1.5 + arms * 0.45 + star * 1.8;
		return col;
	}

	return ca;
}
