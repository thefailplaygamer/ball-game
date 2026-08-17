extends Control

## Vorschau-Kachel eines Trikots fürs Inventar-Grid und den Kisten-Streifen.
##
## Das Muster kommt aus demselben Shader-Code wie der Stoff am 3D-Spieler
## (shaders/jersey_patterns.gdshaderinc), gezeichnet in eine Trikot-Silhouette.
## Dadurch stimmen Icon und Spielfigur immer überein, und animierte Muster
## (episch/legendär) laufen hier ohne zusätzlichen Aufwand mit — TIME im Shader
## läuft von allein weiter, es ist kein queue_redraw() pro Frame nötig.

const JerseyData := preload("res://scripts/jersey_data.gd")
const ICON_SHADER := preload("res://shaders/jersey_icon.gdshader")
const BG_COLOR := Color(0.05, 0.055, 0.07)

var jersey_id: int = 0
var locked: bool = false

var _rect: ColorRect
var _mat: ShaderMaterial
var _lock_label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mat = ShaderMaterial.new()
	_mat.shader = ICON_SHADER
	_mat.set_shader_parameter("bg_color", BG_COLOR)

	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.color = Color.WHITE # nur Träger für den Shader
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

	_lock_label = Label.new()
	_lock_label.text = "?"
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock_label.add_theme_font_size_override("font_size", 26)
	_lock_label.add_theme_color_override("font_color", Color(0.42, 0.43, 0.5))
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_label.visible = false
	add_child(_lock_label)

func setup(id: int, is_locked: bool = false) -> void:
	jersey_id = id
	locked = is_locked
	_apply()

func _apply() -> void:
	var def: Dictionary = JerseyData.get_by_id(jersey_id)
	var rarity: int = def.get("rarity", JerseyData.Rarity.COMMON)

	# id 0 hat keine eigene Farbe (die kommt im Spiel vom Team), im Inventar
	# zeigen wir dafür ein neutrales Grau.
	var a: Color = def.get("color_a", Color(0.55, 0.57, 0.6))
	var b: Color = def.get("color_b", a)
	var c: Color = def.get("color_c", b)

	_mat.set_shader_parameter("pattern_mode", int(def["pattern"]))
	_mat.set_shader_parameter("color_a", a)
	_mat.set_shader_parameter("color_b", b)
	_mat.set_shader_parameter("color_c", c)
	_mat.set_shader_parameter("rarity_color", JerseyData.RARITY_COLOR[rarity])
	_mat.set_shader_parameter("rarity_glow", float(JerseyData.RARITY_GLOW[rarity]))
	_mat.set_shader_parameter("glow_pulse", 1.0 if rarity == JerseyData.Rarity.LEGENDARY else 0.0)
	_mat.set_shader_parameter("locked", locked)

	_lock_label.visible = locked
