extends Control

@onready var main_panel: Control = $MainPanel
@onready var options_instance: Control = $OptionsInstance

func _ready() -> void:
	add_to_group("pause_menu")
	visible = false
	options_instance.visible = false
	options_instance.standalone = false
	options_instance.closed.connect(_on_options_closed)
	for button in [$MainPanel/VBox/ResumeButton, $MainPanel/VBox/OptionsButton, $MainPanel/VBox/DisconnectButton, $MainPanel/VBox/QuitButton]:
		button.pressed.connect(SFX.play_ui_click)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var chat := get_tree().get_first_node_in_group("chat_box")
	if chat and chat.is_open():
		return
	var selector := get_tree().get_first_node_in_group("position_select")
	if selector and selector.visible:
		return
	get_viewport().set_input_as_handled()
	if options_instance.visible:
		options_instance.visible = false
		main_panel.visible = true
		return
	_toggle()

func _toggle() -> void:
	visible = not visible
	main_panel.visible = visible
	Network.recompute_input_lock()

func _on_resume_button_pressed() -> void:
	_toggle()

func _on_options_button_pressed() -> void:
	main_panel.visible = false
	options_instance.visible = true

func _on_options_closed() -> void:
	options_instance.visible = false
	main_panel.visible = true

func _on_disconnect_button_pressed() -> void:
	Network.disconnect_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
