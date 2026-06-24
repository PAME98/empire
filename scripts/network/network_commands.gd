extends Node
## NetworkCommands — autoload singleton (add to Project > Autoload as "NetworkCommands").
## All player actions flow through here:
##   Client  ->  rpc_id(1, ...)  ->  Host validates & executes
##   Host    ->  rpc(...)        ->  All clients see result
##
## This is the single choke-point that prevents desyncs:
## clients NEVER touch simulation state directly.

# ---------------------------------------------------------------------------
# Unit counter — host assigns, clients receive via spawn sync
# ---------------------------------------------------------------------------
var _next_id: int = 1

func _alloc_unit_id() -> int:
	_next_id += 1
	return _next_id


# ---------------------------------------------------------------------------
# MOVEMENT
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_move(unit_ids: Array, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_move(pos)


@rpc("any_peer", "reliable")
func request_attack(unit_ids: Array, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	var target := get_node_or_null(target_path)
	if target == null:
		return
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_attack(target)


@rpc("any_peer", "reliable")
func request_attack_position(unit_ids: Array, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_attack_position(pos)


@rpc("any_peer", "reliable")
func request_gather(unit_ids: Array, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	var target := get_node_or_null(target_path)
	if target == null:
		return
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_gather(target)


@rpc("any_peer", "reliable")
func request_build_on(unit_ids: Array, site_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	var site := get_node_or_null(site_path)
	if site == null:
		return
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_build(site)


# ---------------------------------------------------------------------------
# BUILDING PLACEMENT
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_place_building(building_id: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id   := multiplayer.get_remote_sender_id()
	var sender_team := NetworkManager.team_for_peer(sender_id)

	var cost: Dictionary = GameManager.COSTS.get(building_id, {})
	if cost.is_empty():
		return
	if not GameManager.can_afford_for_team(cost, sender_team):
		_notify_peer.rpc_id(sender_id, "Not enough resources.")
		return

	var scene_path: String = _building_scene(building_id)
	if scene_path.is_empty():
		return

	# Validate terrain (host-side)
	var footprint := 36.0 * Building.GLOBAL_BUILDING_SCALE
	if not GameManager.can_place_building_at(pos, footprint):
		_notify_peer.rpc_id(sender_id, "Can't build there.")
		return

	GameManager.spend_for_team(cost, sender_team)
	_spawn_building_on_all.rpc(building_id, pos, sender_team)


@rpc("authority", "call_local", "reliable")
func _spawn_building_on_all(building_id: String, pos: Vector3, team: int) -> void:
	var scene_path := _building_scene(building_id)
	if scene_path.is_empty():
		return
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	var scene := get_tree().current_scene
	scene.get_node("Buildings").add_child(building)
	building.global_position = pos
	# Rebake nav on host only
	if multiplayer.is_server():
		var map_gen := scene.get_node_or_null("MapGenerator")
		if map_gen and map_gen.has_method("rebake_navigation"):
			map_gen.rebake_navigation()


# ---------------------------------------------------------------------------
# UNIT TRAINING  (Barracks / Village Center)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_train_unit(building_path: NodePath, unit_type: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id   := multiplayer.get_remote_sender_id()
	var sender_team := NetworkManager.team_for_peer(sender_id)
	var building    := get_node_or_null(building_path)
	if building == null or building.team != sender_team:
		return
	match unit_type:
		"soldier":
			building.queue_soldier()
		"artillery":
			building.queue_artillery()
		"citizen":
			building.queue_citizen()


# ---------------------------------------------------------------------------
# DEMOLISH
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_demolish(building_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team := NetworkManager.team_for_peer(multiplayer.get_remote_sender_id())
	var building    := get_node_or_null(building_path)
	if building == null or building.team != sender_team:
		return
	building.destroy()


# ---------------------------------------------------------------------------
# NOTIFICATIONS  (host -> specific client)
# ---------------------------------------------------------------------------
@rpc("authority", "reliable")
func _notify_peer(text: String) -> void:
	GameManager.notify(text)


# ---------------------------------------------------------------------------
# UNIT SPAWNING  (host spawns, syncs unit_id to all clients)
## Call this from Barracks._complete_training() and StartPlacement
# ---------------------------------------------------------------------------
func server_spawn_unit(scene_path: String, pos: Vector3, team: int) -> Node3D:
	if not multiplayer.is_server():
		return null
	var uid  := _alloc_unit_id()
	var unit: Node3D = load(scene_path).instantiate()
	unit.set_meta("unit_id", uid)
	unit.team = team
	get_tree().current_scene.get_node("Units").add_child(unit)
	unit.global_position = pos
	# Tell all clients to mirror this spawn
	_replicate_unit_spawn.rpc(scene_path, pos, team, uid)
	return unit


@rpc("authority", "reliable")
func _replicate_unit_spawn(scene_path: String, pos: Vector3, team: int, uid: int) -> void:
	if multiplayer.is_server():
		return   # host already has it
	var unit: Node3D = load(scene_path).instantiate()
	unit.set_meta("unit_id", uid)
	unit.team = team
	# Clients don't run AI or physics for units — host does
	unit.set_physics_process(false)
	unit.set_process(false)
	get_tree().current_scene.get_node("Units").add_child(unit)
	unit.global_position = pos


# ---------------------------------------------------------------------------
# POSITION BROADCAST  (host -> clients, called from UnitSyncTicker)
# ---------------------------------------------------------------------------
@rpc("authority", "unreliable")
func sync_unit_positions(data: Array) -> void:
	## data = [ {id, pos, health}, ... ]
	if multiplayer.is_server():
		return
	for entry in data:
		var unit := _find_unit(entry["id"])
		if unit == null:
			continue
		unit.global_position = entry["pos"]
		if "health" in entry and unit.has_method("set_health_display"):
			unit.set_health_display(entry["health"])


# ---------------------------------------------------------------------------
# RESOURCE SYNC  (host -> owning client only)
# ---------------------------------------------------------------------------
func server_sync_resources(team: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := NetworkManager.peer_for_team(team)
	if peer_id == -1:
		return
	var res := GameManager.team_resources.get(team, {})
	var pop := GameManager.team_population.get(team, {})
	if peer_id == 1:
		# Host updates its own UI directly
		GameManager.resources_changed.emit(
			res.get("food",0), res.get("wood",0), res.get("stone",0),
			res.get("gold",0), res.get("iron",0), res.get("water",0),
			pop.get("population",0), pop.get("housing_capacity",0)
		)
	else:
		_receive_resources.rpc_id(peer_id, res, pop)


@rpc("authority", "reliable")
func _receive_resources(res: Dictionary, pop: Dictionary) -> void:
	GameManager.resources_changed.emit(
		res.get("food",0), res.get("wood",0), res.get("stone",0),
		res.get("gold",0), res.get("iron",0), res.get("water",0),
		pop.get("population",0), pop.get("housing_capacity",0)
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _find_unit(uid: int) -> Node:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get_meta("unit_id", -1) == uid:
			return unit
	return null


func _building_scene(id: String) -> String:
	const SCENES := {
		"house":         "res://scenes/buildings/house.tscn",
		"farm":          "res://scenes/buildings/farm.tscn",
		"grain_farm":    "res://scenes/buildings/grain_farm.tscn",
		"veg_garden":    "res://scenes/buildings/veg_garden.tscn",
		"hunter":        "res://scenes/buildings/hunter.tscn",
		"lumber_camp":   "res://scenes/buildings/lumber_camp.tscn",
		"quarry":        "res://scenes/buildings/quarry.tscn",
		"mine":          "res://scenes/buildings/mine.tscn",
		"herbalist":     "res://scenes/buildings/herbalist.tscn",
		"well":          "res://scenes/buildings/well.tscn",
		"charcoal_kiln": "res://scenes/buildings/charcoal_kiln.tscn",
		"mill":          "res://scenes/buildings/mill.tscn",
		"bakery":        "res://scenes/buildings/bakery.tscn",
		"sawmill":       "res://scenes/buildings/sawmill.tscn",
		"smelter":       "res://scenes/buildings/smelter.tscn",
		"blacksmith":    "res://scenes/buildings/blacksmith.tscn",
		"apothecary":    "res://scenes/buildings/apothecary.tscn",
		"barracks":      "res://scenes/buildings/barracks.tscn",
	}
	return SCENES.get(id, "")
