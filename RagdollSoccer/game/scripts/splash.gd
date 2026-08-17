extends Control

var _transitioning := false

func _ready() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(2.4).timeout
	_go_to_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_go_to_menu()

func _go_to_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	var tw_out := create_tween()
	tw_out.tween_property(self, "modulate:a", 0.0, 0.35)
	await tw_out.finished
	get_tree().change_scene_to_file("res://scenes/login_screen.tscn")
