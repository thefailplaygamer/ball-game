shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Nacht-Skyline-Fassade: dunkler Baukörper mit einem Raster zufällig
// erleuchteter Fenster (Cyberpunk/Tokyo-Nacht-Look statt Beton-Tribüne).

uniform vec4 facade_color : source_color = vec4(0.05, 0.055, 0.07, 1.0);
uniform vec4 window_color : source_color = vec4(1.0, 0.72, 0.35, 1.0);
uniform vec4 accent_color : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float grid_x = 6.0;
uniform float grid_y = 14.0;
uniform float lit_chance : hint_range(0.0, 1.0) = 0.4;
uniform float accent_chance : hint_range(0.0, 1.0) = 0.12;
uniform float window_emission = 1.7;
uniform float seed_offset = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed_offset);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 cell = floor(UV * vec2(grid_x, grid_y));
	vec2 cell_uv = fract(UV * vec2(grid_x, grid_y));

	// Kleiner Fenster-Rahmen innerhalb jeder Zelle, Rest ist Fassade.
	float window_shape = step(0.18, cell_uv.x) * step(cell_uv.x, 0.82) * step(0.15, cell_uv.y) * step(cell_uv.y, 0.85);

	float r = hash(cell);
	float is_lit = step(1.0 - lit_chance, r);
	float is_accent = step(1.0 - accent_chance, hash(cell + vec2(7.7, 3.3)));

	vec3 lit_col = mix(window_color.rgb, accent_color.rgb, is_accent);
	vec3 base = mix(facade_color.rgb, lit_col, window_shape * is_lit);

	ALBEDO = base;
	EMISSION = lit_col * window_shape * is_lit * window_emission;
	ROUGHNESS = 0.65;
	METALLIC = 0.15;
}
