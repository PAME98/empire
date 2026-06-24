class_name Smelter
extends ProductionBuilding

## iron_ore + coal -> iron_ingot. The gateway to tools and weapons.
##
## NOTE: your Mine currently yields "iron". If you rename the mine's
## yield_resource to "iron_ore" (recommended — keeps "iron" free as a HUD
## metal if you want it), change the input key below to match. As shipped this
## consumes "iron" so it works against the current Mine with no other edits.


func _ready() -> void:
	resource_group = "smelters"
	yield_resource = "iron_ingot"
	inputs = {"iron": 1, "coal": 1}
	max_workers = 2
	base_production_rate = 0.5
	max_stockpile = 30
	super._ready()
