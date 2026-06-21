extends Node

signal resources_changed(food: int, wood: int, population: int, max_pop: int)
signal unit_selected(unit)
signal building_selected(building)
signal selection_cleared
signal placement_mode_changed(active: bool, building_type: String)

# Resources
var food: int = 200
var wood: int = 150
var population: int = 0
var max_population: int = 10

# Costs
const WORKER_COST = {"food": 50, "wood": 0}
const SOLDIER_COST = {"food": 75, "wood": 25}
const FARM_COST = {"food": 0, "wood": 75}
const HOUSE_COST = {"food": 0, "wood": 50}

# Selection
var selected_units: Array[Node2D] = []
var selected_building: Node2D = null

# Building placement
var is_placing_building: bool = false
var placement_building_type: String = ""
var placement_builder: Node2D = null

func _ready():
	update_ui()

func can_afford(cost: Dictionary) -> bool:
	return food >= cost.get("food", 0) and wood >= cost.get("wood", 0)

func spend_resources(cost: Dictionary):
	food -= cost.get("food", 0)
	wood -= cost.get("wood", 0)
	update_ui()

func add_resources(food_add: int = 0, wood_add: int = 0):
	food += food_add
	wood += wood_add
	update_ui()

func update_ui():
	resources_changed.emit(food, wood, population, max_population)

func select_unit(unit: Node2D):
	clear_selection()
	selected_units.append(unit)
	unit.set_selected(true)
	unit_selected.emit(unit)

func select_building(building: Node2D):
	clear_selection()
	selected_building = building
	building.set_selected(true)
	building_selected.emit(building)

func clear_selection():
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected_units.clear()
	if selected_building and is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	selection_cleared.emit()

func add_population():
	population += 1
	update_ui()

func remove_population():
	population -= 1
	update_ui()

func start_building_placement(building_type: String, builder: Node2D):
	is_placing_building = true
	placement_building_type = building_type
	placement_builder = builder
	placement_mode_changed.emit(true, building_type)

func cancel_building_placement():
	is_placing_building = false
	placement_building_type = ""
	placement_builder = null
	placement_mode_changed.emit(false, "")
