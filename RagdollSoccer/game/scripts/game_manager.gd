extends Node3D

enum Phase { WARMUP, FIRST_HALF, HALFTIME, SECOND_HALF, FULL_TIME }
enum MatchState { NONE, KICKOFF, GOAL_CELEBRATION, GOAL_REPLAY }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HALF_DURATION := 300.0 # 5 Minuten
const HALFTIME_BREAK := 15.0
const KICKOFF_DELAY := 3.0
const GOAL_CELEBRATION_DURATION := 2.5
const GOAL_REPLAY_DURATION := 4.0
const TIMER_RESYNC_INTERVAL := 5.0
const HALFTIME_BANNER_DURATION := 4.0
const TACKLE_LOCK_DURATION := 3.0

@onready var players_container: Node3D = $Players
@onready var ball: RigidBody3D = $Ball
@onready var score_label: RichTextLabel = $UI/HUD/ScoreLabel
@onready var timer_label: Label = $UI/HUD/TimerPanel/TimerChip/TimerLabel
@onready var phase_label: Label = $UI/HUD/PhaseLabel
@onready var state_banner: Label = $UI/HUD/StateBanner
@onready var phase_banner: Label = $UI/HUD/PhaseBanner

var score := {0: 0, 1: 0}
var player_goals: Dictionary = {} # peer_id -> Anzahl Tore
## Fünf Rollen-Slots pro Team: Sturm (macht auch den Anstoß), Torhüter,
## drei Verteidiger in einer Reihe. Werden erst nach dem Verbinden per Karte gewählt.
var slots := {
	"0_goalkeeper": {"team": 0, "position": Vector3(-13, 1.0, 0)},
	"0_defender_0": {"team": 0, "position": Vector3(-8, 1.0, -4)},
	"0_defender_1": {"team": 0, "position": Vector3(-8, 1.0, 0)},
	"0_defender_2": {"team": 0, "position": Vector3(-8, 1.0, 4)},
	"0_striker": {"team": 0, "position": Vector3(-2, 1.0, 0)},
	"1_goalkeeper": {"team": 1, "position": Vector3(13, 1.0, 0)},
	"1_defender_0": {"team": 1, "position": Vector3(8, 1.0, -4)},
	"1_defender_1": {"team": 1, "position": Vector3(8, 1.0, 0)},
	"1_defender_2": {"team": 1, "position": Vector3(8, 1.0, 4)},
	"1_striker": {"team": 1, "position": Vector3(2, 1.0, 0)},
}
var slot_owner: Dictionary = {} # slot_id -> peer_id
var player_slot: Dictionary = {} # peer_id -> slot_id
var team_colors := {0: Color(0.85, 0.2, 0.2), 1: Color(0.2, 0.4, 0.9)}

var phase: int = Phase.WARMUP
var match_state: int = MatchState.NONE
var is_paused: bool = false
var time_remaining: float = 0.0
var kickoff_lock: float = 0.0
var tackle_lock_remaining: float = 0.0
var ready_votes: Dictionary = {}
var reset_votes: Dictionary = {}
var ready_status_text := ""
var last_scorer_name := ""
var goal_sequence_active := false
var _timer_broadcast_accum := 0.0
var _next_dummy_id := -1

func _ready() -> void:
	add_to_group("game_manager")
	update_score_display(0, 0)
	Ambience.start_stadium_ambience()
	_update_phase_ui()
	_update_state_banner()
	phase_banner.text = ""
	if not Network.is_host():
		return
	Network.players_changed.connect(_on_players_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(delta: float) -> void:
	# Der Countdown läuft auf JEDEM Peer lokal jede Frame in Echtzeit weiter,
	# damit die Anzeige nicht am Netzwerktakt hängt und ruckelt. Während Torjubel,
	# Wiederholung und Pause steht die Uhr still.
	var in_timed_phase := phase == Phase.FIRST_HALF or phase == Phase.SECOND_HALF or phase == Phase.HALFTIME
	var goal_sequence_paused := match_state == MatchState.GOAL_CELEBRATION or match_state == MatchState.GOAL_REPLAY
	var timer_running := in_timed_phase and not goal_sequence_paused and not is_paused
	if timer_running:
		time_remaining = max(time_remaining - delta, 0.0)
	if in_timed_phase:
		timer_label.text = _format_time(time_remaining)

	if not Network.is_host():
		return
	if is_paused:
		return

	if kickoff_lock > 0.0:
		kickoff_lock -= delta
		if kickoff_lock <= 0.0:
			ball.freeze = false
			for child in players_container.get_children():
				child.freeze = false
			set_match_state(MatchState.NONE)
			# Kurze Grätsch-Sperre ab dem Moment, in dem sich alle wieder bewegen
			# dürfen, damit sich die beiden Stürmer nicht direkt zu Anstoß-Beginn umgrätschen.
			tackle_lock_remaining = TACKLE_LOCK_DURATION

	if tackle_lock_remaining > 0.0:
		tackle_lock_remaining -= delta

	if timer_running and not goal_sequence_paused and time_remaining <= 0.0:
		_advance_phase()

	# Nur gelegentliche Korrektur-Syncs, der eigentliche Countdown läuft lokal.
	_timer_broadcast_accum += delta
	if _timer_broadcast_accum >= TIMER_RESYNC_INTERVAL:
		_timer_broadcast_accum -= TIMER_RESYNC_INTERVAL
		sync_phase.rpc(phase, int(ceil(max(time_remaining, 0.0))))

func register_ready_vote(peer_id: int) -> void:
	if not Network.is_host() or phase != Phase.WARMUP:
		return
	if not (peer_id in slot_owner.values()):
		return # nur wer eine Position gewählt hat, darf mitstimmen
	ready_votes[peer_id] = true
	var total: int = max(Network.players.size(), 1)
	var needed: int = int(ceil(total / 2.0))
	sync_ready_votes.rpc(ready_votes.size(), needed)
	if ready_votes.size() >= needed:
		_start_match()

func register_reset_vote(peer_id: int) -> void:
	if not Network.is_host() or phase == Phase.WARMUP:
		return
	if not (peer_id in slot_owner.values()):
		return
	reset_votes[peer_id] = true
	var total: int = max(Network.players.size(), 1)
	var needed: int = int(ceil(total / 2.0))
	if reset_votes.size() >= needed:
		_reset_to_warmup()

func _reset_to_warmup() -> void:
	goal_sequence_active = false
	phase = Phase.WARMUP
	score = {0: 0, 1: 0}
	player_goals.clear()
	sync_player_goals.rpc(player_goals)
	ready_votes.clear()
	reset_votes.clear()
	ready_status_text = ""
	update_score_display.rpc(0, 0)
	sync_phase.rpc(phase, 0)
	set_match_state(MatchState.NONE)
	ball.freeze = false
	ball.reset_ball()
	for child in players_container.get_children():
		child.freeze = false
		child.cancel_penalty()

func _start_match() -> void:
	phase = Phase.FIRST_HALF
	time_remaining = HALF_DURATION
	sync_phase.rpc(phase, int(HALF_DURATION))
	_reset_round()

func _advance_phase() -> void:
	match phase:
		Phase.FIRST_HALF:
			_go_to_halftime()
		Phase.HALFTIME:
			phase = Phase.SECOND_HALF
			time_remaining = HALF_DURATION
			_reset_round()
		Phase.SECOND_HALF:
			phase = Phase.FULL_TIME
			time_remaining = 0.0
			SFX.play_fulltime_fanfare.rpc()
			# Nur bei einem *echt* durchgespielten Match (Timer läuft ab) gibt's
			# eine Kiste, nicht wenn der Host per /end vorzeitig abbricht.
			_award_crates.rpc()
	sync_phase.rpc(phase, int(ceil(max(time_remaining, 0.0))))

## Läuft lokal auf jedem Peer (auch dem Host selbst): jeder bekommt eine
## Kiste in sein eigenes, rein lokales Inventar. Unterliegt dort dem
## Tageslimit, das jeder Client selbst durchsetzt.
@rpc("call_local", "reliable")
func _award_crates() -> void:
	Inventory.add_crate()

func _go_to_halftime() -> void:
	phase = Phase.HALFTIME
	time_remaining = HALFTIME_BREAK
	_reset_round()
	SFX.play_halftime_jingle.rpc()

func set_match_state(new_state: int) -> void:
	match_state = new_state
	sync_match_state.rpc(new_state, last_scorer_name)

@rpc("call_local", "reliable")
func sync_match_state(new_state: int, scorer_name: String) -> void:
	match_state = new_state
	last_scorer_name = scorer_name
	_update_state_banner()

@rpc("call_local", "reliable")
func sync_phase(new_phase: int, seconds_left: int) -> void:
	var phase_changed := new_phase != phase
	phase = new_phase
	time_remaining = float(seconds_left)
	_update_phase_ui()
	if phase_changed:
		_on_phase_changed()

@rpc("call_local", "reliable")
func sync_ready_votes(count: int, needed: int) -> void:
	ready_status_text = "(%d / %d bereit)" % [count, needed]
	if phase == Phase.WARMUP:
		_update_phase_ui()

func _update_phase_ui() -> void:
	match phase:
		Phase.WARMUP:
			phase_label.text = "Aufwärmphase — \"/vs\" oder \"/votestart\" in den Chat schreiben %s" % ready_status_text
		Phase.FIRST_HALF:
			phase_label.text = "1. Halbzeit"
		Phase.HALFTIME:
			phase_label.text = "Halbzeitpause"
		Phase.SECOND_HALF:
			phase_label.text = "2. Halbzeit"
		Phase.FULL_TIME:
			phase_label.text = "Spiel beendet — Endstand %d : %d — \"/vw\" für Neustart" % [score[0], score[1]]
			timer_label.text = "00:00"
	if phase == Phase.WARMUP:
		timer_label.text = ""

## Wird nur bei einem tatsächlichen Phasenwechsel aufgerufen (nicht bei den
## regelmäßigen Resync-Broadcasts), damit der große Banner-Text nicht alle
## paar Sekunden erneut aufblitzt.
func _on_phase_changed() -> void:
	match phase:
		Phase.HALFTIME:
			_show_phase_banner("HALBZEIT", true)
		Phase.FULL_TIME:
			_show_phase_banner("SPIELENDE\nEndstand %d : %d" % [score[0], score[1]], false)
		_:
			phase_banner.text = ""

func _show_phase_banner(banner_text: String, auto_hide: bool) -> void:
	phase_banner.text = banner_text
	if not auto_hide:
		return
	await get_tree().create_timer(HALFTIME_BANNER_DURATION).timeout
	if is_instance_valid(phase_banner) and phase_banner.text == banner_text:
		phase_banner.text = ""

func _update_state_banner() -> void:
	match match_state:
		MatchState.NONE:
			state_banner.text = ""
		MatchState.KICKOFF:
			state_banner.text = "ANSTOSS"
		MatchState.GOAL_CELEBRATION:
			state_banner.text = "TOR! (%s)" % last_scorer_name if last_scorer_name != "" else "TOR!"
		MatchState.GOAL_REPLAY:
			state_banner.text = "WIEDERHOLUNG"

func _format_time(seconds: float) -> String:
	var s := int(max(seconds, 0.0))
	return "%02d:%02d" % [s / 60, s % 60]

func _on_players_changed() -> void:
	# Neu verbundene Spieler bekommen den aktuellen Stand der Positionswahl.
	sync_slots.rpc(slot_owner)

@rpc("any_peer", "reliable")
func request_slot(slot_id: String) -> void:
	if not Network.is_host():
		return
	try_assign_slot(slot_id, multiplayer.get_remote_sender_id())

func try_assign_slot(slot_id: String, peer_id: int) -> void:
	if not Network.is_host():
		return
	if not slots.has(slot_id):
		return
	if slot_owner.has(slot_id):
		return # schon vergeben
	if peer_id in slot_owner.values():
		return # hat schon eine Position gewählt
	slot_owner[slot_id] = peer_id
	sync_slots.rpc(slot_owner)
	_spawn_at_slot(peer_id, slot_id)

@rpc("call_local", "reliable")
func sync_slots(new_slot_owner: Dictionary) -> void:
	slot_owner = new_slot_owner
	var selector := get_tree().get_first_node_in_group("position_select")
	if selector:
		selector.update_occupancy(slot_owner)

func _spawn_at_slot(peer_id: int, slot_id: String) -> void:
	var slot: Dictionary = slots[slot_id]
	var team: int = slot["team"]
	var pos: Vector3 = slot["position"]
	player_slot[peer_id] = slot_id

	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.owner_peer_id = peer_id
	player.body_color = team_colors[team]
	player.player_number = Network.player_numbers.get(peer_id, 0)
	player.equipped_jersey_id = Network.equipped_jerseys.get(peer_id, 0)
	player.position = pos
	if team == 1:
		player.rotate_y(PI)
	players_container.add_child(player)

## Spawnt einen Test-Dummy (nutzt dieselbe Player-Szene/Physik/Ragdoll wie ein
## echter Spieler, hat aber keine Eingabe und läuft nicht mit) zum Ausprobieren
## von Grätsche/Kick etc. ohne einen zweiten echten Mitspieler.
func spawn_dummy(sender_id: int) -> void:
	if not Network.is_host():
		return
	var spawn_pos := Vector3(0.0, 1.0, 3.0)
	var spawn_yaw := 0.0
	var sender_node := players_container.get_node_or_null(str(sender_id))
	if sender_node:
		var forward: Vector3 = -sender_node.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.05:
			forward = forward.normalized()
			spawn_pos = sender_node.global_position + forward * 2.5
			var facing_back := -forward
			spawn_yaw = atan2(-facing_back.x, -facing_back.z)
	spawn_pos.y = 1.0

	var dummy := PLAYER_SCENE.instantiate()
	dummy.name = str(_next_dummy_id)
	_next_dummy_id -= 1
	dummy.body_color = team_colors[0]
	dummy.position = spawn_pos
	dummy.rotation = Vector3(0.0, spawn_yaw, 0.0)
	dummy.add_to_group("dummy_player")
	players_container.add_child(dummy)

func clear_dummies() -> void:
	if not Network.is_host():
		return
	for node in get_tree().get_nodes_in_group("dummy_player"):
		node.queue_free()

## Admin-Befehl: überspringt die Mehrheitsabstimmung und startet sofort.
func force_start() -> void:
	if not Network.is_host():
		return
	if phase != Phase.WARMUP:
		return
	ready_votes.clear()
	_start_match()

## Admin-Befehl: Zeit, Ball und alle Spieler einfrieren/wieder freigeben.
func set_paused(new_paused: bool) -> void:
	if not Network.is_host():
		return
	if phase != Phase.FIRST_HALF and phase != Phase.SECOND_HALF and phase != Phase.HALFTIME:
		return
	if new_paused == is_paused:
		return
	if new_paused and match_state != MatchState.NONE:
		return # Nicht mitten in Anstoß-Sperre/Torjubel/Replay pausieren.
	is_paused = new_paused
	if is_paused:
		ball.freeze = true
		for child in players_container.get_children():
			child.freeze = true
	elif kickoff_lock <= 0.0 and not goal_sequence_active:
		ball.freeze = false
		for child in players_container.get_children():
			child.freeze = false
	sync_paused.rpc(is_paused)

@rpc("call_local", "reliable")
func sync_paused(paused: bool) -> void:
	is_paused = paused
	phase_banner.text = "PAUSE" if paused else ""

## Admin-Befehl: verbleibende Zeit der aktuellen Phase direkt setzen.
func set_time_remaining(seconds: float) -> void:
	if not Network.is_host():
		return
	if phase != Phase.FIRST_HALF and phase != Phase.SECOND_HALF and phase != Phase.HALFTIME:
		return
	time_remaining = max(seconds, 0.0)
	sync_phase.rpc(phase, int(ceil(time_remaining)))

## Admin-Befehl: Spiel sofort beenden und zurück in die Aufwärmphase.
func force_end() -> void:
	if not Network.is_host():
		return
	if is_paused:
		is_paused = false
		sync_paused.rpc(false)
	_reset_to_warmup()

## Admin-Befehl: direkt in die Halbzeitpause springen (nur in Halbzeit 1 sinnvoll).
func force_halftime() -> void:
	if not Network.is_host():
		return
	if phase != Phase.FIRST_HALF:
		return
	_go_to_halftime()
	sync_phase.rpc(phase, int(ceil(max(time_remaining, 0.0))))

## Admin-Befehl: verbleibende Zeit relativ verändern (auch negativ).
func add_time(seconds: float) -> void:
	if not Network.is_host():
		return
	if phase != Phase.FIRST_HALF and phase != Phase.SECOND_HALF and phase != Phase.HALFTIME:
		return
	time_remaining = max(time_remaining + seconds, 0.0)
	sync_phase.rpc(phase, int(ceil(time_remaining)))

## Admin-Befehl: Spieler anhand des (Teil-)Namens vom Server werfen.
func kick_player(name_query: String) -> void:
	if not Network.is_host():
		return
	var query := name_query.strip_edges().to_lower()
	if query == "":
		return
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return
	for peer_id in Network.players.keys():
		if peer_id == 1:
			continue # Host kann sich nicht selbst kicken.
		var pname: String = Network.players[peer_id]
		if pname.to_lower() == query or pname.to_lower().begins_with(query):
			enet_peer.disconnect_peer(peer_id)
			return

## Admin-Befehl: Spieler anhand des (Teil-)Namens zum jeweils anderen Team
## verschieben, ohne dass er sich neu einwählen muss (gleiche Rolle wenn frei,
## sonst irgendein freier Slot im Zielteam).
func swap_player_team(name_query: String) -> void:
	if not Network.is_host():
		return
	var query := name_query.strip_edges().to_lower()
	if query == "":
		return
	var target_peer := -1
	for peer_id in Network.players.keys():
		var pname: String = Network.players[peer_id]
		if pname.to_lower() == query or pname.to_lower().begins_with(query):
			target_peer = peer_id
			break
	if target_peer == -1:
		return

	var current_slot: String = player_slot.get(target_peer, "")
	if current_slot == "" or not slots.has(current_slot):
		return # hat noch keine Position gewählt

	var current_team: int = slots[current_slot]["team"]
	var target_team: int = 1 - current_team
	var role := current_slot.substr(2)
	var target_slot_id := "%d_%s" % [target_team, role]
	if not slots.has(target_slot_id) or slot_owner.has(target_slot_id):
		target_slot_id = ""
		for slot_id in slots.keys():
			if slots[slot_id]["team"] == target_team and not slot_owner.has(slot_id):
				target_slot_id = slot_id
				break
	if target_slot_id == "":
		return # kein freier Platz im Zielteam

	slot_owner.erase(current_slot)
	slot_owner[target_slot_id] = target_peer
	player_slot[target_peer] = target_slot_id
	sync_slots.rpc(slot_owner)

	var node := players_container.get_node_or_null(str(target_peer))
	if node:
		# Sofort umbenennen, da queue_free() erst am Frame-Ende greift und der
		# neue Spieler-Node noch in diesem Frame denselben Namen braucht.
		node.name = "leaving_%d" % target_peer
		node.queue_free()
	_spawn_at_slot(target_peer, target_slot_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var node := players_container.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
	ready_votes.erase(peer_id)
	reset_votes.erase(peer_id)
	var freed_slot: String = player_slot.get(peer_id, "")
	player_slot.erase(peer_id)
	if freed_slot != "" and slot_owner.has(freed_slot):
		slot_owner.erase(freed_slot)
		sync_slots.rpc(slot_owner)
	# Angezeigten Abstimmungsstand aktualisieren, sonst bleibt "3 / 4 bereit"
	# sichtbar, obwohl einer der Stimmenden gerade die Lobby verlassen hat.
	if phase == Phase.WARMUP:
		var total: int = max(Network.players.size(), 1)
		var needed: int = int(ceil(total / 2.0))
		sync_ready_votes.rpc(ready_votes.size(), needed)

func on_goal_scored(team: int) -> void:
	if goal_sequence_active:
		return
	if phase != Phase.FIRST_HALF and phase != Phase.SECOND_HALF:
		_reset_round()
		return

	goal_sequence_active = true
	var scorer_id: int = ball.last_toucher_peer_id
	last_scorer_name = Network.players.get(scorer_id, "")
	score[team] += 1
	update_score_display.rpc(score[0], score[1])
	if scorer_id != -1:
		player_goals[scorer_id] = player_goals.get(scorer_id, 0) + 1
		sync_player_goals.rpc(player_goals)
	SFX.play_goal.rpc()
	set_match_state(MatchState.GOAL_CELEBRATION)

	# Feier-Phase: Ball und Spieler laufen ganz normal weiter, Uhr pausiert.
	await get_tree().create_timer(GOAL_CELEBRATION_DURATION).timeout
	if not goal_sequence_active:
		return # Inzwischen per /end o.ä. abgebrochen (setzt das Flag zurück).

	# Jetzt einfrieren (an Ort und Stelle, noch nicht auf Spawn zurücksetzen)
	# und allen Peers das Replay der letzten Sekunden zeigen (Ball + alle Spieler).
	ball.freeze = true
	for child in players_container.get_children():
		child.freeze = true
	set_match_state(MatchState.GOAL_REPLAY)
	ball.play_goal_replay.rpc(GOAL_REPLAY_DURATION)
	for child in players_container.get_children():
		child.play_goal_replay.rpc(GOAL_REPLAY_DURATION)

	await get_tree().create_timer(GOAL_REPLAY_DURATION).timeout
	if not goal_sequence_active:
		return # Inzwischen per /end o.ä. abgebrochen.

	_reset_round()
	goal_sequence_active = false

@rpc("call_local", "reliable")
func update_score_display(s0: int, s1: int) -> void:
	score_label.text = "[center][color=#f2453f]%d[/color]  :  [color=#3f8bff]%d[/color][/center]" % [s0, s1]

@rpc("call_local", "reliable")
func sync_player_goals(new_goals: Dictionary) -> void:
	player_goals = new_goals

func _reset_round() -> void:
	ball.freeze = true
	ball.reset_ball()
	ball.last_toucher_peer_id = -1
	kickoff_lock = KICKOFF_DELAY
	set_match_state(MatchState.KICKOFF)
	for child in players_container.get_children():
		child.freeze = true
		if child.in_penalty:
			continue # Zeitstrafe läuft unabhängig vom Anstoß weiter, nicht zurückteleportieren.
		var pid := int(child.name)
		var slot_id: String = player_slot.get(pid, "")
		if slot_id == "" or not slots.has(slot_id):
			continue
		var slot: Dictionary = slots[slot_id]
		child.position = slot["position"]
		child.linear_velocity = Vector3.ZERO
		child.angular_velocity = Vector3.ZERO
		child.stamina = child.max_stamina
		# Körper UND Kamera beim Anstoß Richtung Ball ausrichten, statt stur
		# zum gegnerischen Tor zu zeigen.
		var to_ball: Vector3 = ball.spawn_position - slot["position"]
		to_ball.y = 0.0
		var face_yaw: float = atan2(-to_ball.x, -to_ball.z) if to_ball.length() > 0.05 else (PI if slot["team"] == 1 else 0.0)
		child.rotation = Vector3.ZERO
		child.rotation.y = face_yaw
		child.set_camera_yaw.rpc(face_yaw)
		child.state = Player.State.STANDING
