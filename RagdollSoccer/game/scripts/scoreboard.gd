extends Control

const REFRESH_INTERVAL := 0.5

@onready var list_container: VBoxContainer = $Panel/VBox/List

var _refresh_accum: float = 0.0

func _ready() -> void:
	add_to_group("scoreboard")
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("scoreboard"):
		_refresh_accum = 0.0
		_refresh()
		visible = true
	elif event.is_action_released("scoreboard"):
		visible = false

func _refresh() -> void:
	for child in list_container.get_children():
		child.queue_free()

	var gm := get_tree().get_first_node_in_group("game_manager")
	var peer_team: Dictionary = {}
	if gm:
		for slot_id in gm.slot_owner.keys():
			var peer_id: int = gm.slot_owner[slot_id]
			peer_team[peer_id] = gm.slots[slot_id]["team"]

	var goals: Dictionary = gm.player_goals if gm else {}
	for peer_id in Network.players.keys():
		var pname: String = Network.players[peer_id]
		var team: int = peer_team.get(peer_id, -1)
		var goal_count: int = goals.get(peer_id, 0)
		var ping_ms: int = Network.pings.get(peer_id, 0)
		var row := Label.new()
		if team == 0:
			row.text = "%s — Team Rot (%d Tore) — %d ms" % [pname, goal_count, ping_ms]
			row.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
		elif team == 1:
			row.text = "%s — Team Blau (%d Tore) — %d ms" % [pname, goal_count, ping_ms]
			row.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
		else:
			row.text = "%s — wählt noch Position — %d ms" % [pname, ping_ms]
		list_container.add_child(row)
