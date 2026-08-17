extends Control

const IDLE_HIDE_DELAY := 5.0

@onready var panel: Control = $Panel
@onready var log_label: RichTextLabel = $Panel/VBox/Log
@onready var input_edit: LineEdit = $Panel/VBox/Input

var _last_activity_time: float = 0.0

func _ready() -> void:
	add_to_group("chat_box")
	input_edit.visible = false
	input_edit.text_submitted.connect(_on_text_submitted)
	Chat.message_received.connect(_on_message_received)
	_last_activity_time = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	# Nach IDLE_HIDE_DELAY ohne Nachricht ausblenden, außer man tippt gerade selbst.
	var now := Time.get_ticks_msec() / 1000.0
	panel.visible = is_open() or (now - _last_activity_time < IDLE_HIDE_DELAY)

func is_open() -> bool:
	return input_edit.visible

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		get_viewport().set_input_as_handled()
		if is_open():
			return # LineEdit sendet text_submitted selbst
		var pause := get_tree().get_first_node_in_group("pause_menu")
		if pause and pause.visible:
			return
		_open_input()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_input()

func _open_input() -> void:
	input_edit.visible = true
	input_edit.grab_focus()
	_last_activity_time = Time.get_ticks_msec() / 1000.0
	Network.recompute_input_lock()

func _close_input() -> void:
	input_edit.visible = false
	input_edit.text = ""
	Network.recompute_input_lock()

func _on_text_submitted(text: String) -> void:
	Chat.submit_chat(text)
	_close_input()

func _on_message_received(sender_name: String, text: String) -> void:
	log_label.append_text("[b]%s:[/b] %s\n" % [sender_name.replace("[", "(").replace("]", ")"), text.replace("[", "(").replace("]", ")")])
	_last_activity_time = Time.get_ticks_msec() / 1000.0
