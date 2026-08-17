extends Control

## Zeichnet eine flache 2D-Vorschau eines Trikot-Musters (siehe JerseyData),
## fürs Inventar-Grid und den Kisten-Öffnen-Streifen. Kein Bild-Asset nötig,
## rein prozedural passend zum 3D-Shader.

const JerseyData := preload("res://scripts/jersey_data.gd")

var jersey_id: int = 0
var locked: bool = false

func setup(id: int, is_locked: bool = false) -> void:
	jersey_id = id
	locked = is_locked
	queue_redraw()

func _draw() -> void:
	var def: Dictionary = JerseyData.get_by_id(jersey_id)
	var pad := 3.0
	var inner := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.08), true)

	if locked:
		draw_rect(inner, Color(0.16, 0.17, 0.19), true)
		var font := ThemeDB.fallback_font
		draw_string(font, inner.position + inner.size * 0.5 - Vector2(6, -7), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(0.4, 0.4, 0.46))
	else:
		_draw_pattern(inner, def)

	var rarity: int = def.get("rarity", 0)
	var border_col: Color = Color(0.28, 0.28, 0.32) if locked else JerseyData.RARITY_COLOR[rarity]
	draw_rect(inner, border_col, false, 3.0)

func _draw_pattern(rect: Rect2, def: Dictionary) -> void:
	var id: int = def["id"]
	if id == 0:
		draw_rect(rect, Color(0.55, 0.57, 0.6), true)
		return

	var pattern: int = def["pattern"]
	var a: Color = def.get("color_a", Color.WHITE)
	var b: Color = def.get("color_b", a)
	var c: Color = def.get("color_c", b)

	match pattern:
		JerseyData.Pattern.SOLID:
			draw_rect(rect, a, true)
		JerseyData.Pattern.STRIPES_H:
			_bands(rect, [a, b], 5, true)
		JerseyData.Pattern.STRIPES_V:
			_bands(rect, [a, b], 5, false)
		JerseyData.Pattern.HALF_SPLIT:
			var half := rect.size.x * 0.5
			draw_rect(Rect2(rect.position, Vector2(half, rect.size.y)), a, true)
			draw_rect(Rect2(rect.position + Vector2(half, 0), Vector2(rect.size.x - half, rect.size.y)), b, true)
		JerseyData.Pattern.COLOR_BLOCK:
			var w := rect.size.x / 3.0
			draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), a, true)
			draw_rect(Rect2(rect.position + Vector2(w, 0), Vector2(w, rect.size.y)), b, true)
			draw_rect(Rect2(rect.position + Vector2(w * 2.0, 0), Vector2(w, rect.size.y)), a, true)
		JerseyData.Pattern.HOOPS_TRICOLOR:
			_bands(rect, [a, b, c], 6, true)
		JerseyData.Pattern.SASH:
			draw_rect(rect, a, true)
			_diagonal_sash(rect, b)
		JerseyData.Pattern.CHECKERBOARD:
			_checkerboard(rect, a, b, 4)
		JerseyData.Pattern.PINSTRIPE:
			draw_rect(rect, a, true)
			_pinstripes(rect, b)
		JerseyData.Pattern.GRADIENT_V, JerseyData.Pattern.GRADIENT_DIAGONAL, JerseyData.Pattern.GRADIENT_DUAL, JerseyData.Pattern.GRADIENT_RADIAL:
			_gradient(rect, a, b, 12)
		JerseyData.Pattern.RAINBOW, JerseyData.Pattern.HOLOGRAPHIC:
			_rainbow(rect)
		JerseyData.Pattern.CAMO:
			_camo(rect, a, b, c, id)
		JerseyData.Pattern.FLAME:
			_flame(rect, a, b, c)
		_:
			draw_rect(rect, a, true)

func _bands(rect: Rect2, colors: Array, count: int, horizontal: bool) -> void:
	for i in count:
		var t0 := float(i) / count
		var t1 := float(i + 1) / count
		var col: Color = colors[i % colors.size()]
		if horizontal:
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * t0), Vector2(rect.size.x, rect.size.y * (t1 - t0) + 0.5)), col, true)
		else:
			draw_rect(Rect2(rect.position + Vector2(rect.size.x * t0, 0), Vector2(rect.size.x * (t1 - t0) + 0.5, rect.size.y)), col, true)

func _gradient(rect: Rect2, a: Color, b: Color, steps: int) -> void:
	for i in steps:
		var t := float(i) / float(steps - 1)
		var col := a.lerp(b, t)
		draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * float(i) / steps), Vector2(rect.size.x, rect.size.y / steps + 1.0)), col, true)

func _rainbow(rect: Rect2) -> void:
	var steps := 7
	for i in steps:
		var hue := float(i) / steps
		var col := Color.from_hsv(hue, 0.75, 0.95)
		draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * float(i) / steps), Vector2(rect.size.x, rect.size.y / steps + 1.0)), col, true)

func _checkerboard(rect: Rect2, a: Color, b: Color, n: int) -> void:
	var cw := rect.size.x / n
	var ch := rect.size.y / n
	for y in n:
		for x in n:
			var col := a if (x + y) % 2 == 0 else b
			draw_rect(Rect2(rect.position + Vector2(x * cw, y * ch), Vector2(cw + 1.0, ch + 1.0)), col, true)

func _pinstripes(rect: Rect2, col: Color) -> void:
	var n := 6
	for i in n:
		var x := rect.position.x + rect.size.x * (float(i) + 0.5) / n
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + rect.size.y), col, 1.5)

func _diagonal_sash(rect: Rect2, col: Color) -> void:
	var w := rect.size.x * 0.3
	var p1 := rect.position + Vector2(0, rect.size.y * 0.15)
	var p2 := rect.position + Vector2(w, 0)
	var p3 := rect.position + Vector2(rect.size.x, rect.size.y - rect.size.y * 0.15)
	var p4 := rect.position + Vector2(rect.size.x - w, rect.size.y)
	draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), col)

func _camo(rect: Rect2, a: Color, b: Color, c: Color, seed_val: int) -> void:
	draw_rect(rect, a, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in 6:
		var pos := rect.position + Vector2(rng.randf_range(0.0, rect.size.x), rng.randf_range(0.0, rect.size.y))
		var r := rng.randf_range(rect.size.x * 0.12, rect.size.x * 0.22)
		draw_circle(pos, r, b if i % 2 == 0 else c)

func _flame(rect: Rect2, a: Color, b: Color, c: Color) -> void:
	draw_rect(rect, c, true)
	var pts1 := PackedVector2Array([
		rect.position + Vector2(rect.size.x * 0.2, rect.size.y),
		rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.1),
		rect.position + Vector2(rect.size.x * 0.8, rect.size.y),
	])
	draw_colored_polygon(pts1, a)
	var pts2 := PackedVector2Array([
		rect.position + Vector2(rect.size.x * 0.35, rect.size.y),
		rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.4),
		rect.position + Vector2(rect.size.x * 0.65, rect.size.y),
	])
	draw_colored_polygon(pts2, b)
