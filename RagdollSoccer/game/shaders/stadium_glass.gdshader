shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.9, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.18;
uniform float line_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float grid_scale = 6.0;

void fragment() {
	vec2 uv = UV * grid_scale;
	vec2 grid = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = min(grid.x, grid.y);
	float pattern = 1.0 - clamp(line, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = mix(base_alpha, line_alpha, pattern);
	ROUGHNESS = 0.15;
	METALLIC = 0.1;
}
