class_name VegetableGarden
extends ResourceBuilding

## Grows vegetables — a "variety" food that lifts the birth rate.


func _ready() -> void:
	resource_group = "veg_gardens"
	yield_resource = "vegetables"
	max_workers = 3
	base_production_rate = 0.9
	max_stockpile = 60
	super._ready()
