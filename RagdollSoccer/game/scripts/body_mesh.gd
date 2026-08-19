extends RefCounted

## Baut die Körperteile des Spielermodells prozedural als Rotations-Loft.
##
## Godot bringt nur Box/Kapsel/Kugel mit — daraus sah der Spieler aus wie ein
## Stapel Bauklötze. Hier wird stattdessen für jedes Körperteil eine Kette von
## Querschnitten (Ellipse bzw. abgerundetes Rechteck) übereinandergelegt und
## vernäht. Dadurch bekommen Torso, Arme und Beine eine echte Verjüngung,
## abgerundete Enden und vor allem eine DURCHGEHENDE zylindrische UV-Abwicklung:
##
##   UV.x = 0 an der Rückenmitte, 0.5 an der Vorderseite, 1 wieder am Rücken
##   UV.y = 0 oben, 1 unten
##
## Das ist wichtig für die Trikot-Skins: auf dem alten BoxMesh fing das Muster
## auf jeder der sechs Würfelseiten neu an, jetzt läuft es sauber um den Körper
## herum, und die "Blickfang"-Muster (Sonne, Galaxienkern) sitzen bei UV 0.5/0.5
## genau auf der Brust.

## Fertige Meshes werden über alle Spieler hinweg geteilt — sie sind identisch
## und würden sonst pro Spawn neu berechnet.
static var _cache: Dictionary = {}

static func get_part(part: String) -> ArrayMesh:
	if _cache.has(part):
		return _cache[part]
	var mesh: ArrayMesh = _build_part(part)
	_cache[part] = mesh
	return mesh

static func _build_part(part: String) -> ArrayMesh:
	match part:
		"torso":
			# Hüfte -> Brustkorb -> Schultern -> Halsansatz.
			return build([
				_sec(0.0, 0.155, 0.105, 0.85),
				_sec(0.1, 0.15, 0.1, 0.85),
				_sec(0.22, 0.155, 0.103, 0.85),
				_sec(0.36, 0.185, 0.115, 0.8),
				_sec(0.5, 0.215, 0.125, 0.78),
				_sec(0.58, 0.19, 0.118, 0.82),
				_sec(0.62, 0.09, 0.08, 0.9),
			], 26, true, false, 4)
		"upper_arm":
			return build([
				_sec(-0.27, 0.058, 0.058, 1.0),
				_sec(-0.15, 0.062, 0.062, 1.0),
				_sec(-0.04, 0.073, 0.073, 1.0),
				_sec(0.0, 0.075, 0.075, 1.0),
			], 12, true, true, 3)
		"forearm":
			return build([
				_sec(-0.25, 0.046, 0.046, 1.0),
				_sec(-0.12, 0.052, 0.052, 1.0),
				_sec(0.0, 0.058, 0.058, 1.0),
			], 12, true, true, 3)
		"hand":
			return build([
				_sec(-0.09, 0.035, 0.022, 0.8),
				_sec(-0.04, 0.045, 0.028, 0.8),
				_sec(0.0, 0.042, 0.026, 0.8),
			], 10, true, true, 3)
		"thigh":
			return build([
				_sec(-0.35, 0.081, 0.083, 1.0),
				_sec(-0.20, 0.093, 0.096, 1.0),
				_sec(-0.05, 0.104, 0.107, 1.0),
				_sec(0.0, 0.105, 0.108, 1.0),
			], 14, true, true, 3)
		"shin":
			# Unten offen: das Ende steckt im Schuh, eine Kappe wäre nie sichtbar.
			return build([
				_sec(-0.30, 0.049, 0.052, 1.0),
				_sec(-0.21, 0.056, 0.06, 1.0),
				_sec(-0.09, 0.075, 0.081, 1.0),
				_sec(0.0, 0.081, 0.084, 1.0),
			], 14, false, true, 3)
		"foot":
			# Wird im Szenenbaum um -90 Grad um X gedreht, deshalb liegt die
			# Schuhlänge hier noch auf der Y-Achse: rx = Breite, rz = Höhe.
			return build([
				_sec(0.0, 0.049, 0.038, 0.65),
				_sec(0.04, 0.055, 0.042, 0.6),
				_sec(0.1, 0.052, 0.036, 0.6),
				_sec(0.135, 0.04, 0.026, 0.7),
			], 12, true, true, 3)
		"head":
			# Eiform: Schädel oben breiter als das Kinn, Origin am Halsansatz.
			return build([
				_sec(0.04, 0.072, 0.078, 0.9),
				_sec(0.09, 0.098, 0.105, 0.9),
				_sec(0.15, 0.113, 0.122, 0.92),
				_sec(0.22, 0.115, 0.12, 0.95),
				_sec(0.27, 0.098, 0.1, 1.0),
			], 20, true, true, 5)
		"hair":
			# Sitzt als eigene Kappe knapp über dem Stirnband auf der
			# Schädelkalotte — tiefer angesetzt sähe es aus wie eine Mütze.
			return build([
				_sec(0.263, 0.104, 0.108, 0.95),
				_sec(0.272, 0.102, 0.105, 1.0),
			], 20, false, true, 4)
		"neck":
			return build([
				_sec(0.0, 0.062, 0.058, 1.0),
				_sec(0.06, 0.058, 0.055, 1.0),
			], 12, false, false, 0)
		"headband":
			# Team-farbenes Stirnband, Origin in der Mitte. Es sitzt knapp über
			# dem Schädel, damit man die Mannschaft auch dann noch erkennt, wenn
			# ein Trikot-Skin den ganzen Körper umfärbt.
			return build([
				_sec(-0.018, 0.112, 0.117, 0.93),
				_sec(0.018, 0.108, 0.113, 0.93),
			], 20, false, false, 0)
		"armband":
			return build([
				_sec(-0.022, 0.077, 0.077, 1.0),
				_sec(0.022, 0.076, 0.076, 1.0),
			], 12, false, false, 0)
	push_error("BodyMesh: unbekanntes Körperteil '%s'" % part)
	return ArrayMesh.new()

static func _sec(y: float, rx: float, rz: float, e: float) -> Dictionary:
	return {"y": y, "rx": rx, "rz": rz, "e": e}

## Zieht die Querschnitte (aufsteigend nach y) zu einer geschlossenen Fläche.
## `e` steuert die Form des Querschnitts: 1.0 = Ellipse, kleiner = kastiger.
static func build(sections: Array, radial: int, round_bottom: bool, round_top: bool, cap_steps: int) -> ArrayMesh:
	var rings: Array = []

	if round_bottom and cap_steps > 0:
		var s0: Dictionary = sections[0]
		var r0: float = (float(s0["rx"]) + float(s0["rz"])) * 0.5
		for k in range(cap_steps, 0, -1):
			var a: float = float(k) / float(cap_steps) * PI * 0.5
			rings.append(_sec(float(s0["y"]) - r0 * sin(a),
				float(s0["rx"]) * cos(a), float(s0["rz"]) * cos(a), float(s0["e"])))

	for s in sections:
		rings.append(s)

	if round_top and cap_steps > 0:
		var s1: Dictionary = sections[sections.size() - 1]
		var r1: float = (float(s1["rx"]) + float(s1["rz"])) * 0.5
		for k in range(1, cap_steps + 1):
			var a: float = float(k) / float(cap_steps) * PI * 0.5
			rings.append(_sec(float(s1["y"]) + r1 * sin(a),
				float(s1["rx"]) * cos(a), float(s1["rz"]) * cos(a), float(s1["e"])))

	# UV-Y läuft über die gesamte Bauhöhe, damit Muster nicht gestaucht werden.
	var y_min: float = float(rings[0]["y"])
	var y_max: float = float(rings[rings.size() - 1]["y"])
	var y_span: float = max(y_max - y_min, 0.0001)

	# Positionen einmal vorab in ein Gitter legen, die Normalen entstehen danach
	# aus den Nachbarpunkten (analytisch wäre bei Superellipsen fehleranfällig).
	var grid: Array = []
	for j in range(rings.size()):
		var row: Array = []
		for i in range(radial + 1):
			row.append(_ring_point(rings[j], i, radial))
		grid.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(rings.size() - 1):
		for i in range(radial):
			var p00: Vector3 = grid[j][i]
			var p10: Vector3 = grid[j][i + 1]
			var p11: Vector3 = grid[j + 1][i + 1]
			var p01: Vector3 = grid[j + 1][i]
			var n00 := _grid_normal(grid, j, i, radial, rings.size())
			var n10 := _grid_normal(grid, j, i + 1, radial, rings.size())
			var n11 := _grid_normal(grid, j + 1, i + 1, radial, rings.size())
			var n01 := _grid_normal(grid, j + 1, i, radial, rings.size())
			var u0: float = float(i) / float(radial)
			var u1: float = float(i + 1) / float(radial)
			var v0: float = 1.0 - (float(rings[j]["y"]) - y_min) / y_span
			var v1: float = 1.0 - (float(rings[j + 1]["y"]) - y_min) / y_span

			_vert(st, p00, n00, Vector2(u0, v0))
			_vert(st, p01, n01, Vector2(u0, v1))
			_vert(st, p11, n11, Vector2(u1, v1))

			_vert(st, p00, n00, Vector2(u0, v0))
			_vert(st, p11, n11, Vector2(u1, v1))
			_vert(st, p10, n10, Vector2(u1, v0))
	st.generate_tangents()
	return st.commit()

static func _vert(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)

## Punkt auf einem Querschnitt. Winkel 0 zeigt nach +Z (Rücken), damit UV.x = 0.5
## genau vorne auf der Brust landet.
static func _ring_point(ring: Dictionary, i: int, radial: int) -> Vector3:
	var theta: float = TAU * float(i) / float(radial)
	var s := sin(theta)
	var c := cos(theta)
	var e: float = float(ring["e"])
	var sx: float = signf(s) * pow(absf(s), e)
	var sz: float = signf(c) * pow(absf(c), e)
	return Vector3(float(ring["rx"]) * sx, float(ring["y"]), float(ring["rz"]) * sz)

static func _grid_normal(grid: Array, j: int, i: int, radial: int, ring_count: int) -> Vector3:
	var i_prev: int = posmod(i - 1, radial)
	var i_next: int = posmod(i + 1, radial)
	var j_prev: int = max(j - 1, 0)
	var j_next: int = min(j + 1, ring_count - 1)
	var tu: Vector3 = grid[j][i_next] - grid[j][i_prev]
	var tv: Vector3 = grid[j_next][i] - grid[j_prev][i]
	var n: Vector3 = tu.cross(tv)
	if n.length_squared() < 0.0000001:
		# Pol: dort entartet der Ring zu einem Punkt.
		var p: Vector3 = grid[j][i]
		var mid: Vector3 = grid[ring_count / 2][i]
		return Vector3.UP if p.y > mid.y else Vector3.DOWN
	return n.normalized()
