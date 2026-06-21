class_name Building
extends StaticBody2D

@export var build_time: float = 5.0
@export var health: int = 500
@export var max_health: int = 500
@export var team: int = 0

var build_progress: float = 0.0
var is_constructed: bool = false

@onready var construction_sprite = $ConstructionSprite
@onready var finished_sprite = $FinishedSprite
@onready var health_bar = $HealthBar
@onready var selection_ring = $SelectionRing

func _ready():
	selection_ring.visible = false
	construction_sprite.visible = true
	finished_sprite.visible = false
	update_health_bar()

func finish_building():
	is_constructed = true
	construction_sprite.visible = false
	finished_sprite.visible = true

func set_selected(value: bool):
	selection_ring.visible = value

func take_damage(amount: int):
	health -= amount
	update_health_bar()
	if health <= 0:
		destroy()

func update_health_bar():
	if health_bar:
		health_bar.value = float(health) / max_health * 100

func destroy():
	queue_free()

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameManager.select_building(self)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		pass
