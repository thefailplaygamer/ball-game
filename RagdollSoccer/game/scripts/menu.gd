extends Control

const REPO_OWNER := "thefailplaygamer"
const REPO_NAME := "ball-game"

@onready var welcome_label: Label = $MainPanel/VBox/WelcomeLabel
@onready var number_edit: LineEdit = $MainPanel/VBox/NumberRow/NumberEdit
@onready var ip_edit: LineEdit = $MainPanel/VBox/IPEdit
@onready var status_label: Label = $MainPanel/VBox/StatusLabel
@onready var version_label: Label = $VersionLabel
@onready var patch_notes_title: Label = $PatchNotesPanel/VBox/Title
@onready var patch_notes_body: RichTextLabel = $PatchNotesPanel/VBox/Body

func _ready() -> void:
	status_label.text = "Deine lokale IP (zum Teilen): %s" % Network.get_local_ip()
	version_label.text = "v%s" % Settings.game_version
	welcome_label.text = "Angemeldet als %s" % Network.my_name
	for button in [$MainPanel/VBox/HostButton, $MainPanel/VBox/JoinButton, $MainPanel/VBox/OptionsButton, $MainPanel/VBox/InventoryButton, $MainPanel/VBox/LogoutButton, $MainPanel/VBox/QuitButton]:
		button.pressed.connect(SFX.play_ui_click)
	_load_patch_notes()

func _get_number() -> int:
	var n := number_edit.text.to_int()
	return clamp(n, 0, 99) if number_edit.text != "" else 10

func _on_host_pressed() -> void:
	Network.host_game(Network.my_name, _get_number(), Inventory.equipped)

func _on_join_pressed() -> void:
	var ip := ip_edit.text if ip_edit.text != "" else "127.0.0.1"
	Network.join_game(ip, Network.my_name, _get_number(), Inventory.equipped)

func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/options.tscn")

func _on_inventory_pressed() -> void:
	Network.my_number = _get_number()
	get_tree().change_scene_to_file("res://scenes/inventory_screen.tscn")

func _on_logout_pressed() -> void:
	Supabase.logout()
	get_tree().change_scene_to_file("res://scenes/login_screen.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

## Holt ALLE GitHub-Releases (neueste zuerst) und zeigt sie hintereinander im
## Hauptmenü an, sodass man flüssig durch die komplette Historie scrollen kann
## (RichTextLabel scrollt von selbst, sobald der Inhalt überläuft). Schlägt
## das fehl (kein Internet, Rate-Limit, etc.), wird das Menü dadurch nicht
## blockiert, nur ein Hinweistext angezeigt.
func _load_patch_notes() -> void:
	patch_notes_body.text = "Lade Patchnotes …"
	var http := HTTPRequest.new()
	add_child(http)
	var url := "https://api.github.com/repos/%s/%s/releases" % [REPO_OWNER, REPO_NAME]
	var err := http.request(url, ["User-Agent: BallGame"])
	if err != OK:
		http.queue_free()
		patch_notes_body.text = "Patchnotes nicht verfügbar."
		return

	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var body: PackedByteArray = response[3]
	if code != 200:
		patch_notes_body.text = "Patchnotes nicht verfügbar."
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not (json is Array) or json.is_empty():
		patch_notes_body.text = "Patchnotes nicht verfügbar."
		return

	var latest_tag: String = json[0].get("tag_name", "")
	patch_notes_title.text = "Was ist neu — %s" % latest_tag if latest_tag != "" else "Was ist neu"

	var sections: Array[String] = []
	for release in json:
		var tag_name: String = release.get("tag_name", "")
		var notes: String = release.get("body", "")
		var header := "[b][color=#f2a53f]%s[/color][/b]" % (tag_name if tag_name != "" else "?")
		var notes_bbcode := _markdown_to_bbcode(notes) if notes != "" else "(keine Beschreibung)"
		sections.append("%s\n%s" % [header, notes_bbcode])
	patch_notes_body.text = "\n\n[color=#3a4150]────────────────────[/color]\n\n".join(sections)

## Wandelt simples GitHub-Markdown (Überschriften, Listen, **fett**) in BBCode
## fürs RichTextLabel um. Eckige Klammern aus dem Originaltext werden zuerst
## escaped, damit aus dem Release-Text selbst kein BBCode eingeschleust wird.
func _markdown_to_bbcode(markdown: String) -> String:
	var lines := markdown.replace("\r\n", "\n").split("\n")
	var out: Array[String] = []
	for raw_line in lines:
		var line: String = raw_line.strip_edges().replace("[", "[lb]").replace("]", "[rb]")
		if line.begins_with("### "):
			out.append("[b][u]%s[/u][/b]" % line.substr(4))
		elif line.begins_with("## "):
			out.append("[b][u]%s[/u][/b]" % line.substr(3))
		elif line.begins_with("# "):
			out.append("[b][u]%s[/u][/b]" % line.substr(2))
		elif line.begins_with("- ") or line.begins_with("* "):
			out.append("• %s" % line.substr(2))
		else:
			out.append(line)
	var text := "\n".join(out)
	var bold_re := RegEx.new()
	bold_re.compile("\\*\\*(.+?)\\*\\*")
	text = bold_re.sub(text, "[b]$1[/b]", true)
	return text
