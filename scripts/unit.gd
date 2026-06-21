class_name Unit
extends CharacterBody2D

## Shared base for every player/AI controlled unit (citizens AND soldiers).
## Handles: movement, selection ring, health bar, basic combat resolution.
## Subclasses override `_on_command_move/_on_command_attack/_on_command_gather`
## hooks rather than re-implementing input handling, so the camera controller
## (RTS input layer) can treat every unit uniformly.

signal died(unit)

@export var speed: float = 90.0
@export var max_health: int = 100
@export var team: int = 0

var health: int
var selected: bool = false
var is_alive: bool = true

var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var move_arrival_radius: float = 6.0

@onready var selection_ring: Node = get_node_or_null("SelectionRing")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")


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
	var to_target = target_position - global_position
	var distance = to_target.length()
	if distance > move_arrival_radius:
		velocity = to_target.normalized() * speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		is_moving = false
		_on_reached_target()


func _on_reached_target() -> void:
	pass


func move_to(pos: Vector2) -> void:
	target_position = pos
	is_moving = true


func stop() -> void:
	is_moving = false
	velocity = Vector2.ZERO


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
# The camera/input controller calls these without knowing which subclass it
# is talking to, which is what keeps multi-unit right-click orders working
# uniformly across citizens and soldiers.
# ---------------------------------------------------------------------------
func command_move(pos: Vector2) -> void:
	stop_special_orders()
	move_to(pos)


func command_attack(_target) -> void:
	pass  # overridden by Soldier


func command_gather(_resource_node) -> void:
	pass  # overridden by Citizen


func command_build(_site) -> void:
	pass  # overridden by Citizen


func stop_special_orders() -> void:
	pass  # subclasses clear job/target state here


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
	if health_bar:
		health_bar.value = float(health) / float(max_health) * 100.0


func die(_cause: String = "unknown") -> void:
	if not is_alive:
		return
	is_alive = false
	died.emit(self)
	queue_free()
