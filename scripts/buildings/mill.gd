class_name Mill
extends ProductionBuilding

## grain -> flour. The first link in the bread chain.


func _ready() -> void:
	resource_group = "mills"
	yield_resource = "flour"
	inputs = {"grain": 1}
	max_workers = 2
	base_production_rate = 0.7
	max_stockpile = 40
	super._ready()
