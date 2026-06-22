class_name Mine
extends ResourceBuilding
## Iron mine. Like the Quarry, must be built on top of a deposit
## (an iron-ore ResourceNode) and drains that deposit as it produces.


func _ready() -> void:
	resource_group = "mines"
	deposit_group = "iron_sources"   # must be built on an iron-ore deposit
	max_workers = 3
	base_production_rate = 0.8
	max_stockpile = 60
	super._ready()
