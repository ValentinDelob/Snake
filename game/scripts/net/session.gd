extends Node

## Autoload "Session": hosting, joining and the peer list.
##
## The host is authoritative. It runs the whole match and sends snapshots;
## the clients send nothing but their steering. That keeps the rules in one
## place - the same SnakeMatch the solo game uses - and means a client can
## never be out of step with the host about who died first.

signal peer_joined(id: int)
signal peer_left(id: int)
signal connected_to_host()
signal connection_failed()
signal host_disconnected()

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 8

## How long to wait for the host to answer before giving up. ENet keeps
## retrying for far longer than anybody is willing to stare at a lobby, so
## the wait is cut short here instead.
const CONNECT_TIMEOUT := 5.0

enum Role { OFFLINE, HOST, CLIENT }

var role: Role = Role.OFFLINE
var players: Dictionary = {}        # id -> { "name": String }
var last_error := ""
var connecting := false             # dialling a host, no answer yet

var _connect_address := ""
var _connect_countdown := 0.0


func _ready() -> void:
	set_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Only ticks while a connection attempt is in flight.
func _process(delta: float) -> void:
	if not connecting:
		set_process(false)
		return
	_connect_countdown -= delta
	if _connect_countdown <= 0.0:
		_give_up_connecting()


func _give_up_connecting() -> void:
	connecting = false
	set_process(false)
	leave()
	last_error = "no answer from %s after %d s" % [_connect_address, int(CONNECT_TIMEOUT)]
	Journal.warn("net", last_error)
	connection_failed.emit()


## The host being dialled, for the waiting screen.
func connect_address() -> String:
	return _connect_address


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Open a session others can join. Returns true when the port was taken.
func host(port: int = DEFAULT_PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		last_error = "could not listen on port %d (error %d)" % [port, error]
		Journal.error("net", last_error)
		return false

	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	players = {1: {"name": "host"}}
	Journal.info("net", "Hosting on port %d, local addresses: %s" % [port, local_addresses()])
	return true


## Join a session. The result arrives through connected_to_host or
## connection_failed, never straight away.
func join(address: String, port: int = DEFAULT_PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		last_error = "could not reach %s:%d (error %d)" % [address, port, error]
		Journal.error("net", last_error)
		return false

	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	players = {}
	connecting = true
	_connect_address = address
	_connect_countdown = CONNECT_TIMEOUT
	set_process(true)
	Journal.info("net", "Connecting to %s:%d (giving up after %d s)" % [address, port, int(CONNECT_TIMEOUT)])
	return true


func leave() -> void:
	connecting = false
	set_process(false)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if role != Role.OFFLINE:
		Journal.info("net", "Session closed")
	role = Role.OFFLINE
	players = {}


## The addresses worth reading out loud to somebody on the other machine:
## real local network ones, never loopback or the link-local noise Windows
## hands out for virtual adapters.
func local_addresses(limit: int = 2) -> String:
	var preferred: Array[String] = []
	var others: Array[String] = []
	for address: String in IP.get_local_addresses():
		if address.begins_with("127.") or address.begins_with("169.254.") or address.contains(":"):
			continue
		if address.begins_with("192.168.") or address.begins_with("10."):
			preferred.append(address)
		else:
			others.append(address)
	var found := preferred + others
	if found.is_empty():
		return "no network address"
	return ", ".join(found.slice(0, limit))


# --------------------------------------------------------------------------- #
func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return
	players[id] = {"name": "player %d" % id}
	Journal.info("net", "Player %d joined (%d in session)" % [id, players.size()])
	_publish_roster()
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	Journal.info("net", "Player %d left (%d in session)" % [id, players.size()])
	if role == Role.HOST:
		_publish_roster()
	peer_left.emit(id)


func _on_connected() -> void:
	connecting = false
	set_process(false)
	players[multiplayer.get_unique_id()] = {"name": "you"}
	Journal.info("net", "Connected as player %d" % multiplayer.get_unique_id())
	connected_to_host.emit()


## Only the host knows who is in the session, so it tells everybody. Without
## this a client believes it is alone even mid-match.
func _publish_roster() -> void:
	_receive_roster.rpc(players.keys())


@rpc("authority", "call_remote", "reliable")
func _receive_roster(ids: Array) -> void:
	var known: Dictionary = {}
	for id in ids:
		var key := int(id)
		known[key] = players.get(key, {"name": "player %d" % key})
	players = known
	Journal.info("net", "Session roster: %s" % str(players.keys()))


func _on_connection_failed() -> void:
	connecting = false
	set_process(false)
	last_error = "no answer from %s" % _connect_address
	Journal.warn("net", "Connection failed")
	role = Role.OFFLINE
	connection_failed.emit()


func _on_server_disconnected() -> void:
	Journal.warn("net", "The host closed the session")
	role = Role.OFFLINE
	players = {}
	host_disconnected.emit()
