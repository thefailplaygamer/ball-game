extends Control

const JerseyData := preload("res://scripts/jersey_data.gd")
const JERSEY_ICON_SCRIPT := preload("res://scripts/jersey_icon.gd")
const ITEM_WIDTH := 110.0
const REVEAL_ITEM_COUNT := 28
const REVEAL_ITEMS_AFTER_WIN := 6
const REVEAL_DURATION := 3.2

@onready var crate_label: Label = $MainPanel/HBox/LeftColumn/HeaderRow/CrateLabel
@onready var open_button: Button = $MainPanel/HBox/LeftColumn/HeaderRow/OpenCrateButton
@onready var back_button: Button = $MainPanel/HBox/LeftColumn/HeaderRow/BackButton
@onready var grid_scroll: ScrollContainer = $MainPanel/HBox/LeftColumn/GridScroll
@onready var grid: GridContainer = $MainPanel/HBox/LeftColumn/GridScroll/Grid
@onready var reveal_layer: Control = $MainPanel/HBox/LeftColumn/RevealLayer
@onready var strip: HBoxContainer = $MainPanel/HBox/LeftColumn/RevealLayer/Strip
@onready var result_label: Label = $MainPanel/HBox/LeftColumn/ResultLabel
@onready var character_preview: Node = $MainPanel/HBox/RightColumn/VBox/PreviewViewportContainer/SubViewport/CharacterPreview

var _opening: bool = false
var _reveal_tween: Tween = null

func _ready() -> void:
	open_button.pressed.connect(_on_open_crate_pressed)
	back_button.pressed.connect(_on_back_pressed)
	reveal_layer.visible = false
	result_label.visible = false
	_refresh()

func _refresh() -> void:
	crate_label.text = "Kisten: %d" % Inventory.crates
	open_button.disabled = Inventory.crates <= 0 or _opening
	back_button.disabled = _opening
	_refresh_grid()

func _refresh_grid() -> void:
	for child in grid.get_children():
		child.queue_free()
	for def in JerseyData.JERSEYS:
		grid.add_child(_build_cell(def))

func _build_cell(def: Dictionary) -> Control:
	var id: int = def["id"]
	var count: int = Inventory.get_count(id)
	var owned: bool = count > 0
	var is_equipped: bool = id == Inventory.equipped

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(96, 152)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	cell.add_child(vb)

	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(84, 84)
	vb.add_child(icon_wrap)

	var icon: Control = JERSEY_ICON_SCRIPT.new()
	icon.custom_minimum_size = Vector2(84, 84)
	icon.size = Vector2(84, 84)
	icon.setup(id, not owned)
	icon_wrap.add_child(icon)

	# Dubletten waren als kleiner Textzusatz kaum zu erkennen — jetzt ein
	# deutlich sichtbares Badge oben auf dem Icon, wichtig weil Dubletten
	# später für Trade-Ups zählen sollen.
	if count > 1:
		icon_wrap.add_child(_build_count_badge(count))

	var name_label := Label.new()
	name_label.text = def["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 10)
	if not owned:
		name_label.modulate = Color(0.5, 0.5, 0.55)
	vb.add_child(name_label)

	var tag_label := Label.new()
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", 9)
	if owned:
		tag_label.text = JerseyData.RARITY_NAMES[def["rarity"]]
		tag_label.add_theme_color_override("font_color", JerseyData.RARITY_COLOR[def["rarity"]])
	else:
		tag_label.text = "Gesperrt"
		tag_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	vb.add_child(tag_label)

	var equip_button := Button.new()
	equip_button.custom_minimum_size = Vector2(0, 28)
	equip_button.add_theme_font_size_override("font_size", 10)
	if not owned:
		equip_button.text = "Gesperrt"
		equip_button.disabled = true
	elif is_equipped:
		equip_button.text = "Ausgerüstet"
		equip_button.disabled = true
		equip_button.modulate = Color(0.55, 0.55, 0.55)
	else:
		equip_button.text = "Ausrüsten"
		equip_button.pressed.connect(_on_equip.bind(id))
	vb.add_child(equip_button)

	return cell

## Kleines "×N"-Schild, das über die untere rechte Ecke eines Trikot-Icons
## gelegt wird, um Dubletten deutlich sichtbar zu machen.
func _build_count_badge(count: int) -> Control:
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.15, 0.6, 0.95, 0.95)
	badge_bg.corner_radius_top_left = 8
	badge_bg.corner_radius_top_right = 8
	badge_bg.corner_radius_bottom_left = 8
	badge_bg.corner_radius_bottom_right = 8
	badge_bg.content_margin_left = 5
	badge_bg.content_margin_right = 5
	badge_bg.content_margin_top = 1
	badge_bg.content_margin_bottom = 1

	var badge_label := Label.new()
	badge_label.text = "×%d" % count
	badge_label.add_theme_font_size_override("font_size", 12)
	badge_label.add_theme_color_override("font_color", Color(1, 1, 1))
	badge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	badge_label.add_theme_constant_override("outline_size", 3)

	var badge_panel := PanelContainer.new()
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_theme_stylebox_override("panel", badge_bg)
	badge_panel.add_child(badge_label)
	badge_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
	return badge_panel

func _on_equip(id: int) -> void:
	if await Inventory.equip(id):
		SFX.play_ui_click()
		_refresh_grid()
		character_preview.set_jersey(id)

func _on_back_pressed() -> void:
	SFX.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_open_crate_pressed() -> void:
	if _opening or Inventory.crates <= 0:
		return
	# Sofort sperren, nicht erst nach der Server-Antwort: sonst könnte ein
	# zweiter Klick während der (jetzt asynchronen, netzwerkbasierten)
	# Anfrage noch durchrutschen, bevor _opening gesetzt ist.
	_opening = true
	open_button.disabled = true
	back_button.disabled = true
	SFX.play_ui_click()
	var won_id := await Inventory.open_crate()
	if won_id < 0:
		_opening = false
		_refresh()
		return
	crate_label.text = "Kisten: %d" % Inventory.crates
	await _play_reveal(won_id)
	_opening = false
	_refresh()

## Baut einen horizontal scrollenden Streifen aus Zufalls-Trikots. Das
## gewonnene Trikot sitzt NICHT am Ende des Streifens, sondern hat noch ein
## paar weitere Zufalls-Icons hinter sich — sonst läuft die Reihe sichtbar
## "ins Leere" und man erahnt das Ergebnis, sobald das Streifenende in Sicht
## kommt. Landet an einer zufälligen Stelle INNERHALB des Gewinn-Icons (nicht
## immer exakt mittig), damit man es nicht vorzeitig an der Position ablesen kann.
func _play_reveal(won_id: int) -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null

	# Sofort (nicht deferred) entfernen: queue_free() würde die alten Kinder
	# erst am Frame-Ende wirklich aus dem Baum nehmen, wodurch beim zweiten
	# Öffnen kurzzeitig alte UND neue Icons gleichzeitig im Strip stecken und
	# die Zielberechnung unten verfälscht wird.
	for child in strip.get_children():
		strip.remove_child(child)
		child.free()
	strip.position.x = 0.0

	var loot: Array = JerseyData.JERSEYS
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var items_before_win := REVEAL_ITEM_COUNT - 1 - REVEAL_ITEMS_AFTER_WIN
	for i in items_before_win:
		var random_def: Dictionary = loot[rng.randi_range(1, loot.size() - 1)]
		strip.add_child(_build_reveal_icon(random_def["id"]))
	var won_wrap := _build_reveal_icon(won_id)
	strip.add_child(won_wrap)
	for i in REVEAL_ITEMS_AFTER_WIN:
		var trailing_def: Dictionary = loot[rng.randi_range(1, loot.size() - 1)]
		strip.add_child(_build_reveal_icon(trailing_def["id"]))

	result_label.visible = false
	reveal_layer.visible = true
	grid_scroll.visible = false
	var spin_player := SFX.play_crate_spin()

	# Auf ein fertiges Layout warten statt blind einen Frame zu raten: sonst
	# ist reveal_layer.size manchmal noch 0/veraltet (z.B. gleich nach dem
	# Öffnen des Screens), und die Zielberechnung unten wäre falsch.
	var guard := 0
	await get_tree().process_frame
	while reveal_layer.size.x < ITEM_WIDTH and guard < 20:
		await get_tree().process_frame
		guard += 1

	# Zielposition EINMAL vorab exakt berechnen (keine nachträgliche Korrektur
	# mehr danach — die hatte vorher zu einem sichtbaren "Sprung" am Ende
	# geführt).
	var landing_spot_in_icon: float = rng.randf_range(ITEM_WIDTH * 0.22, ITEM_WIDTH * 0.78)
	var center_x: float = reveal_layer.size.x * 0.5
	var target_offset: float = won_wrap.position.x + landing_spot_in_icon - center_x

	_reveal_tween = create_tween()
	_reveal_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(strip, "position:x", -target_offset, REVEAL_DURATION)
	await _reveal_tween.finished
	_reveal_tween = null

	SFX.stop_crate_spin(spin_player)
	SFX.play_crate_win()

	var def: Dictionary = JerseyData.get_by_id(won_id)
	var rarity: int = def["rarity"]
	result_label.text = "%s — %s" % [def["name"], JerseyData.RARITY_NAMES[rarity]]
	result_label.add_theme_color_override("font_color", JerseyData.RARITY_COLOR[rarity])
	result_label.visible = true

	var pulse := create_tween()
	pulse.tween_property(won_wrap, "scale", Vector2(1.25, 1.25), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(won_wrap, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(2.2).timeout
	reveal_layer.visible = false
	grid_scroll.visible = true

func _build_reveal_icon(id: int) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(ITEM_WIDTH, 100)
	wrap.pivot_offset = Vector2(ITEM_WIDTH, 100) * 0.5
	var icon: Control = JERSEY_ICON_SCRIPT.new()
	icon.position = Vector2((ITEM_WIDTH - 90.0) * 0.5, 5)
	icon.size = Vector2(90, 90)
	icon.setup(id, false)
	wrap.add_child(icon)
	return wrap
