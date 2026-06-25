class_name ResourceBuilding
extends Building

## Shared base for the gatherable-resource buildings (Farm, Lumber Camp,
## Quarry, Mine). Holds a small worker-slot system and an internal stockpile
## that assigned citizens draw from with `harvest()`.
##
## DEPOSIT-BACKED buildings (Quarry, Mine) set `deposit_group` to the group
## name of the Mountain they must sit on ("stone_sources" / "iron_sources").
## A Mountain holds separate stone and iron pools, so the SAME mountain can
## host both a quarry (drawing its stone) and a mine (drawing its iron). On
## placement the building binds to the nearest matching mountain and its
## production drains that mountain's pool for `yield_resource`; once the pool
## is empty, production stops. Buildings with an empty `deposit_group` (Farm,
## Lumber Camp) produce freely.
##
## NETWORKING: `_process` here mutates `stockpile` (this building's own state)
## and, for deposit-backed buildings, calls `host_deposit.harvest(...)` which
## mutates a Mountain's stone/iron pool — a piece of state SHARED by every
## building bound to that mountain, and visible to every peer. If this ran on
## every client too, each one would independently drain the mountain and
## accumulate its own stockpile, and those numbers would diverge from the
## host's within seconds. It must only run where GameManager.is_sim_authority()
## is true. worker_count()/deposit_remaining() stay safe to call anywhere
## since they only read state, and that state is whatever it last was on this
## peer — host-correct on the host, and (for now) display-only on a client
## until/unless a building-state sync is added alongside the existing
## resource/unit syncs.

@export var max_workers: int = 3
@export var base_production_rate: float = 1.0  # stockpile units / second / worker
@export var max_stockpile: int = 60
@export var resource_group: String = ""  # "farms" / "lumber_camps" / "quarries" / "mines"
@export var deposit_group: String = ""   # "" = produces freely; else must bind to a deposit
@export var yield_resource: String = ""  # what a worker carries away: food/wood/stone/iron

var workers: Array = []
var stockpile: float = 0.0
var host_deposit: Node = null    # a Mountain, set by bind_to_deposit() for deposit-backed buildings
var _depleted_notice_sent: bool = false


func _ready() -> void:
	super._ready()
	if resource_group != "":
		add_to_group(resource_group)


func _process(delta: float) -> void:
	super._process(delta)

	# Production is shared simulation state (this building's stockpile, and
	# for deposit-backed buildings, the bound Mountain's pool too). Only the
	# peer with simulation authority may advance it.
	if not GameManager.is_sim_authority():
		return

	if not is_constructed:
		return
	var active = 0
	for w in workers:
		if is_instance_valid(w):
			active += 1
	if active == 0:
		return

	var produced = base_production_rate * active * delta

	# Deposit-backed buildings can only produce what the bound mountain still
	# holds of *their* resource (stone for a quarry, iron for a mine).
	if deposit_group != "":
		if host_deposit == null or not is_instance_valid(host_deposit) or host_deposit.is_depleted(yield_resource):
			if not _depleted_notice_sent:
				_depleted_notice_sent = true
				GameManager.notify("%s deposit exhausted." % resource_group.capitalize())
			return
		var pulled = host_deposit.harvest(yield_resource, int(ceil(produced)))
		produced = minf(produced, float(pulled))

	stockpile = minf(stockpile + produced, max_stockpile)


## Called right after the building is placed. Finds the nearest Mountain in
## `deposit_group` (that still holds this building's resource) within `radius`;
## returns false if none.
func bind_to_deposit(radius: float = 64.0) -> bool:
	if deposit_group == "":
		return true  # free producers don't need a deposit
	var best: Node = null
	var best_dist = radius
	for node in get_tree().get_nodes_in_group(deposit_group):
		if not is_instance_valid(node):
			continue
		if node.has_method("remaining") and node.remaining(yield_resource) <= 0:
			continue  # this mountain is tapped out for our resource
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
	if host_deposit != null and is_instance_valid(host_deposit) and host_deposit.has_method("remaining"):
		return host_deposit.remaining(yield_resource)
	return -1   # not deposit-backed
