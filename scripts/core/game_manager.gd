extends Node

## Central autoload: economy resources, time/season/aging simulation,
## global selection state, and signals the UI listens to.
## This is the single source of truth other scripts read/write through —
## buildings, citizens and soldiers never talk to each other directly
## for resources/population, they always go through GameManager.

signal resources_changed(food: int, wood: int, stone: int, gold: int, iron: int, water: int, population: int, max_population: int)
signal selection_changed(units: Array, building, resource_node)
signal time_changed(year: int, season: String, season_progress: float)
signal citizen_born(citizen)
signal citizen_died(citizen, cause: String)
signal placement_mode_changed(active: bool, building_id: String)
signal attack_targeting_mode_changed(active: bool, radius: float)
signal notification(text: String)

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------
var food: int = 250
var wood: int = 200
var stone: int = 100
var gold: int = 50
var iron: int = 0    # mined from iron-ore deposits; used for advanced units
var water: int = 60  # gathered from rivers; consumed when recruiting citizens

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
var all_artillery: Array = []

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
	"mine":        {"wood": 40, "stone": 20},
	"barracks":    {"wood": 80, "stone": 40},
	"soldier":     {"food": 60, "gold": 10},
	"artillery":   {"food": 90, "wood": 20, "iron": 20, "gold": 20},
}

const BUILD_TIMES := {
	"house": 6.0,
	"farm": 6.0,
	"lumber_camp": 7.0,
	"quarry": 7.0,
	"mine": 8.0,
	"barracks": 10.0,
	"soldier": 8.0,
	"artillery": 14.0,
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

# ---------------------------------------------------------------------------
# Artillery attack-position targeting (T then left-click an area)
# ---------------------------------------------------------------------------
var is_targeting_attack_position: bool = false


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

	var child = preload("res://scenes/units/citizen.tscn").instantiate()
	child.global_position = house.global_position + Vector3(randf_range(-24, 24), 0, randf_range(-24, 24))
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
		and gold >= cost.get("gold", 0)
		and iron >= cost.get("iron", 0)
		and water >= cost.get("water", 0))


func spend(cost: Dictionary) -> void:
	food -= cost.get("food", 0)
	wood -= cost.get("wood", 0)
	stone -= cost.get("stone", 0)
	gold -= cost.get("gold", 0)
	iron -= cost.get("iron", 0)
	water -= cost.get("water", 0)
	update_ui()


func add_resources(f: int = 0, w: int = 0, s: int = 0, g: int = 0, i: int = 0, wa: int = 0) -> void:
	food += f
	wood += w
	stone += s
	gold += g
	iron += i
	water += wa
	update_ui()


func update_ui() -> void:
	resources_changed.emit(food, wood, stone, gold, iron, water, population, housing_capacity)


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
	
func register_artillery(artillery) -> void:
	population += 1
	all_artillery.append(artillery)
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


## Whoever currently drives the placement ghost (camera_controller.gd /
## ui_controller.gd — moves PlacementGhost to the mouse's ground raycast hit
## each frame) should call this before confirming a placement on click.
## Previously nothing validated placement at all, so buildings could be
## dropped on top of rivers, mountains, or trees.
##
## `footprint_radius` should be roughly half the building's largest XZ
## dimension (e.g. farm.tscn's 64x64 footprint -> ~36 to include a margin).
func can_place_building_at(world_pos: Vector3, footprint_radius: float = 36.0) -> bool:
	# Coastline check: must be on land (this is what blocks the ocean).
	var map_gen = Engine.get_main_loop().current_scene.get_node_or_null("MapGenerator")
	if map_gen and map_gen.has_method("is_land_at"):
		if not map_gen.is_land_at(Vector2(world_pos.x, world_pos.z)):
			return false
 
	var space_state = Engine.get_main_loop().current_scene.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = footprint_radius
	shape.height = 40.0
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, world_pos)
	query.collision_mask = 1
 
	var hits = space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider = hit.get("collider")
		if collider == null:
			continue
		# Trees (wood_sources) are intentionally NOT blocking — they get
		# cleared on build. Only hard obstacles block.
		if collider.is_in_group("mountains") \
				or collider.is_in_group("rivers") \
				or collider.is_in_group("water_sources") \
				or collider.is_in_group("buildings"):
			return false
	return true

# Removes any trees overlapping the footprint (call right after placing a
# building, and when founding the town on a forest).
func clear_trees_at(world_pos: Vector3, radius: float = 44.0) -> void:
	var space_state = Engine.get_main_loop().current_scene.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 60.0
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, world_pos)
	query.collision_mask = 1
 
	var hits = space_state.intersect_shape(query, 32)
	for hit in hits:
		var collider = hit.get("collider")
		if collider and is_instance_valid(collider) and collider.is_in_group("wood_sources"):
			collider.queue_free()
 

# ---------------------------------------------------------------------------
# Artillery attack-position targeting mode
# ---------------------------------------------------------------------------
func start_attack_position_targeting(radius: float = 60.0) -> void:
	is_targeting_attack_position = true
	attack_targeting_mode_changed.emit(true, radius)


func cancel_attack_position_targeting() -> void:
	is_targeting_attack_position = false
	attack_targeting_mode_changed.emit(false, 0.0)


func notify(text: String) -> void:
	notification.emit(text)
