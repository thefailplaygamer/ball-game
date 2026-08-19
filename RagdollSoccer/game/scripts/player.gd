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
const BodyMesh := preload("res://scripts/body_mesh.gd")
const JERSEY_SHADER := preload("res://shaders/player_jersey.gdshader")
const SKIN_SHADER := preload("res://shaders/player_skin.gdshader")

## Der Fuß hängt im Szenenbaum um -90° gekippt am Schienbein (die Schuhlänge
## liegt im Mesh auf der Y-Achse). Die Animation rechnet immer auf diesen
## Grundwinkel drauf.
const FOOT_BASE_PITCH := -PI * 0.5
const KICK_ANIM_DURATION := 0.45
const TACKLE_ANIM_DURATION := 0.5

## Hautton und Haarfarbe werden aus der Peer-ID abgeleitet: so sieht jeder
## Spieler anders aus, aber auf JEDEM Client identisch — ohne dass dafür etwas
## zusätzlich übers Netz repliziert werden müsste.
const SKIN_TONES := [
	Color(0.94, 0.78, 0.66), Color(0.87, 0.68, 0.54), Color(0.78, 0.58, 0.44),
	Color(0.62, 0.44, 0.32), Color(0.45, 0.31, 0.22), Color(0.33, 0.22, 0.16),
]
const HAIR_COLORS := [
	Color(0.06, 0.05, 0.05), Color(0.16, 0.1, 0.07), Color(0.28, 0.17, 0.09),
	Color(0.45, 0.32, 0.16), Color(0.68, 0.56, 0.32), Color(0.35, 0.35, 0.37),
]

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
var _anim_speed: float = 0.0
var _anim_seed: float = 0.0
var _kick_anim: float = 0.0
var _tackle_anim: float = 0.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var model: Node3D = $Model
@onready var hips: Node3D = $Model/Hips
@onready var chest: Node3D = $Model/Chest
@onready var torso: MeshInstance3D = $Model/Chest/Torso
@onready var neck: MeshInstance3D = $Model/Chest/Neck
@onready var head: MeshInstance3D = $Model/Chest/Neck/Head
@onready var hair: MeshInstance3D = $Model/Chest/Neck/Head/Hair
@onready var headband: MeshInstance3D = $Model/Chest/Neck/Head/Headband
@onready var arm_l: MeshInstance3D = $Model/Chest/ArmL
@onready var arm_r: MeshInstance3D = $Model/Chest/ArmR
@onready var forearm_l: MeshInstance3D = $Model/Chest/ArmL/ForearmL
@onready var forearm_r: MeshInstance3D = $Model/Chest/ArmR/ForearmR
@onready var hand_l: MeshInstance3D = $Model/Chest/ArmL/ForearmL/HandL
@onready var hand_r: MeshInstance3D = $Model/Chest/ArmR/ForearmR/HandR
@onready var armband_r: MeshInstance3D = $Model/Chest/ArmR/ArmbandR
@onready var leg_l: MeshInstance3D = $Model/Hips/LegL
@onready var leg_r: MeshInstance3D = $Model/Hips/LegR
@onready var shin_l: MeshInstance3D = $Model/Hips/LegL/ShinL
@onready var shin_r: MeshInstance3D = $Model/Hips/LegR/ShinR
@onready var foot_l: MeshInstance3D = $Model/Hips/LegL/ShinL/FootL
@onready var foot_r: MeshInstance3D = $Model/Hips/LegR/ShinR/FootR
@onready var jersey_name: Label3D = $Model/Chest/JerseyName
@onready var jersey_number: Label3D = $Model/Chest/JerseyNumber
@onready var name_tag: Label3D = $Model/NameTag

var _active_ghost: Node3D = null

func _ready() -> void:
	# owner_peer_id und body_color werden vom Host nur lokal vor add_child() gesetzt
	# und replizieren sich NICHT automatisch zu den Clients. Der Node-Name dagegen
	# wird vom MultiplayerSpawner zuverlässig mitübertragen, also aus ihm ableiten.
	owner_peer_id = int(str(name))
	_anim_seed = float(abs(owner_peer_id) % 97) * 0.31
	_build_body()
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

## Setzt die prozedural erzeugten Körper-Meshes ein. Die Meshes selbst liegen
## in einem gemeinsamen Cache (siehe body_mesh.gd), pro Spieler entsteht also
## kein zusätzlicher Speicher.
func _build_body() -> void:
	torso.mesh = BodyMesh.get_part("torso")
	neck.mesh = BodyMesh.get_part("neck")
	head.mesh = BodyMesh.get_part("head")
	hair.mesh = BodyMesh.get_part("hair")
	headband.mesh = BodyMesh.get_part("headband")
	armband_r.mesh = BodyMesh.get_part("armband")
	for part in [arm_l, arm_r]:
		part.mesh = BodyMesh.get_part("upper_arm")
	for part in [forearm_l, forearm_r]:
		part.mesh = BodyMesh.get_part("forearm")
	for part in [hand_l, hand_r]:
		part.mesh = BodyMesh.get_part("hand")
	for part in [leg_l, leg_r]:
		part.mesh = BodyMesh.get_part("thigh")
	for part in [shin_l, shin_r]:
		part.mesh = BodyMesh.get_part("shin")
	for part in [foot_l, foot_r]:
		part.mesh = BodyMesh.get_part("foot")

## Alle Teile, die der Trikot-Shader einfärbt.
func _jersey_parts() -> Array:
	return [torso, arm_l, arm_r, forearm_l, forearm_r, leg_l, leg_r, shin_l, shin_r]

func _apply_body_color() -> void:
	if torso == null:
		return # onready-Referenzen noch nicht befüllt, _ready() ruft das gleich selbst noch mal auf
	var def: Dictionary = JerseyData.get_by_id(equipped_jersey_id)
	var mode: int = JerseyData.Pattern.SOLID if def["id"] == 0 else int(def["pattern"])
	var col_a: Color = body_color if def["id"] == 0 else def.get("color_a", body_color)
	var col_b: Color = def.get("color_b", col_a)
	var col_c: Color = def.get("color_c", col_b)

	# Muster mit einem einzelnen Blickfang (Sonne, Galaxienkern) bekommen an
	# Armen und Beinen nur einen schmalen Randstreifen des Musters zu sehen —
	# sonst säße das Motiv fünfmal am Körper. Alle anderen Muster kacheln
	# ohnehin und laufen unverändert über alle Teile.
	var focal: bool = mode in JerseyData.FOCAL_PATTERNS
	var full := [Vector2.ZERO, Vector2.ONE]
	var strip_l := [Vector2(0.02, 0.0), Vector2(0.2, 1.0)]
	var strip_r := [Vector2(0.78, 0.0), Vector2(0.2, 1.0)]
	var strip_leg_l := [Vector2(0.09, 0.0), Vector2(0.18, 1.0)]
	var strip_leg_r := [Vector2(0.73, 0.0), Vector2(0.18, 1.0)]
	var regions := {
		torso: full,
		arm_l: strip_l if focal else full,
		forearm_l: strip_l if focal else full,
		arm_r: strip_r if focal else full,
		forearm_r: strip_r if focal else full,
		leg_l: strip_leg_l if focal else full,
		shin_l: strip_leg_l if focal else full,
		leg_r: strip_leg_r if focal else full,
		shin_r: strip_leg_r if focal else full,
	}
	# Hose und Stutzen bekommen dasselbe Muster in einer anderen Stoffhelligkeit,
	# damit der Spieler ein erkennbares Trikot-Hose-Stutzen-Set trägt statt eines
	# einfarbigen Ganzkörperanzugs. Das Muster selbst bleibt unangetastet.
	var shades := {torso: 1.0, arm_l: 1.0, arm_r: 1.0, forearm_l: 1.0, forearm_r: 1.0,
		leg_l: 0.68, leg_r: 0.68, shin_l: 0.86, shin_r: 0.86}
	for part in regions:
		var jersey_mat := ShaderMaterial.new()
		jersey_mat.shader = JERSEY_SHADER
		jersey_mat.set_shader_parameter("pattern_mode", mode)
		jersey_mat.set_shader_parameter("color_a", col_a)
		jersey_mat.set_shader_parameter("color_b", col_b)
		jersey_mat.set_shader_parameter("color_c", col_c)
		jersey_mat.set_shader_parameter("uv_offset", regions[part][0])
		jersey_mat.set_shader_parameter("uv_scale", regions[part][1])
		jersey_mat.set_shader_parameter("garment_shade", shades[part])
		part.material_override = jersey_mat

	# Kopf, Hals und Hände bekommen einen echten Hautton statt der Team-Farbe.
	# Damit man das Team trotzdem auf einen Blick erkennt — auch wenn ein
	# Trikot-Skin den ganzen Körper umfärbt — wandert die Team-Farbe auf
	# Stirnband, Kapitänsbinde und Schuhe.
	var skin_mat := ShaderMaterial.new()
	skin_mat.shader = SKIN_SHADER
	skin_mat.set_shader_parameter("skin_tone", _skin_tone())
	for part in [head, neck, hand_l, hand_r,
			head.get_node("Nose"), head.get_node("EarL"), head.get_node("EarR")]:
		part.material_override = skin_mat

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = HAIR_COLORS[abs(owner_peer_id * 7 + 3) % HAIR_COLORS.size()]
	hair_mat.roughness = 0.85
	hair.material_override = hair_mat

	var team_mat := StandardMaterial3D.new()
	team_mat.albedo_color = body_color
	team_mat.roughness = 0.5
	headband.material_override = team_mat
	armband_r.material_override = team_mat

	var boot_mat := StandardMaterial3D.new()
	boot_mat.albedo_color = body_color.darkened(0.35)
	boot_mat.roughness = 0.3
	boot_mat.metallic = 0.15
	foot_l.material_override = boot_mat
	foot_r.material_override = boot_mat

func _skin_tone() -> Color:
	return SKIN_TONES[abs(owner_peer_id * 13 + 5) % SKIN_TONES.size()]

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
	play_tackle_anim.rpc()

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
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.announce_penalty(Network.players.get(owner_peer_id, "Spieler"), int(penalty_duration))

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
	play_kick_anim.rpc()

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
	_animate(delta)

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

## Komplette Körperanimation. Läuft auf JEDEM Peer und speist sich nur aus
## Werten, die überall gleich sind — der replizierten Position (daraus das
## Tempo), der replizierten Rotation (daraus "liegt am Boden") und den beiden
## Animations-RPCs für Schuss und Grätsche. Deshalb sehen alle Clients dieselbe
## Bewegung, ohne dass dafür ein einziges zusätzliches Byte übertragen wird.
func _animate(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var moved := global_position - _last_position
	_last_position = global_position
	var raw_speed: float = Vector2(moved.x, moved.z).length() / max(delta, 0.0001)
	# Die replizierte Position kommt in Sprüngen an — ohne Glättung würde die
	# Schrittfrequenz bei fremden Spielern zappeln.
	_anim_speed = lerp(_anim_speed, min(raw_speed, sprint_speed * 1.3), clamp(delta * 9.0, 0.0, 1.0))

	_kick_anim = max(_kick_anim - delta, 0.0)
	_tackle_anim = max(_tackle_anim - delta, 0.0)

	var tilt: float = rad_to_deg(global_transform.basis.y.angle_to(Vector3.UP))
	var fallen: bool = tilt > 45.0

	var pose := {}
	if fallen:
		pose = _pose_fallen(now)
	elif _tackle_anim > 0.0:
		pose = _pose_tackle()
	else:
		pose = _pose_locomotion(delta, now)
		if _kick_anim > 0.0:
			_blend_kick(pose)

	_apply_pose(pose, delta, 18.0 if (_kick_anim > 0.0 or _tackle_anim > 0.0) else 11.0)

## Normales Stehen und Laufen.
func _pose_locomotion(delta: float, now: float) -> Dictionary:
	var amp: float = clamp(_anim_speed / sprint_speed, 0.0, 1.0)
	var running: bool = _anim_speed > 0.35
	if running:
		# Schrittfrequenz wächst mit dem Tempo, aber nicht linear — sonst
		# trippelt der Spieler beim Sprint.
		_walk_phase += (2.6 + _anim_speed * 0.85) * delta

	var swing: float = sin(_walk_phase)
	var swing_off: float = sin(_walk_phase + PI)
	var leg_amp: float = 0.16 + amp * 0.52
	var arm_amp: float = 0.12 + amp * 0.42
	# Beim Laufen beugt sich das Knie in der Schwungphase stark, im Standbein
	# bleibt es fast gestreckt.
	var flex_l: float = 0.1 + 0.95 * maxf(-sin(_walk_phase - 0.5), 0.0)
	var flex_r: float = 0.1 + 0.95 * maxf(-sin(_walk_phase + PI - 0.5), 0.0)

	# Ruheatmung und leichtes Gewichtsverlagern, damit ein stehender Spieler
	# nicht wie eine Schaufensterpuppe wirkt.
	var idle: float = 1.0 - amp
	var breath: float = sin(now * 1.5 + _anim_seed) * 0.02 * idle
	var sway: float = sin(now * 0.7 + _anim_seed) * 0.035 * idle

	var lean: float = amp * 0.2

	return {
		"bob": sin(_walk_phase * 2.0) * 0.022 * amp + breath * 0.4,
		"chest": Vector3(-lean, swing * 0.1 * amp, sway * 0.4),
		"hips": Vector3(0.0, -swing * 0.08 * amp, sway),
		"neck": Vector3(lean * 0.7 + breath, -swing * 0.06 * amp, 0.0),
		"hip_l": swing * leg_amp,
		"hip_r": swing_off * leg_amp,
		"knee_l": -flex_l * amp,
		"knee_r": -flex_r * amp,
		"ankle_l": -(swing * leg_amp - flex_l * amp) * 0.4,
		"ankle_r": -(swing_off * leg_amp - flex_r * amp) * 0.4,
		"shoulder_l": Vector3(-swing * arm_amp, 0.0, -0.2 - idle * 0.04),
		"shoulder_r": Vector3(-swing_off * arm_amp, 0.0, 0.2 + idle * 0.04),
		"elbow_l": 0.35 + amp * 0.45 + maxf(-swing, 0.0) * amp * 0.5,
		"elbow_r": 0.35 + amp * 0.45 + maxf(-swing_off, 0.0) * amp * 0.5,
	}

## Am Boden liegend: unkontrolliertes Rudern mit Armen und Beinen.
func _pose_fallen(now: float) -> Dictionary:
	var t: float = now * 1.0 + _anim_seed * 7.0
	return {
		"bob": 0.0,
		"chest": Vector3(sin(t * 6.0) * 0.2, sin(t * 4.3) * 0.25, cos(t * 5.1) * 0.2),
		"hips": Vector3(0.0, cos(t * 3.7) * 0.2, sin(t * 4.9) * 0.15),
		"neck": Vector3(sin(t * 7.3) * 0.3, cos(t * 6.1) * 0.35, 0.0),
		"hip_l": sin(t * 9.0) * 0.85 + 0.2,
		"hip_r": sin(t * 9.0 + 2.1) * 0.85 + 0.2,
		"knee_l": -0.5 - maxf(sin(t * 11.0), 0.0) * 0.8,
		"knee_r": -0.5 - maxf(sin(t * 11.0 + 1.4), 0.0) * 0.8,
		"ankle_l": sin(t * 8.0) * 0.3,
		"ankle_r": sin(t * 8.0 + 1.7) * 0.3,
		"shoulder_l": Vector3(sin(t * 8.5) * 1.2, 0.0, -0.5 - absf(sin(t * 6.0)) * 0.5),
		"shoulder_r": Vector3(sin(t * 8.5 + 2.6) * 1.2, 0.0, 0.5 + absf(sin(t * 6.4)) * 0.5),
		"elbow_l": 0.5 + absf(sin(t * 10.0)) * 0.9,
		"elbow_r": 0.5 + absf(sin(t * 10.0 + 1.1)) * 0.9,
	}

## Grätsche: Ausfallschritt mit vorgestrecktem Bein und tiefem Schwerpunkt.
func _pose_tackle() -> Dictionary:
	var phase: float = 1.0 - _tackle_anim / TACKLE_ANIM_DURATION
	var punch: float = sin(clamp(phase, 0.0, 1.0) * PI)
	return {
		"bob": -0.14 * punch,
		"chest": Vector3(0.35 * punch, 0.0, 0.0),
		"hips": Vector3(0.0, 0.0, 0.0),
		"neck": Vector3(-0.3 * punch, 0.0, 0.0),
		"hip_l": 1.25 * punch,
		"hip_r": -0.55 * punch,
		"knee_l": -0.1 * punch,
		"knee_r": -1.1 * punch,
		"ankle_l": -0.3 * punch,
		"ankle_r": 0.2 * punch,
		"shoulder_l": Vector3(-1.1 * punch, 0.0, -0.45),
		"shoulder_r": Vector3(-0.9 * punch, 0.0, 0.45),
		"elbow_l": 0.4,
		"elbow_r": 0.4,
	}

## Schuss: Ausholen, Durchziehen, Nachschwingen — wird über die Laufanimation
## gelegt, damit der Oberkörper weiter mitläuft.
func _blend_kick(pose: Dictionary) -> void:
	var phase: float = 1.0 - _kick_anim / KICK_ANIM_DURATION
	var swing_angle: float
	if phase < 0.3:
		# Ausholen nach hinten.
		swing_angle = lerp(0.0, -0.85, phase / 0.3)
	elif phase < 0.55:
		# Durchziehen nach vorne.
		swing_angle = lerp(-0.85, 1.15, (phase - 0.3) / 0.25)
	else:
		swing_angle = lerp(1.15, 0.0, (phase - 0.55) / 0.45)
	var weight: float = sin(clamp(phase, 0.0, 1.0) * PI)

	pose["hip_r"] = swing_angle
	pose["knee_r"] = -maxf(-swing_angle, 0.0) * 1.1 - 0.1
	pose["ankle_r"] = -0.25 * weight
	# Standbein leicht gebeugt, Oberkörper lehnt zurück, Arme balancieren aus.
	pose["hip_l"] = lerp(float(pose["hip_l"]), -0.15, weight)
	pose["knee_l"] = lerp(float(pose["knee_l"]), -0.3, weight)
	pose["chest"] = Vector3(0.22 * weight, -0.18 * weight, 0.0)
	pose["shoulder_l"] = Vector3(-0.9 * weight, 0.0, -0.35 - 0.2 * weight)
	pose["shoulder_r"] = Vector3(0.5 * weight, 0.0, 0.3 + 0.25 * weight)

func _apply_pose(pose: Dictionary, delta: float, rate: float) -> void:
	var f: float = clamp(delta * rate, 0.0, 1.0)
	model.position.y = lerp(model.position.y, float(pose["bob"]), f)
	chest.rotation = chest.rotation.lerp(pose["chest"], f)
	hips.rotation = hips.rotation.lerp(pose["hips"], f)
	neck.rotation = neck.rotation.lerp(pose["neck"], f)
	leg_l.rotation.x = lerp(leg_l.rotation.x, float(pose["hip_l"]), f)
	leg_r.rotation.x = lerp(leg_r.rotation.x, float(pose["hip_r"]), f)
	shin_l.rotation.x = lerp(shin_l.rotation.x, float(pose["knee_l"]), f)
	shin_r.rotation.x = lerp(shin_r.rotation.x, float(pose["knee_r"]), f)
	foot_l.rotation.x = lerp(foot_l.rotation.x, FOOT_BASE_PITCH + float(pose["ankle_l"]), f)
	foot_r.rotation.x = lerp(foot_r.rotation.x, FOOT_BASE_PITCH + float(pose["ankle_r"]), f)
	arm_l.rotation = arm_l.rotation.lerp(pose["shoulder_l"], f)
	arm_r.rotation = arm_r.rotation.lerp(pose["shoulder_r"], f)
	forearm_l.rotation.x = lerp(forearm_l.rotation.x, float(pose["elbow_l"]), f)
	forearm_r.rotation.x = lerp(forearm_r.rotation.x, float(pose["elbow_r"]), f)

## Vom Host ausgelöst, damit Schuss und Grätsche auf allen Clients zu sehen sind.
@rpc("call_local", "reliable")
func play_kick_anim() -> void:
	_kick_anim = KICK_ANIM_DURATION

@rpc("call_local", "reliable")
func play_tackle_anim() -> void:
	_tackle_anim = TACKLE_ANIM_DURATION

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

	# Der Geist ist eine Kopie des kompletten Modell-Astes: Rig, Trikot-Material,
	# Name und Nummer kommen dadurch automatisch mit, und die Gliedmaßen behalten
	# ihre Pose. (Früher wurden die Körperteile einzeln dupliziert — das ginge
	# mit dem neuen, verschachtelten Skelett nicht mehr, weil die Teile ihre
	# Position erst über die Elternknochen bekommen.)
	var ghost: Node3D = model.duplicate()
	get_parent().add_child(ghost)
	_active_ghost = ghost
	# Beim eigenen Spieler ist der Kopf ausgeblendet (Ego-Kamera) — im Replay
	# sieht man sich aber von außen, also gehört er dort wieder dazu.
	ghost.get_node("Chest/Neck/Head").visible = true
	ghost.get_node("NameTag").visible = true
	model.visible = false

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
	model.visible = true

func _sample_history(clip: Array, t: float) -> Dictionary:
	for i in range(clip.size() - 1):
		if clip[i]["t"] <= t and t <= clip[i + 1]["t"]:
			var span: float = max(clip[i + 1]["t"] - clip[i]["t"], 0.0001)
			var f: float = (t - clip[i]["t"]) / span
			var pos: Vector3 = clip[i]["pos"].lerp(clip[i + 1]["pos"], f)
			var quat: Quaternion = clip[i]["quat"].slerp(clip[i + 1]["quat"], f)
			return {"pos": pos, "quat": quat}
	return clip[clip.size() - 1]
