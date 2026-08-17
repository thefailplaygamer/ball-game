shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform float cell_scale = 3.2;
uniform vec3 white_color : source_color = vec3(0.95, 0.95, 0.92);
uniform vec3 black_color : source_color = vec3(0.05, 0.05, 0.05);

varying vec3 obj_pos;

void vertex() {
	obj_pos = normalize(VERTEX);
}

vec3 hash3(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123);
}

void fragment() {
	vec3 p = obj_pos * cell_scale;
	vec3 base_cell = floor(p);
	float min_dist = 10.0;
	float cell_id = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 neighbor = base_cell + vec3(float(x), float(y), float(z));
				vec3 point = neighbor + hash3(neighbor);
				float d = length(p - point);
				if (d < min_dist) {
					min_dist = d;
					cell_id = hash3(neighbor).x;
				}
			}
		}
	}
	ALBEDO = cell_id < 0.32 ? black_color : white_color;
	ROUGHNESS = 0.35;
}
