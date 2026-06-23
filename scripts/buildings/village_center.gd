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
	var citizen = preload("res://scenes/units/citizen.tscn").instantiate()
	citizen.global_position = global_position + spawn_offset + Vector3(randf_range(-18, 18), 0, randf_range(-18, 18))
	citizen.team = team
	get_tree().current_scene.get_node("Units").add_child(citizen)
	citizen.setup_as_adult()
	GameManager.register_population(citizen)
