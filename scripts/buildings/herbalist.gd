class_name HerbalistHut
extends ResourceBuilding

## Gathers herbs — the input to medicine at the Apothecary.


func _ready() -> void:
	resource_group = "herbalists"
	yield_resource = "herbs"
	max_workers = 2
	base_production_rate = 0.7
	max_stockpile = 40
	super._ready()
