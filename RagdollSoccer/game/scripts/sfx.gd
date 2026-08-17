extends Node

const KICK := preload("res://assets/audio/kick.ogg")
const GOAL_HORN := preload("res://assets/audio/goal_horn.ogg")
const BALL_TOUCH := preload("res://assets/audio/ball_touch.ogg")
const UI_CLICK := preload("res://assets/audio/ui_click.ogg")
const UI_CONFIRM := preload("res://assets/audio/ui_confirm.ogg")
const UI_ERROR := preload("res://assets/audio/ui_error.ogg")
const HALFTIME_JINGLE := preload("res://assets/audio/halftime_jingle.ogg")
const FULLTIME_FANFARE := preload("res://assets/audio/fulltime_fanfare.wav")
const CRATE_SPIN := preload("res://assets/audio/crate_spin.mp3")
const CRATE_WIN := preload("res://assets/audio/crate_win.mp3")

@rpc("call_local", "reliable")
func play_goal() -> void:
	_play(GOAL_HORN, "Ball", 0.0)
	Ambience.goal_cheer()

@rpc("call_local", "reliable")
func play_halftime_jingle() -> void:
	_play(HALFTIME_JINGLE, "Music", -4.0)

@rpc("call_local", "reliable")
func play_fulltime_fanfare() -> void:
	_play(FULLTIME_FANFARE, "Music", -4.0)

func play_ui_click() -> void:
	_play(UI_CLICK, "UI", -4.0)

func play_ui_confirm() -> void:
	_play(UI_CONFIRM, "UI", -4.0)

func play_ui_error() -> void:
	_play(UI_ERROR, "UI", -4.0)

## Startet den Kisten-Öffnen-Spin-Sound in Dauerschleife (der Clip selbst ist
## kurz, wir triggern ihn beim Enden einfach neu, statt den Loop-Import zu
## nutzen — so kann der Aufrufer ihn per stop_crate_spin() jederzeit sauber
## abbrechen, sobald die Animation landet).
func play_crate_spin() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = CRATE_SPIN
	player.bus = "UI"
	player.volume_db = -6.0
	add_child(player)
	player.finished.connect(player.play)
	player.play()
	return player

func stop_crate_spin(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player):
		return
	if player.finished.is_connected(player.play):
		player.finished.disconnect(player.play)
	player.stop()
	player.queue_free()

func play_crate_win() -> void:
	_play(CRATE_WIN, "UI", -2.0)

func _play(stream: AudioStream, bus: String, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
