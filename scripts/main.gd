extends Node2D

func _ready():
	# Without this, CollisionObject2D "input_event" signals (used by
	# buildings and units for click-to-select) never fire, since physics
	# picking is off by default on the viewport.
	get_viewport().physics_object_picking = true
