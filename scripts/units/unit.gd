class_name Unit
extends CharacterBody3D
## Shared base for every player/AI controlled unit (citizens AND soldiers).
## 3D port: units live on the ground plane (XZ); Y is height and stays 0.
##
## KEY NAVIGATION IMPROVEMENTS:
##   - Each unit gets a unique arrival_offset so workers spread around buildings
##     instead of all pathing to the exact same point and blocking each other.
##   - move_to() only re-sends the target to the nav agent when the destination
##     actually changes, preventing constant re-pathing that resets avoidance.
##   - Stall recovery uses a gentler push + cooldown so it doesn't fight avoidance.
##   - _interaction_range results are cached per-target to avoid repeated shape queries.

signal died(unit)

@export var speed: float = 90.0
@export var max_health: int = 100
@export var team: int = 0

var health: int
var selected: bool = false
var is_alive: bool = true
var target_position: Vector3 = Vector3.ZERO
var is_moving: bool = false
var move_arrival_radius: float = 6.0

## Per-unit spatial offset applied when arriving at a shared target (building,
## resource node). Randomised once on _ready so workers spread naturally around
## a workplace instead of all converging on the exact centre point.
var arrival_offset: Vector3 = Vector3.ZERO

## Cache of interaction ranges keyed by target node so we don't query the
## CollisionShape every frame for the same building.
var _interaction_range_cache: Dictionary = {}

@onready var selection_ring: Node = get_node_or_null("SelectionRing")
@onready var health_bar: Node = get_node_or_null("HealthBar")

var nav_agent: NavigationAgent3D
var _nav_ready: bool = false

## The last position we actually sent to the nav agent. We only resend when
## the destination changes meaningfully, preventing constant re-pathing.
var _last_nav_target: Vector3 = Vector3(INF, INF, INF)
const _NAV_TARGET_CHANGE_THRESHOLD: float = 8.0

## Stall detection
var _last_progress_check_pos: Vector3 = Vector3.ZERO
var _stall_timer: float = 0.0
var _stall_recovery_cooldown: float = 0.0
const _STALL_TIME_THRESHOLD: float = 0.8
const _STALL_MOVE_EPSILON: float = 2.5
const _STALL_RECOVERY_COOLDOWN: float = 1.2  # don't re-trigger recovery immediately

## Client-side position smoothing
var _net_target: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
const NET_LERP_SPEED: float = 12.0


func set_network_target(pos: Vector3) -> void:
	if not _has_net_target:
		global_position = pos
	_net_target = pos
	_has_net_target = true


func _ready() -> void:
	health = max_health
	add_to_group("units")
	if selection_ring:
		selection_ring.visible = false
	_update_health_bar()
	# Give each unit a unique spatial offset so groups of workers spread around
	# their shared workplace rather than all standing on the same point.
	var angle := randf() * TAU
	var radius := randf_range(12.0, 32.0)
	arrival_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_setup_navigation()


func _has_movement_authority() -> bool:
	return GameManager.is_sim_authority()


func _setup_navigation() -> void:
	nav_agent = get_node_or_null("NavigationAgent3D")
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child.call_deferred(nav_agent)

	await get_tree().process_frame
	await get_tree().physics_frame

	if not nav_agent.is_inside_tree():
		push_warning("Unit._setup_navigation: nav_agent still not in tree on " + name)
		return

	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = move_arrival_radius

	var col := get_node_or_null("CollisionShape3D")
	if col and col.shape is CapsuleShape3D:
		nav_agent.radius = col.shape.radius
	elif col and col.shape is CylinderShape3D:
		nav_agent.radius = col.shape.radius
	else:
		nav_agent.radius = 8.0

	nav_agent.avoidance_enabled = true
	nav_agent.radius = max(nav_agent.radius, 8.0)
	nav_agent.max_speed = speed
	# Wider neighbour sensing so units are aware of each other further out and
	# start steering earlier rather than only reacting when already overlapping.
	nav_agent.neighbor_distance = 120.0
	nav_agent.max_neighbors = 12
	nav_agent.time_horizon_agents = 2.0
	nav_agent.time_horizon_obstacles = 0.8
	# avoidance_layers / avoidance_mask: all units share layer 1 so they avoid
	# each other. This is the default so no explicit set needed, but documented.

	nav_agent.velocity_computed.connect(_on_velocity_computed)
	_nav_ready = true


func _physics_process(delta: float) -> void:
	if not _has_movement_authority():
		if _has_net_target:
			global_position = global_position.lerp(
				_net_target, clampf(NET_LERP_SPEED * delta, 0.0, 1.0))
		return
	if _stall_recovery_cooldown > 0.0:
		_stall_recovery_cooldown -= delta
	if is_moving:
		_step_toward_target(delta)


func _step_toward_target(delta: float) -> void:
	if not _nav_ready or nav_agent == null or not nav_agent.is_inside_tree():
		_step_direct(delta)
		return

	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		is_moving = false
		_stall_timer = 0.0
		_on_reached_target()
		return

	# Stall detection — only trigger if we're not in the cooldown window after
	# a previous recovery (avoidance needs time to settle after a nudge).
	if _stall_recovery_cooldown <= 0.0:
		var moved := global_position.distance_to(_last_progress_check_pos)
		if moved < _STALL_MOVE_EPSILON:
			_stall_timer += delta
			if _stall_timer >= _STALL_TIME_THRESHOLD:
				_stall_timer = 0.0
				_stall_recovery_cooldown = _STALL_RECOVERY_COOLDOWN
				_recover_from_stall()
				_last_progress_check_pos = global_position
				return
		else:
			_stall_timer = 0.0
			_last_progress_check_pos = global_position
	else:
		# During cooldown, still update the reference position so we don't
		# immediately re-trigger once the cooldown expires.
		_last_progress_check_pos = global_position

	var next_point := nav_agent.get_next_path_position()
	var to_next := next_point - global_position
	to_next.y = 0.0

	if to_next.length() < 0.01:
		if not nav_agent.is_target_reached() and nav_agent.get_current_navigation_path().is_empty():
			_resend_nav_target(target_position)
			_step_direct(delta)
		return

	var desired_velocity := to_next.normalized() * speed
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(desired_velocity)
	else:
		_apply_velocity(desired_velocity)


func _step_direct(_delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > move_arrival_radius:
		_apply_velocity(to_target.normalized() * speed)
	else:
		velocity = Vector3.ZERO
		is_moving = false
		_on_reached_target()


func _recover_from_stall() -> void:
	# Collect collision normals from the last physics step to find which way is free.
	var push := Vector3.ZERO
	for i in get_slide_collision_count():
		push += get_slide_collision(i).get_normal()

	if push.length() > 0.01:
		push = push.normalized()
	else:
		# No collision info — step sideways relative to our desired direction.
		# This avoids the unit just walking backwards into where it came from.
		var to_goal := (target_position - global_position)
		to_goal.y = 0.0
		if to_goal.length() > 0.01:
			push = to_goal.normalized().rotated(Vector3.UP, PI * 0.5)
		else:
			push = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()

	# Small nudge — just enough to escape the stuck point without teleporting.
	global_position += push * (move_arrival_radius * 0.6)

	# Re-path from the new position.
	if nav_agent and nav_agent.is_inside_tree():
		_resend_nav_target(target_position)


func _resend_nav_target(pos: Vector3) -> void:
	_last_nav_target = pos
	if nav_agent and nav_agent.is_inside_tree():
		nav_agent.target_position = pos


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_apply_velocity(safe_velocity)


func _apply_velocity(v: Vector3) -> void:
	velocity = v
	move_and_slide()
	if velocity.length() > 0.01:
		var yaw := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, yaw, 0.2)


func _on_reached_target() -> void:
	pass


func move_to(pos: Vector3) -> void:
	target_position = pos
	is_moving = true
	_stall_timer = 0.0
	_last_progress_check_pos = global_position

	# Only resend to the nav agent if the destination changed meaningfully.
	# Resending every frame resets the computed path and disrupts avoidance.
	if pos.distance_to(_last_nav_target) > _NAV_TARGET_CHANGE_THRESHOLD:
		_resend_nav_target(pos)


func has_stalled_near_target() -> bool:
	if not _nav_ready or nav_agent == null or not nav_agent.is_inside_tree():
		return false
	return is_moving and nav_agent.is_navigation_finished()


func stop() -> void:
	is_moving = false
	velocity = Vector3.ZERO


## Returns the interaction range for `target`, cached so we don't re-query
## the CollisionShape every frame for the same node.
func interaction_range_for(target: Node) -> float:
	var instance_id := target.get_instance_id()
	if _interaction_range_cache.has(instance_id):
		return _interaction_range_cache[instance_id]

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

	# Scale by the target's actual world scale if it has one.
	if "scale" in target and target.scale.x != 1.0:
		target_half_size *= target.scale.x

	const OWN_RADIUS: float = 12.0
	const INTERACTION_MARGIN: float = 18.0
	var result := target_half_size + OWN_RADIUS + INTERACTION_MARGIN
	_interaction_range_cache[instance_id] = result
	return result


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func set_selected(value: bool) -> void:
	selected = value
	if selection_ring:
		selection_ring.visible = value


func is_selectable_by_player() -> bool:
	return team == _player_team() and is_alive


func _player_team() -> int:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		nm = get_node_or_null("/root/network_manager")
	if nm and nm.has_method("my_team"):
		return nm.my_team()
	return 0


# ---------------------------------------------------------------------------
# RTS command hooks
# ---------------------------------------------------------------------------
func command_move(pos: Vector3) -> void:
	stop_special_orders()
	move_to(pos)


func command_attack(_target) -> void:
	pass


func command_gather(_resource_node) -> void:
	pass


func command_build(_site) -> void:
	pass


func command_attack_position(_world_pos: Vector3) -> void:
	pass


func stop_special_orders() -> void:
	pass


# ---------------------------------------------------------------------------
# Combat / health
# ---------------------------------------------------------------------------
func take_damage(amount: int, attacker = null) -> void:
	if not is_alive:
		return
	health -= amount
	_update_health_bar()
	if health <= 0:
		die("combat")
	elif attacker:
		_on_attacked(attacker)


func set_health_display(value: int) -> void:
	health = value
	_update_health_bar()


func _on_attacked(_attacker) -> void:
	pass


func _update_health_bar() -> void:
	if health_bar and health_bar.has_method("set_ratio"):
		health_bar.set_ratio(float(health) / float(max_health))


func die(_cause: String = "unknown") -> void:
	if not is_alive:
		return
	is_alive = false
	died.emit(self)
	NetworkCommands.server_kill_unit(self, _cause)
	queue_free()
