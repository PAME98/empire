class_name Blacksmith
extends ProductionBuilding

## iron_ingot + planks -> tools. Tools are the economy's flywheel: see
## INTEGRATION.md for the one-line hook that makes citizens gather faster
## while the town has tools in stock.


func _ready() -> void:
	resource_group = "blacksmiths"
	yield_resource = "tools"
	inputs = {"iron_ingot": 1, "planks": 1}
	max_workers = 2
	base_production_rate = 0.45
	max_stockpile = 25
	super._ready()
