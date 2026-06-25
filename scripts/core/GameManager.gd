extends Node
## GameManager — central autoload, now multiplayer-aware.
## Per-team resource pools replace the old single global pool.
## Simulation (aging, births, starvation) runs on HOST ONLY.
## Clients receive resource snapshots via NetworkCommands._receive_resources.

signal resources_changed(food: int, wood: int, stone: int, gold: int, iron: int, water: int, population: int, max_population: int)
signal selection_changed(units: Array, building, resource_node)
signal time_changed(year: int, season: String, season_progress: float)
signal citizen_born(citizen)
signal citizen_died(citizen, cause: String)
signal placement_mode_changed(active: bool, building_id: String)
signal attack_targeting_mode_changed(active: bool, radius: float)
signal notification(text: String)
signal demolish_mode_changed(active: bool)

# ---------------------------------------------------------------------------
# Per-team resources  { team_int -> { resource_key -> int } }
# ---------------------------------------------------------------------------
var team_resources: Dictionary = {}
var team_population: Dictionary = {}

# ---------------------------------------------------------------------------
# Legacy single-player aliases (read my own team)
# ---------------------------------------------------------------------------
var food:   int: get = _get_food
var wood:   int: get = _get_wood
var stone:  int: get = _get_stone
var gold:   int: get = _get_gold
var iron:   int: get = _get_iron
var water:  int: get = _get_water
var population:       int: get = _get_pop
var housing_capacity: int: get = _get_housing

func _get_food()    -> int: return _res("food")
func _get_wood()    -> int: return _res("wood")
func _get_stone()   -> int: return _res("stone")
func _get_gold()    -> int: return _res("gold")
func _get_iron()    -> int: return _res("iron")
func _get_water()   -> int: return _res("water")
func _get_pop()     -> int: return _pop("population")
func _get_housing() -> int: return _pop("housing_capacity")

func _res(key: String) -> int:
	return team_resources.get(_my_team(), {}).get(key, 0)

func _pop(key: String) -> int:
	return team_population.get(_my_team(), {}).get(key, 0)

func _my_team() -> int:
	# NetworkManager is an autoload (a regular scene-tree node), not an Engine
	# singleton — Engine.has_singleton() never finds it, and worse, it makes
	# the parser choke on the bare "NetworkManager" identifier in some load
	# orders ("Identifier not declared in the current scope"). Looking it up
	# via the tree by its well-known autoload path avoids both problems and
	# degrades cleanly to team 0 in single-player, before NetworkManager (or
	# any autoload) is even relevant.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		return nm.my_team()
	return 0

# ---------------------------------------------------------------------------
# NetworkCommands accessor — SAME PARSER QUIRK AS _my_team() ABOVE.
# ---------------------------------------------------------------------------
## GameManager and NetworkCommands reference each other, which is a genuine
## bidirectional autoload dependency: whichever one is listed first in the
## Autoload settings holds a forward reference to the one listed second and
## the parser reports "Identifier not declared in the current scope" on the
## bare name. NO autoload ordering can resolve a mutual reference — reordering
## only moves the error to the other file. Resolving via the tree by the
## well-known autoload path breaks the cycle at parse time and works in any
## order. Untyped on purpose so member access stays dynamic (the parser never
## type-checks NetworkCommands' members against a static type here).
var _net_commands = null

func _nc():
	if not is_instance_valid(_net_commands):
		_net_commands = get_node_or_null("/root/NetworkCommands")
	return _net_commands

# ---------------------------------------------------------------------------
# NETWORK AUTHORITY HELPER
# ---------------------------------------------------------------------------
## True if THIS peer is allowed to run simulation logic and mutate shared
## gameplay state (resources, building stockpiles, unit AI, construction
## progress, combat, etc). True in single-player (no multiplayer peer set up
## at all) and true on the host in a networked game. False on every client.
##
## Every script that runs autonomous/timed gameplay logic in _process or
## _physics_process MUST early-return when this is false, or that logic runs
## redundantly (and independently, since RNG/timing differs per peer) on
## every machine — which is what causes desyncs. Player-issued *commands*
## (move/attack/gather/build/place) are NOT affected by this: those already
## go through NetworkCommands RPCs and are validated/executed host-side only.
func is_sim_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()

## Kept for backwards compatibility with existing call sites in this file.
func _is_host() -> bool:
	return is_sim_authority()

# ---------------------------------------------------------------------------
# Population (per-team)
# ---------------------------------------------------------------------------
var child_count:   int = 0
var adult_count:   int = 0
var elder_count:   int = 0
var all_citizens:  Array = []
var all_soldiers:  Array = []
var all_artillery: Array = []

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------
const SEASONS:         Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_DURATION: float         = 45.0
var year:         int   = 1
var season_index: int   = 0
var season_timer: float = 0.0

# ---------------------------------------------------------------------------
# Costs
# ---------------------------------------------------------------------------
const COSTS := {
	"house":       {"wood": 40, "stone": 10},
	"farm":        {"wood": 50},
	"grain_farm":  {"wood": 40},
	"veg_garden":  {"wood": 30},
	"hunter":      {"wood": 30},
	"lumber_camp": {"wood": 30, "stone": 10},
	"quarry":      {"wood": 40},
	"mine":        {"wood": 40, "stone": 20},
	"herbalist":   {"wood": 30},
	"well":        {"wood": 30, "stone": 10},
	"charcoal_kiln": {"wood": 40},
	"mill":        {"wood": 50, "stone": 10},
	"bakery":      {"wood": 50, "stone": 10},
	"sawmill":     {"wood": 40},
	"smelter":     {"wood": 60, "stone": 20},
	"blacksmith":  {"wood": 50, "stone": 20},
	"apothecary":  {"wood": 40},
	"barracks":    {"wood": 80, "stone": 40},
	"soldier":     {"food": 60, "gold": 10},
	"artillery":   {"food": 90, "wood": 20, "iron": 20, "gold": 20},
}

const BUILD_TIMES := {
	"house": 6.0, "farm": 6.0, "lumber_camp": 7.0, "quarry": 7.0,
	"mine": 8.0, "barracks": 10.0, "soldier": 8.0, "artillery": 14.0,
}

# ---------------------------------------------------------------------------
# Selection state
# ---------------------------------------------------------------------------
var selected_units:         Array = []
var selected_building             = null
var selected_resource_node        = null

# ---------------------------------------------------------------------------
# Placement / targeting mode
# ---------------------------------------------------------------------------
var is_placing_building:          bool   = false
var placement_building_id:        String = ""
var placement_builder                    = null
var is_targeting_attack_position: bool   = false
var is_demolish_mode:             bool   = false


# ---------------------------------------------------------------------------
# Init — create resource pools for each team
# ---------------------------------------------------------------------------
func _ready() -> void:
	_init_team(0)
	_init_team(1)


func _init_team(team: int) -> void:
	team_resources[team] = {
		"food": 250, "wood": 200, "stone": 100,
		"gold": 50,  "iron": 0,   "water": 60,
	}
	team_population[team] = {"population": 0, "housing_capacity": 0}


# ---------------------------------------------------------------------------
# Time / season  — host only
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not is_sim_authority():
		return
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
	for team in team_resources.keys():
		var res  := team_resources[team] as Dictionary
		var pop  := team_population[team].get("population", 0) as int
		if res["food"] >= pop:
			res["food"] -= pop
		else:
			var deficit :Variant = pop - res["food"]
			res["food"] = 0
			_starve(deficit, team)
		_nc().server_sync_resources(team)

	for c in all_citizens.duplicate():
		if is_instance_valid(c):
			c.age_up()
	_check_births()
	update_ui()
	# Citizen.age_up() can change life_stage/appearance, which clients need
	# to know about even though they don't run the AI themselves.
	_nc().server_sync_citizen_states()


func _starve(deficit: int, team: int) -> void:
	var victims := all_citizens.filter(func(c): return is_instance_valid(c) and c.team == team)
	for i in mini(deficit, victims.size()):
		victims.pick_random().die("starvation")


func _check_births() -> void:
	for team in team_population.keys():
		var pop  := team_population[team]
		var free := pop["housing_capacity"] - pop["population"]
		var res  := team_resources[team]
		if free <= 0 or res["food"] < 30:
			continue
		var pairs  := int(adult_count / 2.0)
		var births := mini(pairs, mini(free, int(res["food"] / 15.0)))
		for _i in births:
			_spawn_child(team)


func _spawn_child(team: int) -> void:
	var houses := get_tree().get_nodes_in_group("houses").filter(
		func(h): return is_instance_valid(h) and h.team == team
	)
	if houses.is_empty():
		return
	var house: Node = houses.pick_random()
	var pos   := house.global_position + Vector3(
		randf_range(-24, 24), 0, randf_range(-24, 24)
	)
	var child: Node3D = _nc().server_spawn_unit(
		"res://scenes/units/citizen.tscn", pos, team
	)
	if child == null:
		return
	child.setup_as_child()
	all_citizens.append(child)
	child_count += 1
	team_population[team]["population"] += 1
	team_resources[team]["food"] -= 15
	citizen_born.emit(child)
	_nc().server_sync_resources(team)
	update_ui()


# ---------------------------------------------------------------------------
# Resource helpers — PER TEAM
# ---------------------------------------------------------------------------
func can_afford_for_team(cost: Dictionary, team: int) -> bool:
	var res := team_resources.get(team, {})
	for k in cost:
		if res.get(k, 0) < cost[k]:
			return false
	return true


func spend_for_team(cost: Dictionary, team: int) -> void:
	if not is_sim_authority():
		return
	var res := team_resources[team]
	for k in cost:
		res[k] = maxi(0, res.get(k, 0) - cost[k])
	_nc().server_sync_resources(team)
	update_ui()


func add_resources_for_team(team: int, amounts: Dictionary) -> void:
	if not is_sim_authority():
		return
	var res := team_resources.get(team, {})
	for k in amounts:
		res[k] = res.get(k, 0) + amounts[k]
	_nc().server_sync_resources(team)
	update_ui()


## Legacy single-player helpers — operate on MY team
func can_afford(cost: Dictionary) -> bool:
	return can_afford_for_team(cost, _my_team())

func spend(cost: Dictionary) -> void:
	spend_for_team(cost, _my_team())

func add_resources(f:int=0,w:int=0,s:int=0,g:int=0,i:int=0,wa:int=0) -> void:
	add_resources_for_team(_my_team(), {
		"food":f,"wood":w,"stone":s,"gold":g,"iron":i,"water":wa
	})

func update_ui() -> void:
	var team := _my_team()
	var res  := team_resources.get(team, {})
	var pop  := team_population.get(team, {})
	resources_changed.emit(
		res.get("food",0), res.get("wood",0), res.get("stone",0),
		res.get("gold",0), res.get("iron",0), res.get("water",0),
		pop.get("population",0), pop.get("housing_capacity",0)
	)

## Production building check — uses team 0 (host) in single-player.
func has_inputs(inputs: Dictionary) -> bool:
	return can_afford_for_team(inputs, _my_team())

func consume_inputs(inputs: Dictionary) -> void:
	spend_for_team(inputs, _my_team())

# ---------------------------------------------------------------------------
# Population helpers
# ---------------------------------------------------------------------------
func register_population(citizen) -> void:
	if not is_sim_authority():
		return
	var team := citizen.team if "team" in citizen else 0
	team_population.get(team, {})["population"] = \
		team_population.get(team, {}).get("population", 0) + 1
	all_citizens.append(citizen)
	adult_count += 1
	_nc().server_sync_resources(team)
	update_ui()


func register_soldier(soldier) -> void:
	if not is_sim_authority():
		return
	var team := soldier.team if "team" in soldier else 0
	team_population.get(team, {})["population"] = \
		team_population.get(team, {}).get("population", 0) + 1
	all_soldiers.append(soldier)
	_nc().server_sync_resources(team)
	update_ui()


func register_artillery(art) -> void:
	if not is_sim_authority():
		return
	var team :Variant = art.team if "team" in art else 0
	team_population.get(team, {})["population"] = \
		team_population.get(team, {}).get("population", 0) + 1
	all_artillery.append(art)
	_nc().server_sync_resources(team)
	update_ui()


func remove_population(unit, cause: String = "") -> void:
	if not is_sim_authority():
		return
	var team := unit.team if "team" in unit else 0
	var pop  := team_population.get(team, {})
	pop["population"] = maxi(0, pop.get("population", 0) - 1)

	if unit in all_citizens:
		all_citizens.erase(unit)
		match unit.life_stage:
			unit.LifeStage.CHILD:  child_count -= 1
			unit.LifeStage.ADULT:  adult_count -= 1
			unit.LifeStage.ELDER:  elder_count -= 1
		citizen_died.emit(unit, cause)
	elif unit in all_soldiers:
		all_soldiers.erase(unit)
	elif unit in all_artillery:
		all_artillery.erase(unit)

	_nc().server_sync_resources(team)
	update_ui()


## Housing capacity changes a shared per-team pool exactly like spending
## resources does — it MUST only ever be applied once, by the host. Without
## this guard, a client running Building/Citizen construction logic locally
## (e.g. before all client-side AI gating is in place, or for any future
## building type someone forgets to gate) would double-apply this.
func change_housing(delta: int) -> void:
	if not is_sim_authority():
		return
	var team := _my_team()
	var pop  := team_population.get(team, {})
	pop["housing_capacity"] = pop.get("housing_capacity", 0) + delta
	_nc().server_sync_resources(team)
	update_ui()


# ---------------------------------------------------------------------------
# Selection
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
		if is_instance_valid(u): u.set_selected(false)
	selected_units.clear()
	if selected_building and is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	if selected_resource_node and is_instance_valid(selected_resource_node):
		selected_resource_node.set_selected(false)
	selected_resource_node = null
	selection_changed.emit([], null, null)


# ---------------------------------------------------------------------------
# Placement mode  (local UI state only — actual spawn goes via NetworkCommands)
# ---------------------------------------------------------------------------
func start_building_placement(building_id: String, builder = null) -> void:
	is_placing_building   = true
	placement_building_id = building_id
	placement_builder     = builder
	placement_mode_changed.emit(true, building_id)


func cancel_building_placement() -> void:
	is_placing_building   = false
	placement_building_id = ""
	placement_builder     = null
	placement_mode_changed.emit(false, "")


func start_attack_position_targeting(radius: float = 60.0) -> void:
	is_targeting_attack_position = true
	attack_targeting_mode_changed.emit(true, radius)


func cancel_attack_position_targeting() -> void:
	is_targeting_attack_position = false
	attack_targeting_mode_changed.emit(false, 0.0)


func start_demolish_mode() -> void:
	is_demolish_mode = true
	demolish_mode_changed.emit(true)


func cancel_demolish_mode() -> void:
	is_demolish_mode = false
	demolish_mode_changed.emit(false)


func can_place_building_at(world_pos: Vector3, footprint_radius: float = 36.0) -> bool:
	var map_gen = Engine.get_main_loop().current_scene.get_node_or_null("MapGenerator")
	if map_gen and map_gen.has_method("is_land_at"):
		if not map_gen.is_land_at(Vector2(world_pos.x, world_pos.z)):
			return false
	var space_state = Engine.get_main_loop().current_scene.get_world_3d().direct_space_state
	var query       := PhysicsShapeQueryParameters3D.new()
	var shape       := CylinderShape3D.new()
	shape.radius     = footprint_radius
	shape.height     = 40.0
	query.shape      = shape
	query.transform  = Transform3D(Basis.IDENTITY, world_pos)
	query.collision_mask = 1
	for hit in space_state.intersect_shape(query, 16):
		var c = hit.get("collider")
		if c == null: continue
		if c.is_in_group("mountains") or c.is_in_group("rivers") \
				or c.is_in_group("water_sources") or c.is_in_group("buildings"):
			return false
	return true


func clear_trees_at(world_pos: Vector3, radius: float = 44.0) -> void:
	if not is_sim_authority():
		return
	var space_state = Engine.get_main_loop().current_scene.get_world_3d().direct_space_state
	var query       := PhysicsShapeQueryParameters3D.new()
	var shape       := CylinderShape3D.new()
	shape.radius     = radius
	shape.height     = 60.0
	query.shape      = shape
	query.transform  = Transform3D(Basis.IDENTITY, world_pos)
	query.collision_mask = 1
	for hit in space_state.intersect_shape(query, 32):
		var c = hit.get("collider")
		if c and is_instance_valid(c) and c.is_in_group("wood_sources"):
			c.queue_free()


func notify(text: String) -> void:
	notification.emit(text)
