class_name HunterHut
extends ResourceBuilding

## Yields meat — a "variety" food. (Later: also produce hide/wool for cloth.)


func _ready() -> void:
	resource_group = "hunters"
	yield_resource = "meat"
	max_workers = 2
	base_production_rate = 0.7
	max_stockpile = 40
	super._ready()
