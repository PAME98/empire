extends Node3D

## On a procedurally-generated map, the starting town center and citizens are
## spawned AND registered by MapGenerator the moment the player founds the town
## (see map_generator._confirm_placement). So there's nothing to register here
## on boot — doing so would double-count or register citizens that get cleared.
## We just make sure the HUD is initialised.
##
## FIX: any units/buildings that were placed directly in main.tscn (the 5
## starting citizens, the VillageCenter, the House) never go through
## server_spawn_unit / server_spawn_building, so they never get a unit_id or
## building_net_id meta tag. Every right-click command filters by unit_id
## (get_meta("unit_id", -1) == -1 -> filtered out -> unit_ids is empty ->
## nothing happens). We assign IDs here on _ready so those units and buildings
## are addressable by the command system.


func _ready() -> void:
	_assign_missing_ids()
	GameManager.update_ui()


func _assign_missing_ids() -> void:
	# Assign unit_id to any units already in the tree that don't have one.
	# This covers the 5 starting citizens placed directly in main.tscn.
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit):
			continue
		if not unit.has_meta("unit_id") or unit.get_meta("unit_id", -1) == -1:
			var uid := NetworkCommands._alloc_unit_id()
			unit.set_meta("unit_id", uid)

	# Assign building_net_id to any buildings already in the tree that don't have one.
	# This covers the VillageCenter and House placed directly in main.tscn.
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		if not building.has_meta("building_net_id") or building.get_meta("building_net_id", -1) == -1:
			var bid := NetworkCommands._alloc_building_id()
			building.set_meta("building_net_id", bid)
