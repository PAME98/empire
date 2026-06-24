extends Node
## NetworkManager — autoload singleton (add to Project > Autoload as "NetworkManager").
## Handles peer creation, lobby state, and player registry.
## The host (peer 1) is always the authority for all simulation.

const PORT        := 7777
const MAX_PEERS   := 4

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal all_players_ready
signal lobby_updated

## peer_id -> { "name": String, "team": int, "ready": bool }
var players: Dictionary = {}

var my_name: String = "Player"
var is_hosting: bool = false


# ---------------------------------------------------------------------------
# Host / Join
# ---------------------------------------------------------------------------
func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_hosting = true
	# Register host as team 0
	players[1] = {"name": my_name, "team": 0, "ready": false}
	lobby_updated.emit()
	return OK


func join_game(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.server_disconnected.connect(
		func(): server_disconnected.emit()
	)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	is_hosting = false
	return OK


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_hosting = false


# ---------------------------------------------------------------------------
# Internal callbacks
# ---------------------------------------------------------------------------
func _on_connected_to_server() -> void:
	# Tell host who we are
	_register_player.rpc_id(1, my_name)


func _on_peer_connected(peer_id: int) -> void:
	# Host sends the joining peer the current player list
	if multiplayer.is_server():
		_sync_player_list.rpc_id(peer_id, players)


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)
	lobby_updated.emit()


# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var team   := players.size()   # simple sequential team assignment
	players[sender] = {"name": player_name, "team": team, "ready": false}
	# Broadcast updated list to everyone
	_sync_player_list.rpc(players)
	player_connected.emit(sender)
	lobby_updated.emit()


@rpc("authority", "call_local", "reliable")
func _sync_player_list(player_dict: Dictionary) -> void:
	players = player_dict
	lobby_updated.emit()


## Host calls this once everyone is ready — clients load the game scene.
@rpc("authority", "call_local", "reliable")
func start_game(seed_val: int, map_size: Vector2) -> void:
	MapSettings.rng_seed  = seed_val
	MapSettings.map_size  = map_size
	get_tree().change_scene_to_file("res://scenes/core/main.tscn")


## Called by host lobby UI when all players have readied up.
func server_start_game(map_size: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var seed_val := randi()
	start_game.rpc(seed_val, map_size)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func my_peer_id() -> int:
	return multiplayer.get_unique_id()


func my_team() -> int:
	return players.get(my_peer_id(), {}).get("team", 0)


func peer_for_team(team: int) -> int:
	for pid in players:
		if players[pid]["team"] == team:
			return pid
	return -1


func team_for_peer(peer_id: int) -> int:
	return players.get(peer_id, {}).get("team", -1)


func is_server() -> bool:
	return multiplayer.is_server()
