class_name VillageCenter
extends Building

@export var spawn_offset: Vector2 = Vector2(0, 80)
@export var worker_recruit_time: float = 4.0
@export var soldier_recruit_time: float = 6.0

@onready var recruit_bar: ProgressBar = $RecruitBar

# Each entry: {"type": "worker"|"soldier", "duration": float}
var recruit_queue: Array = []
var recruit_elapsed: float = 0.0
var is_recruiting: bool = false

func _ready():
	super._ready()
	add_to_group("village_centers")
	# A Village Center placed directly in a scene is already built.
	if not is_constructed:
		finish_building()
	if recruit_bar:
		recruit_bar.visible = false
		recruit_bar.value = 0

func _process(delta):
	if not is_recruiting:
		return

	recruit_elapsed += delta
	var current = recruit_queue[0]
	recruit_bar.value = clamp(recruit_elapsed / current["duration"] * 100.0, 0, 100)

	if recruit_elapsed >= current["duration"]:
		_complete_recruit(current["type"])
		recruit_queue.pop_front()
		recruit_elapsed = 0.0
		_start_next_recruit()

func spawn_worker() -> bool:
	return _queue_recruit("worker", GameManager.WORKER_COST, worker_recruit_time)

func spawn_soldier() -> bool:
	return _queue_recruit("soldier", GameManager.SOLDIER_COST, soldier_recruit_time)

func _queue_recruit(unit_type: String, cost: Dictionary, duration: float) -> bool:
	if GameManager.population + recruit_queue.size() >= GameManager.max_population:
		return false
	if not GameManager.can_afford(cost):
		return false

	GameManager.spend_resources(cost)
	recruit_queue.append({"type": unit_type, "duration": duration})

	if not is_recruiting:
		_start_next_recruit()

	return true

func _start_next_recruit():
	if recruit_queue.is_empty():
		is_recruiting = false
		if recruit_bar:
			recruit_bar.visible = false
		return

	is_recruiting = true
	recruit_elapsed = 0.0
	if recruit_bar:
		recruit_bar.visible = true
		recruit_bar.value = 0

func _complete_recruit(unit_type: String):
	GameManager.add_population()

	var unit
	if unit_type == "worker":
		unit = preload("res://scenes/worker.tscn").instantiate()
	else:
		unit = preload("res://scenes/soldier.tscn").instantiate()

	unit.global_position = global_position + spawn_offset
	unit.team = team
	get_tree().current_scene.add_child(unit)

	GameManager.clear_selection()
	GameManager.select_unit(unit)
