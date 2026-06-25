extends Node
## NetworkManager — autoload singleton (add to Project > Autoload as "NetworkManager").
## Handles peer creation, lobby state, and the player registry.
## The host (peer 1) is always the authority for all simulation.
##
## SINGLE-PLAYER = LOCAL HOST SESSION. start_solo() sets an OfflineMultiplayerPeer
## and registers the local player exactly the way host_game() does, so solo runs
## the *same* code path as hosting (multiplayer.is_server() is reliably true, the
## player registry is populated, team lookups resolve to 0). There is no separate
## "peerless" path to special-case in citizen/unit/building/etc. anymore.
##
## FIXED: added client_set_ready RPC here so it lives on this persistent autoload
## node rather than on the transient Lobby Control node. The old lobby.gd defined
## _set_self_ready as an @rpc on itself — after start_game() changed the scene that
## node was freed, and any in-flight RPC targeting it produced "Invalid packet
## received. Requested node was not found."

const PORT      := 7777
const MAX_PEERS := 4

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal all_players_ready
signal lobby_updated
## Emitted on a client the moment the transport connection to the host is
## established (before registration completes). The menu waits for this before
## switching to the lobby, so a failed/absent host never lands you in an empty one.
signal connection_succeeded
## Emitted on a client when the host refuses its join (game already started, or
## the lobby is full). Carries a human-readable reason the menu can display.
signal join_rejected(reason: String)

## peer_id -> { "name": String, "team": int, "ready": bool }
var players: Dictionary = {}

var my_name: String = "Player"
var is_hosting: bool = false

## True once the host has launched the match. Gates late joins so the lobby is
## not accessible after the game has started. Reset whenever a fresh session
## (host/join/solo) begins or the current one is torn down.
var game_started: bool = false

## Last connection-level error, shared between the lobby and the main menu so
## whichever scene is showing can surface it. The menu reads and clears it on
## _ready; the lobby sets it before bouncing back to the menu.
var last_error: String = ""


# ---------------------------------------------------------------------------
# Session setup
# ---------------------------------------------------------------------------
func host_game() -> Error:
	_reset_session_state()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_host_signals()
	is_hosting = true
	# Register host as team 0
	players[1] = {"name": my_name, "team": 0, "ready": false}
	lobby_updated.emit()
	return OK


func join_game(address: String) -> Error:
	_reset_session_state()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_client_signals()
	is_hosting = false
	return OK


## Single-player. An OfflineMultiplayerPeer opens no socket and binds no port —
## it just makes the multiplayer API report "connected, I'm the server, id 1",
## so every host-authoritative path runs locally as if hosting a game with zero
## remote players. The registry is seeded so team resolution returns 0.
func start_solo() -> void:
	_reset_session_state()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_hosting = true
	if my_name.strip_edges().is_empty():
		my_name = "Player"
	players[1] = {"name": my_name, "team": 0, "ready": true}
	lobby_updated.emit()


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_hosting = false
	game_started = false
	# NOTE: last_error is intentionally NOT cleared here — the menu we're about
	# to return to needs to read it. The menu clears it once displayed.


## Wipe per-session state so a previous solo/host/join can never leak into a new
## one (e.g. stale players entries or a lingering game_started flag).
func _reset_session_state() -> void:
	players.clear()
	is_hosting = false
	game_started = false


func _connect_host_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _connect_client_signals() -> void:
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


# ---------------------------------------------------------------------------
# Internal callbacks
# ---------------------------------------------------------------------------
func _on_connected_to_server() -> void:
	# Tell host who we are
	_register_player.rpc_id(1, my_name)


func _on_connection_failed() -> void:
	# Could not establish the connection at all (bad address, host refusing new
	# connections because the game already started, etc.).
	last_error = "Failed to connect to host."
	server_disconnected.emit()


func _on_peer_connected(peer_id: int) -> void:
	# Host sends the joining peer the current player list
	if multiplayer.is_server():
		_sync_player_list.rpc_id(peer_id, players)


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)
	lobby_updated.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()


# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()

	# LOBBY LOCKOUT: refuse anyone trying to join after the match has begun, or
	# once the lobby is full. The would-be client gets a reason and bounces back
	# to its menu; it never appears in the registry or the lobby list.
	if game_started:
		_join_rejected.rpc_id(sender, "Game already in progress.")
		return
	if players.size() >= MAX_PEERS:
		_join_rejected.rpc_id(sender, "Lobby is full.")
		return

	var team := players.size()   # simple sequential team assignment
	players[sender] = {"name": player_name, "team": team, "ready": false}
	# Broadcast updated list to everyone
	_sync_player_list.rpc(players)
	player_connected.emit(sender)
	lobby_updated.emit()


@rpc("authority", "call_local", "reliable")
func _sync_player_list(player_dict: Dictionary) -> void:
	players = player_dict
	lobby_updated.emit()


## Host -> a single rejected client. Records the reason and signals it so the
## client's lobby can show it and return to the menu.
@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	last_error = reason
	join_rejected.emit(reason)


## FIX: moved from lobby.gd to here so it targets this persistent autoload.
## lobby.gd now calls NetworkManager.client_set_ready.rpc_id(1, true) instead
## of _set_self_ready.rpc_id(1, true) on itself.
@rpc("any_peer", "reliable")
func client_set_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	if game_started:
		return
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid):
		players[pid]["ready"] = value
		_sync_player_list.rpc(players)


## Host calls this once everyone is ready — clients load the game scene.
@rpc("authority", "call_local", "reliable")
func start_game(seed_val: int, map_size: Vector2) -> void:
	game_started = true
	MapSettings.rng_seed = seed_val
	MapSettings.map_size = map_size
	get_tree().change_scene_to_file("res://scenes/core/main.tscn")


## Called by host lobby UI when all players have readied up. Locks the lobby at
## both the transport level (no new ENet connections accepted) and the logic
## level (game_started gates _register_player), then tells everyone to load in.
func server_start_game(map_size: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if game_started:
		return
	game_started = true
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.refuse_new_connections = true
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
