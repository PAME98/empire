class_name VillageCenter
extends Building

## The starting hub: drop-off point for all gathered resources (citizens path
## here automatically) and where new citizens are recruited. Always starts
## already-built so a fresh game has somewhere to deliver to immediately.

@export var spawn_offset: Vector3 = Vector3(0, 0, 86)
@export var recruit_time: float = 5.0

var recruit_queue: Array = []  # [{type, duration}]
var recruit_elapsed: float = 0.0
var is_recruiting: bool = false

@onready var recruit_bar: ProgressBar = get_node_or_null("RecruitBar")


func _ready() -> void:
	super._ready()
	add_to_group("village_centers")
	if not is_constructed:
		finish_building()
	if recruit_bar:
		recruit_bar.visible = false


func _process(delta: float) -> void:
	super._process(delta)

	if not is_recruiting or recruit_queue.is_empty():
		return

	recruit_elapsed += delta
	var current = recruit_queue[0]
	if recruit_bar:
		recruit_bar.value = clampf(recruit_elapsed / current["duration"] * 100.0, 0.0, 100.0)

	if recruit_elapsed >= current["duration"]:
		_complete_recruit()
		recruit_queue.pop_front()
		recruit_elapsed = 0.0
		_start_next_recruit()


func queue_citizen() -> bool:
	var cost = {"food": 40, "water": 8}
	if GameManager.population >= GameManager.housing_capacity:
		GameManager.notify("Need more housing before recruiting.")
		return false
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough food or water to recruit a citizen.")
		return false
	GameManager.spend(cost)
	recruit_queue.append({"type": "citizen", "duration": recruit_time})
	if not is_recruiting:
		_start_next_recruit()
	return true


func _start_next_recruit() -> void:
	if recruit_queue.is_empty():
		is_recruiting = false
		if recruit_bar:
			recruit_bar.visible = false
		return
	is_recruiting = true
	recruit_elapsed = 0.0
	if recruit_bar:
		recruit_bar.visible = true
		recruit_bar.value = 0.0


func _complete_recruit() -> void:
	# Recruiting mutates shared state, so only the authority spawns. The unit
	# MUST go through server_spawn_unit so it gets a unit_id and is replicated
	# to every peer — instantiating locally makes it invisible to clients and
	# uncommandable (no unit_id for the order filter to reference).
	if not GameManager.is_sim_authority():
		return
	var spawn_pos := global_position + spawn_offset \
		+ Vector3(randf_range(-18, 18), 0, randf_range(-18, 18))
	var citizen = NetworkCommands.server_spawn_unit(
		"res://scenes/units/citizen.tscn", spawn_pos, team
	)
	if citizen == null:
		return
	if citizen.has_method("setup_as_adult"):
		citizen.setup_as_adult()
	GameManager.register_population(citizen)
