extends Node3D

## Registers the hand-placed starting citizens with GameManager on boot, and
## seeds initial housing from the starting house(s) already in the scene
## (Building._ready -> House._ready run before this, but registration of the
## housing total itself happens through normal House.finish_building, so all
## this needs to do is count citizens).


func _ready() -> void:
	for citizen in get_tree().get_nodes_in_group("citizens"):
		if is_instance_valid(citizen):
			GameManager.all_citizens.append(citizen)
			GameManager.adult_count += 1
			GameManager.population += 1

	GameManager.update_ui()
