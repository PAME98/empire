class_name Stockpile
extends StorageBuilding

## Small, cheap, open-air storage. Quick to build — drop several near your
## fields so harvested crops have somewhere close to be hauled. Takes the bulky
## everyday goods; refined/precious goods (gold, ingots) want a Warehouse.


func _ready() -> void:
	capacity = 120
	accepts = ["wheat", "grain", "flour", "food", "vegetables", "meat", "wood", "stone"]
	super._ready()
	add_to_group("stockpiles")
