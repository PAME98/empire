class_name Barracks
extends Building

## Converts stockpiled resources into military units. This is the bridge
## between the economy half of the game and the RTS-combat half: soldiers
## cost food/gold the citizen economy produced, so a healthy economy is a
## prerequisite for a real army rather than the two systems being unrelated.

@export var spawn_offset: Vector2 = Vector2(0, 70)

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

	if not is_constructed or not is_training or train_queue.is_empty():
		return

	train_elapsed += delta
	var duration = GameManager.BUILD_TIMES.get("soldier", 8.0)
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
	train_queue.append(true)
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
	var soldier = preload("res://scenes/soldier.tscn").instantiate()
	soldier.global_position = global_position + spawn_offset + Vector2(randf_range(-18, 18), randf_range(-18, 18))
	soldier.team = team
	get_tree().current_scene.get_node("Units").add_child(soldier)
	GameManager.register_soldier(soldier)
