class_name ResourceNode
extends StaticBody2D

## A depletable world resource (tree, berry bush, stone deposit...) that
## citizens gather directly via command_gather / the woodcutter auto-job.
## Distinct from ResourceBuilding: this has no worker-slot cap and shrinks
## visually as it's consumed, then disappears when empty.

@export var resource_type: String = "wood"  # "wood", "food", "stone"
@export var amount: int = 120
@export var resource_group: String = "wood_sources"

var max_amount: int
var selected: bool = false
var _selection_ring: ColorRect = null

@onready var sprite: Node = get_node_or_null("Sprite2D")


func _ready() -> void:
	max_amount = amount
	add_to_group("resources")
	add_to_group(resource_group)


func harvest(requested: int) -> int:
	var actual = mini(requested, amount)
	amount -= actual
	_refresh_visual()
	if amount <= 0:
		_deplete()
	return actual


func is_depleted() -> bool:
	return amount <= 0


func set_selected(value: bool) -> void:
	selected = value
	if value and _selection_ring == null:
		_selection_ring = ColorRect.new()
		_selection_ring.color = Color(0, 1, 0, 0.5)
		_selection_ring.size = Vector2(46, 46)
		_selection_ring.position = Vector2(-23, -23)
		add_child(_selection_ring)
		move_child(_selection_ring, 0)  # draw behind the resource sprite, not on top of it
	if _selection_ring:
		_selection_ring.visible = value


func _refresh_visual() -> void:
	if not sprite:
		return
	var ratio = float(amount) / float(max_axis_amount())
	sprite.scale = Vector2.ONE * maxf(ratio, 0.35)


func max_axis_amount() -> int:
	return max_amount if max_amount > 0 else 1


func _deplete() -> void:
	remove_from_group("resources")
	remove_from_group(resource_group)
	if sprite:
		sprite.modulate = Color(0.45, 0.3, 0.15, 0.6)
