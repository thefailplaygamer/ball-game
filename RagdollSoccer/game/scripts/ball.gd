extends RigidBody3D

const HISTORY_SECONDS := 6.0
const TOUCH_SFX_SPEED_THRESHOLD := 2.0
const TOUCH_SFX_COOLDOWN := 0.15
# Seitliche, mittig-hohe Replay-Kamera-Position relativ zum Ball (statt der alten
# steilen Diagonale von oben, die nur das letzte Drittel vorm Tor zeigte).
const REPLAY_SIDE_OFFSET := Vector3(0.0, 4.0, 11.0)

var spawn_position: Vector3
var last_toucher_peer_id: int = -1
var _history: Array = [] # Array of {t: float, pos: Vector3, quat: Quaternion}
var _last_touch_sfx_time: float = -999.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var kick_sound: AudioStreamPlayer3D = $KickSound
@onready var touch_sound: AudioStreamPlayer3D = $TouchSound

func _ready() -> void:
	spawn_position = global_position
	# Nur der Host simuliert die Ballphysik, Clients bekommen sie synchronisiert.
	freeze = not Network.is_host()
	set_multiplayer_authority(1)
	if Network.is_host():
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		last_toucher_peer_id = body.owner_peer_id
	_maybe_play_touch_sfx()

func _maybe_play_touch_sfx() -> void:
	# Debounce, damit ein Kontakt-Wackler nicht mehrfach pro Frame/Tick auslöst.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_touch_sfx_time < TOUCH_SFX_COOLDOWN:
		return
	if linear_velocity.length() < TOUCH_SFX_SPEED_THRESHOLD:
		return
	_last_touch_sfx_time = now
	play_touch_sfx.rpc()

## 3D-Sound direkt am Ball statt zentral, damit man ihn am Ohr orten kann.
@rpc("call_local", "reliable")
func play_touch_sfx() -> void:
	touch_sound.stream = SFX.BALL_TOUCH
	touch_sound.play()

@rpc("call_local", "reliable")
func play_kick_sfx() -> void:
	kick_sound.stream = SFX.KICK
	kick_sound.play()

func set_last_toucher(peer_id: int) -> void:
	last_toucher_peer_id = peer_id

func reset_ball() -> void:
	global_position = spawn_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_history.append({"t": now, "pos": global_position, "quat": quaternion})
	while _history.size() > 1 and now - _history[0]["t"] > HISTORY_SECONDS:
		_history.pop_front()

## Spielt den aufgezeichneten Ballverlauf der letzten `duration` Sekunden
## als sichtbaren Geist-Ball ab, ohne die echte (physikalische) Ballposition zu berühren.
## Schaltet dabei lokal auf eine schräge Kamera von oben um.
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

	mesh_instance.visible = false
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh_instance.mesh
	ghost.set_surface_override_material(0, mesh_instance.get_surface_override_material(0))
	get_parent().add_child(ghost)

	var local_camera := _find_local_camera()
	var replay_cam: Camera3D = get_tree().get_first_node_in_group("replay_camera")
	if replay_cam:
		replay_cam.current = true

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
		if replay_cam:
			# Seitliche, mittig-hohe Kamera, die dem Ball die ganze Zeit folgt,
			# statt fix auf einen einzigen Punkt der Aufnahme zu zeigen.
			replay_cam.global_position = sample["pos"] + REPLAY_SIDE_OFFSET
			replay_cam.look_at(sample["pos"], Vector3.UP)
		await get_tree().process_frame

	ghost.queue_free()
	mesh_instance.visible = true
	if replay_cam:
		replay_cam.current = false
	if local_camera:
		local_camera.current = true

func _find_local_camera() -> Camera3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p.owner_peer_id == Network.get_my_id():
			return p.camera
	return null

func _sample_history(clip: Array, t: float) -> Dictionary:
	for i in range(clip.size() - 1):
		if clip[i]["t"] <= t and t <= clip[i + 1]["t"]:
			var span: float = max(clip[i + 1]["t"] - clip[i]["t"], 0.0001)
			var f: float = (t - clip[i]["t"]) / span
			var pos: Vector3 = clip[i]["pos"].lerp(clip[i + 1]["pos"], f)
			var quat: Quaternion = clip[i]["quat"].slerp(clip[i + 1]["quat"], f)
			return {"pos": pos, "quat": quat}
	return clip[clip.size() - 1]
