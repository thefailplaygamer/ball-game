shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Hautton mit feinem Rauschen statt einer komplett glatten Team-Farb-Kugel als Kopf.

uniform vec4 skin_tone : source_color = vec4(0.87, 0.68, 0.56, 1.0);
uniform float grain_scale = 40.0;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV * grain_scale;
	float grain = hash(floor(uv)) - 0.5;
	ALBEDO = clamp(skin_tone.rgb + grain * grain_strength, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.55;
	METALLIC = 0.0;
}
