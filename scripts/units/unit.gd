class_name Unit
extends CharacterBody3D
## Shared base for every player/AI controlled unit (citizens AND soldiers).
## 3D port: units live on the ground plane (XZ); Y is height and stays 0.
## Movement, selection ring, health, and basic combat all resolve here so the
## camera/input layer can treat every unit uniformly.
##
## NAVIGATION: movement goes through a NavigationAgent3D child instead of
## walking a straight line toward target_position. With the navmesh baked by
## MapGenerator (which excludes mountains/trees/rivers and requires the
## generator's NavFloor collider to exist so there's walkable surface to
## bake in the first place), this is what makes those obstacles actually
## block units in a way that *looks* intentional — units route around them
## — rather than just stalling against the edge.
##
## If this unit's scene doesn't have a NavigationAgent3D child, one is
## created automatically in _ready() so existing .tscn files don't need to
## be hand-edited.

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

@onready var selection_ring: Node = get_node_or_null("SelectionRing")
@onready var health_bar: Node = get_node_or_null("HealthBar")

var nav_agent: NavigationAgent3D
var _nav_ready: bool = false

# Stall detection: a known NavigationAgent3D limitation lets an agent cut a
# static obstacle's corner tightly enough to clip just outside the navmesh,
# at which point it can stop making forward progress while still technically
# "navigating" (is_navigation_finished() stays false, but global_position
# barely changes frame to frame). Tracked here so _step_toward_target can
# notice this and force a recovery instead of leaving the unit stuck against
# the obstacle indefinitely.
var _last_progress_check_pos: Vector3 = Vector3.ZERO
var _stall_timer: float = 0.0
const _STALL_TIME_THRESHOLD: float = 0.6   # seconds of near-zero progress before recovering
const _STALL_MOVE_EPSILON: float = 2.0     # units of movement below which we count as "not progressing"


func _ready() -> void:
	health = max_health
	add_to_group("units")
	if selection_ring:
		selection_ring.visible = false
	_update_health_bar()
	_setup_navigation()


func _setup_navigation() -> void:
	nav_agent = get_node_or_null("NavigationAgent3D")
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		# This Unit is still inside its own _ready() (and Citizen/Soldier's
		# _ready(), which calls super._ready() before doing their own setup)
		# when this runs. add_child() on self while self is mid-setup throws
		# "Parent node is busy setting up children". Deferring queues the
		# add for once _ready() has fully returned.
		add_child.call_deferred(nav_agent)

	# Wait for the deferred add_child above to actually run, AND for the
	# navigation server to sync after a region bake.
	await get_tree().process_frame
	await get_tree().physics_frame

	if not nav_agent.is_inside_tree():
		push_warning("Unit._setup_navigation: nav_agent still not in tree on " + name)
		return

	# path_desired_distance kept small and deliberately SMALLER than the
	# baked navmesh's erosion margin (NAV_AGENT_RADIUS, currently 10). A
	# known NavigationAgent3D limitation (acknowledged upstream, not fully
	# fixable via config alone: godotengine/godot#88237) lets agents cut
	# corners of static colliders tightly enough to clip outside the
	# navmesh and stall against the obstacle's actual collision shape. A
	# smaller desired distance makes the agent commit to its next waypoint
	# sooner — i.e. turn earlier — leaving more clearance at the corner
	# instead of cutting close to it.
	nav_agent.path_desired_distance = 2.0
	nav_agent.target_desired_distance = move_arrival_radius
	# Radius should roughly match this unit's collision footprint so the
	# agent doesn't path through gaps narrower than the unit actually is.
	var col := get_node_or_null("CollisionShape3D")
	if col and col.shape is CapsuleShape3D:
		nav_agent.radius = col.shape.radius
	elif col and col.shape is CylinderShape3D:
		nav_agent.radius = col.shape.radius
	else:
		nav_agent.radius = 8.0

	# Avoidance is what makes units steer around EACH OTHER, on top of the
	# static navmesh routing them around terrain/buildings. Without this,
	# every unit just walks its own shortest path and physically shoves
	# into anyone else doing the same, relying on move_and_slide() collision
	# alone — which looks like units getting stuck on each other in a crowd.
	nav_agent.avoidance_enabled = true
	nav_agent.radius = max(nav_agent.radius, 8.0)
	nav_agent.max_speed = speed
	nav_agent.neighbor_distance = 80.0
	nav_agent.max_neighbors = 8
	nav_agent.time_horizon_agents = 1.5
	nav_agent.time_horizon_obstacles = 0.5

	nav_agent.velocity_computed.connect(_on_velocity_computed)
	_nav_ready = true


func _physics_process(delta: float) -> void:
	if is_moving:
		_step_toward_target(delta)


func _step_toward_target(delta: float) -> void:
	if not _nav_ready or nav_agent == null or not nav_agent.is_inside_tree():
		# Navigation hasn't finished its deferred setup yet (can happen if a
		# command arrives the same frame a unit spawns). Fall back to a
		# direct walk so the unit still moves; once nav_agent is ready, the
		# next move_to() call switches back to real pathing.
		_step_direct(delta)
		return

	if nav_agent.is_navigation_finished():
		# is_navigation_finished() only means "reached the end of the
		# COMPUTED path" — that path's endpoint gets silently clamped by the
		# navmesh to the nearest reachable point if the requested
		# target_position fell inside an obstacle's eroded margin (every
		# obstacle erodes NAV_AGENT_RADIUS-ish of walkable ground from its
		# own edge; a target right next to a tree/mountain/building can
		# legitimately land inside that margin). That's a normal, expected
		# outcome when moving right up next to an obstacle — not a failure —
		# so it's treated as arrival rather than retried forever.
		velocity = Vector3.ZERO
		is_moving = false
		_stall_timer = 0.0
		_on_reached_target()
		return

	# Stall detection: still actively navigating (not finished), but if
	# global_position hasn't meaningfully changed for a while, the agent is
	# very likely clipped against an obstacle corner (acknowledged upstream
	# NavigationAgent3D limitation — see godotengine/godot#88237). Recover
	# by forcing the path to recompute AND nudging slightly away from the
	# obstacle so the agent isn't asking for a path from the exact stuck
	# point it just failed to leave.
	var moved_since_last_check := global_position.distance_to(_last_progress_check_pos)
	if moved_since_last_check < _STALL_MOVE_EPSILON:
		_stall_timer += delta
		if _stall_timer >= _STALL_TIME_THRESHOLD:
			_stall_timer = 0.0
			_recover_from_stall()
			_last_progress_check_pos = global_position
			return
	else:
		_stall_timer = 0.0
		_last_progress_check_pos = global_position

	var next_point := nav_agent.get_next_path_position()
	var to_next := next_point - global_position
	to_next.y = 0.0

	if to_next.length() < 0.01:
		# get_next_path_position() returning our own current position can
		# mean we're standing exactly on the next waypoint (harmless, next
		# tick advances) OR that no path has been computed yet for this
		# target (the navmesh wasn't ready, or the agent's start/end point
		# briefly fell outside it). Re-asserting the target nudges the
		# server to retry rather than leaving the unit stuck here forever.
		if not nav_agent.is_target_reached() and nav_agent.get_current_navigation_path().is_empty():
			nav_agent.target_position = target_position
			_step_direct(delta)  # keep moving via fallback while retrying
		return

	var desired_velocity := to_next.normalized() * speed

	if nav_agent.avoidance_enabled:
		# set_velocity will trigger velocity_computed -> _on_velocity_computed,
		# which actually applies movement (lets other agents avoid each other).
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


## Called when _step_toward_target detects no meaningful progress for
## _STALL_TIME_THRESHOLD seconds while still actively navigating — almost
## always an agent clipped against an obstacle's corner (see comment at the
## call site). CharacterBody3D already tracks the actual physical contacts
## from its last move_and_slide() call, which is a much more reliable source
## for "which way is free" than guessing — push away from the nearest real
## collision normal, then ask the navigation server for a fresh path from
## this new position so it isn't re-requesting a route from the exact spot
## it just got clipped at.
func _recover_from_stall() -> void:
	var push := Vector3.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		push += collision.get_normal()
	if push.length() > 0.01:
		push = push.normalized()
	else:
		# No recent collision info to go on — fall back to stepping back
		# the way we came, which at minimum gets off whatever degenerate
		# point the agent got wedged into.
		push = -velocity.normalized() if velocity.length() > 0.01 else Vector3.FORWARD

	global_position += push * (move_arrival_radius * 0.5)
	if nav_agent:
		nav_agent.target_position = target_position


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
	if _nav_ready and nav_agent and nav_agent.is_inside_tree():
		nav_agent.target_position = pos
	# else: _step_toward_target() falls back to a direct walk using
	# target_position until nav_agent finishes its deferred setup.


## True once the navigation agent itself reports it cannot get any closer to
## the current target — e.g. because the requested point is inside/behind an
## obstacle and the navmesh's erosion margin keeps the reachable area farther
## away than a hand-computed "interaction range" assumed. Callers that wait
## on a raw distance check (Citizen's gather/build/deliver logic) should also
## accept this as "close enough", or a unit can get stuck waiting to close a
## gap the navmesh will never actually let it close.
func has_stalled_near_target() -> bool:
	if not _nav_ready or nav_agent == null or not nav_agent.is_inside_tree():
		return false
	return is_moving and nav_agent.is_navigation_finished()


func stop() -> void:
	is_moving = false
	velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
func set_selected(value: bool) -> void:
	selected = value
	if selection_ring:
		selection_ring.visible = value


func is_selectable_by_player() -> bool:
	return team == 0 and is_alive


# ---------------------------------------------------------------------------
# RTS command hooks — every concrete unit implements the ones it cares about.
# ---------------------------------------------------------------------------
func command_move(pos: Vector3) -> void:
	stop_special_orders()
	move_to(pos)


func command_attack(_target) -> void:
	pass  # overridden by Soldier


func command_gather(_resource_node) -> void:
	pass  # overridden by Citizen


func command_build(_site) -> void:
	pass  # overridden by Citizen


func command_attack_position(_world_pos: Vector3) -> void:
	pass  # overridden by Artillery


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
	queue_free()
