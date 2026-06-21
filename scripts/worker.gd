class_name Worker
extends Unit

enum Task { IDLE, MOVING_TO_RESOURCE, GATHERING_WOOD, GATHERING_FOOD, RETURNING, BUILDING }

@export var gather_speed: float = 1.0
@export var carry_capacity: int = 10
@export var gather_range: float = 60.0
@export var deliver_range: float = 75.0
@export var chop_bob_height: float = 4.0
@export var chop_bob_speed: float = 8.0

var current_task_enum: Task = Task.IDLE
var target_resource = null
var target_building = null
var carried_resource: String = ""
var carried_amount: int = 0
var gather_timer: float = 0.0
var chop_time: float = 0.0
var last_job_type: String = "wood"

@onready var interact_range = $InteractRange
@onready var sprite = $Sprite2D
@onready var wood_icon: ColorRect = $WoodIcon

var sprite_base_pos: Vector2

func _ready():
	super._ready()
	if sprite:
		sprite_base_pos = sprite.position
	if wood_icon:
		wood_icon.visible = false

func _process(delta):
	match current_task_enum:
		Task.MOVING_TO_RESOURCE:
			_approach_resource()
		Task.GATHERING_WOOD, Task.GATHERING_FOOD:
			_gather_resource(delta)
		Task.RETURNING:
			_approach_delivery()
		Task.BUILDING:
			_build_structure(delta)

	_update_chop_animation(delta)
	_update_carry_indicator()

func _approach_resource():
	if not is_instance_valid(target_resource):
		_find_more_work()
		return

	if global_position.distance_to(target_resource.global_position) > gather_range:
		move_to(target_resource.global_position)
	else:
		is_moving = false
		current_task_enum = Task.GATHERING_WOOD if target_resource.is_in_group("wood_sources") else Task.GATHERING_FOOD
		gather_timer = 0.0

func _gather_resource(delta):
	if not is_instance_valid(target_resource) or (target_resource.is_depleted() and not _is_standing_job(target_resource)):
		if carried_amount > 0:
			_begin_return()
		else:
			_find_more_work()
		return

	if global_position.distance_to(target_resource.global_position) > gather_range:
		current_task_enum = Task.MOVING_TO_RESOURCE
		return

	is_moving = false
	gather_timer += delta

	if gather_timer >= 1.0 / gather_speed:
		gather_timer = 0.0
		var amount = min(carry_capacity - carried_amount, target_resource.gather(1))
		carried_amount += amount
		if amount > 0:
			carried_resource = "wood" if target_resource.is_in_group("wood_sources") else "food"

		if carried_amount >= carry_capacity:
			_begin_return()
		elif target_resource.is_depleted() and not _is_standing_job(target_resource):
			_begin_return()

func _is_standing_job(resource) -> bool:
	# Farmsteads (and similar production buildings) are a standing post:
	# a worker should wait there for more output rather than wander off.
	return resource.is_in_group("farmsteads")

func _begin_return():
	var centers = get_tree().get_nodes_in_group("village_centers")
	var nearest = null
	var min_dist = INF

	for center in centers:
		if center.team == team and is_instance_valid(center):
			var dist = global_position.distance_to(center.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = center

	if nearest == null:
		# Nowhere to deliver to; just keep chopping where possible.
		current_task_enum = Task.GATHERING_WOOD if carried_resource != "food" else Task.GATHERING_FOOD
		return

	target_building = nearest
	current_task_enum = Task.RETURNING
	move_to(nearest.global_position)

func _approach_delivery():
	if not is_instance_valid(target_building):
		_find_more_work()
		return

	if global_position.distance_to(target_building.global_position) > deliver_range:
		move_to(target_building.global_position)
	else:
		is_moving = false
		_deliver_resources()

func _deliver_resources():
	if carried_amount > 0:
		if carried_resource == "food":
			GameManager.add_resources(carried_amount, 0)
		else:
			GameManager.add_resources(0, carried_amount)

	carried_amount = 0
	carried_resource = ""

	# Keep the job: head back to the same job site if it's still good,
	# otherwise look for more work of the same kind.
	if is_instance_valid(target_resource) and (_is_standing_job(target_resource) or not target_resource.is_depleted()):
		current_task_enum = Task.MOVING_TO_RESOURCE
	else:
		_find_more_work()

func _find_more_work():
	if last_job_type == "food":
		_find_new_resource_or_idle("food_sources")
	else:
		_find_new_resource_or_idle("wood_sources")

func _find_new_resource_or_idle(group_name: String):
	var sources = get_tree().get_nodes_in_group(group_name)
	var nearest = null
	var min_dist = INF

	for source in sources:
		if is_instance_valid(source) and (not source.is_depleted() or _is_standing_job(source)):
			var dist = global_position.distance_to(source.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = source

	if nearest:
		target_resource = nearest
		current_task_enum = Task.MOVING_TO_RESOURCE
	else:
		target_resource = null
		current_task_enum = Task.IDLE
		is_moving = false

func _build_structure(delta):
	if not is_instance_valid(target_building):
		current_task_enum = Task.IDLE
		return

	if global_position.distance_to(target_building.global_position) > deliver_range:
		move_to(target_building.global_position)
		return

	is_moving = false
	target_building.build_progress += delta * 10

	if target_building.build_progress >= target_building.build_time:
		target_building.finish_building()
		current_task_enum = Task.IDLE
		target_building = null

func _update_chop_animation(delta):
	if not sprite:
		return

	if current_task_enum == Task.GATHERING_WOOD or current_task_enum == Task.GATHERING_FOOD:
		chop_time += delta * chop_bob_speed
		sprite.position = sprite_base_pos + Vector2(0, -abs(sin(chop_time)) * chop_bob_height)
	else:
		chop_time = 0.0
		sprite.position = sprite_base_pos

func _update_carry_indicator():
	if not wood_icon:
		return

	if carried_amount > 0:
		wood_icon.visible = true
		wood_icon.color = Color(0.45, 0.27, 0.1, 1) if carried_resource == "wood" else Color(0.9, 0.75, 0.2, 1)
		wood_icon.scale = Vector2.ONE * clamp(float(carried_amount) / carry_capacity, 0.4, 1.0)
	else:
		wood_icon.visible = false

func assign_gather(resource):
	target_resource = resource
	current_task_enum = Task.MOVING_TO_RESOURCE
	gather_timer = 0.0
	last_job_type = "food" if resource.is_in_group("food_sources") else "wood"
	
func assign_return(building):
	target_building = building
	current_task_enum = Task.RETURNING

func assign_build(building):
	target_building = building
	current_task_enum = Task.BUILDING

func command_move(pos: Vector2):
	# Player override: drop whatever job we were doing and just walk.
	current_task_enum = Task.IDLE
	target_resource = null
	target_building = null
	move_to(pos)

func _on_input_event(_viewport, event, _shape_idx):
	super._on_input_event(_viewport, event, _shape_idx)
