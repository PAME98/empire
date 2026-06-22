# ===========================================================================
# CHANGES FOR camera_controller.gd
# ===========================================================================
#
# 1) Add "mine" to the BUILDING_SCENES dictionary:

const BUILDING_SCENES := {
	"house": "res://scenes/house.tscn",
	"farm": "res://scenes/farm.tscn",
	"lumber_camp": "res://scenes/lumber_camp.tscn",
	"quarry": "res://scenes/quarry.tscn",
	"mine": "res://scenes/mine.tscn",
	"barracks": "res://scenes/barracks.tscn",
}


# 2) REPLACE the whole _confirm_placement() function with this version.
#    The only new part is the deposit bind/validation block — it instantiates
#    the building, tries to bind it to a deposit if it needs one, and rolls
#    everything back (refund + free the node) if there's no deposit under it.

func _confirm_placement() -> void:
	var building_id = GameManager.placement_building_id
	var scene_path = BUILDING_SCENES.get(building_id)
	var cost = GameManager.COSTS.get(building_id)
	if scene_path == null or cost == null:
		GameManager.cancel_building_placement()
		return
	if not GameManager.can_afford(cost):
		GameManager.notify("Not enough resources for that building.")
		GameManager.cancel_building_placement()
		return

	var building = load(scene_path).instantiate()
	building.global_position = get_global_mouse_position()
	get_tree().current_scene.get_node("Buildings").add_child(building)

	# Deposit-backed buildings (quarry/mine) must sit on a matching deposit.
	if building is ResourceBuilding and building.deposit_group != "":
		if not building.bind_to_deposit(48.0):
			var what = "a mountain" if building.deposit_group == "stone_sources" else "an iron-ore deposit"
			GameManager.notify("A %s must be placed on %s." % [building_id, what])
			building.queue_free()
			GameManager.cancel_building_placement()
			return

	# Only spend once we know the placement is valid.
	GameManager.spend(cost)

	var builder = GameManager.placement_builder
	if is_instance_valid(builder) and builder.has_method("command_build"):
		builder.command_build(building)
	elif not GameManager.selected_units.is_empty():
		for unit in GameManager.selected_units:
			if is_instance_valid(unit) and unit.has_method("command_build"):
				unit.command_build(building)

	GameManager.cancel_building_placement()
