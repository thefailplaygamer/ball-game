extends Control

var slot_buttons: Dictionary = {} # slot_id -> Button

func _ready() -> void:
	add_to_group("position_select")
	for child in $Panel/PitchMap.get_children():
		if child is Button:
			slot_buttons[child.name] = child
			child.pressed.connect(_on_slot_pressed.bind(child.name))
	# Setzt die (kurzen) Rollen-Labels sofort, sonst zeigt der Host beim allerersten
	# Aufruf noch den alten, langen Platzhaltertext aus der Szene (update_occupancy()
	# kommt sonst erst, wenn sich die Spielerliste/Slots das erste Mal ändern).
	update_occupancy({})
	show_selection()

func _on_slot_pressed(slot_id: String) -> void:
	SFX.play_ui_click()
	var gm := get_tree().get_first_node_in_group("game_manager")
	if Network.is_host():
		gm.try_assign_slot(slot_id, Network.get_my_id())
	else:
		gm.request_slot.rpc_id(1, slot_id)

func _role_label(slot_id: String) -> String:
	if "goalkeeper" in slot_id:
		return "TW"
	if "striker" in slot_id:
		return "S"
	if "defender_0" in slot_id:
		return "LF"
	if "defender_2" in slot_id:
		return "RF"
	return "IV"

func update_occupancy(slot_owner: Dictionary) -> void:
	for slot_id in slot_buttons.keys():
		var btn: Button = slot_buttons[slot_id]
		var label := _role_label(slot_id)
		if slot_owner.has(slot_id):
			var pname: String = Network.players.get(slot_owner[slot_id], "?")
			btn.disabled = true
			btn.text = "%s\n(%s)" % [label, pname]
		else:
			btn.disabled = false
			btn.text = label
	if Network.get_my_id() in slot_owner.values():
		hide_selection()

func show_selection() -> void:
	visible = true
	Network.recompute_input_lock()

func hide_selection() -> void:
	visible = false
	Network.recompute_input_lock()
