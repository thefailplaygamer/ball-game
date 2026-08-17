extends Area3D

const BALL_RADIUS := 0.22

## team: welchem Team dieses Tor gehört (0 oder 1).
## Landet der Ball hier, bekommt das JEWEILS ANDERE Team einen Punkt.
@export var team: int = 0
## x-Position der Torlinie (Toröffnung in der Bande, nicht die Torbox selbst).
@export var goal_line_x: float = 0.0
## +1 wenn das Tor in +X-Richtung liegt, -1 wenn in -X-Richtung.
@export var into_goal_sign: float = 1.0

## Zählt erst, wenn der Ball mit vollem Umfang hinter der Torlinie ist, nicht
## schon beim ersten Berühren des Sensors (sonst zählen auch Pfosten-Treffer).
func _physics_process(_delta: float) -> void:
	if not Network.is_host():
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group("ball"):
			continue
		var depth := (body.global_position.x - goal_line_x) * into_goal_sign
		if depth >= BALL_RADIUS:
			var scoring_team := 1 - team
			get_tree().get_first_node_in_group("game_manager").on_goal_scored(scoring_team)
