class_name Soldier
extends Unit

## Military unit. Always under direct RTS control when selected — no economy
## behaviour. Right-click an enemy to attack, right-click ground to move.
## Idle soldiers (no order) will engage nearby enemies on their own so a
## standing army actually defends itself, but never wander off to gather or
## build — that ambiguity was part of what broke the old prototype.

@export var attack_damage: int = 14
@export var attack_range: float = 46.0
@export var attack_cooldown: float = 1.0
@export var aggro_range: float = 220.0

var attack_target = null
var has_player_order: bool = false
var _attack_timer: float = 0.0

@onready var sprite: Node = get_node_or_null("Mesh")


func _ready() -> void:
	super._ready()
	add_to_group("soldiers")
	speed = 95.0
	max_health = 150
	health = max_health


func _process(delta: float) -> void:
	if not is_alive:
		return

	if _has_valid_attack_target():
		_pursue_and_attack(delta)
	elif not has_player_order:
		_look_for_nearby_enemy()


func _has_valid_attack_target() -> bool:
	if not is_instance_valid(attack_target):
		return false
	if "is_alive" in attack_target and not attack_target.is_alive:
		return false
	return true


func _pursue_and_attack(delta: float) -> void:
	var dist = global_position.distance_to(attack_target.global_position)
	if dist <= attack_range:
		stop()
		_attack_timer += delta
		if _attack_timer >= attack_cooldown:
			_attack_timer = 0.0
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(attack_damage, self)
	else:
		move_to(attack_target.global_position)


func _look_for_nearby_enemy() -> void:
	var nearest = null
	var nearest_dist = aggro_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			var d = global_position.distance_to(enemy.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = enemy
	if nearest:
		attack_target = nearest


# ---------------------------------------------------------------------------
# RTS commands
# ---------------------------------------------------------------------------
func command_move(pos: Vector3) -> void:
	has_player_order = true
	attack_target = null
	move_to(pos)


func command_attack(target) -> void:
	has_player_order = true
	attack_target = target


func stop_special_orders() -> void:
	has_player_order = false
	attack_target = null


func _on_reached_target() -> void:
	has_player_order = false


func die(cause: String = "unknown") -> void:
	if not is_alive:
		return
	is_alive = false
	GameManager.remove_population(self, cause)
	died.emit(self)
	queue_free()
