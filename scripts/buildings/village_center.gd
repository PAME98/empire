class_name VillageCenter
extends Building

## The starting hub: drop-off point for all gathered resources (citizens path
## here automatically) and where new citizens are recruited. Always starts
## already-built so a fresh game has somewhere to deliver to immediately.
##
## CLIENT STATE: recruit_elapsed/recruit_queue/is_recruiting only ever advance
## on the host's copy (see _process below) — see Barracks for the identical
## issue and why apply_network_state_extra exists.

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

	if not GameManager.is_sim_authority():
		return

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
	var cost := {"food": 40, "water": 8}
	# Runs on the HOST for whichever team owns this building, so it must use
	# THAT team's pool — not _my_team(), which is always the host's team.
	var pop: Dictionary = GameManager.team_population.get(team, {})
	if pop.get("population", 0) >= pop.get("housing_capacity", 0):
		GameManager.notify_team(team, "Need more housing before recruiting.")
		return false
	if not GameManager.can_afford_for_team(cost, team):
		GameManager.notify_team(team, "Not enough food or water to recruit a citizen.")
		return false
	GameManager.spend_for_team(cost, team)
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


## NETWORKING: client-only mirror of the host's recruit queue/progress.
func apply_network_state_extra(p_recruit_queue: Array, p_recruit_elapsed: float, p_is_recruiting: bool) -> void:
	recruit_queue = p_recruit_queue.duplicate(true)
	recruit_elapsed = p_recruit_elapsed
	is_recruiting = p_is_recruiting
	if recruit_bar:
		if is_recruiting and not recruit_queue.is_empty():
			recruit_bar.visible = true
			recruit_bar.value = clampf(recruit_elapsed / recruit_queue[0]["duration"] * 100.0, 0.0, 100.0)
		else:
			recruit_bar.visible = false
