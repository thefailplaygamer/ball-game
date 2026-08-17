extends Node3D

const SHADER := preload("res://shaders/city_building.gdshader")

@export var building_count := 42
@export var ring_radius_min := 42.0
@export var ring_radius_max := 95.0
@export var height_min := 10.0
@export var height_max := 42.0
@export var rng_seed := 20260815

func _ready() -> void:
	_generate()

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var angle_step := TAU / building_count
	for i in range(building_count):
		var angle := i * angle_step + rng.randf_range(-angle_step * 0.35, angle_step * 0.35)
		var radius := rng.randf_range(ring_radius_min, ring_radius_max)
		var depth_fraction: float = (radius - ring_radius_min) / max(ring_radius_max - ring_radius_min, 0.01)
		var height: float = rng.randf_range(height_min, height_max) * lerp(0.75, 1.3, depth_fraction)
		# Vereinzelte hohe "Tower" für Silhouetten-Abwechslung.
		if i % 7 == 0:
			height *= 1.6
		var width := rng.randf_range(6.0, 16.0)
		var depth := rng.randf_range(6.0, 16.0)

		var building := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, depth)
		building.mesh = mesh

		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var grey := rng.randf_range(0.025, 0.085)
		mat.set_shader_parameter("facade_color", Color(grey, grey * 1.05, grey * 1.2, 1.0))
		mat.set_shader_parameter("grid_x", float(rng.randi_range(4, 9)))
		mat.set_shader_parameter("grid_y", float(rng.randi_range(10, 22)))
		mat.set_shader_parameter("lit_chance", rng.randf_range(0.22, 0.55))
		mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 1000.0))
		if rng.randf() < 0.18:
			mat.set_shader_parameter("accent_chance", rng.randf_range(0.35, 0.65))
		building.material_override = mat

		building.position = Vector3(cos(angle) * radius, height / 2.0 - 1.0, sin(angle) * radius)
		building.rotation.y = rng.randf_range(0.0, TAU)
		add_child(building)
