extends Node
## UnitSyncTicker — add as a child of Main (or as an autoload).
## Runs ONLY on the host. Every SYNC_INTERVAL seconds it collects
## all unit positions + health and broadcasts them to clients via
## NetworkCommands.sync_unit_positions (unreliable — OK to drop frames).

const SYNC_INTERVAL := 0.1   # 10 times per second

var _timer: float = 0.0


func _ready() -> void:
	# Only the host ticks simulation and broadcasts
	if not multiplayer.is_server():
		set_process(false)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < SYNC_INTERVAL:
		return
	_timer = 0.0
	_broadcast_unit_states()


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
