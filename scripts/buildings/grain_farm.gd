class_name GrainFarm
extends ResourceBuilding

## Grows grain — the head of the bread chain (grain -> flour -> bread).
## Produces freely (no deposit), staffed automatically like any farm.


func _ready() -> void:
	resource_group = "grain_farms"
	yield_resource = "grain"
	max_workers = 3
	base_production_rate = 1.0
	max_stockpile = 60
	super._ready()
