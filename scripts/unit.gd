class_name Unit
extends CharacterBody2D

@export var speed: float = 100.0
@export var health: int = 100
@export var max_health: int = 100
@export var team: int = 0

var selected: bool = false
var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var current_task: String = "idle"

@onready var selection_ring = $SelectionRing
@onready var health_bar = $HealthBar

func _ready():
	add_to_group("units")
	selection_ring.visible = false
	update_health_bar()

func _physics_process(_delta):
	if is_moving:
		var direction = (target_position - global_position).normalized()
		var distance = global_position.distance_to(target_position)

		if distance > 5:
			velocity = direction * speed
			move_and_slide()
		else:
			is_moving = false
			velocity = Vector2.ZERO
			on_reached_target()

func move_to(pos: Vector2):
	target_position = pos
	is_moving = true

func on_reached_target():
	pass

func set_selected(value: bool):
	selected = value
	selection_ring.visible = value

func take_damage(amount: int):
	health -= amount
	update_health_bar()
	if health <= 0:
		die()

func update_health_bar():
	if health_bar:
		health_bar.value = float(health) / max_health * 100

func die():
	GameManager.remove_population()
	queue_free()

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameManager.select_unit(self)
