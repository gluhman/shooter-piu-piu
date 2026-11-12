extends Node

const PORT := 7777
const CHANNEL_COUNT := 4
const Balance := preload("res://game/combat/combat_balance.gd")
const MAX_PLAYERS: int = Balance.MATCH.max_players_total
const MAX_NAME_LENGTH := 24
const INTERNET_ADDRESS := "136.234.32.193"

signal joined
signal connection_failed
signal host_lost

var active := false
var solo := false
var dedicated := false
var directory := false
var match_server := false
var match_client := false
var browsing := false
var internet := false
var pending_password := ""
var pending_token := ""
var room_file := ""
var room_status_path := ""
var notice := ""
var last_failure := ""
var last_ip := ""
var display_name := ""
var client_session := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://net.cfg") == OK:
		last_ip = str(config.get_value("net", "ip", ""))
		display_name = clean_display_name(str(config.get_value("net", "display_name", "")))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var match_port := _user_arg("--match-port")
	room_file = _user_arg("--room-file")
	if match_port != "":
		room_status_path = room_file + ".status"
		var match_err := host_match(match_port.to_int())
		if match_err != OK:
			print("Не удалось открыть UDP-порт %s." % match_port)
			get_tree().quit(1)
	elif _wants_dedicated():
		var err := host_dedicated()
		if err != OK:
			print("Не удалось открыть UDP-порт %d." % PORT)
			get_tree().quit(1)


func local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func lan_addresses() -> PackedStringArray:
	var preferred := PackedStringArray()
	var rest := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127."):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			preferred.append(address)
		else:
			rest.append(address)
	preferred.append_array(rest)
	return preferred


func remember_ip(ip: String) -> void:
	last_ip = ip
	_save_preferences()


func remember_display_name(value: String) -> void:
	var cleaned := clean_display_name(value)
	if cleaned == display_name:
		return
	display_name = cleaned
	_save_preferences()


func clean_display_name(value: String) -> String:
	var result := ""
	var candidate := value.strip_edges().substr(0, MAX_NAME_LENGTH)
	for index in candidate.length():
		var code := candidate.unicode_at(index)
		if code >= 32 and (code < 127 or code >= 160) and (code < 0x2028 or code > 0x202E):
			result += candidate[index]
	return result.strip_edges()


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("net", "ip", last_ip)
	config.set_value("net", "display_name", display_name)
	config.save("user://net.cfg")


func play_solo() -> void:
	_close()
	solo = true


func host_game() -> Error:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1, CHANNEL_COUNT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	return OK


func host_dedicated() -> Error:
	var err := _listen(PORT, 32)
	if err != OK:
		return err
	dedicated = true
	directory = true
	print("Интернет-сервер слушает UDP %d. Игроки заходят на %s." % [PORT, INTERNET_ADDRESS])
	return OK


func host_match(port: int) -> Error:
	var err := _listen(port, MAX_PLAYERS)
	if err != OK:
		return err
	dedicated = true
	match_server = true
	print("Комната слушает UDP %d." % port)
	return OK


func _listen(port: int, clients: int) -> Error:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, clients, CHANNEL_COUNT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	return OK


func join_game(ip: String) -> Error:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT, CHANNEL_COUNT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	return OK


func join_internet() -> Error:
	var err := join_game(INTERNET_ADDRESS)
	if err == OK:
		internet = true
		browsing = true
	return err


func open_match(port: int, password: String, token: String) -> Error:
	client_session = false
	notice = ""
	_close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(INTERNET_ADDRESS, port, CHANNEL_COUNT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	internet = true
	match_client = true
	pending_password = password
	pending_token = token
	return OK


func leave_game() -> void:
	client_session = false
	_close()


func _close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	active = false
	solo = false
	dedicated = false
	directory = false
	match_server = false
	match_client = false
	browsing = false
	internet = false
	pending_password = ""
	pending_token = ""
	client_session = false


func _user_arg(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return ""


func _wants_dedicated() -> bool:
	if OS.get_cmdline_user_args().has("--dedicated"):
		return true
	for arg in OS.get_cmdline_args():
		if arg == "--dedicated":
			return true
	return false


func _on_connected() -> void:
	client_session = true
	joined.emit()


func _on_connection_failed() -> void:
	last_failure = "internet" if internet else "lan"
	active = false
	_close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if not client_session:
		return
	client_session = false
	if notice.is_empty():
		notice = "Сервер отключился" if internet else "Хост отключился"
	_close()
	host_lost.emit()
