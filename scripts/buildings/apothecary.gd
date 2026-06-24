class_name Apothecary
extends ProductionBuilding

## herbs + water -> medicine. Medicine raises the birth ceiling (health_factor
## in _check_births) and can optionally cut elder deaths (see INTEGRATION.md).


func _ready() -> void:
	resource_group = "apothecaries"
	yield_resource = "medicine"
	inputs = {"herbs": 1, "water": 1}
	max_workers = 2
	base_production_rate = 0.4
	max_stockpile = 20
	super._ready()
