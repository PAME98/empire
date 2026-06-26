class_name Warehouse
extends StorageBuilding

## Large enclosed storage that accepts every good. Pricier and slower to raise
## than a Stockpile but central to a mature town's logistics.


func _ready() -> void:
	capacity = 600
	accepts = []  # empty = accept anything
	super._ready()
	add_to_group("warehouses")
