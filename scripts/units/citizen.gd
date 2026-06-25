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
##
## NETWORKING: everything in this file is simulation state (job assignment,
## harvesting, delivery, building progress) — it must only ever run on the
## peer with simulation authority (single-player, or the host in a networked
## game). _process is gated accordingly. Clients still get _refresh_appearance
## calls (driven by life_stage/current_job/carried_resource, which arrive via
## NetworkCommands' citizen-state sync) so they SEE the right model/colour,
## they just never decide it themselves.

enum LifeStage { CHILD, ADULT, ELDER }
enum Job { NONE, FARMER, WOODCUTTER, MINER, BUILDER, TRADER, WATERCARRIER }

const CHILD_TO_ADULT_AGE := 14
const ADULT_TO_ELDER_AGE := 50
const MAX_AGE := 75
const ELDER_DEATH_CHANCE := 0.06

@export var carry_capacity: int = 8
@export var gather_interval: float = 1.2
@export var build_rate: float = 12.0

var life_stage: LifeStage = LifeStage.ADULT
var age: int = 18

var current_job: Job = Job.NONE
var workplace = null
var carried_resource: String = ""
var carried_amount: int = 0
var is_delivering: bool = false

var has_player_order: bool = false
var order_target = null
var order_kind: String = ""

var _gather_timer: float = 0.0
var _job_search_cooldown: float = 0.0
var _resume_workplace_after_delivery = null

@onready var sprite: Node = get_node_or_null("Mesh")
@onready var job_icon: Node = get_node_or_null("JobIcon")
@onready var carry_icon: Node = get_node_or_null("CarryIcon")

const INTERACTION_MARGIN: float = 14.0
const OWN_RADIUS: float = 12.0


func _interaction_range(target: Node) -> float:
	var target_half_size: float = 16.0
	var shape_node = target.get_node_or_null("CollisionShape3D")
	if shape_node and shape_node.shape:
		var sh = shape_node.shape
		if sh is BoxShape3D:
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
	if life_stage == LifeStage.ADULT and _has_movement_authority():
		_try_autofind_job()


func _process(delta: float) -> void:
	if not _has_movement_authority():
		return
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
# Aging
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
# Autonomous job AI
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
			# Clear stale or finished construction targets.
			if not is_instance_valid(order_target) \
					or (order_target.has_method("is_constructed") and order_target.is_constructed):
				order_target = null
				current_job  = Job.NONE
			else:
				_auto_build(delta)
		Job.NONE:
			_job_search_cooldown -= delta
			if _job_search_cooldown <= 0.0:
				_job_search_cooldown = 2.0
				_try_autofind_job()


func _try_autofind_job() -> bool:
	if life_stage != LifeStage.ADULT:
		return false

	# Construction sites first — an unbuilt building on our team is urgent.
	if _autofind_construction():
		return true

	# Then resource producers.
	var candidates = [
		{"group": "farms",        "job": Job.FARMER,     "resource": "food"},
		{"group": "lumber_camps", "job": Job.WOODCUTTER,  "resource": "wood"},
		{"group": "quarries",     "job": Job.MINER,       "resource": "stone"},
		{"group": "mines",        "job": Job.MINER,       "resource": "iron"},
	]
	for c in candidates:
		for site in get_tree().get_nodes_in_group(c["group"]):
			if is_instance_valid(site) and site.is_constructed \
					and site.has_method("assign_worker") and site.assign_worker(self):
				current_job = c["job"]
				workplace   = site
				return true
	return false


func _autofind_construction() -> bool:
	## Find the nearest unfinished building on our team and go build it.
	var best      = null
	var best_dist := INF
	for site in get_tree().get_nodes_in_group("construction_sites"):
		if not is_instance_valid(site):
			continue
		if "team" in site and site.team != team:
			continue
		var d := global_position.distance_to(site.global_position)
		if d < best_dist:
			best_dist = d
			best      = site
	if best == null:
		return false
	current_job  = Job.BUILDER
	workplace    = null
	order_target = best
	return true


func _auto_work_job(delta: float) -> void:
	if is_delivering:
		_continue_delivery()
		return

	if not is_instance_valid(workplace):
		current_job = Job.NONE
		workplace = null
		return

	if global_position.distance_to(workplace.global_position) > _interaction_range(workplace) and not has_stalled_near_target():
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
		_leave_workplace()
		current_job = Job.NONE
		return
	else:
		_leave_workplace()
		current_job = Job.NONE
		is_delivering = true
		_continue_delivery()
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

	if global_position.distance_to(site.global_position) > _interaction_range(site) and not has_stalled_near_target():
		move_to(site.global_position)
		return

	stop()
	site.add_build_progress(build_rate * get_process_delta_time())
	if site.is_constructed:
		current_job = Job.NONE
		order_target = null


# ---------------------------------------------------------------------------
# Player orders
# ---------------------------------------------------------------------------
func command_gather(resource_node) -> void:
	if is_delivering:
		return
	var job := _job_for_target(resource_node)
	if job == Job.NONE:
		GameManager.notify("Citizens can't gather that directly.")
		return
	if carried_amount > 0:
		_leave_workplace()
		has_player_order = true
		order_kind = "gather"
		order_target = resource_node
		is_delivering = true
		_continue_delivery()
		return
	_leave_workplace()
	if resource_node.has_method("assign_worker") and not resource_node.assign_worker(self):
		GameManager.notify("That workplace is already full.")
		return
	has_player_order = true
	order_kind = "gather"
	order_target = resource_node
	workplace = resource_node
	current_job = job
	_gather_timer = 0.0


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
	is_delivering = false
	has_player_order = true
	order_kind = "build"
	order_target = site
	current_job = Job.BUILDER


func command_move(pos: Vector3) -> void:
	_leave_workplace()
	is_delivering = false
	has_player_order = true
	order_kind = "move"
	order_target = null
	current_job = Job.NONE
	move_to(pos)


func command_return_to_work() -> void:
	var previous_workplace = workplace
	_leave_workplace()

	if carried_amount > 0:
		has_player_order = false
		order_kind = ""
		order_target = null
		is_delivering = true
		_resume_workplace_after_delivery = previous_workplace
		_continue_delivery()
		return

	stop_special_orders()
	current_job = Job.NONE
	if is_instance_valid(previous_workplace) and previous_workplace.has_method("assign_worker") \
			and previous_workplace.assign_worker(self):
		workplace = previous_workplace
		current_job = _job_for_target(previous_workplace)
		_gather_timer = 0.0
	else:
		_try_autofind_job()


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
			if is_delivering:
				_continue_delivery()
				return
			_auto_work_job(delta)
			if workplace == null and not is_delivering:
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
	if global_position.distance_to(site.global_position) > _interaction_range(site) and not has_stalled_near_target():
		move_to(site.global_position)
		return
	stop()
	var dt := get_process_delta_time()
	print("[BUILD DEBUG] citizen_uid=", get_meta("unit_id", -1),
		" my_team=", team,
		" site=", site.name,
		" site_team=", (site.team if "team" in site else "?"),
		" is_constructed=", site.is_constructed,
		" progress=", site.build_progress, "/", site.build_time,
		" dt=", dt, " rate=", build_rate)
	site.add_build_progress(build_rate * dt)
	if site.is_constructed:
		stop_special_orders()
		current_job = Job.NONE


# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------
func _continue_delivery() -> void:
	var center = _nearest_in_group("village_centers")
	if center == null:
		return
	if global_position.distance_to(center.global_position) > _interaction_range(center) and not has_stalled_near_target():
		move_to(center.global_position)
		return
	stop()
	if carried_amount > 0 and carried_resource != "":
		GameManager.add_resources_for_team(team, {carried_resource: carried_amount})
	carried_amount = 0
	carried_resource = ""
	is_delivering = false

	if _resume_workplace_after_delivery != null:
		var prev = _resume_workplace_after_delivery
		_resume_workplace_after_delivery = null
		if is_instance_valid(prev) and prev.has_method("assign_worker") and prev.assign_worker(self):
			workplace = prev
			current_job = _job_for_target(prev)
			_gather_timer = 0.0
		else:
			_try_autofind_job()
		return

	if has_player_order and order_kind == "gather" and is_instance_valid(order_target) and workplace == null:
		var site = order_target
		var job := _job_for_target(site)
		if job == Job.NONE:
			stop_special_orders()
			return
		if site.has_method("assign_worker") and not site.assign_worker(self):
			GameManager.notify("That workplace is already full.")
			stop_special_orders()
			return
		workplace = site
		current_job = job
		_gather_timer = 0.0


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
	NetworkCommands.server_kill_unit(self, cause)
	queue_free()


# ---------------------------------------------------------------------------
# Appearance
# ---------------------------------------------------------------------------
func _set_mesh_color(node: Node, c: Color) -> void:
	if node == null:
		return
	var mat: StandardMaterial3D
	if node.material_override is StandardMaterial3D:
		mat = node.material_override as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		node.material_override = mat
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
			Job.FARMER:       _set_mesh_color(job_icon, Color(0.2, 0.8, 0.2))
			Job.WOODCUTTER:   _set_mesh_color(job_icon, Color(0.5, 0.32, 0.1))
			Job.MINER:        _set_mesh_color(job_icon, Color(0.55, 0.55, 0.55))
			Job.BUILDER:      _set_mesh_color(job_icon, Color(0.9, 0.7, 0.2))
			Job.WATERCARRIER: _set_mesh_color(job_icon, Color(0.3, 0.55, 0.85))
			_:                _set_mesh_color(job_icon, Color(1, 1, 1, 0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if carry_icon:
		carry_icon.visible = carried_amount > 0
		if carried_amount > 0:
			_set_mesh_color(carry_icon, _color_for_resource(carried_resource))


func _color_for_resource(res: String) -> Color:
	match res:
		"wood":  return Color(0.45, 0.27, 0.1)
		"stone": return Color(0.6, 0.6, 0.6)
		"food":  return Color(0.9, 0.75, 0.2)
		"iron":  return Color(0.36, 0.36, 0.42)
		"water": return Color(0.3, 0.55, 0.85)
	return Color(1, 1, 1)


func apply_network_state(p_life_stage: int, p_age: int, p_job: int, p_carried_resource: String, p_carried_amount: int) -> void:
	life_stage = p_life_stage as LifeStage
	age = p_age
	current_job = p_job as Job
	carried_resource = p_carried_resource
	carried_amount = p_carried_amount
	_refresh_appearance()


func job_label() -> String:
	match current_job:
		Job.FARMER:       return "Farmer"
		Job.WOODCUTTER:   return "Woodcutter"
		Job.MINER:        return "Miner"
		Job.BUILDER:      return "Builder"
		Job.TRADER:       return "Trader"
		Job.WATERCARRIER: return "Water Carrier"
	return "Idle"


func life_stage_label() -> String:
	match life_stage:
		LifeStage.CHILD: return "Child"
		LifeStage.ADULT: return "Adult"
		LifeStage.ELDER: return "Elder"
	return "?"


func is_selectable_by_player() -> bool:
	return team == _player_team() and is_alive and life_stage != LifeStage.CHILD
