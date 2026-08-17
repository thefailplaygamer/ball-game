shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Real net texture (alpha mask: white = rope, black = hole) tiled across the panel,
// framed by a solid metal-look border so each panel reads as a goal-net segment
// bounded by posts/bars. Team color tints both the netting and the frame slightly
// so it's still obvious at a glance which goal belongs to which team.

uniform sampler2D net_mask : hint_default_black;
uniform vec4 team_tint : source_color = vec4(0.85, 0.2, 0.2, 1.0);
uniform vec4 net_rope_color : source_color = vec4(0.92, 0.93, 0.95, 1.0);
uniform vec4 frame_color : source_color = vec4(0.82, 0.84, 0.88, 1.0);
uniform float net_scale = 6.0;
uniform float net_opacity = 0.9;
// Mindest-Deckkraft auch zwischen den Netzmaschen, damit das Tor aus normaler
// Entfernung klar als Tor erkennbar bleibt statt fast unsichtbar zu sein.
uniform float base_alpha : hint_range(0.0, 1.0) = 0.6;
uniform float frame_width : hint_range(0.0, 0.3) = 0.07;
uniform float team_tint_strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 tiled_uv = fract(UV * net_scale);
	float mask = texture(net_mask, tiled_uv).r;

	// Distance to the panel edge in local UV space (0 = edge, 0.5 = center)
	float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float frame = 1.0 - smoothstep(0.0, frame_width, edge_dist);

	vec3 base_col = mix(vec3(0.08, 0.08, 0.09), team_tint.rgb, team_tint_strength);
	vec3 rope = mix(base_col, net_rope_color.rgb, mask);
	rope = mix(rope, team_tint.rgb, team_tint_strength * mask);

	vec3 post = mix(frame_color.rgb, team_tint.rgb, team_tint_strength);

	ALBEDO = mix(rope, post, frame);
	float net_alpha = clamp(base_alpha + mask * (1.0 - base_alpha) * net_opacity, 0.0, 1.0);
	ALPHA = mix(net_alpha, 1.0, frame);
	METALLIC = mix(0.05, 0.55, frame);
	ROUGHNESS = mix(0.75, 0.3, frame);
}
