extends Node3D

## Statische 3rd-Person-Vorschau des eigenen Charakters mit dem aktuell
## ausgerüsteten Trikot, für den Inventar-Screen. Kein echter Multiplayer-Peer
## (owner_peer_id = -999), daher bleibt der Player komplett unbeweglich/inert.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var player_slot: Node3D = $PlayerSlot
@onready var camera: Camera3D = $Camera3D

var _player: Node = null

func _ready() -> void:
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	_spawn_player()

func set_jersey(jersey_id: int) -> void:
	if _player:
		_player.equipped_jersey_id = jersey_id

func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "-999" # neutrale, garantiert nicht-lokale Peer-ID
	_player.body_color = Color(0.55, 0.58, 0.65)
	_player.equipped_jersey_id = Inventory.equipped
	_player.player_number = Network.my_number
	player_slot.add_child(_player)
	_player.freeze = true # unbeweglich, egal was player.gd sonst entscheidet
	# Trikotname/-nummer sitzen auf dem Rücken (+Z), Kamera steht bewusst auf
	# der +Z-Seite (siehe character_preview.tscn), Spieler bleibt unrotiert.
	_refresh_text()

func _refresh_text() -> void:
	if _player == null:
		return
	_player.jersey_name.text = Network.my_name.to_upper()
	_player.jersey_number.text = str(Network.my_number) if Network.my_number > 0 else ""
