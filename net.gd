extends Node

const PORT := 7777
const CHANNEL_COUNT := 4
const MAX_PLAYERS := 10
const MAX_NAME_LENGTH := 24

signal joined
signal connection_failed
signal host_lost

var active := false
var solo := false
var notice := ""
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


func join_game(ip: String) -> Error:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT, CHANNEL_COUNT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
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
	client_session = false


func _on_connected() -> void:
	client_session = true
	joined.emit()


func _on_connection_failed() -> void:
	active = false
	_close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if not client_session:
		return
	client_session = false
	notice = "Хост отключился"
	_close()
	host_lost.emit()
