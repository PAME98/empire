class_name CharcoalKiln
extends ProductionBuilding

## wood -> coal (charcoal). Gives the Smelter its fuel without needing a coal
## deposit on the map. Swap to a real Coal Mine later if you add coal-bearing
## mountains.


func _ready() -> void:
	resource_group = "charcoal_kilns"
	yield_resource = "coal"
	inputs = {"wood": 2}
	max_workers = 2
	base_production_rate = 0.6
	max_stockpile = 40
	super._ready()
