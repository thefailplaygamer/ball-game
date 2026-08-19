extends Node3D

## Prozedurale Stadion-Kulisse rund um die Spielfläche.
##
## Gebaut wird alles aus EINEM Prinzip: ein Profil (eine Linienkette aus
## "wie weit nach außen / wie weit nach oben") wird entlang eines abgerundeten
## Rechtecks um das Spielfeld herumgezogen. Damit entstehen Tribünenränge,
## Sockelmauer, Außenfassade und Dach ohne ein einziges von Hand gesetztes Mesh
## — und die Ecken schließen sauber, statt wie bei vier einzelnen Quader-
## Tribünen zu klaffen.
##
## Die UV der erzeugten Flächen sind bewusst KEINE 0..1-Koordinaten:
##   UV.x = Meter entlang der Tribüne, UV.y = Rangnummer (bzw. Meter in der Höhe).
## Die Shader rechnen damit direkt in echten Maßen (Sitzabstand, Plattenraster).

const CROWD_SHADER := preload("res://shaders/stadium_crowd.gdshader")
const CONCRETE_SHADER := preload("res://shaders/stadium_concrete.gdshader")
const LED_SHADER := preload("res://shaders/stadium_led.gdshader")

@export var inner_half_x := 18.0
@export var inner_half_z := 11.6
@export var corner_radius := 6.5
## Höhe der Sockelmauer unter dem ersten Rang.
@export var wall_height := 1.35
@export var rows := 24
@export var row_tread := 0.55
@export var row_rise := 0.44
## Lichte Höhe zwischen oberstem Rang und Dachunterkante.
@export var roof_gap := 5.2
@export var roof_thickness := 0.55
@export var roof_overhang := 2.4
@export var path_spacing := 0.75

@export var team_a_color := Color(0.85, 0.2, 0.2)
@export var team_b_color := Color(0.2, 0.4, 0.9)

@export var build_floodlights := true
@export var build_goals := true
@export var build_led_boards := true
## Torlinie und Torpfostenabstand, für die sichtbaren Torrahmen.
@export var goal_line_x := 14.0
@export var goal_post_z := 1.91
@export var goal_height := 3.0

var _path_pos: PackedVector2Array = PackedVector2Array()
var _path_nrm: PackedVector2Array = PackedVector2Array()
var _path_dist: PackedFloat32Array = PackedFloat32Array()
var _path_len := 0.0

func _ready() -> void:
	_build_path()
	_build_bowl()
	_build_roof()
	if build_led_boards:
		_build_led_boards()
	if build_goals:
		_build_goal_frames()
	if build_floodlights:
		_build_floodlights()

# --------------------------------------------------------------------------
# Grundriss
# --------------------------------------------------------------------------

func _build_path() -> void:
	var sx: float = inner_half_x - corner_radius
	var sz: float = inner_half_z - corner_radius
	_path_pos.clear()
	_path_nrm.clear()

	_add_line(Vector2(inner_half_x, -sz), Vector2(inner_half_x, sz), Vector2(1, 0))
	_add_arc(Vector2(sx, sz), 0.0, PI * 0.5)
	_add_line(Vector2(sx, inner_half_z), Vector2(-sx, inner_half_z), Vector2(0, 1))
	_add_arc(Vector2(-sx, sz), PI * 0.5, PI)
	_add_line(Vector2(-inner_half_x, sz), Vector2(-inner_half_x, -sz), Vector2(-1, 0))
	_add_arc(Vector2(-sx, -sz), PI, PI * 1.5)
	_add_line(Vector2(-sx, -inner_half_z), Vector2(sx, -inner_half_z), Vector2(0, -1))
	_add_arc(Vector2(sx, -sz), PI * 1.5, TAU)

	# Laufende Bogenlänge, sie wird später zur UV-X in Metern.
	_path_dist.resize(_path_pos.size())
	var d := 0.0
	for i in range(_path_pos.size()):
		if i > 0:
			d += _path_pos[i].distance_to(_path_pos[i - 1])
		_path_dist[i] = d
	_path_len = d + _path_pos[_path_pos.size() - 1].distance_to(_path_pos[0])

## Fügt eine Gerade hinzu (ohne den Endpunkt, den liefert das nächste Stück).
func _add_line(a: Vector2, b: Vector2, n: Vector2) -> void:
	var steps: int = max(1, int(ceil(a.distance_to(b) / path_spacing)))
	for i in range(steps):
		_path_pos.append(a.lerp(b, float(i) / float(steps)))
		_path_nrm.append(n)

## Fügt einen Eckbogen hinzu (ohne den Endpunkt).
func _add_arc(center: Vector2, a0: float, a1: float) -> void:
	var arc_len: float = abs(a1 - a0) * corner_radius
	var steps: int = max(2, int(ceil(arc_len / path_spacing)))
	for i in range(steps):
		var a: float = lerp(a0, a1, float(i) / float(steps))
		var n := Vector2(cos(a), sin(a))
		_path_pos.append(center + n * corner_radius)
		_path_nrm.append(n)

# --------------------------------------------------------------------------
# Sweep-Kern
# --------------------------------------------------------------------------

## Zieht eine Liste von Profil-Abschnitten einmal komplett um das Spielfeld.
## Jeder Abschnitt ist ein Dictionary:
##   a, b : Vector2(nach außen, nach oben) — Anfangs- und Endpunkt im Profil
##   va, vb : UV-Y an diesen beiden Punkten
##   n    : Vector2(Außen-Anteil, Hoch-Anteil) der Flächennormale
func _sweep(segments: Array, mat: Material, node_name: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = _path_pos.size()

	for seg in segments:
		var pa: Vector2 = seg["a"]
		var pb: Vector2 = seg["b"]
		var va: float = seg["va"]
		var vb: float = seg["vb"]
		var pn: Vector2 = seg["n"]
		for i in range(count):
			var j: int = (i + 1) % count
			var oi: Vector2 = _path_pos[i]
			var oj: Vector2 = _path_pos[j]
			var ni: Vector2 = _path_nrm[i]
			var nj: Vector2 = _path_nrm[j]
			var di: float = _path_dist[i]
			var dj: float = _path_dist[j] if j > 0 else _path_len

			var v0 := _pt(oi, ni, pa)
			var v1 := _pt(oj, nj, pa)
			var v2 := _pt(oj, nj, pb)
			var v3 := _pt(oi, ni, pb)
			var n0 := _nrm(ni, pn)
			var n1 := _nrm(nj, pn)

			_tri(st, v0, n0, Vector2(di, va), v1, n1, Vector2(dj, va), v2, n1, Vector2(dj, vb))
			_tri(st, v0, n0, Vector2(di, va), v2, n1, Vector2(dj, vb), v3, n0, Vector2(di, vb))

	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	# Die Kulisse wirft keine Schatten aufs Spielfeld, spart Schattenpasses.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _pt(pos: Vector2, nrm: Vector2, profile: Vector2) -> Vector3:
	return Vector3(pos.x + nrm.x * profile.x, profile.y, pos.y + nrm.y * profile.x)

func _nrm(nrm: Vector2, pn: Vector2) -> Vector3:
	return Vector3(nrm.x * pn.x, pn.y, nrm.y * pn.x).normalized()

func _tri(st: SurfaceTool, a: Vector3, na: Vector3, ua: Vector2,
		b: Vector3, nb: Vector3, ub: Vector2,
		c: Vector3, nc: Vector3, uc: Vector2) -> void:
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)

# --------------------------------------------------------------------------
# Tribüne
# --------------------------------------------------------------------------

func _bowl_depth() -> float:
	return float(rows) * row_tread

func _bowl_top() -> float:
	return wall_height + float(rows) * row_rise

func _build_bowl() -> void:
	# Umlaufender Vorplatz zwischen Spielfeldrand und Tribüne. Ohne ihn klafft
	# dort eine Lücke, durch die man die (sandfarbene) Grundfarbe des Himmels
	# sieht — von innen wirkte das wie ein heller Streifen um das Feld herum.
	# Liegt bewusst 2 cm unter der Rasenoberkante, damit es dort, wo sich beide
	# überlappen, keine Z-Fighting-Flimmerkante gibt.
	var apron_mat := ShaderMaterial.new()
	apron_mat.shader = CONCRETE_SHADER
	apron_mat.set_shader_parameter("base_color", Color(0.11, 0.12, 0.13))
	apron_mat.set_shader_parameter("panel_size", 2.0)
	apron_mat.set_shader_parameter("stain_strength", 0.2)
	_sweep([
		{"a": Vector2(-3.5, -0.02), "b": Vector2(0.0, -0.02), "va": 0.0, "vb": 3.5, "n": Vector2(0, 1)},
	], apron_mat, "Apron")

	# Sockelmauer unter dem ersten Rang.
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = CONCRETE_SHADER
	wall_mat.set_shader_parameter("base_color", Color(0.13, 0.14, 0.16))
	wall_mat.set_shader_parameter("panel_size", 3.0)
	_sweep([
		{"a": Vector2(0.0, 0.0), "b": Vector2(0.0, wall_height), "va": 0.0, "vb": wall_height, "n": Vector2(-1, 0)},
	], wall_mat, "PerimeterWall")

	# Ränge: pro Reihe erst die senkrechte Stufenwange (dort sitzt das Publikum),
	# dann die waagerechte Trittstufe.
	var crowd_mat := ShaderMaterial.new()
	crowd_mat.shader = CROWD_SHADER
	crowd_mat.set_shader_parameter("team_a_color", team_a_color)
	crowd_mat.set_shader_parameter("team_b_color", team_b_color)
	crowd_mat.set_shader_parameter("seat_color_a", team_a_color.darkened(0.55))
	crowd_mat.set_shader_parameter("seat_color_b", team_b_color.darkened(0.55))

	var segs: Array = []
	for i in range(rows):
		var out0: float = float(i) * row_tread
		var out1: float = float(i + 1) * row_tread
		var y0: float = wall_height + float(i) * row_rise
		var y1: float = y0 + row_rise
		segs.append({"a": Vector2(out0, y0), "b": Vector2(out0, y1),
			"va": float(i), "vb": float(i) + 0.5, "n": Vector2(-1, 0)})
		segs.append({"a": Vector2(out0, y1), "b": Vector2(out1, y1),
			"va": float(i) + 0.5, "vb": float(i) + 1.0, "n": Vector2(0, 1)})
	_sweep(segs, crowd_mat, "Stands")

	# Außenfassade: schließt die Tribüne nach hinten ab, sonst schaut man von
	# außen (Replay-Kamera, Menü-Orbit) durch die Ränge ins Nichts.
	var facade_mat := ShaderMaterial.new()
	facade_mat.shader = CONCRETE_SHADER
	facade_mat.set_shader_parameter("base_color", Color(0.16, 0.17, 0.19))
	facade_mat.set_shader_parameter("panel_size", 3.4)
	facade_mat.set_shader_parameter("stain_strength", 0.55)
	var depth := _bowl_depth()
	var top := _bowl_top()
	_sweep([
		{"a": Vector2(depth, 0.0), "b": Vector2(depth, top), "va": 0.0, "vb": top, "n": Vector2(1, 0)},
	], facade_mat, "Facade")

# --------------------------------------------------------------------------
# Dach
# --------------------------------------------------------------------------

func _build_roof() -> void:
	var depth := _bowl_depth()
	var top := _bowl_top()
	var y_under: float = top + roof_gap
	var y_top: float = y_under + roof_thickness
	# Das Dach kragt über die vordersten Ränge aus, reicht aber bewusst nicht
	# bis über das Spielfeld.
	var inner_out := 1.5
	var outer_out: float = depth + roof_overhang

	var roof_mat := ShaderMaterial.new()
	roof_mat.shader = CONCRETE_SHADER
	roof_mat.set_shader_parameter("base_color", Color(0.19, 0.2, 0.23))
	roof_mat.set_shader_parameter("panel_size", 4.0)
	roof_mat.set_shader_parameter("stain_strength", 0.3)

	_sweep([
		# Unterseite
		{"a": Vector2(inner_out, y_under), "b": Vector2(outer_out, y_under),
			"va": 0.0, "vb": outer_out - inner_out, "n": Vector2(0, -1)},
		# Oberseite
		{"a": Vector2(inner_out, y_top), "b": Vector2(outer_out, y_top),
			"va": 0.0, "vb": outer_out - inner_out, "n": Vector2(0, 1)},
		# Vordere Blende
		{"a": Vector2(inner_out, y_under), "b": Vector2(inner_out, y_top),
			"va": 0.0, "vb": roof_thickness, "n": Vector2(-1, 0)},
		# Hintere Kante
		{"a": Vector2(outer_out, y_under), "b": Vector2(outer_out, y_top),
			"va": 0.0, "vb": roof_thickness, "n": Vector2(1, 0)},
	], roof_mat, "Roof")

	# Lichtband an der Dachunterkante.
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.9, 0.93, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.85, 0.9, 1.0)
	strip_mat.emission_energy_multiplier = 3.5
	strip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sweep([
		{"a": Vector2(inner_out + 0.25, y_under - 0.06), "b": Vector2(inner_out + 0.95, y_under - 0.06),
			"va": 0.0, "vb": 0.7, "n": Vector2(0, -1)},
	], strip_mat, "RoofLightStrip")

	# Dachstützen im Abstand von rund 9 m, damit das Dach nicht schwebt.
	var pillar_mat := ShaderMaterial.new()
	pillar_mat.shader = CONCRETE_SHADER
	pillar_mat.set_shader_parameter("base_color", Color(0.14, 0.15, 0.17))
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.22
	pillar_mesh.bottom_radius = 0.28
	pillar_mesh.height = y_under
	pillar_mesh.radial_segments = 10
	var pillars := Node3D.new()
	pillars.name = "RoofPillars"
	add_child(pillars)
	var spacing := 9.0
	var n_pillars: int = max(4, int(_path_len / spacing))
	for i in range(n_pillars):
		var target: float = float(i) * (_path_len / float(n_pillars))
		var idx := _index_at_distance(target)
		var pos: Vector2 = _path_pos[idx]
		var nrm: Vector2 = _path_nrm[idx]
		var out: float = depth + roof_overhang * 0.4
		var mi := MeshInstance3D.new()
		mi.mesh = pillar_mesh
		mi.material_override = pillar_mat
		mi.position = Vector3(pos.x + nrm.x * out, y_under * 0.5, pos.y + nrm.y * out)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillars.add_child(mi)

func _index_at_distance(d: float) -> int:
	for i in range(_path_dist.size()):
		if _path_dist[i] >= d:
			return i
	return _path_dist.size() - 1

# --------------------------------------------------------------------------
# Bandenwerbung
# --------------------------------------------------------------------------

func _build_led_boards() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = LED_SHADER
	mat.set_shader_parameter("color_a", team_a_color)
	mat.set_shader_parameter("color_b", team_b_color)

	var holder := Node3D.new()
	holder.name = "LedBoards"
	add_child(holder)

	# Längsseiten direkt hinter den Glaswänden, dazu je eine Bande hinter den Toren.
	_led_run(holder, mat, Vector3(-14.2, 0.0, 9.75), Vector3(14.2, 0.0, 9.75), Vector3(0, 0, -1), 0.95)
	_led_run(holder, mat, Vector3(14.2, 0.0, -9.75), Vector3(-14.2, 0.0, -9.75), Vector3(0, 0, 1), 0.95)
	_led_run(holder, mat, Vector3(16.95, 0.0, 4.4), Vector3(16.95, 0.0, -4.4), Vector3(-1, 0, 0), 0.95)
	_led_run(holder, mat, Vector3(-16.95, 0.0, -4.4), Vector3(-16.95, 0.0, 4.4), Vector3(1, 0, 0), 0.95)

## Eine gerade Bande als aufrechtes Rechteck von `a` nach `b`, Schauseite `facing`.
func _led_run(parent: Node3D, mat: Material, a: Vector3, b: Vector3, facing: Vector3, height: float) -> void:
	var length := a.distance_to(b)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP * height
	var n := facing.normalized()
	var v0 := a
	var v1 := b
	var v2 := b + up
	var v3 := a + up
	_tri(st, v0, n, Vector2(0.0, 0.0), v1, n, Vector2(length, 0.0), v2, n, Vector2(length, 1.0))
	_tri(st, v0, n, Vector2(0.0, 0.0), v2, n, Vector2(length, 1.0), v3, n, Vector2(0.0, 1.0))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

# --------------------------------------------------------------------------
# Torrahmen
# --------------------------------------------------------------------------

## Sichtbare Pfosten und Latte. Sie sitzen bewusst exakt auf den Innenflächen
## der bereits vorhandenen Tor-Kollisionswände, damit sie rein optisch bleiben
## und die Ballphysik nicht verändern.
func _build_goal_frames() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.96, 0.97)
	mat.roughness = 0.35
	mat.metallic = 0.25

	var holder := Node3D.new()
	holder.name = "GoalFrames"
	add_child(holder)

	var post_r := 0.06
	var bar_y: float = goal_height + post_r
	for s in [-1.0, 1.0]:
		var x: float = s * goal_line_x
		for pz in [-goal_post_z, goal_post_z]:
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = post_r
			pm.bottom_radius = post_r
			pm.height = bar_y
			pm.radial_segments = 12
			post.mesh = pm
			post.material_override = mat
			post.position = Vector3(x, bar_y * 0.5, pz)
			holder.add_child(post)
		var bar := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = post_r
		bm.bottom_radius = post_r
		bm.height = goal_post_z * 2.0 + post_r * 2.0
		bm.radial_segments = 12
		bar.mesh = bm
		bar.material_override = mat
		bar.position = Vector3(x, bar_y, 0.0)
		bar.rotation_degrees = Vector3(90, 0, 0)
		holder.add_child(bar)

# --------------------------------------------------------------------------
# Flutlicht
# --------------------------------------------------------------------------

func _build_floodlights() -> void:
	var holder := Node3D.new()
	holder.name = "Floodlights"
	add_child(holder)

	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color(0.16, 0.17, 0.2)
	mast_mat.roughness = 0.6
	mast_mat.metallic = 0.5

	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.98, 0.92)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.97, 0.88)
	lamp_mat.emission_energy_multiplier = 9.0

	var mast_height := 24.0
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c in corners:
		var base := Vector3(c.x * 25.5, 0.0, c.y * 19.5)
		var mast := Node3D.new()
		mast.position = base
		holder.add_child(mast)

		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.35
		pm.bottom_radius = 0.75
		pm.height = mast_height
		pm.radial_segments = 12
		pole.mesh = pm
		pole.material_override = mast_mat
		pole.position = Vector3(0, mast_height * 0.5, 0)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mast.add_child(pole)

		# Leuchtenträger, zur Spielfeldmitte gedreht. Die Drehung wird direkt
		# gerechnet statt per look_at: der Mast hängt noch nicht im Baum, wenn
		# der Kopf gebaut wird, und look_at bräuchte eine gültige Welt-Transform.
		var yaw: float = atan2(base.x, base.z)
		var horizontal: float = Vector2(base.x, base.z).length()
		var pitch: float = atan2(mast_height, max(horizontal, 0.01))
		var head := Node3D.new()
		head.position = Vector3(0, mast_height, 0)
		head.rotation = Vector3(-pitch, yaw, 0.0)
		mast.add_child(head)

		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(6.0, 2.6, 0.35)
		frame.mesh = fm
		frame.material_override = mast_mat
		frame.position = Vector3(0, 0, -0.3)
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(frame)

		for row in range(2):
			for col in range(5):
				var lamp := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(0.95, 0.95, 0.12)
				lamp.mesh = lm
				lamp.material_override = lamp_mat
				lamp.position = Vector3(-2.2 + float(col) * 1.1, -0.6 + float(row) * 1.2, -0.52)
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				head.add_child(lamp)

		# Ein echter Lichtkegel pro Mast, bewusst ohne Schatten: die Kulisse
		# soll die Stimmung tragen, nicht vier zusätzliche Schattenpasses kosten.
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, mast_height - 0.5, 0)
		spot.rotation = Vector3(-pitch, yaw, 0.0)
		spot.light_color = Color(0.92, 0.95, 1.0)
		spot.light_energy = 2.2
		spot.spot_range = 60.0
		spot.spot_angle = 42.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = false
		mast.add_child(spot)
