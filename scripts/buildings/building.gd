class_name Building
extends StaticBody3D

## Shared base for all structures: village center, houses, resource buildings,
## barracks. Handles construction progress, health, and selection — concrete
## buildings add production/training behaviour on top.
##
## 3D port: construction progress is shown by swapping the translucent
## ConstructionMesh for the solid FinishedMesh (and in the HUD when selected),
## rather than the in-world 2D progress bar the 2D version drew.

signal destroyed(building)

@export var max_health: int = 400
@export var build_time: float = 6.0
@export var team: int = 0
## When true the building is already finished on spawn (used for the
## hand-placed starting buildings).
@export var starts_built: bool = false

var health: int
var build_progress: float = 0.0
var is_constructed: bool = false
var selected: bool = false

@onready var construction_sprite: Node = get_node_or_null("ConstructionMesh")
@onready var finished_sprite: Node = get_node_or_null("FinishedMesh")
@onready var selection_ring: Node = get_node_or_null("SelectionRing")


func _ready() -> void:
	health = max_health
	add_to_group("buildings")
	if starts_built:
		build_progress = build_time
	if not is_constructed and not starts_built:
		add_to_group("construction_sites")
	_refresh_construction_visual()
	if selection_ring:
		selection_ring.visible = false
	if not is_constructed and build_progress >= build_time:
		finish_building()


func _process(_delta: float) -> void:
	# Kept so subclasses can safely call super._process(delta).
	pass


func add_build_progress(amount: float) -> void:
	if is_constructed:
		return
	build_progress += amount
	if build_progress >= build_time:
		finish_building()


func finish_building() -> void:
	if is_constructed:
		return
	is_constructed = true
	remove_from_group("construction_sites")
	_refresh_construction_visual()


func _refresh_construction_visual() -> void:
	if construction_sprite:
		construction_sprite.visible = not is_constructed
	if finished_sprite:
		finished_sprite.visible = is_constructed


func set_selected(value: bool) -> void:
	selected = value
	if selection_ring:
		selection_ring.visible = value


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		destroy()


func destroy() -> void:
	destroyed.emit(self)
	queue_free()
