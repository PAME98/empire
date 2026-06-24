class_name Bakery
extends ProductionBuilding

## flour + water -> bread. Bread is a staple food AND a "variety" food, so a
## working bakery both feeds the town and nudges the birth rate up.


func _ready() -> void:
	resource_group = "bakeries"
	yield_resource = "bread"
	inputs = {"flour": 1, "water": 1}
	max_workers = 2
	base_production_rate = 0.6
	max_stockpile = 40
	super._ready()
