extends Node

const MAX_ROOMS := 3
const ROOM_PORTS := [7778, 7779, 7780]
const EMPTY_GRACE := 90.0

var listed: Array = []

var _records: Array[Dictionary] = []
var _starting_ports: Dictionary[int, bool] = {}
var _next_id := 1
var _typed_password := ""
var _poll := 0.0


func _ready() -> void:
	if not Net.directory:
		return
	multiplayer.peer_connected.connect(_on_peer)
	print("Одновременно не больше %d комнат." % MAX_ROOMS)


func _process(delta: float) -> void:
	if not Net.directory:
		return
	_poll += delta
	if _poll < 1.0:
		return
	_poll = 0.0
	if _refresh_records():
		_broadcast()


func request_create(password: String, weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	_typed_password = password.strip_edges()
	net_request_create.rpc_id(1, _typed_password, weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)


func request_join(room_id: int, password: String) -> void:
	_typed_password = password.strip_edges()
	net_request_join.rpc_id(1, room_id, _typed_password)


@rpc("any_peer", "reliable")
func net_request_create(password: String, weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if not Net.directory or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var cleaned := password.strip_edges()
	if cleaned.is_empty() or cleaned.length() > 24 or cleaned.contains("\n") or cleaned.contains("\r"):
		_reply(sender, false, 0, "", "Введи пароль комнаты.")
		return
	if _records.size() + _starting_ports.size() >= MAX_ROOMS:
		_reply(sender, false, 0, "", "На сервере уже 3 комнаты.")
		return
	var port := _free_port()
	if port == 0:
		_reply(sender, false, 0, "", "На сервере уже 3 комнаты.")
		return
	_starting_ports[port] = true
	var rules := _clean_rules(weapons, arena, limits, difficulty, bot_count, size)
	var token := "%08x%08x" % [randi(), randi()]
	var folder := OS.get_cache_dir().path_join("shooter-rooms")
	DirAccess.make_dir_recursive_absolute(folder)
	var room_path := folder.path_join("room-%d.cfg" % port)
	var status_path := room_path + ".status"
	DirAccess.remove_absolute(status_path)
	var cfg := ConfigFile.new()
	cfg.set_value("room", "password", cleaned)
	cfg.set_value("room", "token", token)
	cfg.set_value("room", "weapons", rules.weapons)
	cfg.set_value("room", "arena", rules.arena)
	cfg.set_value("room", "time", rules.time)
	cfg.set_value("room", "kills", rules.kills)
	cfg.set_value("room", "difficulty", rules.difficulty)
	cfg.set_value("room", "bots", rules.bots)
	cfg.set_value("room", "size", rules.size)
	cfg.set_value("room", "teams", teams)
	cfg.set_value("room", "random_map", random_map)
	cfg.set_value("room", "blue_bots", clampi(blue_bots, -1, 10))
	if cfg.save(room_path) != OK:
		_starting_ports.erase(port)
		_reply(sender, false, 0, "", "Не удалось создать комнату.")
		return
	var pid := _spawn_match(port, room_path)
	if pid <= 0:
		DirAccess.remove_absolute(room_path)
		_starting_ports.erase(port)
		_reply(sender, false, 0, "", "Не удалось создать комнату.")
		return
	var ready := false
	for _attempt in 40:
		await get_tree().create_timer(0.2).timeout
		if not OS.is_process_running(pid):
			break
		var status := ConfigFile.new()
		if status.load(status_path) == OK and bool(status.get_value("room", "ready", false)):
			ready = true
			break
	if not ready:
		if OS.is_process_running(pid):
			OS.kill(pid)
		DirAccess.remove_absolute(room_path)
		DirAccess.remove_absolute(status_path)
		_starting_ports.erase(port)
		_reply(sender, false, 0, "", "Комната не запустилась.")
		return
	_records.append({
		"id": _next_id,
		"port": port,
		"pid": pid,
		"password": cleaned,
		"map_id": rules.arena,
		"players": 0,
		"playing": false,
		"status": status_path,
		"born": Time.get_unix_time_from_system(),
	})
	_starting_ports.erase(port)
	_next_id += 1
	print("Комната %d на UDP %d." % [_next_id - 1, port])
	_broadcast()
	_reply(sender, true, port, token, "")


@rpc("any_peer", "reliable")
func net_request_join(room_id: int, password: String) -> void:
	if not Net.directory or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var record := _record(room_id)
	if record.is_empty() or not OS.is_process_running(int(record.pid)):
		_reply(sender, false, 0, "", "Комната уже закрыта.")
		return
	if str(record.password) != password.strip_edges():
		_reply(sender, false, 0, "", "Неверный пароль.")
		return
	if int(record.players) >= Net.MAX_PLAYERS:
		_reply(sender, false, 0, "", "Комната заполнена.")
		return
	_reply(sender, true, int(record.port), "", "")


@rpc("authority", "reliable")
func net_directory_result(ok: bool, port: int, token: String, message: String) -> void:
	var lobby := _lobby()
	if not ok:
		_typed_password = ""
		if lobby:
			lobby.show_room_browser(message)
		return
	if lobby:
		lobby.show_internet_wait("Входим в комнату…")
	var err := Net.open_match(port, _typed_password, token)
	_typed_password = ""
	if err != OK:
		Net.notice = "Не удалось войти в комнату."
		var game := get_tree().current_scene
		if game and game.has_method("leave_round"):
			game.leave_round()


@rpc("authority", "reliable")
func net_directory_rooms(rooms: Array) -> void:
	listed = rooms
	var lobby := _lobby()
	if lobby and lobby.is_browsing():
		lobby.show_room_browser()


func _reply(peer: int, ok: bool, port: int, token: String, message: String) -> void:
	if multiplayer.get_peers().has(peer):
		net_directory_result.rpc_id(peer, ok, port, token, message)


func _on_peer(id: int) -> void:
	if multiplayer.get_peers().has(id):
		net_directory_rooms.rpc_id(id, _public_rooms())


func _record(room_id: int) -> Dictionary:
	for record in _records:
		if int(record.id) == room_id:
			return record
	return {}


func _free_port() -> int:
	for port in ROOM_PORTS:
		if _starting_ports.has(port):
			continue
		var used := false
		for record in _records:
			if int(record.port) == port:
				used = true
				break
		if not used:
			return port
	return 0


func _clean_rules(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int) -> Dictionary:
	var map := load("res://game/maps/map_builder.gd") as GDScript
	return {
		"weapons": clampi(weapons, 0, 2),
		"arena": clampi(arena, 0, map.MAP_NAMES.size() - 1),
		"time": clampi(limits.x, 0, 8),
		"kills": clampi(limits.y, 0, 8),
		"difficulty": clampi(difficulty, 0, 4),
		"bots": clampi(bot_count, 0, 10),
		"size": clampi(size, 0, map.SIZE_WIDTHS.size() - 1),
	}


func _spawn_match(port: int, room_path: String) -> int:
	var args := PackedStringArray(["--headless", "--", "--match-port", str(port), "--room-file", room_path])
	if OS.has_feature("editor"):
		args = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--match-port", str(port), "--room-file", room_path])
	return OS.create_process(OS.get_executable_path(), args, false)


func _refresh_records() -> bool:
	var changed := false
	var now := Time.get_unix_time_from_system()
	var alive: Array[Dictionary] = []
	for record in _records:
		var pid := int(record.pid)
		if not OS.is_process_running(pid):
			DirAccess.remove_absolute(str(record.status))
			print("Комната %d закрыта." % int(record.id))
			changed = true
			continue
		var status := ConfigFile.new()
		if status.load(str(record.status)) == OK:
			var players := int(status.get_value("room", "players", 0))
			var playing := bool(status.get_value("room", "playing", false))
			var arena := int(status.get_value("room", "arena", record.map_id))
			if players != int(record.players) or playing != bool(record.playing) or arena != int(record.map_id):
				record.players = players
				record.playing = playing
				record.map_id = arena
				changed = true
		if int(record.players) == 0 and now - float(record.born) > EMPTY_GRACE:
			OS.kill(pid)
			changed = true
		alive.append(record)
	_records = alive
	return changed


func _broadcast() -> void:
	var rooms := _public_rooms()
	for peer in multiplayer.get_peers():
		net_directory_rooms.rpc_id(peer, rooms)


func _public_rooms() -> Array:
	var rooms: Array = []
	for record in _records:
		rooms.append({
			"id": int(record.id),
			"map": int(record.map_id),
			"players": int(record.players),
			"playing": bool(record.playing),
		})
	return rooms


func _lobby() -> Control:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("HUD/Lobby")
