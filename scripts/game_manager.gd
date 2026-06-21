extends Node

## Central autoload: economy resources, time/season/aging simulation,
## global selection state, and signals the UI listens to.
## This is the single source of truth other scripts read/write through —
## buildings, citizens and soldiers never talk to each other directly
## for resources/population, they always go through GameManager.

signal resources_changed(food: int, wood: int, stone: int, gold: int, population: int, max_population: int)
signal selection_changed(units: Array, building, resource_node)
signal time_changed(year: int, season: String, season_progress: float)
signal citizen_born(citizen)
signal citizen_died(citizen, cause: String)
signal placement_mode_changed(active: bool, building_id: String)
signal notification(text: String)

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------
var food: int = 250
var wood: int = 200
var stone: int = 100
var gold: int = 50

# ---------------------------------------------------------------------------
# Population
# ---------------------------------------------------------------------------
var population: int = 0
var housing_capacity: int = 0
var child_count: int = 0
var adult_count: int = 0
var elder_count: int = 0
var all_citizens: Array = []
var all_soldiers: Array = []

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------
const SEASONS: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_DURATION: float = 45.0  # seconds per season -> 3 min/year
var year: int = 1
var season_index: int = 0
var season_timer: float = 0.0

# ---------------------------------------------------------------------------
# Building / unit costs — single source of truth for the whole game
# ---------------------------------------------------------------------------
const COSTS := {
	"house":       {"wood": 40, "stone": 10},
	"farm":        {"wood": 50},
	"lumber_camp": {"wood": 30, "stone": 10},
	"quarry":      {"wood": 40},
	"barracks":    {"wood": 80, "stone": 40},
	"soldier":     {"food": 60, "gold": 10},
}

const BUILD_TIMES := {
	"house": 6.0,
	"farm": 6.0,
	"lumber_camp": 7.0,
	"quarry": 7.0,
	"barracks": 10.0,
	"soldier": 8.0,
}

# ---------------------------------------------------------------------------
# Selection state — multi-select friendly. Buildings/resources are exclusive
# of units and of each other (selecting one clears the others).
# ---------------------------------------------------------------------------
var selected_units: Array = []
var selected_building = null
var selected_resource_node = null

# ---------------------------------------------------------------------------
# Building placement (ghost-follow-mouse mode)
# ---------------------------------------------------------------------------
var is_placing_building: bool = false
var placement_building_id: String = ""
var placement_builder = null  # citizen who queued the building, if any


func _process(delta: float) -> void:
	season_timer += delta
	if season_timer >= SEASON_DURATION:
		season_timer -= SEASON_DURATION
		_advance_season()
	time_changed.emit(year, SEASONS[season_index], season_timer / SEASON_DURATION)


func _advance_season() -> void:
	season_index = (season_index + 1) % 4
	if season_index == 0:
		year += 1
		_yearly_tick()


func _yearly_tick() -> void:
	# Citizens eat once a year. Shortfall causes starvation deaths.
	var needed = population
	if food >= needed:
		food -= needed
	else:
		var deficit = needed - food
		food = 0
		_starve(deficit)

	# Citizens age up by exactly one year.
	for c in all_citizens.duplicate():
		if is_instance_valid(c):
			c.age_up()

	_check_births()
	update_ui()


func _starve(deficit: int) -> void:
	var deaths = mini(deficit, all_citizens.size())
	for i in range(deaths):
		if all_citizens.is_empty():
			break
		var victim = all_citizens.pick_random()
		if is_instance_valid(victim):
			victim.die("starvation")


func _check_births() -> void:
	var free_housing = housing_capacity - population
	if free_housing <= 0 or food < 30:
		return
	var adult_pairs = int(adult_count / 2.0)
	var births = mini(adult_pairs, mini(free_housing, int(food / 15.0)))
	for i in range(births):
		_spawn_child()


func _spawn_child() -> void:
	var houses = get_tree().get_nodes_in_group("houses")
	if houses.is_empty():
		return
	var house = houses.pick_random()
	if not is_instance_valid(house):
		return

	var child = preload("res://scenes/citizen.tscn").instantiate()
	child.global_position = house.global_position + Vector2(randf_range(-24, 24), randf_range(-24, 24))
	get_tree().current_scene.get_node("Units").add_child(child)
	child.setup_as_child()

	all_citizens.append(child)
	child_count += 1
	population += 1
	food -= 15
	citizen_born.emit(child)
	update_ui()


# ---------------------------------------------------------------------------
# Resource helpers
# ---------------------------------------------------------------------------
func can_afford(cost: Dictionary) -> bool:
	return (food >= cost.get("food", 0)
		and wood >= cost.get("wood", 0)
		and stone >= cost.get("stone", 0)
		and gold >= cost.get("gold", 0))


func spend(cost: Dictionary) -> void:
	food -= cost.get("food", 0)
	wood -= cost.get("wood", 0)
	stone -= cost.get("stone", 0)
	gold -= cost.get("gold", 0)
	update_ui()


func add_resources(f: int = 0, w: int = 0, s: int = 0, g: int = 0) -> void:
	food += f
	wood += w
	stone += s
	gold += g
	update_ui()


func update_ui() -> void:
	resources_changed.emit(food, wood, stone, gold, population, housing_capacity)


# ---------------------------------------------------------------------------
# Population helpers
# ---------------------------------------------------------------------------
func register_population(citizen) -> void:
	population += 1
	all_citizens.append(citizen)
	adult_count += 1
	update_ui()


func register_soldier(soldier) -> void:
	population += 1
	all_soldiers.append(soldier)
	update_ui()


func remove_population(unit, cause: String = "") -> void:
	population -= 1
	if unit in all_citizens:
		all_citizens.erase(unit)
		match unit.life_stage:
			unit.LifeStage.CHILD:
				child_count -= 1
			unit.LifeStage.ADULT:
				adult_count -= 1
			unit.LifeStage.ELDER:
				elder_count -= 1
		citizen_died.emit(unit, cause)
	elif unit in all_soldiers:
		all_soldiers.erase(unit)
	update_ui()


func change_housing(delta: int) -> void:
	housing_capacity += delta
	update_ui()


# ---------------------------------------------------------------------------
# Selection — this is what makes the RTS controls solid.
# ---------------------------------------------------------------------------
func select_units(units: Array) -> void:
	clear_selection()
	for u in units:
		if is_instance_valid(u):
			selected_units.append(u)
			u.set_selected(true)
	selection_changed.emit(selected_units, null, null)


func select_building(building) -> void:
	clear_selection()
	selected_building = building
	building.set_selected(true)
	selection_changed.emit([], building, null)


func select_resource_node(resource_node) -> void:
	clear_selection()
	selected_resource_node = resource_node
	resource_node.set_selected(true)
	selection_changed.emit([], null, resource_node)


func clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()
	if selected_building and is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	if selected_resource_node and is_instance_valid(selected_resource_node):
		selected_resource_node.set_selected(false)
	selected_resource_node = null
	selection_changed.emit([], null, null)


# ---------------------------------------------------------------------------
# Building placement mode
# ---------------------------------------------------------------------------
func start_building_placement(building_id: String, builder = null) -> void:
	is_placing_building = true
	placement_building_id = building_id
	placement_builder = builder
	placement_mode_changed.emit(true, building_id)


func cancel_building_placement() -> void:
	is_placing_building = false
	placement_building_id = ""
	placement_builder = null
	placement_mode_changed.emit(false, "")


func notify(text: String) -> void:
	notification.emit(text)
