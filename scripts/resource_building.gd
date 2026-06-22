class_name ResourceBuilding
extends Building

## Shared base for the gatherable-resource buildings (Farm, Lumber Camp,
## Quarry, Mine). Holds a small worker-slot system and an internal stockpile
## that assigned citizens draw from with `harvest()`.
##
## DEPOSIT-BACKED buildings (Quarry, Mine) set `deposit_group` to the group
## name of the world ResourceNode they must sit on ("stone_sources" /
## "iron_sources"). On placement they bind to the nearest such node and their
## production drains it; once the deposit is empty, production stops.
## Buildings with an empty `deposit_group` (Farm, Lumber Camp) produce freely
## as before.

@export var max_workers: int = 3
@export var base_production_rate: float = 1.0  # stockpile units / second / worker
@export var max_stockpile: int = 60
@export var resource_group: String = ""  # "farms" / "lumber_camps" / "quarries" / "mines"
@export var deposit_group: String = ""   # "" = produces freely; else must bind to a deposit

var workers: Array = []
var stockpile: float = 0.0
var host_deposit: ResourceNode = null    # set by bind_to_deposit() for deposit-backed buildings
var _depleted_notice_sent: bool = false


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

	var produced = base_production_rate * active * delta

	# Deposit-backed buildings can only produce what the deposit still holds.
	if deposit_group != "":
		if host_deposit == null or not is_instance_valid(host_deposit) or host_deposit.is_depleted():
			if not _depleted_notice_sent:
				_depleted_notice_sent = true
				GameManager.notify("%s deposit exhausted." % resource_group.capitalize())
			return
		var pulled = host_deposit.harvest(int(ceil(produced)))
		produced = minf(produced, float(pulled))

	stockpile = minf(stockpile + produced, max_stockpile)


## Called right after the building is placed. Finds the nearest world
## ResourceNode in `deposit_group` within `radius`; returns false if none.
func bind_to_deposit(radius: float = 48.0) -> bool:
	if deposit_group == "":
		return true  # free producers don't need a deposit
	var best: ResourceNode = null
	var best_dist = radius
	for node in get_tree().get_nodes_in_group(deposit_group):
		if not is_instance_valid(node):
			continue
		var d = global_position.distance_to(node.global_position)
		if d <= best_dist:
			best_dist = d
			best = node
	if best == null:
		return false
	host_deposit = best
	return true


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


func deposit_remaining() -> int:
	if host_deposit != null and is_instance_valid(host_deposit):
		return host_deposit.amount
	return -1   # not deposit-backed
