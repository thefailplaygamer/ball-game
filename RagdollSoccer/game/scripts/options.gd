extends Control

signal closed

@export var standalone: bool = true

@onready var master_slider: HSlider = $Panel/VBox/MasterSlider
@onready var ambient_slider: HSlider = $Panel/VBox/AmbientSlider
@onready var ui_slider: HSlider = $Panel/VBox/UISlider
@onready var ball_slider: HSlider = $Panel/VBox/BallSlider
@onready var music_slider: HSlider = $Panel/VBox/MusicSlider
@onready var fullscreen_check: CheckBox = $Panel/VBox/FullscreenCheck
@onready var back_button: Button = $Panel/VBox/BackButton

func _ready() -> void:
	master_slider.value = Settings.volumes["Master"]
	ambient_slider.value = Settings.volumes["Ambient"]
	ui_slider.value = Settings.volumes["UI"]
	ball_slider.value = Settings.volumes["Ball"]
	music_slider.value = Settings.volumes["Music"]
	fullscreen_check.button_pressed = Settings.fullscreen
	for button in [back_button]:
		button.pressed.connect(SFX.play_ui_click)

func _on_master_slider_value_changed(value: float) -> void:
	Settings.set_volume("Master", value)

func _on_ambient_slider_value_changed(value: float) -> void:
	Settings.set_volume("Ambient", value)

func _on_ui_slider_value_changed(value: float) -> void:
	Settings.set_volume("UI", value)

func _on_ball_slider_value_changed(value: float) -> void:
	Settings.set_volume("Ball", value)

func _on_music_slider_value_changed(value: float) -> void:
	Settings.set_volume("Music", value)

func _on_fullscreen_check_toggled(pressed: bool) -> void:
	Settings.fullscreen = pressed

func _on_back_pressed() -> void:
	Settings.save_settings()
	if standalone:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	else:
		visible = false
		closed.emit()
