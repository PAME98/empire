class_name Farm
extends ResourceBuilding


func _ready() -> void:
	resource_group = "farms"
	yield_resource = "food"
	max_workers = 3
	base_production_rate = 1.4
	max_stockpile = 60
	super._ready()
	add_to_group("food_sources")
