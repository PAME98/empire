class_name Unit
extends CharacterBody3D

## Shared base for every player/AI controlled unit (citizens AND soldiers).
## 3D port: units live on the ground plane (XZ); Y is height and stays 0.
## Movement, selection ring, health, and basic combat all resolve here so the
## camera/input layer can treat every unit uniformly.

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


func _ready() -> void:
	health = max_health
	add_to_group("units")
	if selection_ring:
		selection_ring.visible = false
	_update_health_bar()


func _physics_process(delta: float) -> void:
	if is_moving:
		_step_toward_target(delta)


func _step_toward_target(_delta: float) -> void:
	# Move only on the ground plane — ignore any Y component so units never
	# try to fly toward a target that's at a different height.
	var to_target := target_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > move_arrival_radius:
		velocity = to_target.normalized() * speed
		move_and_slide()
		# Face the direction of travel (yaw only).
		if velocity.length() > 0.01:
			var yaw := atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, yaw, 0.2)
	else:
		velocity = Vector3.ZERO
		is_moving = false
		_on_reached_target()


func _on_reached_target() -> void:
	pass


func move_to(pos: Vector3) -> void:
	target_position = pos
	is_moving = true


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
	# Health bars are shown in the HUD selection panel in the 3D build; if a
	# unit scene provides its own 3D bar with set_ratio(), drive it here.
	if health_bar and health_bar.has_method("set_ratio"):
		health_bar.set_ratio(float(health) / float(max_health))


func die(_cause: String = "unknown") -> void:
	if not is_alive:
		return
	is_alive = false
	died.emit(self)
	queue_free()
