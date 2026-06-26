class_name Citizen
extends Unit

## Economy unit. Citizens gather resources, construct buildings, and deliver
## goods to the village center.
##
## KEY AI IMPROVEMENTS over the previous version:
##   - Workers use their Unit.arrival_offset to spread around a workplace so
##     they don't all stand on the exact same point.
##   - move_to() for work targets passes workplace.global_position + arrival_offset
##     so each citizen has a unique personal spot to walk to.
##   - Gather timers are staggered on spawn (random phase) so a group of freshly
##     assigned workers don't all try to harvest simultaneously.
##   - Re-pathing is throttled: we only call move_to() again after a minimum
##     interval rather than every _process frame, which was resetting the nav
##     path and disrupting avoidance every tick.
##   - Delivery targets use arrival_offset too so citizens don't queue in a
##     single-file column into the village center.
##   - Job-search cooldown is randomised slightly so multiple idle citizens
##     don't all pick the same building in the same frame.

enum LifeStage { CHILD, ADULT, ELDER }
enum Job { NONE, FARMER, WOODCUTTER, MINER, BUILDER, TRADER, WATERCARRIER }

const CHILD_TO_ADULT_AGE := 14
const ADULT_TO_ELDER_AGE := 50
const MAX_AGE := 75
const ELDER_DEATH_CHANCE := 0.06
const GATHER_CONTINUE_RANGE := 1600.0

## Minimum seconds between re-issuing a move_to() while already travelling to
## the same target. Prevents resetting the nav path (and avoidance) every tick.
const REPATH_INTERVAL: float = 0.6

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

## Throttle re-pathing so we don't call move_to() every frame.
var _repath_timer: float = 0.0
## The last target we issued a move_to() for, to detect when destination changes.
var _last_move_target: Vector3 = Vector3(INF, INF, INF)

@onready var sprite: Node = get_node_or_null("Mesh")
@onready var job_icon: Node = get_node_or_null("JobIcon")
@onready var carry_icon: Node = get_node_or_null("CarryIcon")


## Returns the position this citizen should walk to when working at `target`.
## Adds the citizen's personal arrival_offset so workers spread around a building.
func _work_pos(target: Node) -> Vector3:
	if target == null:
		return Vector3.ZERO
	return target.global_position + arrival_offset


## Returns the position this citizen should walk to when delivering to `target`.
## Uses a smaller offset so citizens don't walk too far past the center.
func _delivery_pos(target: Node) -> Vector3:
	if target == null:
		return Vector3.ZERO
	# Use a quieter offset for delivery — we just need to be close enough to
	# hand over resources, not stand at a specific workstation.
	var small_offset := Vector3(arrival_offset.x * 0.4, 0.0, arrival_offset.z * 0.4)
	return target.global_position + small_offset


## Issue a move_to() only when the target position has changed meaningfully
## OR the repath timer has expired. This prevents resetting the nav agent
## (and its avoidance computation) every single frame.
func _move_toward(pos: Vector3) -> void:
	_repath_timer -= get_process_delta_time()
	var changed := pos.distance_to(_last_move_target) > 12.0
	if changed or _repath_timer <= 0.0:
		_last_move_target = pos
		_repath_timer = REPATH_INTERVAL
		move_to(pos)


func _ready() -> void:
	super._ready()
	add_to_group("citizens")
	speed = 85.0
	# Stagger gather timers so a freshly-grouped set of workers don't all
	# try to harvest in the same frame, causing a spike of simultaneous activity.
	_gather_timer = randf_range(0.0, gather_interval)
	# Stagger job-search so citizens assigned together don't all pick the same
	# workplace in the same frame.
	_job_search_cooldown = randf_range(0.0, 1.5)
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
			if not is_instance_valid(order_target) \
					or (order_target.has_method("is_constructed") and order_target.is_constructed):
				order_target = null
				current_job = Job.NONE
			else:
				_auto_build(delta)
		Job.NONE:
			_job_search_cooldown -= delta
			if _job_search_cooldown <= 0.0:
				# Randomise the next search slightly so batches of idle citizens
				# don't all converge on the same building simultaneously.
				_job_search_cooldown = randf_range(1.8, 2.8)
				_try_autofind_job()


func _try_autofind_job() -> bool:
	if life_stage != LifeStage.ADULT:
		return false

	if _autofind_construction():
		return true

	var candidates = [
		{"group": "farms",        "job": Job.FARMER},
		{"group": "lumber_camps", "job": Job.WOODCUTTER},
		{"group": "quarries",     "job": Job.MINER},
		{"group": "mines",        "job": Job.MINER},
	]
	for c in candidates:
		var best = null
		var best_dist := INF
		for site in get_tree().get_nodes_in_group(c["group"]):
			if not is_instance_valid(site) or not site.is_constructed:
				continue
			if "team" in site and site.team != team:
				continue
			if not site.has_method("assign_worker"):
				continue
			if site.has_method("worker_count") and "max_workers" in site \
					and site.worker_count() >= site.max_workers:
				continue
			var d := global_position.distance_to(site.global_position)
			if d < best_dist:
				best_dist = d
				best = site
		if best != null and best.assign_worker(self):
			current_job = c["job"]
			workplace   = best
			return true
	return false


func _autofind_construction() -> bool:
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

	var wp_pos := _work_pos(workplace)
	var dist   := global_position.distance_to(wp_pos)
	var range  := interaction_range_for(workplace)

	if dist > range and not has_stalled_near_target():
		_move_toward(wp_pos)
		return

	stop()
	_gather_timer += delta
	if _gather_timer < gather_interval:
		return
	_gather_timer = 0.0

	var resource_type := _carried_type_for(workplace)
	var got :Variant = workplace.harvest(carry_capacity - carried_amount)
	if got > 0:
		carried_amount += got
		carried_resource = resource_type
	elif carried_amount == 0:
		var dead = workplace
		_leave_workplace()
		if _gather_continue_to_nearest(dead):
			return
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
		Job.FARMER:       return "food"
		Job.WOODCUTTER:   return "wood"
		Job.MINER:        return "stone"
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

	var wp_pos := _work_pos(site)
	var dist   := global_position.distance_to(wp_pos)
	if dist > interaction_range_for(site) and not has_stalled_near_target():
		_move_toward(wp_pos)
		return

	stop()
	site.add_build_progress(build_rate * get_process_delta_time())
	if site.is_constructed:
		current_job  = Job.NONE
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
	_gather_timer = randf_range(0.0, gather_interval * 0.5)  # stagger on new assignment


func _job_for_target(node) -> Job:
	if "resource_type" in node:
		match node.resource_type:
			"wood": return Job.WOODCUTTER
			"stone", "iron": return Job.MINER
			"food": return Job.FARMER
			"water": return Job.WATERCARRIER
		return Job.NONE
	if node.is_in_group("farms"):       return Job.FARMER
	if node.is_in_group("lumber_camps"): return Job.WOODCUTTER
	if node.is_in_group("quarries") or node.is_in_group("mines"): return Job.MINER
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
	_last_move_target = Vector3(INF, INF, INF)  # force fresh path
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
		_gather_timer = randf_range(0.0, gather_interval * 0.5)
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
	var wp_pos := _work_pos(site)
	if global_position.distance_to(wp_pos) > interaction_range_for(site) \
			and not has_stalled_near_target():
		_move_toward(wp_pos)
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
		return
	var dp    := _delivery_pos(center)
	var range := interaction_range_for(center)
	if global_position.distance_to(dp) > range and not has_stalled_near_target():
		_move_toward(dp)
		return
	stop()
	if carried_amount > 0 and carried_resource != "":
		GameManager.add_resources_for_team(team, {carried_resource: carried_amount})
	carried_amount = 0
	carried_resource = ""
	is_delivering = false
	# Reset move state so next work leg gets a fresh path.
	_last_move_target = Vector3(INF, INF, INF)

	if _resume_workplace_after_delivery != null:
		var prev = _resume_workplace_after_delivery
		_resume_workplace_after_delivery = null
		if is_instance_valid(prev) and prev.has_method("assign_worker") and prev.assign_worker(self):
			workplace = prev
			current_job = _job_for_target(prev)
			_gather_timer = randf_range(0.0, gather_interval * 0.5)
		else:
			_try_autofind_job()
		return

	if has_player_order and order_kind == "gather" and workplace == null:
		var site = order_target
		if is_instance_valid(site) and ("amount" not in site or site.amount > 0) \
				and site.has_method("assign_worker") and site.assign_worker(self):
			workplace = site
			current_job = _job_for_target(site)
			_gather_timer = randf_range(0.0, gather_interval * 0.5)
			return
		if _gather_continue_to_nearest(site):
			return
		stop_special_orders()


func _gather_continue_to_nearest(prev) -> bool:
	if not (has_player_order and order_kind == "gather"):
		return false

	var want_type := ""
	if is_instance_valid(prev) and "resource_type" in prev:
		want_type = prev.resource_type

	var cands: Array = []
	for n in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(n) or n == prev:
			continue
		if want_type != "" and ("resource_type" in n) and n.resource_type != want_type:
			continue
		if "amount" in n and n.amount <= 0:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if GATHER_CONTINUE_RANGE > 0.0 and d > GATHER_CONTINUE_RANGE:
			continue
		cands.append({"n": n, "d": d})

	cands.sort_custom(func(a, b): return a["d"] < b["d"])

	for c in cands:
		var n = c["n"]
		if n.has_method("assign_worker") and not n.assign_worker(self):
			continue
		workplace = n
		order_target = n
		current_job = _job_for_target(n)
		_gather_timer = randf_range(0.0, gather_interval * 0.5)
		_last_move_target = Vector3(INF, INF, INF)
		return true
	return false


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
	_last_move_target = Vector3(INF, INF, INF)


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


func apply_network_state(p_life_stage: int, p_age: int, p_job: int,
		p_carried_resource: String, p_carried_amount: int) -> void:
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
