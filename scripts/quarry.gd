class_name Quarry
extends ResourceBuilding


func _ready() -> void:
	resource_group = "quarries"
	max_workers = 3
	base_production_rate = 0.9
	max_stockpile = 60
	super._ready()
