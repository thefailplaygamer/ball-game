shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Tornetz, komplett prozedural statt aus einer Alpha-Textur: ein echtes
// Rautennetz aus zwei gegenlaeufigen Schnurscharen, das an den Aufhaengungen
// leicht durchhaengt und zum Boden hin dichter wird. Die Schnuere bekommen
// eine runde Schattierung, dadurch wirkt das Netz raeumlich statt wie eine
// aufgeklebte Tapete.
//
// Die Maschen werden NICHT aus UV, sondern triplanar aus der Weltposition
// berechnet: die Tor-Panels sind unterschiedlich grosse Quader, per-Face-UV
// haette also auf jedem Panel eine andere Maschenweite ergeben. So laeuft das
// Netz mit konstanter Maschengroesse ueber alle Panels durch.

uniform vec4 team_tint : source_color = vec4(0.85, 0.2, 0.2, 1.0);
uniform vec4 rope_color : source_color = vec4(0.93, 0.94, 0.96, 1.0);
// Maschenweite in Metern.
uniform float mesh_size = 0.12;
uniform float rope_width : hint_range(0.01, 0.4) = 0.115;
// Wie stark das Netz zwischen den Aufhaengungen durchhaengt.
uniform float sag = 0.35;
uniform float sag_period = 1.4;
// Sockel-Deckkraft, damit das Tor auch aus der Distanz als Flaeche lesbar bleibt.
uniform float base_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float team_tint_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Abstand zum naechsten Schnur-Mittelpunkt einer Schar, 0 = mitten auf der Schnur.
float cord(float coord, float width) {
	float f = abs(fract(coord) - 0.5) * 2.0;
	return 1.0 - smoothstep(1.0 - width * 2.0, 1.0, f);
}

void fragment() {
	// Triplanare Projektion: die Achse mit der groessten Normalenkomponente
	// faellt weg, die beiden anderen spannen die Netzebene auf.
	vec3 an = abs(world_normal);
	vec2 uv = an.x > max(an.y, an.z)
		? world_pos.zy
		: (an.y > an.z ? world_pos.xz : world_pos.xy);

	// Durchhang: die Maschen verschieben sich wellenfoermig, dadurch sieht das
	// Netz nicht wie ein exakt gespanntes Gitter aus.
	float droop = sin(uv.x / sag_period * 6.2831) * sag * 0.5;
	vec2 p = vec2(uv.x, uv.y + droop * 0.1);

	// Zwei um 45 Grad gedrehte Scharen -> Rautenmaschen.
	vec2 d = vec2(p.x + p.y, p.x - p.y) / (mesh_size * 1.41421356);
	float c1 = cord(d.x, rope_width);
	float c2 = cord(d.y, rope_width);
	float net = max(c1, c2);
	// Knoten an den Kreuzungspunkten.
	float knot = c1 * c2;
	net = clamp(net + knot * 0.6, 0.0, 1.0);

	// Runde Schattierung quer ueber jede Schnur.
	float round1 = abs(fract(d.x) - 0.5) * 2.0;
	float round2 = abs(fract(d.y) - 0.5) * 2.0;
	float shade = mix(0.62, 1.0, max(round1, round2));

	vec3 col = rope_color.rgb * shade;
	col = mix(col, team_tint.rgb, team_tint_strength * 0.5);
	col = mix(col, col * 1.15 + 0.05, knot);

	// Hinter dem Netz ein sehr dunkler, leicht team-getoenter Grund.
	vec3 backdrop = mix(vec3(0.03, 0.03, 0.04), team_tint.rgb * 0.35, team_tint_strength);

	float alpha = clamp(base_alpha + net * (1.0 - base_alpha), 0.0, 1.0);

	ALBEDO = mix(backdrop, col, net);
	ALPHA = alpha;
	ROUGHNESS = mix(0.85, 0.62, net);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
