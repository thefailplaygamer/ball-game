extends Node

const SAVE_PATH := "user://settings.cfg"
const BUS_NAMES := ["Master", "Ambient", "UI", "Ball", "Music"]
const DEFAULT_VOLUMES := {"Master": 0.8, "Ambient": 0.6, "UI": 0.8, "Ball": 0.9, "Music": 0.5}
const VERSION_FILE_NAME := "version.txt"

var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var game_version: String = "dev"

var fullscreen: bool = false:
	set(value):
		fullscreen = value
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
		)

func _ready() -> void:
	_ensure_buses()
	load_settings()
	_load_version()

## Der Launcher legt beim Update-Download ein version.txt mit dem GitHub-Release-
## Tag direkt neben die Spiel-.exe, dieselbe wir hier gerade ausführen. So muss
## die Versionsnummer nirgends im Code hardcodiert/manuell synchron gehalten werden.
func _load_version() -> void:
	var version_path := OS.get_executable_path().get_base_dir().path_join(VERSION_FILE_NAME)
	if not FileAccess.file_exists(version_path):
		return
	var f := FileAccess.open(version_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text().strip_edges()
	f.close()
	if text != "":
		game_version = text

func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		if bus_name == "Master":
			continue
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func set_volume(bus_name: String, value: float) -> void:
	volumes[bus_name] = value
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), linear_to_db(max(value, 0.001)))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var fs := false
	if cfg.load(SAVE_PATH) == OK:
		for bus_name in BUS_NAMES:
			volumes[bus_name] = cfg.get_value("audio", bus_name, DEFAULT_VOLUMES[bus_name])
		fs = cfg.get_value("display", "fullscreen", false)
	for bus_name in BUS_NAMES:
		set_volume(bus_name, volumes[bus_name])
	fullscreen = fs

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in BUS_NAMES:
		cfg.set_value("audio", bus_name, volumes[bus_name])
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)
