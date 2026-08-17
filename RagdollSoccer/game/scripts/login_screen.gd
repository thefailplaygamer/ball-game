extends Control

@onready var username_edit: LineEdit = $MainPanel/VBox/UsernameEdit
@onready var password_edit: LineEdit = $MainPanel/VBox/PasswordEdit
@onready var status_label: Label = $MainPanel/VBox/StatusLabel
@onready var login_button: Button = $MainPanel/VBox/ButtonRow/LoginButton
@onready var register_button: Button = $MainPanel/VBox/ButtonRow/RegisterButton
@onready var quit_button: Button = $MainPanel/VBox/QuitButton

func _ready() -> void:
	for button in [login_button, register_button, quit_button]:
		button.pressed.connect(SFX.play_ui_click)
	status_label.text = "Melde an …"
	_set_busy(true)
	if await Supabase.try_auto_login():
		await _enter_menu()
		return
	_set_busy(false)
	status_label.text = ""

func _on_login_button_pressed() -> void:
	var uname := username_edit.text.strip_edges()
	var pw := password_edit.text
	if not _validate_input(uname, pw):
		return
	_set_busy(true)
	status_label.text = "Bitte warten …"
	var error := await Supabase.login(uname, pw)
	if error != "":
		status_label.text = error
		_set_busy(false)
		return
	await _enter_menu()

func _on_register_button_pressed() -> void:
	var uname := username_edit.text.strip_edges()
	var pw := password_edit.text
	if not _validate_input(uname, pw):
		return
	if pw.length() < 6:
		status_label.text = "Passwort muss mindestens 6 Zeichen haben."
		return
	_set_busy(true)
	status_label.text = "Bitte warten …"
	var error := await Supabase.register(uname, pw)
	if error != "":
		status_label.text = error
		_set_busy(false)
		return
	await _enter_menu()

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _validate_input(uname: String, pw: String) -> bool:
	if uname == "" or pw == "":
		status_label.text = "Bitte Benutzername und Passwort eingeben."
		return false
	return true

func _enter_menu() -> void:
	Network.my_name = Supabase.username
	status_label.text = "Lade Inventar …"
	await Inventory.load_from_cloud()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _set_busy(busy: bool) -> void:
	login_button.disabled = busy
	register_button.disabled = busy
	username_edit.editable = not busy
	password_edit.editable = not busy
