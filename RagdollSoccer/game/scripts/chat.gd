extends Node

signal message_received(sender_name: String, text: String)

func submit_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	if _handle_local_command(text):
		return
	if Network.is_host():
		_handle_chat(1, text)
	else:
		rpc_id(1, "_relay_chat", text)

@rpc("any_peer", "reliable")
func _relay_chat(text: String) -> void:
	if not Network.is_host():
		return
	_handle_chat(multiplayer.get_remote_sender_id(), text)

func _handle_chat(sender_id: int, text: String) -> void:
	if text.begins_with("/"):
		# Befehle werden nicht im Chat angezeigt, nur ausgewertet.
		_check_commands(sender_id, text)
		return
	var pname: String = Network.players.get(sender_id, "Spieler")
	_broadcast_chat.rpc(pname, text)

## Befehle, die rein informativ sind und keine Host-Autorität brauchen,
## werden direkt lokal beantwortet statt übers Netzwerk zu laufen.
func _handle_local_command(text: String) -> bool:
	var normalized := text.to_lower()
	if normalized == "/ping":
		var my_id := 1
		if multiplayer.multiplayer_peer:
			my_id = Network.get_my_id()
		var ms: int = Network.pings.get(my_id, 0)
		message_received.emit("System", "Dein Ping: %d ms" % ms)
		return true
	if normalized == "/help":
		message_received.emit("System", _help_text())
		return true
	return false

func _help_text() -> String:
	var lines := "Befehle: /vs, /votestart, /vw, /votewarmup, /ping, /help"
	if Network.is_host():
		lines += "\nHost: /dummy, /cleardummies, /start, /pause, /resume, /halftime, /settime <s|mm:ss>, /addtime <s>, /end, /kick <Name>, /swap <Name>"
	return lines

func _check_commands(sender_id: int, text: String) -> void:
	var normalized := text.strip_edges().to_lower()
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return

	# Befehle, die jeder Spieler nutzen darf.
	if normalized == "/vs" or normalized == "/votestart":
		gm.register_ready_vote(sender_id)
		return
	if normalized == "/vw" or normalized == "/votewarmup":
		gm.register_reset_vote(sender_id)
		return

	# Ab hier: nur der Lobby-Host (immer Peer-ID 1) darf die Befehle ausführen.
	if sender_id != 1:
		return
	if normalized == "/dummy" or normalized == "/bot":
		gm.spawn_dummy(sender_id)
	elif normalized == "/cleardummies" or normalized == "/clearbots":
		gm.clear_dummies()
	elif normalized == "/start" or normalized == "/forcestart":
		gm.force_start()
	elif normalized == "/pause":
		gm.set_paused(true)
	elif normalized == "/resume" or normalized == "/unpause":
		gm.set_paused(false)
	elif normalized == "/halftime":
		gm.force_halftime()
	elif normalized == "/end" or normalized == "/endgame" or normalized == "/stop":
		gm.force_end()
	elif normalized.begins_with("/settime"):
		var seconds := _parse_seconds(_arg_after(text, "/settime"))
		if not is_nan(seconds):
			gm.set_time_remaining(max(seconds, 0.0))
	elif normalized.begins_with("/addtime"):
		var delta_seconds := _parse_seconds(_arg_after(text, "/addtime"))
		if not is_nan(delta_seconds):
			gm.add_time(delta_seconds)
	elif normalized.begins_with("/kick"):
		var kick_name := _arg_after(text, "/kick")
		if kick_name != "":
			gm.kick_player(kick_name)
	elif normalized.begins_with("/swap"):
		var swap_name := _arg_after(text, "/swap")
		if swap_name != "":
			gm.swap_player_team(swap_name)

## Schneidet den Befehlsnamen vom Original-Text ab (nicht vom lowercase-Text),
## damit z.B. Spielernamen bei /kick und /swap ihre Groß-/Kleinschreibung behalten.
func _arg_after(text: String, command: String) -> String:
	return text.strip_edges().substr(command.length()).strip_edges()

## Erlaubt entweder reine (auch negative) Sekunden ("90", "-15") oder
## Minuten:Sekunden ("1:30"). Gibt NAN bei ungültiger Eingabe zurück.
func _parse_seconds(arg: String) -> float:
	if arg == "":
		return NAN
	if arg.find(":") != -1:
		var parts := arg.split(":")
		if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
			return NAN
		var minutes: float = parts[0].to_float()
		var secs: float = parts[1].to_float()
		return minutes * 60.0 + secs
	if not arg.is_valid_float():
		return NAN
	return arg.to_float()

@rpc("call_local", "reliable")
func _broadcast_chat(sender_name: String, text: String) -> void:
	message_received.emit(sender_name, text)
