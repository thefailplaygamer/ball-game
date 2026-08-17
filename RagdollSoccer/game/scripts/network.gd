extends Node

signal players_changed

const PORT := 7777
const MAX_PLAYERS := 8

var players: Dictionary = {} # peer_id -> Name
var player_numbers: Dictionary = {} # peer_id -> Trikotnummer
var equipped_jerseys: Dictionary = {} # peer_id -> Trikot-ID (siehe JerseyData)
var pings: Dictionary = {} # peer_id -> Ping in ms
var input_locked: bool = false # true während Pause-Menü, Chat oder Positionswahl offen ist
var my_name: String = "Spieler"
var my_number: int = 10

const PING_BROADCAST_INTERVAL := 1.0
var _ping_broadcast_accum: float = 0.0

func _ready() -> void:
	# Läuft auf jedem Client, sobald die Verbindung zum Host abreißt — egal ob
	# der Host sauber getrennt hat oder einfach das Spiel/den Rechner
	# geschlossen hat (ENet erkennt beides). "multiplayer" ist der über die
	# ganze App-Laufzeit gleichbleibende MultiplayerAPI-Singleton, daher reicht
	# das einmalige Verbinden hier im Autoload statt bei jedem join_game().
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if not is_host():
		return
	_ping_broadcast_accum += delta
	if _ping_broadcast_accum < PING_BROADCAST_INTERVAL:
		return
	_ping_broadcast_accum = 0.0
	var new_pings: Dictionary = {1: 0}
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer:
		for peer_id in players.keys():
			if peer_id == 1:
				continue
			var packet_peer := enet_peer.get_peer(peer_id)
			if packet_peer:
				new_pings[peer_id] = int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	pings = new_pings
	sync_pings.rpc(pings)

@rpc("call_local", "reliable")
func sync_pings(new_pings: Dictionary) -> void:
	pings = new_pings

func host_game(player_name: String, number: int, jersey_id: int = 0) -> void:
	my_name = player_name
	my_number = number
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Konnte Server nicht starten: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	players[1] = player_name
	player_numbers[1] = number
	equipped_jerseys[1] = jersey_id
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	players_changed.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func join_game(ip: String, player_name: String, number: int, jersey_id: int = 0) -> void:
	my_name = player_name
	my_number = number
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("Konnte nicht verbinden: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func():
		rpc_id(1, "register_name", my_name, my_number, jersey_id)
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	multiplayer.connection_failed.connect(func():
		push_error("Verbindung fehlgeschlagen")
	)

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	player_numbers.clear()
	equipped_jerseys.clear()
	pings.clear()
	input_locked = false

## Der Host hat die Verbindung geschlossen (bewusst getrennt oder Spiel/PC
## einfach zu). Statt alle in einer toten Verbindung hängen zu lassen: sofort
## selbst trennen, zurück ins Hauptmenü und per Popup Bescheid geben.
func _on_server_disconnected() -> void:
	disconnect_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
	_show_server_lost_popup()

func _show_server_lost_popup() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Verbindung getrennt"
	dialog.dialog_text = "Der Server ist nicht mehr erreichbar — der Host hat das Spiel verlassen."
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)

@rpc("any_peer", "reliable")
func register_name(pname: String, number: int, jersey_id: int = 0) -> void:
	if not is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	players[sender_id] = pname
	player_numbers[sender_id] = number
	equipped_jerseys[sender_id] = jersey_id
	players_changed.emit()
	_sync_players.rpc(players, player_numbers, equipped_jerseys)

## Verteilt die komplette Spielerliste an alle Peers, sonst kennen Clients nur sich selbst.
@rpc("call_local", "reliable")
func _sync_players(new_players: Dictionary, new_numbers: Dictionary, new_jerseys: Dictionary) -> void:
	players = new_players
	player_numbers = new_numbers
	equipped_jerseys = new_jerseys
	players_changed.emit()

func _on_peer_connected(id: int) -> void:
	print("Spieler verbunden: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("Spieler getrennt: %d" % id)
	players.erase(id)
	player_numbers.erase(id)
	equipped_jerseys.erase(id)
	players_changed.emit()
	if is_host():
		_sync_players.rpc(players, player_numbers, equipped_jerseys)

func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"

## Prüft erst den Verbindungsstatus, bevor is_server()/get_unique_id() aufgerufen
## wird: auf einem Client, dessen Peer (noch) nicht vollständig verbunden ist,
## würfe is_server() sonst bei jedem einzelnen Frame einen Engine-Fehler.
func is_host() -> bool:
	var peer := multiplayer.multiplayer_peer
	# Ohne aktive Verbindung setzt Godot selbst einen OfflineMultiplayerPeer
	# ein (nie null!), auf dem is_server() aber trotzdem true liefert. Das
	# würde z.B. im Hauptmenü/Inventar-Screen fälschlich "ich bin Host" sagen.
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return multiplayer.is_server()

## Sichere Variante von multiplayer.get_unique_id(): liefert 0 statt bei
## jedem Frame einen Engine-Fehler zu werfen, wenn der Peer (noch) nicht
## vollständig aktiv ist (gleicher Hintergrund wie bei is_host() oben).
func get_my_id() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return 0
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	return multiplayer.get_unique_id()

## Zentrale Stelle, die entscheidet ob Bewegung/Maussteuerung gesperrt sein soll,
## basierend auf allen UI-Overlays die sich das teilen (Pause, Chat, Positionswahl).
func recompute_input_lock() -> void:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	var st: SceneTree = tree
	var locked := false
	var pause := st.get_first_node_in_group("pause_menu")
	if pause and pause.visible:
		locked = true
	var chat := st.get_first_node_in_group("chat_box")
	if chat and chat.is_open():
		locked = true
	var selector := st.get_first_node_in_group("position_select")
	if selector and selector.visible:
		locked = true
	input_locked = locked
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if locked else Input.MOUSE_MODE_CAPTURED
