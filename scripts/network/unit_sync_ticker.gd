extends Node
## UnitSyncTicker — add as a child of Main (or as an autoload).
## Runs ONLY on the host. Every SYNC_INTERVAL seconds it collects
## all unit positions + health and broadcasts them to clients via
## NetworkCommands.sync_unit_positions (unreliable — OK to drop frames).
##
## Also broadcasts citizen display state (life_stage/age/job/carried cargo)
## at a slower cadence via NetworkCommands.server_sync_citizen_states, and
## building construction/health state at the same slower cadence via
## NetworkCommands.server_sync_all_building_states — without this, a
## client's local copy of a building never learns when the host finishes
## constructing it (Building.add_build_progress only ever runs host-side),
## so "under construction" would show forever on clients even after the
## host completed it.

const SYNC_INTERVAL := 0.1   # 10 times per second
const CITIZEN_STATE_SYNC_INTERVAL := 1.0  # citizen job/cargo/life-stage, 1x/second is plenty
const BUILDING_STATE_SYNC_INTERVAL := 1.0  # construction progress/health, 1x/second is plenty

var _timer: float = 0.0
var _citizen_state_timer: float = 0.0
var _building_state_timer: float = 0.0
var _logged_once := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	if not _logged_once:
		_logged_once = true
		print("[UnitSyncTicker] active on host — broadcasting unit positions.")

	_timer += delta
	if _timer >= SYNC_INTERVAL:
		_timer = 0.0
		_broadcast_unit_states()

	_citizen_state_timer += delta
	if _citizen_state_timer >= CITIZEN_STATE_SYNC_INTERVAL:
		_citizen_state_timer = 0.0
		NetworkCommands.server_sync_citizen_states()

	_building_state_timer += delta
	if _building_state_timer >= BUILDING_STATE_SYNC_INTERVAL:
		_building_state_timer = 0.0
		NetworkCommands.server_sync_all_building_states()


func _broadcast_unit_states() -> void:
	var data: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		var uid: int = unit.get_meta("unit_id", -1)
		if uid == -1:
			continue
		data.append({
			"id":     uid,
			"pos":    unit.global_position,
			"health": unit.health if "health" in unit else 0,
		})
	if data.is_empty():
		return
	NetworkCommands.sync_unit_positions.rpc(data)
