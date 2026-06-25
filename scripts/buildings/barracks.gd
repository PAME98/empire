class_name Barracks
extends Building
## Converts stockpiled resources into military units. This is the bridge
## between the economy half of the game and the RTS-combat half: soldiers
## cost food/gold the citizen economy produced, so a healthy economy is a
## prerequisite for a real army rather than the two systems being unrelated.
##
## NETWORKING: same shape of fix as VillageCenter. Training-queue ticking
## spends shared resources and decides when a unit is born, so it's host-only;
## the spawn itself now goes through NetworkCommands.server_spawn_unit so it
## happens exactly once and gets mirrored to clients, instead of every peer
## instantiating its own (previously-divergent) copy.
##
## CLIENT STATE: train_elapsed/train_queue/is_training only ever advance on
## the host's copy (see _process below) — a client's local Barracks instance
## never runs this logic, so without an explicit sync its progress bar/queue
## display freezes at whatever it was when the building was last touched
## (usually 0%, since clients never run queue_soldier()/queue_artillery()'s
## local side either — those calls are host-only via request_train_unit).
## apply_network_state() below is how NetworkCommands pushes the host's real
## values down so the client's UI actually reflects what's happening.

@export var spawn_offset: Vector3 = Vector3(0, 0, 70)

var train_queue: Array = []
var train_elapsed: float = 0.0
var is_training: bool = false

@onready var train_bar: ProgressBar = get_node_or_null("TrainBar")


func _ready() -> void:
	super._ready()
	add_to_group("barracks")
	if train_bar:
		train_bar.visible = false


func _process(delta: float) -> void:
	super._process(delta)
	if not GameManager.is_sim_authority():
		return
	if not is_constructed or not is_training or train_queue.is_empty():
		return
	train_elapsed += delta
	var unit_type = "artillery" if train_queue.front() == "artillery" else "soldier"
	var duration = GameManager.BUILD_TIMES.get(unit_type, 8.0)
	if train_bar:
		train_bar.value = clampf(train_elapsed / duration * 100.0, 0.0, 100.0)
	if train_elapsed >= duration:
		_complete_training()
		train_queue.pop_front()
		train_elapsed = 0.0
		_start_next()


func queue_soldier() -> bool:
	if not is_constructed:
		return false
	var cost = GameManager.COSTS.get("soldier", {})
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough resources to train a soldier.")
		return false
	GameManager.spend(cost)
	train_queue.append("soldier")
	if not is_training:
		_start_next()
	return true


func queue_artillery() -> bool:
	if not is_constructed:
		return false
	var cost = GameManager.COSTS.get("artillery", {})
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough resources to train artillery.")
		return false
	GameManager.spend(cost)
	train_queue.append("artillery")
	if not is_training:
		_start_next()
	return true


func _start_next() -> void:
	if train_queue.is_empty():
		is_training = false
		if train_bar:
			train_bar.visible = false
		return
	is_training = true
	train_elapsed = 0.0
	if train_bar:
		train_bar.visible = true
		train_bar.value = 0.0


func _complete_training() -> void:
	var entry = train_queue.front()
	var scene_path = "res://scenes/units/artillery.tscn" if entry == "artillery" else "res://scenes/units/soldier.tscn"
	var spawn_pos = global_position + spawn_offset + Vector3(randf_range(-18, 18), 0, randf_range(-18, 18))
	var unit = NetworkCommands.server_spawn_unit(scene_path, spawn_pos, team)
	if unit == null:
		return
	if entry == "artillery":
		GameManager.register_artillery(unit)
	else:
		GameManager.register_soldier(unit)


## NETWORKING: called on CLIENTS ONLY, from NetworkCommands._receive_building_states,
## to mirror the host's authoritative training queue/progress. Never call this on
## the host — its own train_queue/train_elapsed are already correct.
func apply_network_state_extra(p_train_queue: Array, p_train_elapsed: float, p_is_training: bool) -> void:
	train_queue = p_train_queue.duplicate()
	train_elapsed = p_train_elapsed
	is_training = p_is_training
	if train_bar:
		if is_training and not train_queue.is_empty():
			var unit_type = "artillery" if train_queue.front() == "artillery" else "soldier"
			var duration = GameManager.BUILD_TIMES.get(unit_type, 8.0)
			train_bar.visible = true
			train_bar.value = clampf(train_elapsed / duration * 100.0, 0.0, 100.0)
		else:
			train_bar.visible = false
