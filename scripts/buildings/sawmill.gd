class_name Sawmill
extends ProductionBuilding

## wood -> planks. Planks feed the tool/weapon chains and (later) higher-tier
## construction.


func _ready() -> void:
	resource_group = "sawmills"
	yield_resource = "planks"
	inputs = {"wood": 1}
	max_workers = 3
	base_production_rate = 0.8
	max_stockpile = 50
	super._ready()
