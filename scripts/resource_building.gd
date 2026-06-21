class_name ResourceBuilding
extends Building

## Shared base for the three gatherable-resource buildings (Farm, Lumber
## Camp, Quarry). Holds a small worker-slot system and an internal stockpile
## that assigned citizens draw from with `harvest()`. Centralising this here
## is what the original prototype was missing — farm/lumber_camp/quarry each
## reimplemented (and slightly diverged on) the same worker-slot logic.

@export var max_workers: int = 3
@export var base_production_rate: float = 1.0  # stockpile units / second / worker
@export var max_stockpile: int = 60
@export var resource_group: String = ""  # "farms" / "lumber_camps" / "quarries"

var workers: Array = []
var stockpile: float = 0.0


func _ready() -> void:
	super._ready()
	if resource_group != "":
		add_to_group(resource_group)


func _process(delta: float) -> void:
	super._process(delta)

	if not is_constructed:
		return
	var active = 0
	for w in workers:
		if is_instance_valid(w):
			active += 1
	if active == 0:
		return
	stockpile = minf(stockpile + base_production_rate * active * delta, max_stockpile)


func assign_worker(worker) -> bool:
	workers = workers.filter(func(w): return is_instance_valid(w))
	if workers.size() >= max_workers:
		return false
	if worker in workers:
		return true
	workers.append(worker)
	return true


func remove_worker(worker) -> void:
	workers.erase(worker)


func harvest(amount_requested: int) -> int:
	var actual = mini(amount_requested, int(stockpile))
	stockpile -= actual
	return actual


func worker_count() -> int:
	return workers.filter(func(w): return is_instance_valid(w)).size()
