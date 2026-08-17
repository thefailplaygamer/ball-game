extends Control

const REPO_OWNER := "thefailplaygamer"
const REPO_NAME := "ball-game"
const ASSET_NAME := "Ball.exe" # so heißt die Datei im GitHub-Release
const GAME_SUBDIR := "game"
const GAME_EXE_NAME := "Ball_game.exe"
const VERSION_FILE_NAME := "version.txt"

@onready var status_label: Label = $StatusLabel

var base_dir: String
var game_dir: String
var game_exe_path: String
var version_file_path: String

func _ready() -> void:
	base_dir = OS.get_executable_path().get_base_dir()
	game_dir = base_dir.path_join(GAME_SUBDIR)
	game_exe_path = game_dir.path_join(GAME_EXE_NAME)
	version_file_path = game_dir.path_join(VERSION_FILE_NAME)
	DirAccess.make_dir_recursive_absolute(game_dir)
	_check_for_update()

func _check_for_update() -> void:
	status_label.text = "Suche nach Updates..."
	var http := HTTPRequest.new()
	add_child(http)
	var url := "https://api.github.com/repos/%s/%s/releases/latest" % [REPO_OWNER, REPO_NAME]
	var err := http.request(url, ["User-Agent: BallLauncher"])
	if err != OK:
		http.queue_free()
		_fallback_or_fail("Konnte keine Verbindung herstellen.")
		return

	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var body: PackedByteArray = response[3]

	if code != 200:
		_fallback_or_fail("Update-Server nicht erreichbar (Code %d)." % code)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not (json is Dictionary) or not json.has("tag_name"):
		_fallback_or_fail("Antwort vom Update-Server ungültig.")
		return

	var latest_version: String = json["tag_name"]
	var download_url := ""
	for asset in json.get("assets", []):
		if asset["name"] == ASSET_NAME:
			download_url = asset["browser_download_url"]
			break

	if download_url == "":
		_fallback_or_fail("Keine passende Datei im neuesten Release gefunden.")
		return

	if _read_local_version() == latest_version and FileAccess.file_exists(game_exe_path):
		_launch_game()
		return

	await _download_update(download_url, latest_version)

func _read_local_version() -> String:
	if not FileAccess.file_exists(version_file_path):
		return ""
	var f := FileAccess.open(version_file_path, FileAccess.READ)
	var v := f.get_as_text().strip_edges()
	f.close()
	return v

func _write_local_version(version: String) -> void:
	var f := FileAccess.open(version_file_path, FileAccess.WRITE)
	f.store_string(version)
	f.close()

func _download_update(url: String, version: String) -> void:
	status_label.text = "Lade Version %s herunter..." % version
	var tmp_path := game_exe_path + ".download"
	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = tmp_path
	var err := http.request(url, ["User-Agent: BallLauncher"])
	if err != OK:
		http.queue_free()
		_fallback_or_fail("Download konnte nicht gestartet werden.")
		return

	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]

	if code != 200 and code != 302:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		_fallback_or_fail("Download fehlgeschlagen (Code %d)." % code)
		return

	if FileAccess.file_exists(game_exe_path):
		DirAccess.remove_absolute(game_exe_path)
	var dir := DirAccess.open(game_dir)
	dir.rename(GAME_EXE_NAME + ".download", GAME_EXE_NAME)
	_write_local_version(version)
	_launch_game()

func _launch_game() -> void:
	status_label.text = "Starte Spiel..."
	OS.create_process(game_exe_path, [])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

func _fallback_or_fail(message: String) -> void:
	if FileAccess.file_exists(game_exe_path):
		status_label.text = message + "\nStarte vorhandene Version..."
		await get_tree().create_timer(1.5).timeout
		_launch_game()
	else:
		status_label.text = message + "\nKeine lokale Version vorhanden."
