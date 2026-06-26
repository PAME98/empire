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
##
## IMPORTANT: these paths must match the Autoload NODE NAME (Project Settings
## -> Autoload, left column), NOT the underlying .gd filename. This project's
## autoloads are registered as "GameManager" / "NetworkManager" (capitalized)
## even though the files on disk are game_manager.gd / network_manager.gd —
## looking up "/root/game_manager" (lowercase) finds nothing and _gm()/_nm()
## silently return null, crashing the first thing that calls a method on them.
var _game_manager = null
var _network_manager = null

func _gm():
	if not is_instance_valid(_game_manager):
		_game_manager = get_node_or_null("/root/GameManager")
	return _game_manager

func _nm():
	if not is_instance_valid(_network_manager):
		_network_manager = get_node_or_null("/root/NetworkManager")
	return _network_manager


# ---------------------------------------------------------------------------
# AUTHORITY HELPERS
# ---------------------------------------------------------------------------
## True where this peer may run authoritative/simulation logic: single-player
## (no multiplayer peer at all) OR the host in a networked game. This MUST be
## used by every player-action handler and spawn helper instead of the raw
## multiplayer.is_server() — because is_server() returns FALSE in a peerless
## single-player session, which is what silently no-opped every spawn and
## command in solo play (no citizens, no founding, no building, no orders).
## Mirrors GameManager.is_sim_authority() exactly so both layers agree.
func _is_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

## True only when a real network session exists. Outbound .rpc()/.rpc_id()
## replication MUST be guarded by this — calling an RPC with no multiplayer
## peer errors out ("Can't make RPCs without a multiplayer peer") and, for
## call_local methods, won't even run the local body. In single-player there
## are no clients to mirror to, so we simply skip the replication.
func _networked() -> bool:
	return multiplayer.has_multiplayer_peer()


## Resolve the team of whoever issued the current command.
## When a CLIENT calls request_*.rpc_id(1, ...), get_remote_sender_id() is that
## client's peer id. When the HOST issues its OWN orders we call request_*()
## DIRECTLY (not via RPC, because a peer can't RPC itself), and in that case
## get_remote_sender_id() returns 0 — so fall back to the host's own unique id.
## Every request_* handler uses this instead of reading the sender id raw.
func _caller_team() -> int:
	# Single-player launched straight from the map-size menu never calls
	# host_game(), so NetworkManager.players is empty and team_for_peer() would
	# return -1 here — which then fails every "unit.team != sender_team" check
	# and every can_afford_for_team(cost, -1) lookup, silently breaking all
	# commands/building/recruiting. With no peer there is exactly one local
	# team, so resolve to it directly. (my_team() defaults to 0 when the
	# registry is empty, matching GameManager._my_team() and _init_team(0).)
	if not multiplayer.has_multiplayer_peer():
		return _nm().my_team()
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
	if not _is_authority():
		return
	var sender_team: int = _caller_team()
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_move(pos)


@rpc("any_peer", "reliable")
func request_attack(unit_ids: Array, target_path: NodePath) -> void:
	if not _is_authority():
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
	if not _is_authority():
		return
	var sender_team: int = _caller_team()
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		unit.command_attack_position(pos)


@rpc("any_peer", "reliable")
func request_gather(unit_ids: Array, target_path: NodePath) -> void:
	if not _is_authority():
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
	if not _is_authority():
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
	if not _is_authority():
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
	# Networked: broadcast (call_local runs it on the host too). Single-player:
	# there's no peer, so call_local would never execute — invoke it directly.
	if _networked():
		_spawn_building_on_all.rpc(building_id, pos, sender_team, net_id)
	else:
		_spawn_building_on_all(building_id, pos, sender_team, net_id)


@rpc("authority", "call_local", "reliable")
func _spawn_building_on_all(building_id: String, pos: Vector3, team: int, net_id: int) -> void:
	var scene_path := _building_scene(building_id)
	if scene_path.is_empty():
		return
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	building.set_meta("building_net_id", net_id)
	var scene := get_tree().current_scene
	scene.get_node("Buildings").add_child(building)
	building.global_position = pos
	# Rebake on the authority only (host in MP, this peer in single-player).
	# Clients receiving the call_local broadcast must NOT rebake.
	if _is_authority():
		var map_gen := scene.get_node_or_null("MapGenerator")
		if map_gen and map_gen.has_method("rebake_navigation"):
			map_gen.rebake_navigation()


# ---------------------------------------------------------------------------
# TOWN FOUNDING  (StartPlacement) — same shape as building placement: a
# client only ever ASKS; the host validates the spot and is the one peer
# that actually instantiates the Village Center + initial citizens, which
# then reach every client through the normal building/unit spawn replication.
# (In single-player StartPlacement calls _execute_found_town directly and
# never goes through this RPC, but the gate is kept consistent anyway.)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_found_town(pos: Vector3, team: int) -> void:
	if not _is_authority():
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
	if not _is_authority():
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
	if not _is_authority():
		return
	var sender_team: int = _caller_team()
	var building := _resolve_building(building_ref)
	if building == null or building.team != sender_team:
		return
	building.destroy()


# ---------------------------------------------------------------------------
# RETURN TO WORK / DELIVER  (right-click own Village Center)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_return_to_work(unit_ids: Array) -> void:
	if not _is_authority():
		return
	var sender_team: int = _caller_team()
	for uid in unit_ids:
		var unit := _find_unit(uid)
		if unit == null or unit.team != sender_team:
			continue
		if unit.has_method("command_return_to_work"):
			unit.command_return_to_work()


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
	if not _is_authority():
		return null
	var uid  := _alloc_unit_id()
	var unit: Node3D = load(scene_path).instantiate()
	unit.set_meta("unit_id", uid)
	unit.team = team
	get_tree().current_scene.get_node("Units").add_child(unit)
	unit.global_position = pos
	# Tell all clients to mirror this spawn (no-op / skipped in single-player).
	if _networked():
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
## (The local queue_free() happens in unit.die(); this only replicates.)
func server_kill_unit(unit: Node, cause: String = "") -> void:
	if not _is_authority():
		return
	var uid: int = unit.get_meta("unit_id", -1) if unit else -1
	if uid != -1 and _networked():
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
	if not _is_authority():
		return null
	var net_id := _alloc_building_id()
	var building: Node3D = load(scene_path).instantiate()
	building.team = team
	building.set_meta("building_net_id", net_id)
	get_tree().current_scene.get_node("Buildings").add_child(building)
	building.global_position = pos
	if _networked():
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
##
## NOTE: this is a pure host->client PUSH. It stays gated on raw
## multiplayer.is_server() so it cleanly no-ops in single-player (no peers to
## push to, and calling .rpc() with no peer would error). Single-player UI is
## driven directly by GameManager.update_ui(), so nothing is lost here.
# ---------------------------------------------------------------------------
func server_sync_citizen_states() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return   # no clients to push to (e.g. single-player host)
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
# BUILDING STATE SYNC  (host -> clients)
## Generic construction/health sync (every Building) PLUS an optional "extra"
## payload for building types that have their own host-only ticking state
## clients otherwise never see update: Barracks (train_queue/train_elapsed/
## is_training), VillageCenter (recruit_queue/recruit_elapsed/is_recruiting),
## and Field (stage/stage_progress). All three only ever progress inside
## _process, which is gated by GameManager.is_sim_authority() — a client's
## local copy never runs that branch, so without this push its queue/progress
## bar (or, for Field, its till/sow/groom/grow stage) is frozen forever at
## whatever it was when last touched. Like the others, Field exposes its
## extra state via apply_network_state_extra() so this stays a drop-in case
## rather than a special path.
##
## Like the citizen-state push above, these are pure host->client PUSHes and
## stay gated on raw multiplayer.is_server() so they no-op in single-player.
# ---------------------------------------------------------------------------
func _building_extra_state(b: Node) -> Dictionary:
	if b is Barracks:
		return {
			"kind": "barracks",
			"train_queue": b.train_queue,
			"train_elapsed": b.train_elapsed,
			"is_training": b.is_training,
		}
	if b is VillageCenter:
		return {
			"kind": "village_center",
			"recruit_queue": b.recruit_queue,
			"recruit_elapsed": b.recruit_elapsed,
			"is_recruiting": b.is_recruiting,
		}
	if b is Field:
		return {
			"kind": "field",
			"stage": b.stage,
			"stage_progress": b.stage_progress,
		}
	return {}


func _apply_extra_state(b: Node, extra: Dictionary) -> void:
	if extra.is_empty():
		return
	match extra.get("kind", ""):
		"barracks":
			if b.has_method("apply_network_state_extra"):
				b.apply_network_state_extra(extra["train_queue"], extra["train_elapsed"], extra["is_training"])
		"village_center":
			if b.has_method("apply_network_state_extra"):
				b.apply_network_state_extra(extra["recruit_queue"], extra["recruit_elapsed"], extra["is_recruiting"])
		"field":
			if b.has_method("apply_network_state_extra"):
				b.apply_network_state_extra(extra["stage"], extra["stage_progress"])


func server_sync_all_building_states() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return   # no clients to push to (e.g. single-player host)
	var data: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var net_id: int = b.get_meta("building_net_id", -1)
		if net_id == -1:
			continue
		data.append({
			"id": net_id,
			"is_constructed": b.is_constructed,
			"build_progress": b.build_progress,
			"health": b.health,
			"extra": _building_extra_state(b),
		})
	if data.is_empty():
		return
	_receive_building_states.rpc(data)


## One-shot push for a single building (e.g. right when it finishes), so the
## client doesn't have to wait for the next periodic broadcast to see it.
func server_sync_building_state(net_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return   # no clients to push to (e.g. single-player host)
	var b := _find_building(net_id)
	if b == null:
		return
	var data := [{
		"id": net_id,
		"is_constructed": b.is_constructed,
		"build_progress": b.build_progress,
		"health": b.health,
		"extra": _building_extra_state(b),
	}]
	_receive_building_states.rpc(data)


@rpc("authority", "unreliable")
func _receive_building_states(data: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in data:
		var b := _find_building(entry["id"])
		if b == null or not b.has_method("apply_network_state"):
			continue
		b.apply_network_state(entry["is_constructed"], entry["build_progress"], entry["health"])
		_apply_extra_state(b, entry.get("extra", {}))


# ---------------------------------------------------------------------------
# RESOURCE SYNC  (host -> owning client only)
## Pure host->client push. In single-player peer_for_team() returns -1 (no
## registered players), so this returns early — single-player resource UI is
## driven by GameManager.update_ui() instead. Left on raw is_server() so it
## never attempts an .rpc() with no peer.
# ---------------------------------------------------------------------------
func server_sync_resources(team: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = _nm().peer_for_team(team)
	if peer_id == -1:
		return
	var res: Variant = _gm().team_resources.get(team, {})
	var pop: Variant = _gm().team_population.get(team, {})
	if peer_id == 1:
		# Host updates its own UI directly
		_gm().resources_changed.emit(
			_gm().bar_food(res), res.get("wood",0), res.get("stone",0),
			res.get("gold",0), res.get("iron",0), res.get("water",0),
			pop.get("population",0), pop.get("housing_capacity",0)
		)
	else:
		_receive_resources.rpc_id(peer_id, res, pop)


@rpc("authority", "reliable")
func _receive_resources(res: Dictionary, pop: Dictionary) -> void:
	_gm().resources_changed.emit(
		_gm().bar_food(res), res.get("wood",0), res.get("stone",0),
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


# ---------------------------------------------------------------------------
# VARIABLE-SIZE FIELD PLACEMENT  (drag-to-draw, obstacle-conforming)
## FieldPlacer sends the list of valid cell centres (already filtered around
## obstacles client-side) plus a centroid + cell size. The host RE-validates
## every cell, charges per valid cell, then spawns one Field built from those
## cells on every peer.
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_place_field(center: Vector3, cells: Array, cell: float) -> void:
	if not _is_authority():
		return
	var sender_team: int = _caller_team()

	# Re-validate every cell so a client can't claim blocked ground.
	var valid: Array = []
	for wc in cells:
		var p: Vector3 = wc if wc is Vector3 else Vector3(wc.x, 0.0, wc.y)
		if _gm().can_place_building_at(p, cell * 0.45):
			valid.append(p)
	if valid.is_empty():
		_notify_caller("Can't lay a field there.")
		return

	var base_cost: Dictionary = _gm().COSTS.get("field", {})
	var cost: Dictionary = {}
	for k in base_cost:
		cost[k] = base_cost[k] * valid.size()
	if not _gm().can_afford_for_team(cost, sender_team):
		_notify_caller("Not enough resources for a field that size.")
		return

	_gm().spend_for_team(cost, sender_team)
	var net_id := _alloc_building_id()
	if _networked():
		_spawn_field_on_all.rpc(center, valid, cell, sender_team, net_id)
	else:
		_spawn_field_on_all(center, valid, cell, sender_team, net_id)


@rpc("authority", "call_local", "reliable")
func _spawn_field_on_all(center: Vector3, cells: Array, cell: float, team: int, net_id: int) -> void:
	var scene_path := _building_scene("field")
	if scene_path.is_empty():
		return
	var field: Node3D = load(scene_path).instantiate()
	field.team = team
	field.set_meta("building_net_id", net_id)
	get_tree().current_scene.get_node("Buildings").add_child(field)
	field.global_position = center
	if field.has_method("set_cells"):
		field.set_cells(cells, cell)
	# Rebake nav on the authority only (host in MP, this peer in single-player).
	if _is_authority():
		var map_gen = get_tree().current_scene.get_node_or_null("MapGenerator")
		if map_gen and map_gen.has_method("rebake_navigation"):
			map_gen.rebake_navigation()


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
		"field":         "res://scenes/buildings/field.tscn",
		"stockpile":     "res://scenes/buildings/stockpile.tscn",
		"warehouse":     "res://scenes/buildings/warehouse.tscn",
	}
	return SCENES.get(id, "")
