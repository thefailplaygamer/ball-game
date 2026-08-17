extends Node

## Zentrale Schnittstelle zum Supabase-Backend (Auth + Datenbank-Funktionen
## aus supabase/schema.sql). Ersetzt die frühere rein lokale
## user://inventory.json-Speicherung: der Login-Status lebt hier, das
## eigentliche Inventar wird nach dem Login von Inventory (siehe
## inventory.gd) aus der Cloud in den Arbeitsspeicher geladen.
##
## Alle Requests laufen wie schon bei menu.gd's _load_patch_notes() über
## einen kurzlebigen HTTPRequest-Node statt eines SDKs.

const SUPABASE_URL := "https://vbeqextztbhzwckrxpsl.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZiZXFleHR6dGJoendja3J4cHNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MTQ0NDYsImV4cCI6MjEwMjQ5MDQ0Nn0.m_LX5ZgzPc_YZnrtJoV8GaQw1ViqdPovRrFOuNpGzaA"

## Supabase Auth erwartet eine E-Mail-Adresse; da wir reine Benutzername/
## Passwort-Accounts wollen, wird daraus intern eine synthetische, für den
## Spieler unsichtbare E-Mail gebaut. Der echte Benutzername kommt separat
## als Metadata mit und landet über den DB-Trigger in players.username.
const EMAIL_DOMAIN := "@ballgame-account.com"

const SESSION_PATH := "user://session.dat"

## Wird ausgelöst wenn sich der Login-Status ändert (Login/Logout/Auto-Login).
signal auth_changed(logged_in: bool)

var access_token: String = ""
var refresh_token: String = ""
var user_id: String = ""
var username: String = ""

func is_logged_in() -> bool:
	return access_token != "" and user_id != ""

## Registriert einen neuen Account. Gibt bei Erfolg "" zurück, sonst eine
## Fehlermeldung, die direkt im Login-Screen angezeigt werden kann.
func register(uname: String, password: String) -> String:
	var body := {
		"email": _username_to_email(uname),
		"password": password,
		"data": {"username": uname},
	}
	var result: Dictionary = await _request("POST", "/auth/v1/signup", body, false)
	if result["error"] != "":
		return _translate_auth_error(result["error"], result["code"])
	return _apply_auth_response(result["data"], uname)

func login(uname: String, password: String) -> String:
	var body := {"email": _username_to_email(uname), "password": password}
	var result: Dictionary = await _request("POST", "/auth/v1/token?grant_type=password", body, false)
	if result["error"] != "":
		return _translate_auth_error(result["error"], result["code"])
	return _apply_auth_response(result["data"], uname)

## Versucht beim Spielstart automatisch mit einem lokal gespeicherten
## Refresh-Token einzuloggen, damit man sich nicht bei jedem Start neu
## anmelden muss. Gibt true zurück wenn's geklappt hat.
func try_auto_login() -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	var saved_refresh_token := f.get_as_text().strip_edges()
	f.close()
	if saved_refresh_token == "":
		return false

	var body := {"refresh_token": saved_refresh_token}
	var result: Dictionary = await _request("POST", "/auth/v1/token?grant_type=refresh_token", body, false)
	if result["error"] != "":
		return false

	var data: Dictionary = result["data"]
	access_token = data.get("access_token", "")
	refresh_token = data.get("refresh_token", "")
	var user: Dictionary = data.get("user", {})
	user_id = user.get("id", "")
	username = user.get("user_metadata", {}).get("username", "")
	if access_token == "" or user_id == "":
		return false

	_save_session()
	auth_changed.emit(true)
	return true

func logout() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	username = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	auth_changed.emit(false)

## Ruft eine der Postgres-Funktionen aus supabase/schema.sql auf (open_crate,
## award_crate, equip_jersey). Gibt bei Erfolg das JSON-Ergebnis zurück
## (Dictionary, bool, ...), bei Fehler/keiner Verbindung null.
##
## Heißt bewusst nicht "rpc" — das ist bereits eine eingebaute Node-Methode
## für Godots eigenes Multiplayer-RPC-System, ein gleichnamiges Override
## verhindert sonst, dass dieses Autoload überhaupt geladen wird.
func call_rpc(fn_name: String, params: Dictionary = {}) -> Variant:
	var result: Dictionary = await _request("POST", "/rest/v1/rpc/%s" % fn_name, params, true)
	if result["error"] != "":
		push_warning("Supabase RPC '%s' fehlgeschlagen: %s" % [fn_name, result["error"]])
		return null
	return result["data"]

## Liest Zeilen aus einer Tabelle (RLS erlaubt ohnehin nur die eigenen).
## query_suffix z.B. "select=*" oder "select=jersey_id,count".
func select(table: String, query_suffix: String = "select=*") -> Variant:
	var result: Dictionary = await _request("GET", "/rest/v1/%s?%s" % [table, query_suffix], {}, true)
	if result["error"] != "":
		push_warning("Supabase select '%s' fehlgeschlagen: %s" % [table, result["error"]])
		return null
	return result["data"]

func _username_to_email(uname: String) -> String:
	return uname.to_lower().strip_edges() + EMAIL_DOMAIN

func _apply_auth_response(data: Dictionary, uname: String) -> String:
	access_token = data.get("access_token", "")
	refresh_token = data.get("refresh_token", "")
	var user: Dictionary = data.get("user", {})
	user_id = user.get("id", "")
	username = uname
	if access_token == "" or user_id == "":
		return "Unerwartete Antwort vom Server."
	_save_session()
	auth_changed.emit(true)
	return ""

func _save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	f.store_string(refresh_token)
	f.close()

## Führt einen einzelnen HTTP-Request gegen die Supabase-API aus. Wirft nie
## Exceptions, sondern gibt immer {"data": ..., "error": String, "code": int}
## zurück, damit Aufrufer sauber zwischen "kein Internet", "falsches
## Passwort" usw. unterscheiden können.
func _request(method: String, path: String, body: Dictionary, authorized: bool) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := ["Content-Type: application/json", "apikey: %s" % SUPABASE_ANON_KEY]
	if authorized and access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	else:
		headers.append("Authorization: Bearer %s" % SUPABASE_ANON_KEY)
	if method == "POST":
		headers.append("Prefer: return=representation")

	var json_body := JSON.stringify(body) if method == "POST" else ""
	var http_method := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err := http.request(SUPABASE_URL + path, headers, http_method, json_body)
	if err != OK:
		http.queue_free()
		return {"data": null, "error": "Verbindung fehlgeschlagen.", "code": 0}

	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var raw_body: PackedByteArray = response[3]
	var parsed = JSON.parse_string(raw_body.get_string_from_utf8()) if raw_body.size() > 0 else null

	if code < 200 or code >= 300:
		var msg := "Serverfehler (%d)" % code
		if parsed is Dictionary:
			msg = parsed.get("msg", parsed.get("message", parsed.get("error_description", msg)))
		return {"data": null, "error": msg, "code": code}

	return {"data": parsed, "error": "", "code": code}

func _translate_auth_error(raw_msg: String, code: int) -> String:
	var lower := raw_msg.to_lower()
	if code == 0:
		return "Keine Internetverbindung."
	if "already registered" in lower or "already exists" in lower or code == 422:
		return "Dieser Benutzername ist bereits vergeben."
	if "invalid login credentials" in lower:
		return "Benutzername oder Passwort falsch."
	if "password" in lower and ("least" in lower or "short" in lower or "characters" in lower):
		return "Passwort ist zu kurz (mindestens 6 Zeichen)."
	return raw_msg
