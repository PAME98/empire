class_name Well
extends ResourceBuilding

## Produces water away from the river — feeds the bakery and apothecary.
## (water is a legacy resource, so it banks straight into GameManager.water.)


func _ready() -> void:
	resource_group = "wells"
	yield_resource = "water"
	max_workers = 2
	base_production_rate = 0.8
	max_stockpile = 50
	super._ready()
