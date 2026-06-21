class_name Farm
extends Building

@export var food_production: float = 2.0
@export var max_food_storage: int = 50

var stored_food: int = 0
var production_timer: float = 0.0

func _ready():
	super._ready()
	add_to_group("resources")
	add_to_group("food_sources")
	add_to_group("farmsteads")

func _process(_delta):
	if not is_constructed:
		return

	production_timer += _delta
	if production_timer >= 1.0:
		production_timer = 0
		stored_food = min(stored_food + int(food_production), max_food_storage)

func gather(amount: int) -> int:
	return gather_food(amount)

func gather_food(amount: int) -> int:
	var actual = min(amount, stored_food)
	stored_food -= actual
	return actual

func is_depleted() -> bool:
	# A farmstead is never "used up" like a tree - a worker should keep
	# waiting at it for the next batch of food rather than wandering off.
	return false

func has_food_ready() -> bool:
	return stored_food > 0
