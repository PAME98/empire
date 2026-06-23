class_name Artillery
extends Unit

## Long-range siege unit. Slow and fragile compared to a Soldier, and unlike
## Soldier it never auto-engages nearby enemies on its own — real artillery
## only fires on command, so it just sits idle until ordered. Two ways to
## give it a target, both ending in the same area-of-effect shell landing:
##   - Right-click an enemy (same as Soldier): walks into range and keeps
##     bombarding that target's position for as long as it's alive/in range.
##   - Press T then left-click open ground: bombards a fixed point once —
##     a single ground-targeted strike, the way you'd call in a fire mission.
## Every shot has a short aim/windup before it actually lands, telegraphed
## by the barrel swinging onto the target and a shrinking ring at the
## impact point, so a hit never feels instant or unfair.

@export var attack_damage: int = 50
@export var splash_radius: float = 90.0
@export var attack_range: float = 1000.0
@export var min_range: float = 60.0      # too close and the gun can't depress enough to fire
@export var attack_cooldown: float = 2.4
@export var aim_time: float = 0.5        # windup before each shell lands
@export var friendly_fire: bool = true   # area strikes hit anyone in the blast, including own team

var attack_target = null              # enemy Node, set by right-click-on-enemy orders
var attack_position: Vector3 = Vector3.ZERO
var has_attack_position: bool = false  # true while a T+left-click bombardment is pending
var has_player_order: bool = false

var _attack_timer: float = 0.0
var _aiming: bool = false
var _aim_timer: float = 0.0
var _aim_point: Vector3 = Vector3.ZERO
var _reticle: AttackAreaIndicator = null

@onready var sprite: Node = get_node_or_null("Mesh")
@onready var barrel: Node3D = get_node_or_null("Barrel")

const EXPLOSION_SCENE := preload("res://scenes/effects/explosion_effect.tscn")
const RETICLE_SCENE := preload("res://scenes/effects/attack_area_indicator.tscn")


func _ready() -> void:
	super._ready()
	add_to_group("artillery")
	speed = 55.0
	max_health = 70
	health = max_health


func _process(delta: float) -> void:
	if not is_alive:
		return

	if _has_valid_attack_target():
		_run_attack_cycle(delta, attack_target.global_position, attack_target)
	elif has_attack_position:
		_run_attack_cycle(delta, attack_position, null)
	# Deliberately no idle aggro-scan here, unlike Soldier — artillery only
	# fires when the player tells it to.


func _has_valid_attack_target() -> bool:
	if not is_instance_valid(attack_target):
		return false
	if "is_alive" in attack_target and not attack_target.is_alive:
		return false
	return true


func _run_attack_cycle(delta: float, target_pos: Vector3, target_unit) -> void:
	if barrel:
		# Yaw the barrel toward the target on the ground plane.
		var to_t := target_pos - global_position
		barrel.rotation.y = atan2(to_t.x, to_t.z)

	var dist = global_position.distance_to(target_pos)
	if dist > attack_range or dist < min_range:
		stop()
		_cancel_aim()
		_move_into_firing_envelope(target_pos, dist)
		return

	stop()
	if _aiming:
		_aim_timer += delta
		if _reticle:
			_reticle.set_progress(_aim_timer / aim_time)
		if _aim_timer >= aim_time:
			_fire(_aim_point)
			_aiming = false
			_attack_timer = 0.0
				# One-shot ground bombardment — the order is complete.
	else:
		_attack_timer += delta
		if _attack_timer >= attack_cooldown:
			_start_aim(target_pos)


func _move_into_firing_envelope(target_pos: Vector3, dist: float) -> void:
	var dir = (global_position - target_pos).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	var stand_dist = clampf(dist, min_range + 20.0, attack_range - 30.0)
	move_to(target_pos + dir * stand_dist)


func _start_aim(pos: Vector3) -> void:
	_aiming = true
	_aim_timer = 0.0
	_aim_point = pos
	if _reticle == null:
		_reticle = RETICLE_SCENE.instantiate()
		_effects_parent().add_child(_reticle)
	_reticle.set_mode("aiming")
	_reticle.global_position = pos
	_reticle.set_radius(splash_radius)
	_reticle.set_progress(0.0)
	_reticle.visible = true


func _cancel_aim() -> void:
	_aiming = false
	_aim_timer = 0.0
	if _reticle:
		_reticle.queue_free()
		_reticle = null


func _fire(pos: Vector3) -> void:
	if _reticle:
		_reticle.queue_free()
		_reticle = null

	var explosion: ExplosionEffect = EXPLOSION_SCENE.instantiate()
	_effects_parent().add_child(explosion)
	explosion.global_position = pos
	explosion.detonate(splash_radius)

	_apply_splash_damage(pos)


func _apply_splash_damage(pos: Vector3) -> void:
	var targets: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u != self:
			targets.append(u)
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b):
			targets.append(b)

	for node in targets:
		if not friendly_fire and "team" in node and node.team == team:
			continue
		var d = pos.distance_to(node.global_position)
		if d > splash_radius:
			continue
		var falloff = 1.0 - (d / splash_radius) * 0.6  # edge of the blast still does 40%
		var dmg = int(round(attack_damage * falloff))
		if dmg <= 0:
			continue
		if node is Building:
			node.take_damage(dmg)  # Building.take_damage takes no attacker arg
		elif node.has_method("take_damage"):
			node.take_damage(dmg, self)


func _effects_parent() -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return self
	var effects = scene.get_node_or_null("Effects")
	return effects if effects else scene


# ---------------------------------------------------------------------------
# RTS commands
# ---------------------------------------------------------------------------
func command_move(pos: Vector3) -> void:
	has_player_order = true
	attack_target = null
	has_attack_position = false
	_cancel_aim()
	move_to(pos)


func command_attack(target) -> void:
	has_player_order = true
	attack_target = target
	has_attack_position = false
	_cancel_aim()


func command_attack_position(pos: Vector3) -> void:
	has_player_order = true
	attack_target = null
	attack_position = pos
	has_attack_position = true
	_cancel_aim()
	if global_position.distance_to(pos) > attack_range:
		move_to(pos)


func stop_special_orders() -> void:
	has_player_order = false
	attack_target = null
	has_attack_position = false
	_cancel_aim()


func _on_reached_target() -> void:
	has_player_order = false


func die(cause: String = "unknown") -> void:
	if not is_alive:
		return
	is_alive = false
	_cancel_aim()
	GameManager.remove_population(self, cause)
	died.emit(self)
	queue_free()
