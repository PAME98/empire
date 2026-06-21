class_name Building
extends StaticBody2D

## Shared base for all structures: village center, houses, resource buildings,
## barracks. Handles construction progress, health, and selection — concrete
## buildings add production/training behaviour on top.

signal destroyed(building)

@export var max_health: int = 400
@export var build_time: float = 6.0
@export var team: int = 0

var health: int
var build_progress: float = 0.0
var is_constructed: bool = false
var selected: bool = false

@onready var construction_sprite: Node = get_node_or_null("ConstructionSprite")
@onready var finished_sprite: Node = get_node_or_null("FinishedSprite")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var selection_ring: Node = get_node_or_null("SelectionRing")

var construction_bar: ProgressBar = null
var construction_label: Label = null


func _ready() -> void:
	health = max_health
	add_to_group("buildings")
	if not is_constructed:
		add_to_group("construction_sites")
		_create_construction_feedback()
	_refresh_construction_visual()
	_update_health_bar()
	if selection_ring:
		selection_ring.visible = false
	if not is_constructed and build_progress >= build_time:
		finish_building()


func _create_construction_feedback() -> void:
	# Built in code instead of hand-added to every building scene, so every
	# building type gets the same always-visible "how far along is this"
	# feedback with no risk of one scene drifting out of sync with another.
	# Positioned dynamically above the building's own collision height so it
	# never overlaps the health bar regardless of how big the building is.
	var top_offset = _building_top_offset()

	construction_bar = ProgressBar.new()
	construction_bar.show_percentage = false
	construction_bar.value = 0.0
	construction_bar.size = Vector2(64, 8)
	construction_bar.position = Vector2(-32, top_offset - 26.0)
	construction_bar.modulate = Color(1.0, 0.85, 0.2)
	add_child(construction_bar)

	construction_label = Label.new()
	construction_label.text = "0%"
	construction_label.size = Vector2(64, 16)
	construction_label.position = Vector2(-32, top_offset - 44.0)
	construction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	construction_label.add_theme_font_size_override("font_size", 12)
	add_child(construction_label)


func _building_top_offset() -> float:
	# Half-height of this building's collision shape (negative = upward in
	# Godot's Y-down coordinate space), so feedback widgets clear the
	# building's own sprite regardless of size.
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is RectangleShape2D:
		return -shape_node.shape.size.y * 0.5
	return -32.0


func _process(_delta: float) -> void:
	if not is_constructed and construction_bar:
		var pct = clampf(build_progress / build_time * 100.0, 0.0, 100.0)
		construction_bar.value = pct
		if construction_label:
			construction_label.text = "%d%%" % int(pct)


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
	if construction_bar:
		construction_bar.queue_free()
		construction_bar = null
	if construction_label:
		construction_label.queue_free()
		construction_label = null


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
	_update_health_bar()
	if health <= 0:
		destroy()


func _update_health_bar() -> void:
	if health_bar:
		health_bar.value = float(health) / float(max_health) * 100.0


func destroy() -> void:
	destroyed.emit(self)
	queue_free()
