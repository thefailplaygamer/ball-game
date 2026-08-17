extends Node

const CROWD_AMBIENCE := preload("res://assets/audio/crowd_ambience.mp3")
const GOAL_CHEER := preload("res://assets/audio/goal_cheer.mp3")

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = CROWD_AMBIENCE
	_player.bus = "Ambient"
	_player.volume_db = -8.0
	add_child(_player)
	if _player.stream is AudioStreamMP3:
		_player.stream.loop = true

func start_stadium_ambience() -> void:
	if not _player.playing:
		_player.play()

func stop_stadium_ambience() -> void:
	_player.stop()

## Kurzer Jubel-Schwall obendrauf, z.B. beim Torjubel.
func goal_cheer() -> void:
	var cheer_player := AudioStreamPlayer.new()
	cheer_player.stream = GOAL_CHEER
	cheer_player.bus = "Ambient"
	cheer_player.volume_db = -2.0
	add_child(cheer_player)
	cheer_player.finished.connect(cheer_player.queue_free)
	cheer_player.play()
