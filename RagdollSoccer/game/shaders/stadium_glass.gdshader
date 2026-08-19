shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Sicherheitsverglasung der Arena statt eines flachen Gitternetzes:
// echte Scheibenteilung mit Alu-Profilen, gehaertetes Glas mit leichtem
// Gruenstich an der Kante, Fresnel-Reflexion (streifend wird die Scheibe
// deutlich sichtbar, frontal fast klar) sowie Staub und Kratzer.
//
// Die Scheibenteilung kommt aus der Weltposition, damit alle Wandsegmente
// dasselbe Raster teilen, egal wie gross das jeweilige Quader-Panel ist.

uniform vec4 tint : source_color = vec4(0.72, 0.82, 0.85, 1.0);
uniform vec4 frame_color : source_color = vec4(0.42, 0.45, 0.5, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.1;
uniform float fresnel_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float pane_width = 2.6;
uniform float pane_height = 2.0;
uniform float mullion_width = 0.055;
uniform float dirt_strength : hint_range(0.0, 1.0) = 0.35;
uniform float scratch_strength : hint_range(0.0, 1.0) = 0.3;

varying vec3 world_pos;
varying vec3 world_normal;

float ghash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(ghash(i), ghash(i + vec2(1.0, 0.0)), f.x),
		mix(ghash(i + vec2(0.0, 1.0)), ghash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(world_normal);
	// Horizontale Laufrichtung der Wand (die Achse quer zur Normalen).
	float h = an.x > an.z ? world_pos.z : world_pos.x;
	float y = world_pos.y;

	vec2 cell = vec2(h / pane_width, y / pane_height);
	vec2 f = abs(fract(cell) - 0.5);
	// Pfostenbreite in Zellenanteilen umrechnen, damit die Profile in beiden
	// Richtungen gleich dick aussehen.
	float mx = 0.5 - mullion_width / pane_width;
	float my = 0.5 - mullion_width / pane_height;
	float aa = fwidth(cell.x) * 1.5 + 0.001;
	float mullion = max(
		smoothstep(mx - aa, mx + aa, f.x),
		smoothstep(my - aa, my + aa, f.y));

	// Fresnel: streifend blickt man auf eine helle Scheibe, frontal hindurch.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	// Staubfilm und feine Kratzer.
	float dust = gnoise(vec2(h, y) * 1.7) * 0.6 + gnoise(vec2(h, y) * 6.0) * 0.4;
	dust = smoothstep(0.45, 0.9, dust);
	float scratch = gnoise(vec2(h * 22.0, y * 1.4));
	scratch = smoothstep(0.72, 0.98, scratch);

	// Gehaertetes Glas ist an der Kante gruener als in der Mitte.
	float edge = smoothstep(0.3, 0.5, max(f.x, f.y));
	vec3 glass = mix(tint.rgb, tint.rgb * vec3(0.75, 1.0, 0.88), edge * 0.6);
	glass = mix(glass, vec3(0.85, 0.86, 0.88), dust * dirt_strength);
	glass = mix(glass, vec3(1.0), scratch * scratch_strength);

	float glass_alpha = clamp(base_alpha + fres * fresnel_alpha + dust * dirt_strength * 0.25
		+ scratch * scratch_strength * 0.3, 0.0, 1.0);

	ALBEDO = mix(glass, frame_color.rgb, mullion);
	ALPHA = mix(glass_alpha, 1.0, mullion);
	ROUGHNESS = mix(0.05 + dust * 0.25, 0.42, mullion);
	METALLIC = mix(0.0, 0.85, mullion);
	SPECULAR = mix(0.85, 0.5, mullion);
}
