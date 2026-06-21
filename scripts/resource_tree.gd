class_name ResourceTree
extends StaticBody2D

@export var wood_amount: int = 100

@onready var sprite = $Sprite2D

func _ready():
	add_to_group("resources")
	add_to_group("wood_sources")

func gather(amount: int) -> int:
	var actual = mini(amount, wood_amount)
	wood_amount -= actual

	var ratio = float(wood_amount) / 100.0
	if sprite:
		sprite.scale = Vector2.ONE * max(ratio, 0.3)
		if wood_amount <= 0:
			sprite.modulate = Color(0.5, 0.3, 0.1)

	return actual

func is_depleted() -> bool:
	return wood_amount <= 0

func _on_input_event(_viewport, event, _shape_idx):
	pass
