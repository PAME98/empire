class_name Citizen
extends Unit

## The Kingdom-Reborn-style economy unit. Citizens are born at houses, age
## from child -> adult -> elder -> death, and — when not given a direct
## player order — autonomously look for work at resource buildings and feed
## that work back into GameManager's stockpiles.
##
## Crucially, a Citizen is ALSO a first-class RTS unit: box-select it, drag
## it, right-click a tree/farm/quarry/build-site to give it a direct order.
## Player orders always take priority over the autonomous AI; the AI only
## drives a citizen when nobody has told it what to do.

enum LifeStage { CHILD, ADULT, ELDER }
enum Job { NONE, FARMER, WOODCUTTER, MINER, BUILDER, TRADER, WATERCARRIER }

const CHILD_TO_ADULT_AGE := 14
const ADULT_TO_ELDER_AGE := 50
const MAX_AGE := 75
const ELDER_DEATH_CHANCE := 0.06  # rolled once per year past MAX_AGE check

@export var carry_capacity: int = 8
@export var gather_interval: float = 1.2
@export var build_rate: float = 12.0  # build_progress per second while building

var life_stage: LifeStage = LifeStage.ADULT
var age: int = 18

var current_job: Job = Job.NONE
var workplace = null
var carried_resource: String = ""
var carried_amount: int = 0
var is_delivering: bool = false

# Player-issued order. When set, the citizen ignores auto-job AI and follows
# the order until it's cleared or completed.
var has_player_order: bool = false
var order_target = null  # resource node or building, depending on order kind
var order_kind: String = ""  # "gather", "build", "move"

var _gather_timer: float = 0.0
var _job_search_cooldown: float = 0.0

@onready var sprite: Node = get_node_or_null("Mesh")
@onready var job_icon: Node = get_node_or_null("JobIcon")
@onready var carry_icon: Node = get_node_or_null("CarryIcon")

const INTERACTION_MARGIN: float = 14.0  # slack beyond physical contact so movement noise can't strand a citizen just outside range
const OWN_RADIUS: float = 12.0  # matches Citizen's collision radius in citizen.tscn


func _interaction_range(target: Node) -> float:
	# How close this citizen can actually get to a target before solid
	# collision physically stops it, plus a small margin. Uses the horizontal
	# half-diagonal of a building's box so this is correct no matter which
	# angle the citizen approaches from.
	var target_half_size: float = 16.0  # sane default for a small/point target
	var shape_node = target.get_node_or_null("CollisionShape3D")
	if shape_node and shape_node.shape:
		var sh = shape_node.shape
		if sh is BoxShape3D:
			# Footprint diagonal on the ground plane (ignore height).
			target_half_size = Vector2(sh.size.x, sh.size.z).length() * 0.5
		elif sh is CylinderShape3D:
			target_half_size = sh.radius
		elif sh is SphereShape3D:
			target_half_size = sh.radius
		elif sh is CapsuleShape3D:
			target_half_size = sh.radius

	return target_half_size + OWN_RADIUS + INTERACTION_MARGIN


func _ready() -> void:
	super._ready()
	add_to_group("citizens")
	speed = 85.0
	_refresh_appearance()
	if life_stage == LifeStage.ADULT:
		_try_autofind_job()


func _process(delta: float) -> void:
	if not is_alive:
		return

	if has_player_order:
		_run_player_order(delta)
	else:
		_run_auto_job(delta)


# ---------------------------------------------------------------------------
# Spawning helpers
# ---------------------------------------------------------------------------
func setup_as_child() -> void:
	life_stage = LifeStage.CHILD
	age = 0
	current_job = Job.NONE
	workplace = null
	_refresh_appearance()


func setup_as_adult(starting_job: Job = Job.NONE) -> void:
	life_stage = LifeStage.ADULT
	age = 18
	current_job = starting_job
	_refresh_appearance()


# ---------------------------------------------------------------------------
# Aging — called once per in-game year by GameManager
# ---------------------------------------------------------------------------
func age_up() -> void:
	age += 1
	match life_stage:
		LifeStage.CHILD:
			if age >= CHILD_TO_ADULT_AGE:
				life_stage = LifeStage.ADULT
				GameManager.child_count -= 1
				GameManager.adult_count += 1
				_try_autofind_job()
		LifeStage.ADULT:
			if age >= ADULT_TO_ELDER_AGE:
				life_stage = LifeStage.ELDER
				GameManager.adult_count -= 1
				GameManager.elder_count += 1
				_retire_from_labor()
		LifeStage.ELDER:
			if age >= MAX_AGE or randf() < ELDER_DEATH_CHANCE:
				die("old_age")
				return
	_refresh_appearance()


func _retire_from_labor() -> void:
	if current_job in [Job.FARMER, Job.WOODCUTTER, Job.MINER, Job.BUILDER]:
		_leave_workplace()
		current_job = Job.NONE


# ---------------------------------------------------------------------------
# Autonomous job AI (runs only while no player order is active)
# ---------------------------------------------------------------------------
func _run_auto_job(delta: float) -> void:
	if is_delivering:
		_continue_delivery()
		return

	if life_stage != LifeStage.ADULT:
		return

	match current_job:
		Job.FARMER, Job.MINER, Job.WOODCUTTER:
			_auto_work_job(delta)
		Job.BUILDER:
			_auto_build(delta)
		Job.NONE:
			_job_search_cooldown -= delta
			if _job_search_cooldown <= 0.0:
				_job_search_cooldown = 2.0
				_try_autofind_job()


func _try_autofind_job() -> bool:
	if life_stage != LifeStage.ADULT:
		return false

	var candidates = [
		{"group": "farms", "job": Job.FARMER, "resource": "food"},
		{"group": "lumber_camps", "job": Job.WOODCUTTER, "resource": "wood"},
		{"group": "quarries", "job": Job.MINER, "resource": "stone"},
		{"group": "mines", "job": Job.MINER, "resource": "iron"},
	]
	for c in candidates:
		for site in get_tree().get_nodes_in_group(c["group"]):
			if is_instance_valid(site) and site.is_constructed and site.has_method("assign_worker") and site.assign_worker(self):
				current_job = c["job"]
				workplace = site
				return true
	return false


func _auto_work_job(delta: float) -> void:
	if is_delivering:
		_continue_delivery()
		return

	if not is_instance_valid(workplace):
		current_job = Job.NONE
		workplace = null
		return

	if global_position.distance_to(workplace.global_position) > _interaction_range(workplace):
		move_to(workplace.global_position)
		return

	stop()
	_gather_timer += delta
	if _gather_timer < gather_interval:
		return
	_gather_timer = 0.0

	var resource_type = _carried_type_for(workplace)
	var got = workplace.harvest(carry_capacity - carried_amount)
	if got > 0:
		carried_amount += got
		carried_resource = resource_type
	elif carried_amount == 0:
		# Workplace is depleted (e.g. a chopped-out tree) and we're not
		# carrying anything to deliver — drop it and look for new work
		# instead of standing here harvesting zero forever.
		_leave_workplace()
		current_job = Job.NONE
		return

	if carried_amount >= carry_capacity:
		is_delivering = true
		_continue_delivery()


func _resource_for_job(job: Job) -> String:
	match job:
		Job.FARMER: return "food"
		Job.WOODCUTTER: return "wood"
		Job.MINER: return "stone"
		Job.WATERCARRIER: return "water"
	return ""


# What a citizen ends up carrying from a given worksite. World resource nodes
# carry exactly what they are (so mining a mountain yields stone, not "");
# resource buildings map through the citizen's current job.
func _carried_type_for(node) -> String:
	if "resource_type" in node:
		return node.resource_type
	if "yield_resource" in node and node.yield_resource != "":
		return node.yield_resource
	return _resource_for_job(current_job)


func _auto_build(_delta: float) -> void:
	var site = order_target if is_instance_valid(order_target) else null
	if site == null:
		var sites = get_tree().get_nodes_in_group("construction_sites")
		if sites.is_empty():
			current_job = Job.NONE
			return
		site = sites[0]

	if global_position.distance_to(site.global_position) > _interaction_range(site):
		move_to(site.global_position)
		return

	stop()
	site.add_build_progress(build_rate * get_process_delta_time())
	if site.is_constructed:
		current_job = Job.NONE
		order_target = null


# ---------------------------------------------------------------------------
# Player orders — take priority over auto AI and persist until cleared
# ---------------------------------------------------------------------------
func command_gather(resource_node) -> void:
	if is_delivering:
		return  # finish dropping off the current load before taking a new job
	var job := _job_for_target(resource_node)
	if job == Job.NONE:
		# e.g. an iron-ore or water node — not hand-gatherable (yet).
		GameManager.notify("Citizens can't gather that directly.")
		return
	_leave_workplace()
	# Resource *buildings* have worker slots; claim one so the building also
	# starts producing. World nodes (trees, mountains) have no assign_worker.
	if resource_node.has_method("assign_worker") and not resource_node.assign_worker(self):
		GameManager.notify("That workplace is already full.")
		return
	has_player_order = true
	order_kind = "gather"
	order_target = resource_node
	workplace = resource_node
	current_job = job
	_gather_timer = 0.0


# Works out which job a gather target implies — whether it's a depletable
# world node (reads resource_type) or a resource building (reads its group).
# Returns Job.NONE for anything not hand-gatherable.
func _job_for_target(node) -> Job:
	if "resource_type" in node:
		match node.resource_type:
			"wood": return Job.WOODCUTTER
			"stone", "iron": return Job.MINER
			"food": return Job.FARMER
			"water": return Job.WATERCARRIER
		return Job.NONE
	if node.is_in_group("farms"):
		return Job.FARMER
	if node.is_in_group("lumber_camps"):
		return Job.WOODCUTTER
	if node.is_in_group("quarries") or node.is_in_group("mines"):
		return Job.MINER
	return Job.NONE


func command_build(site) -> void:
	_leave_workplace()
	_abandon_delivery()
	has_player_order = true
	order_kind = "build"
	order_target = site
	current_job = Job.BUILDER


func command_move(pos: Vector3) -> void:
	_leave_workplace()
	_abandon_delivery()
	has_player_order = true
	order_kind = "move"
	order_target = null
	current_job = Job.NONE
	move_to(pos)


func _abandon_delivery() -> void:
	# A direct move/build order takes priority over finishing a delivery —
	# matches how most RTS games let you redirect a unit immediately, at
	# the cost of whatever it was carrying.
	is_delivering = false
	carried_amount = 0
	carried_resource = ""


func stop_special_orders() -> void:
	has_player_order = false
	order_kind = ""
	order_target = null


func _run_player_order(delta: float) -> void:
	match order_kind:
		"gather":
			if not is_instance_valid(order_target):
				stop_special_orders()
				return
			_auto_work_job(delta)
			if workplace == null:
				# _auto_work_job gave up on this target (depleted, or it
				# stopped being a valid worksite) — release the order so
				# the citizen goes back to looking for its own work
				# instead of standing here doing nothing forever.
				stop_special_orders()
		"build":
			if not is_instance_valid(order_target) or order_target.is_constructed:
				stop_special_orders()
				current_job = Job.NONE
				return
			_player_build(delta)
		"move":
			if not is_moving:
				stop_special_orders()


func _player_build(_delta: float) -> void:
	var site = order_target
	if global_position.distance_to(site.global_position) > _interaction_range(site):
		move_to(site.global_position)
		return
	stop()
	site.add_build_progress(build_rate * get_process_delta_time())
	if site.is_constructed:
		stop_special_orders()
		current_job = Job.NONE


# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------
func _continue_delivery() -> void:
	var center = _nearest_in_group("village_centers")
	if center == null:
		# No village center exists (e.g. it was destroyed) — hold the
		# resources rather than losing them or getting stuck.
		return
	if global_position.distance_to(center.global_position) > _interaction_range(center):
		move_to(center.global_position)
		return
	stop()
	match carried_resource:
		"food": GameManager.add_resources(carried_amount, 0, 0, 0, 0, 0)
		"wood": GameManager.add_resources(0, carried_amount, 0, 0, 0, 0)
		"stone": GameManager.add_resources(0, 0, carried_amount, 0, 0, 0)
		"gold": GameManager.add_resources(0, 0, 0, carried_amount, 0, 0)
		"iron": GameManager.add_resources(0, 0, 0, 0, carried_amount, 0)
		"water": GameManager.add_resources(0, 0, 0, 0, 0, carried_amount)
	carried_amount = 0
	carried_resource = ""
	is_delivering = false


func _nearest_in_group(group_name: String):
	var best = null
	var best_dist = INF
	for node in get_tree().get_nodes_in_group(group_name):
		if is_instance_valid(node) and node.team == team:
			var d = global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = node
	return best


func _leave_workplace() -> void:
	if is_instance_valid(workplace) and workplace.has_method("remove_worker"):
		workplace.remove_worker(self)
	workplace = null


# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------
func die(cause: String = "unknown") -> void:
	if not is_alive:
		return
	_leave_workplace()
	is_alive = false
	GameManager.remove_population(self, cause)
	died.emit(self)
	queue_free()


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------
func _set_mesh_color(node: Node, c: Color) -> void:
	# Per-instance colour via material_override, so recolouring one citizen
	# (by life stage / job / carried resource) doesn't tint all the others.
	if node == null:
		return
	var mat: StandardMaterial3D
	if node.material_override is StandardMaterial3D:
		mat = node.material_override as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		node.material_override = mat
	# Alpha 0 = hide the marker entirely (used for the "no job" icon).
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = c


func _refresh_appearance() -> void:
	if sprite:
		match life_stage:
			LifeStage.CHILD:
				_set_mesh_color(sprite, Color(0.92, 0.74, 0.52))
				sprite.scale = Vector3(0.6, 0.6, 0.6)
			LifeStage.ADULT:
				_set_mesh_color(sprite, Color(0.22, 0.52, 0.88))
				sprite.scale = Vector3.ONE
			LifeStage.ELDER:
				_set_mesh_color(sprite, Color(0.55, 0.55, 0.6))
				sprite.scale = Vector3(0.9, 0.9, 0.9)

	if job_icon:
		match current_job:
			Job.FARMER: _set_mesh_color(job_icon, Color(0.2, 0.8, 0.2))
			Job.WOODCUTTER: _set_mesh_color(job_icon, Color(0.5, 0.32, 0.1))
			Job.MINER: _set_mesh_color(job_icon, Color(0.55, 0.55, 0.55))
			Job.BUILDER: _set_mesh_color(job_icon, Color(0.9, 0.7, 0.2))
			Job.WATERCARRIER: _set_mesh_color(job_icon, Color(0.3, 0.55, 0.85))
			_: _set_mesh_color(job_icon, Color(1, 1, 1, 0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if carry_icon:
		carry_icon.visible = carried_amount > 0
		if carried_amount > 0:
			_set_mesh_color(carry_icon, _color_for_resource(carried_resource))


func _color_for_resource(res: String) -> Color:
	match res:
		"wood": return Color(0.45, 0.27, 0.1)
		"stone": return Color(0.6, 0.6, 0.6)
		"food": return Color(0.9, 0.75, 0.2)
		"iron": return Color(0.36, 0.36, 0.42)
		"water": return Color(0.3, 0.55, 0.85)
	return Color(1, 1, 1)


func job_label() -> String:
	match current_job:
		Job.FARMER: return "Farmer"
		Job.WOODCUTTER: return "Woodcutter"
		Job.MINER: return "Miner"
		Job.BUILDER: return "Builder"
		Job.TRADER: return "Trader"
		Job.WATERCARRIER: return "Water Carrier"
	return "Idle"


func life_stage_label() -> String:
	match life_stage:
		LifeStage.CHILD: return "Child"
		LifeStage.ADULT: return "Adult"
		LifeStage.ELDER: return "Elder"
	return "?"


func is_selectable_by_player() -> bool:
	return team == 0 and is_alive and life_stage != LifeStage.CHILD
