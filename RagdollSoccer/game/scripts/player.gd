extends RigidBody3D
class_name Player

enum State { STANDING, RAGDOLL, GETTING_UP }

@export var move_speed := 6.5
@export var sprint_speed := 10.5
@export var max_push_force := 45.0
@export var balance_torque_strength := 18.0
@export var balance_damping := 4.0
@export var lean_strength := 6.0
@export var ragdoll_tilt_threshold_deg := 55.0
@export var recover_tilt_threshold_deg := 12.0
@export var ragdoll_min_time := 0.8
@export var getup_torque_strength := 10.0
@export var kick_force := 8.0
@export var kick_range := 1.2
@export var kick_stamina_cost := 20.0
@export var kick_look_weight := 0.75
@export var dribble_range := 1.0
@export var dribble_strength := 5.0
@export var face_torque_strength := 10.0
@export var ragdoll_shake_strength := 6.0
@export var ball_focus_speed := 4.0
@export var body_color: Color = Color.WHITE:
	set(value):
		body_color = value
		_apply_body_color()
@export var player_number: int = 0:
	set(value):
		player_number = value
		_update_jersey_text()
@export var equipped_jersey_id: int = 0:
	set(value):
		equipped_jersey_id = value
		_apply_body_color()
@export var mouse_sensitivity := 0.003
@export var eye_height := 0.68
@export var max_stamina := 100.0
@export var stamina_drain_rate := 22.0
@export var stamina_regen_rate := 14.0
@export var tackle_stamina_cost := 50.0
@export var tackle_impulse := 6.5
@export var tackle_duration := 0.35
@export var tackles_for_penalty := 3
@export var penalty_duration := 10.0

const HISTORY_SECONDS := 6.0
const MAX_RAGDOLL_DURATION := 1.0
const PENALTY_BOX_POSITION := Vector3(0.0, 1.2, 14.0)
const JerseyData := preload("res://scripts/jersey_data.gd")
const JERSEY_SHADER := preload("res://shaders/player_jersey.gdshader")
const SKIN_SHADER := preload("res://shaders/player_skin.gdshader")

var owner_peer_id: int = 1

var state: int = State.STANDING
var ragdoll_timer: float = 0.0
var ragdoll_hard_cap: float = MAX_RAGDOLL_DURATION
var _shake_seed: float = 0.0
var facing_dir: Vector3 = Vector3.FORWARD
var camera_yaw: float = 0.0
var camera_pitch: float = -0.2

var input_dir: Vector3 = Vector3.ZERO
var input_sprint: bool = false
var kick_requested: bool = false
var tackle_requested: bool = false

var stamina: float = 100.0:
	set(value):
		stamina = clamp(value, 0.0, max_stamina)
		_update_stamina_bar()

var tackling: bool = false
var tackle_timer: float = 0.0
var successful_tackle_count: int = 0
var in_penalty: bool = false
var _pre_penalty_position: Vector3 = Vector3.ZERO
var penalty_timer: float = 0.0:
	set(value):
		penalty_timer = value
		_update_penalty_label()

var _history: Array = [] # Array of {t: float, pos: Vector3, quat: Quaternion}
var _last_position: Vector3 = Vector3.ZERO
var _walk_phase: float = 0.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var head: MeshInstance3D = $Head
@onready var torso: MeshInstance3D = $Torso
@onready var arm_l: MeshInstance3D = $ArmL
@onready var arm_r: MeshInstance3D = $ArmR
@onready var leg_l: MeshInstance3D = $LegL
@onready var leg_r: MeshInstance3D = $LegR
@onready var body_parts: Array[MeshInstance3D] = [head, torso, arm_l, arm_r, leg_l, leg_r]
@onready var jersey_name: Label3D = $JerseyName
@onready var jersey_number: Label3D = $JerseyNumber
@onready var name_tag: Label3D = $NameTag

var _active_ghost: Node3D = null

func _ready() -> void:
	# owner_peer_id und body_color werden vom Host nur lokal vor add_child() gesetzt
	# und replizieren sich NICHT automatisch zu den Clients. Der Node-Name dagegen
	# wird vom MultiplayerSpawner zuverlässig mitübertragen, also aus ihm ableiten.
	owner_peer_id = int(str(name))
	_apply_body_color()
	_update_jersey_text()
	Network.players_changed.connect(_update_jersey_text)
	_last_position = global_position

	# Nur der Host simuliert die volle Physik, Clients zeigen nur die synchronisierten Werte.
	if not Network.is_host():
		freeze = true
	else:
		body_entered.connect(_on_body_entered)

	var is_local := owner_peer_id == Network.get_my_id()
	camera.current = is_local
	if is_local:
		# Kamera-Rig hängt nicht an der Rotation des taumelnden Ragdoll-Körpers,
		# sonst würde die Sicht beim Umfallen mitkippen.
		spring_arm.top_level = true
		spring_arm.global_position = global_position + Vector3.UP * eye_height
		_face_ball()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Körper bleibt sichtbar (auch für andere Kameras wie das Replay!) —
		# nur der Kopf wird ausgeblendet, sonst würde die eigene Kamera hineinclippen.
		head.visible = false
		name_tag.visible = false
		_update_stamina_bar()

## Node wird entfernt (z.B. bei Disconnect) — falls gerade ein Replay-Geist
## dieses Spielers existiert, muss der mit verschwinden, sonst bleibt er als
## eingefrorene Leiche an seiner letzten Position liegen.
func _exit_tree() -> void:
	if _active_ghost and is_instance_valid(_active_ghost):
		_active_ghost.queue_free()
		_active_ghost = null

func _physics_process(delta: float) -> void:
	if not Network.is_host():
		return
	if in_penalty:
		penalty_timer = max(penalty_timer - delta, 0.0)
		if penalty_timer <= 0.0:
			_end_penalty()
		return
	if freeze:
		# Keine Kräfte auf einen eingefrorenen Körper anwenden, sonst stauen sie
		# sich auf und entladen sich beim Auftauen als Teleport/Explosion.
		return
	match state:
		State.STANDING:
			_process_standing(delta)
		State.RAGDOLL:
			_process_ragdoll(delta)
		State.GETTING_UP:
			_process_getting_up(delta)
	if kick_requested:
		_try_kick()
		kick_requested = false
	if tackle_requested:
		_start_tackle()
		tackle_requested = false

func _apply_body_color() -> void:
	if body_parts.is_empty():
		return # onready-Array noch nicht befüllt, _ready() ruft das gleich selbst noch mal auf
	var jersey_mat := ShaderMaterial.new()
	jersey_mat.shader = JERSEY_SHADER
	var def: Dictionary = JerseyData.get_by_id(equipped_jersey_id)
	if def["id"] == 0:
		jersey_mat.set_shader_parameter("pattern_mode", JerseyData.Pattern.SOLID)
		jersey_mat.set_shader_parameter("color_a", body_color)
	else:
		jersey_mat.set_shader_parameter("pattern_mode", def["pattern"])
		jersey_mat.set_shader_parameter("color_a", def.get("color_a", body_color))
		jersey_mat.set_shader_parameter("color_b", def.get("color_b", body_color))
		jersey_mat.set_shader_parameter("color_c", def.get("color_c", body_color))
	for part in [torso, arm_l, arm_r, leg_l, leg_r]:
		part.material_override = jersey_mat
	# Kopf behält die Team-Farbe (wichtig für spätere Trikot-Skins, sonst
	# erkennt man das Team nicht mehr am Kopf) - bekommt aber trotzdem eine
	# feine Textur statt einer komplett flachen Fläche.
	var skin_mat := ShaderMaterial.new()
	skin_mat.shader = SKIN_SHADER
	skin_mat.set_shader_parameter("skin_tone", body_color)
	head.material_override = skin_mat

## Trikotname (Rücken) kommt aus der Netzwerk-Spielerliste, Nummer aus der
## synchronisierten player_number-Eigenschaft.
func _update_jersey_text() -> void:
	if jersey_number == null:
		return # onready noch nicht befüllt
	jersey_number.text = str(player_number) if player_number > 0 else ""
	# Negative IDs sind Test-Dummys (siehe game_manager.spawn_dummy), die stehen
	# nicht in Network.players, damit sie z.B. Mehrheits-Abstimmungen nicht verfälschen.
	var display_name: String
	if owner_peer_id < 0:
		display_name = "DUMMY"
	else:
		display_name = Network.players.get(owner_peer_id, "").to_upper()
	jersey_name.text = display_name
	name_tag.text = display_name

func _get_tilt_deg() -> float:
	return rad_to_deg(global_transform.basis.y.angle_to(Vector3.UP))

func _process_standing(delta: float) -> void:
	var tilt := _get_tilt_deg()
	if tilt > ragdoll_tilt_threshold_deg:
		state = State.RAGDOLL
		ragdoll_timer = 0.0
		ragdoll_hard_cap = MAX_RAGDOLL_DURATION
		_shake_seed = randf_range(0.0, 100.0)
		tackling = false
		return

	# Balance: den Spieler aufrecht halten (PD-Regler auf die Up-Achse)
	var up_error := global_transform.basis.y.cross(Vector3.UP)
	var torque := up_error * balance_torque_strength - angular_velocity * balance_damping

	# Leichte Vorlehnung in Bewegungsrichtung, wirkt weniger robotisch beim Laufen.
	var horizontal_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var horizontal_speed := horizontal_vel.length()
	if horizontal_speed > 0.3:
		var lean_axis := Vector3.UP.cross(horizontal_vel / horizontal_speed)
		torque += lean_axis * clamp(horizontal_speed / sprint_speed, 0.0, 1.0) * lean_strength
	torque.y = 0.0
	apply_torque(torque)

	# Körper zur Blickrichtung drehen, sonst zeigen die Schultern beim Laufen
	# immer stur in die (beim Anstoß gesetzte) Ausgangsrichtung statt dorthin,
	# wo man tatsächlich hinschaut.
	var current_forward := -global_transform.basis.z
	current_forward.y = 0.0
	if current_forward.length() > 0.01:
		current_forward = current_forward.normalized()
		var desired_forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
		var face_torque: Vector3 = current_forward.cross(desired_forward) * face_torque_strength
		apply_torque(Vector3(0.0, face_torque.y, 0.0))

	if tackling:
		tackle_timer -= delta
		if tackle_timer <= 0.0:
			tackling = false
		_update_stamina(delta, false)
		return

	# Stamina: Sprinten (während man sich bewegt) kostet, sonst regeneriert sie sich.
	var wants_sprint := input_sprint and input_dir.length() > 0.1
	_update_stamina(delta, wants_sprint)

	# Bewegung als Kraft, dadurch kann man von anderen Spielern umgestoßen werden
	if input_dir.length() > 0.1:
		facing_dir = input_dir.normalized()
	var can_sprint := stamina > 0.0
	var target_speed := sprint_speed if (input_sprint and can_sprint) else move_speed
	var target_vel := input_dir * target_speed
	var vel_error := target_vel - horizontal_vel
	var force := vel_error * mass * 6.0
	if force.length() > max_push_force:
		force = force.normalized() * max_push_force
	apply_central_force(force)
	_apply_dribble_assist()

func _update_stamina(delta: float, draining: bool) -> void:
	if draining:
		stamina -= stamina_drain_rate * delta
	else:
		stamina += stamina_regen_rate * delta

## Sanfte Steuerkraft auf den Ball, wenn er nah an den Füßen ist. Reine Kapsel-
## vs-Kugel-Kollision "fängt" den Ball beim Laufen schlecht (er rutscht drunter
## durch oder wird weggeschubst), das hier sorgt für echtes Ballführungsgefühl.
func _apply_dribble_assist() -> void:
	var ball := get_tree().get_first_node_in_group("ball")
	if ball == null or input_dir.length() < 0.1:
		return
	var to_ball: Vector3 = ball.global_position - global_position
	to_ball.y = 0.0
	var dist := to_ball.length()
	if dist > dribble_range or dist < 0.01:
		return
	var closeness: float = 1.0 - (dist / dribble_range)
	ball.apply_central_force(input_dir.normalized() * closeness * dribble_strength)

func _process_ragdoll(_delta: float) -> void:
	ragdoll_timer += _delta
	var tilt := _get_tilt_deg()
	if ragdoll_timer > ragdoll_min_time and tilt < ragdoll_tilt_threshold_deg and linear_velocity.length() < 1.5:
		state = State.GETTING_UP
		return
	# Liegt der Spieler zu flach (z.B. nach einer Grätsche), erfüllt er die
	# Tilt-Bedingung oben nie von selbst -> spätestens nach ragdoll_hard_cap
	# (bei Grätschen zufällig 1/2/3s) hart aufrichten.
	if ragdoll_timer > ragdoll_hard_cap:
		_force_stand_up()

## Richtet den Spieler unabhängig von seiner aktuellen Lage sofort wieder auf,
## Blickrichtung bleibt dabei möglichst erhalten.
func _force_stand_up() -> void:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_transform.basis = Basis.looking_at(forward, Vector3.UP)
	angular_velocity = Vector3.ZERO
	linear_velocity = Vector3(linear_velocity.x, max(linear_velocity.y, 0.0), linear_velocity.z)
	state = State.STANDING

func _process_getting_up(_delta: float) -> void:
	var tilt := _get_tilt_deg()
	if tilt < recover_tilt_threshold_deg:
		state = State.STANDING
		return
	if tilt > ragdoll_tilt_threshold_deg + 15.0:
		state = State.RAGDOLL
		ragdoll_timer = 0.0
		return
	var up_error := global_transform.basis.y.cross(Vector3.UP)
	var torque := up_error * getup_torque_strength - angular_velocity * (balance_damping * 0.5)
	torque.y = 0.0
	apply_torque(torque)

## Zwingt den Spieler unabhängig von seiner Neigung für `duration` Sekunden in den
## Ragdoll-Zustand, z.B. nach einer Grätsche.
func force_ragdoll(duration: float) -> void:
	state = State.RAGDOLL
	ragdoll_timer = 0.0
	ragdoll_hard_cap = duration
	_shake_seed = randf_range(0.0, 100.0)

func _on_body_entered(body: Node) -> void:
	if not tackling:
		return
	if body is Player and body != self:
		var push_dir: Vector3 = body.global_position - global_position
		push_dir.y = 0.3
		if push_dir.length() > 0.01:
			body.apply_central_impulse(push_dir.normalized() * 4.0)
		body.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 3.0)
		# Aufsteh-Zeit pro Grätsche neu auswürfeln: 50% 1s, 35% 2s, 15% 3s.
		var r := randf()
		var ragdoll_duration := 1.0
		if r >= 0.85:
			ragdoll_duration = 3.0
		elif r >= 0.5:
			ragdoll_duration = 2.0
		body.force_ragdoll(ragdoll_duration)
		tackling = false
		successful_tackle_count += 1
		if successful_tackle_count >= tackles_for_penalty:
			successful_tackle_count = 0
			_start_penalty()

func _start_tackle() -> void:
	if state != State.STANDING or tackling:
		return
	if stamina < tackle_stamina_cost:
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.tackle_lock_remaining > 0.0:
		return
	stamina -= tackle_stamina_cost
	tackling = true
	tackle_timer = tackle_duration
	apply_central_impulse(facing_dir * tackle_impulse)

## Wird nach `tackles_for_penalty` erfolgreichen Grätschen ausgelöst: Spieler
## wird eingefroren, aus dem Spielfeld teleportiert und nach `penalty_duration`
## Sekunden an seiner vorherigen Position wieder freigegeben.
func _start_penalty() -> void:
	if in_penalty:
		return
	in_penalty = true
	tackling = false
	_pre_penalty_position = global_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = PENALTY_BOX_POSITION
	state = State.STANDING
	freeze = true
	penalty_timer = penalty_duration

func _end_penalty() -> void:
	in_penalty = false
	global_position = _pre_penalty_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	state = State.STANDING
	freeze = false
	penalty_timer = 0.0

## Bricht eine laufende Zeitstrafe sofort ab, ohne zur alten Position
## zurückzuteleportieren (z.B. bei einem kompletten Match-Reset per /end oder
## /vw, wo Spieler ohnehin frei herumlaufen dürfen bis zum nächsten Anstoß).
func cancel_penalty() -> void:
	if not in_penalty:
		return
	in_penalty = false
	penalty_timer = 0.0

## Der Zeitstrafen-Countdown wird an alle Peers repliziert, aber nur der
## bestrafte Spieler selbst zeigt ihn in seinem HUD an.
func _update_penalty_label() -> void:
	if owner_peer_id != Network.get_my_id():
		return
	var label := get_tree().get_first_node_in_group("penalty_label")
	if label == null:
		return
	if penalty_timer > 0.0:
		label.text = "Zeitstrafe: %ds" % int(ceil(penalty_timer))
		label.visible = true
	else:
		label.visible = false

func _try_kick() -> void:
	if state != State.STANDING:
		return
	if stamina < kick_stamina_cost:
		return
	var ball := get_tree().get_first_node_in_group("ball")
	if ball == null:
		return
	var to_ball: Vector3 = ball.global_position - global_position
	to_ball.y = 0.0
	if to_ball.length() > kick_range:
		return
	stamina -= kick_stamina_cost
	# Schuss geht überwiegend dorthin, wo man hinschaut, nicht mehr primär nach
	# dem Winkel, aus dem der Ball gerade kommt — der alte winkelbasierte Anteil
	# bleibt als kleiner Zufalls-/Skill-Faktor erhalten.
	var look_dir := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var dir := (look_dir * kick_look_weight + to_ball.normalized() * (1.0 - kick_look_weight)).normalized()
	# Nach oben schauen = höherer Bogen, nach unten schauen = flacherer Schuss.
	var vertical_fraction: float = clamp(0.15 + camera_pitch * 0.45, 0.0, 0.85)
	ball.apply_central_impulse(dir * kick_force + Vector3.UP * kick_force * vertical_fraction)
	if ball.has_method("set_last_toucher"):
		ball.set_last_toucher(owner_peer_id)
	ball.play_kick_sfx.rpc()

## Dreht die Kamera bei gehaltener linker Maustaste sanft Richtung Ball, damit
## man ihn nach einem Dreher/Sturz wiederfindet.
func _apply_ball_focus(delta: float) -> void:
	var ball := get_tree().get_first_node_in_group("ball")
	if ball == null:
		return
	var to_ball: Vector3 = ball.global_position - global_position
	to_ball.y = 0.0
	if to_ball.length() < 0.05:
		return
	var dir := to_ball.normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	camera_yaw = lerp_angle(camera_yaw, target_yaw, clamp(ball_focus_speed * delta, 0.0, 1.0))

## Dreht nur die (lokale) Kamera Richtung Ball, z.B. beim ersten Spawn.
func _face_ball() -> void:
	var ball := get_tree().get_first_node_in_group("ball")
	if ball == null:
		return
	var to_ball: Vector3 = ball.global_position - global_position
	to_ball.y = 0.0
	if to_ball.length() < 0.05:
		return
	var dir := to_ball.normalized()
	camera_yaw = atan2(-dir.x, -dir.z)

## Vom Host beim Anstoß-Reset aufgerufen, damit auch die Kamera (nicht nur der
## Körper) aller Spieler synchron Richtung Ball ausgerichtet wird.
@rpc("call_local", "reliable")
func set_camera_yaw(yaw: float) -> void:
	if owner_peer_id == Network.get_my_id():
		camera_yaw = yaw

@rpc("any_peer", "unreliable_ordered")
func submit_move(dir: Vector3, sprint: bool, pitch: float, yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	input_dir = dir
	input_sprint = sprint
	camera_pitch = pitch
	camera_yaw = yaw

@rpc("any_peer", "reliable")
func request_kick() -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	kick_requested = true

@rpc("any_peer", "reliable")
func request_tackle() -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	tackle_requested = true

func _unhandled_input(event: InputEvent) -> void:
	if owner_peer_id != Network.get_my_id():
		return
	if Network.input_locked:
		return
	if event.is_action_pressed("kick"):
		if Network.is_host():
			kick_requested = true
		else:
			rpc_id(1, "request_kick")
	elif event.is_action_pressed("tackle"):
		if Network.is_host():
			tackle_requested = true
		else:
			rpc_id(1, "request_tackle")
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch = clamp(camera_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.3)

func _process(delta: float) -> void:
	_record_history()
	_animate_walk_cycle(delta)

	if owner_peer_id != Network.get_my_id():
		return

	if state == State.RAGDOLL:
		# Wildes Wackeln, solange man liegt -> Orientierung geht verloren.
		var t := Time.get_ticks_msec() / 1000.0 + _shake_seed
		camera_yaw += (sin(t * 11.0) + sin(t * 23.0) * 0.6) * ragdoll_shake_strength * delta
		camera_pitch = clamp(camera_pitch + (cos(t * 17.0) + sin(t * 7.0) * 0.5) * ragdoll_shake_strength * 0.5 * delta, -1.4, 1.3)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Network.input_locked:
		_apply_ball_focus(delta)

	# Kamera folgt der Position des Körpers, aber nicht seiner (evtl. taumelnden) Rotation.
	spring_arm.global_position = global_position + Vector3.UP * eye_height
	spring_arm.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)

	if Network.input_locked:
		if Network.is_host():
			input_dir = Vector3.ZERO
			input_sprint = false
		else:
			rpc_id(1, "submit_move", Vector3.ZERO, false, camera_pitch, camera_yaw)
		return

	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var dir := right * raw.x + forward * -raw.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	var sprint := Input.is_action_pressed("sprint")
	if Network.is_host():
		input_dir = dir
		input_sprint = sprint
	else:
		rpc_id(1, "submit_move", dir, sprint, camera_pitch, camera_yaw)

func _record_history() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_history.append({"t": now, "pos": global_position, "quat": quaternion})
	while _history.size() > 1 and now - _history[0]["t"] > HISTORY_SECONDS:
		_history.pop_front()

## Läuft auf JEDEM Peer aus der replizierten Position, damit auch fremde Spieler
## eine Lauf-Animation zeigen, obwohl ihre Geschwindigkeit nicht extra synchronisiert wird.
func _animate_walk_cycle(delta: float) -> void:
	var moved := global_position - _last_position
	_last_position = global_position
	var speed: float = Vector2(moved.x, moved.z).length() / max(delta, 0.0001)
	if speed > 0.3 and state == State.STANDING:
		_walk_phase += speed * delta * 4.0
		var swing: float = sin(_walk_phase) * clamp(speed / sprint_speed, 0.0, 1.0) * 0.35
		leg_l.rotation.x = swing
		leg_r.rotation.x = -swing
		arm_l.rotation.x = -swing
		arm_r.rotation.x = swing
	else:
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, delta * 5.0)
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, delta * 5.0)
		arm_l.rotation.x = lerp(arm_l.rotation.x, 0.0, delta * 5.0)
		arm_r.rotation.x = lerp(arm_r.rotation.x, 0.0, delta * 5.0)

func _update_stamina_bar() -> void:
	if owner_peer_id != Network.get_my_id():
		return
	var bar := get_tree().get_first_node_in_group("stamina_bar")
	if bar:
		bar.value = (stamina / max_stamina) * 100.0

## Spielt den aufgezeichneten Bewegungsverlauf der letzten `duration` Sekunden
## als sichtbaren Geist-Körper ab, ohne die echte (physikalische) Position zu berühren.
@rpc("call_local", "reliable")
func play_goal_replay(duration: float) -> void:
	if _history.size() < 2:
		return
	var latest_t: float = _history[_history.size() - 1]["t"]
	var clip_start_t: float = latest_t - duration
	var clip: Array = []
	for entry in _history:
		if entry["t"] >= clip_start_t:
			clip.append(entry)
	if clip.size() < 2:
		return

	var was_head_hidden := not head.visible
	var was_tag_hidden := not name_tag.visible
	for part in body_parts:
		part.visible = false
	jersey_name.visible = false
	jersey_number.visible = false
	name_tag.visible = false
	var ghost := Node3D.new()
	get_parent().add_child(ghost)
	_active_ghost = ghost
	for part in body_parts:
		var dup: MeshInstance3D = part.duplicate()
		dup.visible = true
		ghost.add_child(dup)
	# Trikot-Name/-Nummer und der schwebende Namens-Tag müssen mit ins Replay,
	# sonst bleiben sie an der letzten echten Position stehen statt dem
	# Geist-Körper zu folgen.
	for label in [jersey_name, jersey_number, name_tag]:
		var label_dup: Label3D = label.duplicate()
		label_dup.visible = true
		ghost.add_child(label_dup)

	var clip_t0: float = clip[0]["t"]
	var clip_t1: float = clip[clip.size() - 1]["t"]
	var clip_span: float = max(clip_t1 - clip_t0, 0.01)
	var playback_speed: float = clip_span / duration
	var start_real := Time.get_ticks_msec() / 1000.0

	while true:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - start_real
		if elapsed >= duration:
			break
		var target_t: float = clip_t0 + elapsed * playback_speed
		var sample := _sample_history(clip, target_t)
		ghost.global_position = sample["pos"]
		ghost.quaternion = sample["quat"]
		await get_tree().process_frame

	ghost.queue_free()
	_active_ghost = null
	for part in body_parts:
		part.visible = true
	jersey_name.visible = true
	jersey_number.visible = true
	if was_head_hidden:
		head.visible = false
	if not was_tag_hidden:
		name_tag.visible = true

func _sample_history(clip: Array, t: float) -> Dictionary:
	for i in range(clip.size() - 1):
		if clip[i]["t"] <= t and t <= clip[i + 1]["t"]:
			var span: float = max(clip[i + 1]["t"] - clip[i]["t"], 0.0001)
			var f: float = (t - clip[i]["t"]) / span
			var pos: Vector3 = clip[i]["pos"].lerp(clip[i + 1]["pos"], f)
			var quat: Quaternion = clip[i]["quat"].slerp(clip[i + 1]["quat"], f)
			return {"pos": pos, "quat": quat}
	return clip[clip.size() - 1]
