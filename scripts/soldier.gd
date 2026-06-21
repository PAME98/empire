class_name Soldier
extends Unit

@export var attack_damage: int = 15
@export var attack_range: float = 40.0
@export var attack_cooldown: float = 1.0

var target_enemy = null
var attack_timer: float = 0.0

func _process(_delta):
	if target_enemy and is_instance_valid(target_enemy):
		var dist = global_position.distance_to(target_enemy.global_position)

		if dist <= attack_range:
			is_moving = false
			attack_timer += _delta
			if attack_timer >= attack_cooldown:
				attack_timer = 0
				_attack()
		else:
			move_to(target_enemy.global_position)
	else:
		target_enemy = null

func _attack():
	if target_enemy and target_enemy.has_method("take_damage"):
		target_enemy.take_damage(attack_damage)

func assign_attack_target(enemy):
	target_enemy = enemy

func command_move(pos: Vector2):
	target_enemy = null
	move_to(pos)

func _on_input_event(_viewport, event, _shape_idx):
	super._on_input_event(_viewport, event, _shape_idx)
