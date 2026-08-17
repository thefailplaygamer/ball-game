extends Node

const JerseyData := preload("res://scripts/jersey_data.gd")

## In-Memory-Cache des Spieler-Inventars (Trikots + Kisten). Die eigentlichen
## Daten liegen jetzt in der Supabase-Cloud-Datenbank (siehe supabase/schema.sql),
## nicht mehr lokal — das Kisten-Würfeln, das Tageslimit und die Ausrüsten-
## Prüfung laufen serverseitig in Postgres-Funktionen, damit niemand mehr
## durch Bearbeiten einer lokalen Datei an Kisten/Trikots kommt. Diese Werte
## hier sind nur ein Lesecache für die UI, gefüllt via load_from_cloud() nach
## dem Login und aktualisiert nach jeder erfolgreichen Server-Aktion.

signal inventory_changed

var owned: Dictionary = {0: 1} # Trikot-ID -> Anzahl (Dubletten zählen mit, wichtig für spätere Trade-Ups)
var crates: int = 0
var equipped: int = 0

func owns(id: int) -> bool:
	return get_count(id) > 0

func get_count(id: int) -> int:
	return owned.get(id, 0)

## Holt den aktuellen Stand aus der Cloud. Wird einmal direkt nach
## Login/Registrierung im Login-Screen aufgerufen.
func load_from_cloud() -> void:
	owned = {0: 1}
	crates = 0
	equipped = 0

	var player_rows = await Supabase.select("players", "select=crates,equipped")
	if player_rows is Array and player_rows.size() > 0:
		var row: Dictionary = player_rows[0]
		crates = int(row.get("crates", 0))
		equipped = int(row.get("equipped", 0))

	var inv_rows = await Supabase.select("inventory", "select=jersey_id,count")
	if inv_rows is Array:
		for row in inv_rows:
			owned[int(row["jersey_id"])] = int(row["count"])

	inventory_changed.emit()

## Rüstet ein Trikot aus. Der Server prüft den Besitz noch einmal selbst
## (equip_jersey()-Funktion), damit ein manipulierter Client kein fremdes
## Trikot ausrüsten kann.
func equip(id: int) -> bool:
	if not owns(id):
		return false
	var result = await Supabase.call_rpc("equip_jersey", {"p_jersey_id": id})
	if result != true:
		return false
	equipped = id
	inventory_changed.emit()
	return true

## Vom Host per RPC bei echtem Vollzeit-Ende ausgelöst. Das serverseitige
## Tageslimit wird in der award_crate()-Funktion durchgesetzt, nicht mehr
## hier — ein manipulierter Client kann es dadurch nicht umgehen.
func add_crate() -> void:
	var result = await Supabase.call_rpc("award_crate")
	if result == true:
		crates += 1
		inventory_changed.emit()

## Öffnet eine Kiste. Das Würfeln passiert serverseitig (open_crate()-
## Funktion, gewichtet nach Seltenheit) — der Client bekommt nur das Ergebnis
## zurück und kann es nicht selbst beeinflussen. Gibt die gewonnene
## Trikot-ID zurück, oder -1 bei keiner Kiste/keiner Verbindung.
func open_crate() -> int:
	if crates <= 0:
		return -1
	var result = await Supabase.call_rpc("open_crate")
	if not (result is Dictionary):
		return -1
	var id: int = int(result.get("jersey_id", -1))
	if id < 0:
		return -1
	crates = int(result.get("crates", crates))
	owned[id] = owned.get(id, 0) + 1
	inventory_changed.emit()
	return id
