extends Node
## NetworkCommands — autoload singleton (add to Project > Autoload as "NetworkCommands").
## All player actions flow through here:
##   Client  ->  rpc_id(1, ...)  ->  Host validates & executes
##   Host    ->  rpc(...)        ->  All clients see result
##
## This is the single choke-point that prevents desyncs:
## clients NEVER touch simulation state directly.

# ---------------------------------------------------------------------------
# Cross-autoload accessors — SAME PARSER QUIRK GameManager DOCUMENTS.
# ---------------------------------------------------------------------------
## NetworkCommands and GameManager reference each other, a true bidirectional
## autoload dependency. Whichever autoload is listed first holds a forward
## reference to the one listed second, and the parser reports "Identifier not
## declared in the current scope" on the bare name. Reordering can't fix a
## mutual reference — it only flips which file errors. Resolving GameManager
## and NetworkManager via the tree by their well-known autoload paths breaks
## the cycle at parse time and works in any order. Untyped on purpose so all
## member access stays dynamic (no static type to check members against).
var _game_manager = null
var _network_manager = null

func _gm():
	if not is_instance_valid(_game_manager):
		_game_manager = get_node_or_null("/root/game_manager")
		if not is_instance_valid(_game_manager):
			_game_manager = get_node_or_null("/root/GameManager")
	return _game_manager

func _nm():
	if not is_instance_valid(_network_manager):
		_network_manager = get_node_or_null("/root/network_manager")
		if not is_instance_valid(_network_manager):
			_network_manager = get_node_or_null("/root/NetworkManager")
	return _network_manager


## Resolve the team of whoever issued the current command.
## When a CLIENT calls request_*.rpc_id(1, ...), get_remote_sender_id() is that
## client's peer id. When the HOST issues its OWN orders we call request_*()
## DIRECTLY (not via RPC, because a peer can't RPC itself), and in that case
## get_remote_sender_id() returns 0 — so fall back to the host's own unique id.
## Every request_* handler uses this instead of reading the sender id raw.
func _caller_team() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return _nm().team_for_peer(sender)


## The peer id of whoever issued the current command (0 -> host calling locally).
func _caller_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


## Send a notification back to whoever issued the command. If that's the host
## itself (it called the handler directly), show it locally instead of RPCing —
## a peer can't reliably _notify_peer.rpc_id() itself.
func _notify_caller(text: String) -> void:
	var target := _caller_id()
	if target == multiplayer.get_unique_id():
		_gm().notify(text)
	else:
		_notify_peer.rpc_id(target, text)


# ---------------------------------------------------------------------------
# Unit counter — host assigns, clients receive via spawn sync
# ---------------------------------------------------------------------------
var _next_id: int = 1

func _alloc_unit_id() -> int:
	_next_id += 1
	return _next_id


# Building network ids live in their own counter range so they never collide
# with unit ids. Used to address buildings across machines (build/demolish/
# train) instead of per-machine NodePaths.
var _next_building_id: int = 1

func _alloc_building_id() -> int:
	_next_building_id += 1
	return _next_building_id


func _find_building(net_id: int) -> Node:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get_meta("building_net_id", -1) == net_id:
			return b
	return null


## Resolve a building from either a network id (int, the new cross-machine-safe
## path used by the camera) or a NodePath (legacy callers, e.g. host-local HUD
## buttons that still pass building.get_path()). NodePaths only resolve reliably
## when the caller and host share a tree — fine for host-issued UI actions, but
## clients must use the int id. -1 / null yields no building.
func _resolve_building(ref) -> Node:
	if ref is int:
		if ref < 0:
			return null
		return _find_building(ref)
	if ref is NodePath:
		return get_node_or_null(ref)
	return null


# ---------------------------------------------------------------------------
# MOVEMENT
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_move(unit_ids: Array, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_move(pos)


@rpc("any_peer", "reliable")
func request_attack(unit_ids: Array, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
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
	var sender_team: int = _caller_team()
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_attack_position(pos)


@rpc("any_peer", "reliable")
func request_gather(unit_ids: Array, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	var target := get_node_or_null(target_path)
	if target == null:
		return
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_gather(target)


@rpc("any_peer", "reliable")
func request_build_on(unit_ids: Array, site_ref) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	var site := _resolve_building(site_ref)
	if site == null:
		print("[request_build_on] host could NOT resolve site_ref=", site_ref,
			" (type ", typeof(site_ref), "). Known building ids: ", _all_building_ids())
		return
	if not ("team" in site) or site.team != sender_team:
		print("[request_build_on] team mismatch: site.team=",
			(site.team if "team" in site else "?"), " sender_team=", sender_team)
		return
	var any := false
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		any = true
		unit.command_build(site)
	if not any:
		print("[request_build_on] resolved site but no owned units matched ids=", unit_ids)


func _all_building_ids() -> Array:
	var ids: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		ids.append(b.get_meta("building_net_id", -1))
	return ids


# ---------------------------------------------------------------------------
# BUILDING PLACEMENT
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_place_building(building_id: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()

	var cost: Dictionary = _gm().COSTS.get(building_id, {})
	if cost.is_empty():
		return
	if not _gm().can_afford_for_team(cost, sender_team):
		_notify_caller("Not enough resources.")
		return

	var scene_path: String = _building_scene(building_id)
	if scene_path.is_empty():
		return

	# Validate terrain (host-side)
	var footprint := 36.0 * Building.GLOBAL_BUILDING_SCALE
	if not _gm().can_place_building_at(pos, footprint):
		_notify_caller("Can't build there.")
		return

	_gm().spend_for_team(cost, sender_team)
	var net_id := _alloc_building_id()
	_spawn_building_on_all.rpc(building_id, pos, sender_team, net_id)


@rpc("authority", "call_local", "reliable")
func _spawn_building_on_all(building_id: String, pos: Vector3, team: int, net_id: int) -> void:
	var scene_path := _building_scene(building_id)
	if scene_path.is_empty():
		return
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	# Stable cross-machine id so build/demolish/train commands can reference
	# this exact building on every peer. NodePaths differ per machine (child
	# order under Buildings isn't guaranteed identical), which is why path-based
	# build orders silently missed. The host allocates net_id and passes it in
	# this RPC's args, so host and client tag the same building identically.
	building.set_meta("building_net_id", net_id)
	var scene := get_tree().current_scene
	scene.get_node("Buildings").add_child(building)
	building.global_position = pos
	# Rebake nav on host only
	if multiplayer.is_server():
		var map_gen := scene.get_node_or_null("MapGenerator")
		if map_gen and map_gen.has_method("rebake_navigation"):
			map_gen.rebake_navigation()


# ---------------------------------------------------------------------------
# TOWN FOUNDING  (StartPlacement) — same shape as building placement: a
# client only ever ASKS; the host validates the spot and is the one peer
# that actually instantiates the Village Center + initial citizens, which
# then reach every client through the normal building/unit spawn replication.
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_found_town(pos: Vector3, team: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	# Trust the caller's team derivation from the player registry, not the
	# raw value they sent, so a client can't found a town "as" another team.
	var actual_team: int = sender_team if sender_team != -1 else team

	var start_placement := get_tree().current_scene.get_node_or_null("StartPlacement")
	if start_placement == null or not start_placement.has_method("_is_spot_valid"):
		return
	if not start_placement._is_spot_valid(pos):
		_notify_caller("Can't found your town there.")
		return

	start_placement._execute_found_town(pos, actual_team)


# ---------------------------------------------------------------------------
# UNIT TRAINING  (Barracks / Village Center)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_train_unit(building_ref, unit_type: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	var building := _resolve_building(building_ref)
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
func request_demolish(building_ref) -> void:
	if not multiplayer.is_server():
		return
	var sender_team: int = _caller_team()
	var building := _resolve_building(building_ref)
	if building == null or building.team != sender_team:
		return
	building.destroy()


# ---------------------------------------------------------------------------
# NOTIFICATIONS  (host -> specific client)
# ---------------------------------------------------------------------------
@rpc("authority", "reliable")
func _notify_peer(text: String) -> void:
	_gm().notify(text)


# ---------------------------------------------------------------------------
# UNIT SPAWNING  (host spawns, syncs unit_id to all clients)
## Call this from Barracks._complete_training(), VillageCenter._complete_recruit(),
## StartPlacement._execute_found_town() and GameManager._spawn_child(). Never
## instantiate a unit scene directly from gameplay code — always go through
## this so the spawn happens exactly once and is mirrored consistently.
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
	# Clients don't run AI for units — the host does — but they DO keep
	# _physics_process running so they can smoothly interpolate toward synced
	# positions (Unit._physics_process early-returns from AI on non-authority
	# peers and only runs interpolation). Disabling physics here would freeze
	# that interpolation and bring back the teleport/stutter. We still disable
	# the per-frame _process (cosmetic/AI bookkeeping) which clients don't need.
	unit.set_process(false)
	get_tree().current_scene.get_node("Units").add_child(unit)
	unit.global_position = pos


## Host-authoritative unit death. Call this INSTEAD of freeing a unit directly
## so the death is mirrored: on the host it frees the unit locally and tells
## every client to free their copy by unit_id. Without this, the host's unit
## vanishes but the client keeps showing a "corpse" that never dies.
func server_kill_unit(unit: Node, cause: String = "") -> void:
	if not multiplayer.is_server():
		return
	var uid: int = unit.get_meta("unit_id", -1) if unit else -1
	if uid != -1:
		_replicate_unit_death.rpc(uid)


@rpc("authority", "reliable")
func _replicate_unit_death(uid: int) -> void:
	if multiplayer.is_server():
		return   # host already freed it in die()
	var unit := _find_unit(uid)
	if unit and is_instance_valid(unit):
		unit.queue_free()


## Spawn a building from an arbitrary scene path and mirror it to all peers.
## Used for buildings that don't go through request_place_building's COSTS path
## — notably the Village Center created at town founding. Host-authoritative,
## same contract as server_spawn_unit: call only from authoritative code.
func server_spawn_building(scene_path: String, pos: Vector3, team: int) -> Node3D:
	if not multiplayer.is_server():
		return null
	var net_id := _alloc_building_id()
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	building.set_meta("building_net_id", net_id)
	get_tree().current_scene.get_node("Buildings").add_child(building)
	building.global_position = pos
	_replicate_building_spawn.rpc(scene_path, pos, team, net_id)
	return building


@rpc("authority", "reliable")
func _replicate_building_spawn(scene_path: String, pos: Vector3, team: int, net_id: int) -> void:
	if multiplayer.is_server():
		return   # host already has it
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	building.set_meta("building_net_id", net_id)
	get_tree().current_scene.get_node("Buildings").add_child(building)
	building.global_position = pos


# ---------------------------------------------------------------------------
# POSITION BROADCAST  (host -> clients, called from UnitSyncTicker)
# ---------------------------------------------------------------------------
@rpc("authority", "unreliable")
func sync_unit_positions(data: Array) -> void:
	## data = [ {id, pos, health}, ... ]
	if multiplayer.is_server():
		return
	var resolved := 0
	var missing := 0
	for entry in data:
		var unit := _find_unit(entry["id"])
		if unit == null:
			missing += 1
			continue
		resolved += 1
		# Hand the position to the unit as an interpolation target rather than
		# snapping global_position directly — Unit.set_network_target() lerps
		# toward it each physics frame so client movement looks smooth.
		if unit.has_method("set_network_target"):
			unit.set_network_target(entry["pos"])
		else:
			unit.global_position = entry["pos"]
		if "health" in entry and unit.has_method("set_health_display"):
			unit.set_health_display(entry["health"])
	# One-time diagnostic so we can see, on the CLIENT, whether position data is
	# arriving and whether unit ids resolve. If this never prints, the client is
	# not receiving the RPC at all. If it prints with resolved=0, the client has
	# the data but its units aren't in the "units" group / have mismatched ids.
	if not _logged_sync_once:
		_logged_sync_once = true
		print("[sync_unit_positions] client received: ", data.size(),
			" entries, resolved=", resolved, " missing=", missing)
		var ids: Array = []
		for u in get_tree().get_nodes_in_group("units"):
			ids.append(u.get_meta("unit_id", -1))
		print("[sync_unit_positions] client units-group ids: ", ids)


var _logged_sync_once := false


# ---------------------------------------------------------------------------
# CITIZEN STATE SYNC  (host -> clients, low-frequency)
## Citizens carry extra display-relevant state (life_stage/age/current_job/
## carried_resource+amount) that isn't part of the per-frame position sync.
## Without this, clients never see citizens age up, change job colour, or
## show carried cargo, since Citizen._process (the only thing that used to
## update those fields) is now host-only. Call this whenever that state is
## likely to have changed in bulk — GameManager._yearly_tick() does, for
## aging — and optionally from UnitSyncTicker at a slower cadence if you
## want job/cargo changes to show up sooner than once a year.
# ---------------------------------------------------------------------------
func server_sync_citizen_states() -> void:
	if not multiplayer.is_server():
		return
	var data: Array = []
	for c in _gm().all_citizens:
		if not is_instance_valid(c):
			continue
		var uid: int = c.get_meta("unit_id", -1)
		if uid == -1:
			continue
		data.append({
			"id": uid,
			"life_stage": c.life_stage,
			"age": c.age,
			"job": c.current_job,
			"carried_resource": c.carried_resource,
			"carried_amount": c.carried_amount,
		})
	if data.is_empty():
		return
	_receive_citizen_states.rpc(data)


@rpc("authority", "unreliable")
func _receive_citizen_states(data: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in data:
		var unit := _find_unit(entry["id"])
		if unit == null or not unit.has_method("apply_network_state"):
			continue
		unit.apply_network_state(
			entry["life_stage"], entry["age"], entry["job"],
			entry["carried_resource"], entry["carried_amount"]
		)


# ---------------------------------------------------------------------------
# RESOURCE SYNC  (host -> owning client only)
# ---------------------------------------------------------------------------
func server_sync_resources(team: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = _nm().peer_for_team(team)
	if peer_id == -1:
		return
	var res :Variant = _gm().team_resources.get(team, {})
	var pop :Variant = _gm().team_population.get(team, {})
	if peer_id == 1:
		# Host updates its own UI directly
		_gm().resources_changed.emit(
			res.get("food",0), res.get("wood",0), res.get("stone",0),
			res.get("gold",0), res.get("iron",0), res.get("water",0),
			pop.get("population",0), pop.get("housing_capacity",0)
		)
	else:
		_receive_resources.rpc_id(peer_id, res, pop)


@rpc("authority", "reliable")
func _receive_resources(res: Dictionary, pop: Dictionary) -> void:
	_gm().resources_changed.emit(
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
