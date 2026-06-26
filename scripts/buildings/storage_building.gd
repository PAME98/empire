class_name StorageBuilding
extends Building

## Shared base for the places haulers drop goods and the economy draws from.
## Stockpile (small, cheap, open-air) and Warehouse (large, accepts everything)
## both extend this. Each storage building holds its OWN typed inventory up to
## `capacity` total units.
##
## The left resource bar shows the SUM of every storage building a team owns
## (Stockpiles, Warehouses, and the Village Center, which also stores goods).
## GameManager.recompute_storage(team) does that summation and pushes it to the
## UI through the existing resource-sync path, so team_resources[team] becomes a
## derived cache of "what's physically in this team's storage".
##
## NETWORKING: inventory is shared sim state mutated only under
## is_sim_authority(); the resulting per-team totals reach clients via the same
## GameManager -> server_sync_resources push the old global pool used.

const GROUP := "storage"

@export var capacity: int = 200
## Resource keys this building will accept. Empty = accept anything.
@export var accepts: Array[String] = []

var inventory: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)


func finish_building() -> void:
	var was := is_constructed
	super.finish_building()
	if is_constructed and not was:
		GameManager.recompute_storage(team)


func destroy() -> void:
	# Drop out of the storage group BEFORE freeing and recomputing so this
	# building's contents aren't counted in the new total.
	remove_from_group(GROUP)
	var t := team
	GameManager.recompute_storage(t)
	super.destroy()


func accepts_resource(type: String) -> bool:
	return accepts.is_empty() or type in accepts


func stored_total() -> int:
	var n := 0
	for k in inventory:
		n += inventory[k]
	return n


func free_space() -> int:
	return maxi(0, capacity - stored_total())


## Add up to `amt` of `type`; returns the amount actually stored. Overflow is
## the caller's to keep carrying to another storage building.
func deposit(type: String, amt: int) -> int:
	if not is_constructed or amt <= 0 or not accepts_resource(type):
		return 0
	var stored := mini(amt, free_space())
	if stored <= 0:
		return 0
	inventory[type] = inventory.get(type, 0) + stored
	GameManager.recompute_storage(team)
	return stored


## Remove up to `amt` of `type`; returns how many were removed.
func withdraw(type: String, amt: int) -> int:
	var have: int = inventory.get(type, 0)
	var taken := mini(amt, have)
	if taken <= 0:
		return 0
	inventory[type] = have - taken
	if inventory[type] <= 0:
		inventory.erase(type)
	GameManager.recompute_storage(team)
	return taken
