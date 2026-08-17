extends Camera3D

@export var radius := 18.0
@export var height := 9.0
@export var angular_speed := 0.06
@export var look_target := Vector3(0, 1.0, 0)

var _angle := 0.4

func _process(delta: float) -> void:
	_angle += angular_speed * delta
	global_position = Vector3(cos(_angle) * radius, height, sin(_angle) * radius)
	look_at(look_target, Vector3.UP)
