class_name LumberCamp
extends ResourceBuilding


func _ready() -> void:
	resource_group = "lumber_camps"
	yield_resource = "wood"
	max_workers = 3
	base_production_rate = 1.2
	max_stockpile = 60
	super._ready()
