class_name DroppedResource
extends Node3D

## A loose pile of a harvested good sitting on the ground — the "crops lay on
## the ground after harvest for citizens to pick up" half of the field loop.
## Fields spawn these on harvest; idle citizens (HAULER job) claim one, walk to
## it, pick it up, and carry it to the nearest storage building.
##
## Deliberately a Node3D with NO collision: a pile must not block navigation —
## citizens just path to its global_position. It's discoverable through the
## "dropped_items" group and removes itself once emptied.
##
## CLAIMING: a hauler claims a pile before walking to it so two haulers don't
## both target the same one and one arrive to find it gone. The claim is a soft
## reservation; release() clears it if the hauler dies or gives up.
##
## NETWORKING (v1): piles are spawned by Field._harvest, which only runs on the
## sim authority, so in single-player this peer is the only simulator and stays
## consistent. Cross-peer replication of loose piles is a follow-up (same
## staged approach the rest of the economy's logistics already uses) — until
## then, in a networked game only the host spawns/simulates pickup.

const GROUP := "dropped_items"

@export var resource_type: String = "wheat"
@export var amount: int = 1

var max_amount: int = 1
var _claimant: Node = null
var _mesh: MeshInstance3D = null


## Drop `p_amount` of `p_type` near `origin`, parented under `parent`
## (typically the scene's "Resources" node). `spread` randomises the landing
## spot so multiple piles from one harvest don't stack on the exact same point.
static func spawn(p_type: String, p_amount: int, origin: Vector3, parent: Node, spread: float = 18.0) -> DroppedResource:
	if p_amount <= 0 or parent == null:
		return null
	var pile := DroppedResource.new()
	pile.resource_type = p_type
	pile.amount = p_amount
	parent.add_child(pile)
	var off := Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	pile.global_position = origin + off
	return pile


func _ready() -> void:
	max_amount = maxi(amount, 1)
	add_to_group(GROUP)
	add_to_group("dropped_" + resource_type)
	_build_visual()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, 8, 12)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_for(resource_type)
	_mesh.material_override = mat
	_mesh.position.y = 4.0
	add_child(_mesh)
	_refresh_scale()


func _color_for(t: String) -> Color:
	match t:
		"wheat", "grain", "flour": return Color(0.85, 0.7, 0.2)
		"vegetables":              return Color(0.4, 0.65, 0.3)
		"meat":                    return Color(0.7, 0.35, 0.3)
		"wood":                    return Color(0.55, 0.4, 0.25)
		"stone":                   return Color(0.6, 0.6, 0.62)
		_:                         return Color(0.8, 0.75, 0.5)


func _refresh_scale() -> void:
	if _mesh == null:
		return
	var ratio := clampf(float(amount) / float(max_amount), 0.3, 1.0)
	_mesh.scale = Vector3(ratio, ratio, ratio)


## A hauler reserves this pile. Returns false if someone else already has it.
func claim(by: Node) -> bool:
	if _claimant != null and is_instance_valid(_claimant) and _claimant != by:
		return false
	_claimant = by
	return true


func is_claimed_by_other(by: Node) -> bool:
	return _claimant != null and is_instance_valid(_claimant) and _claimant != by


func release(by: Node) -> void:
	if _claimant == by:
		_claimant = null


## Remove up to `requested` units; returns how many were actually taken, and
## frees the pile when it empties.
func take(requested: int) -> int:
	var taken := mini(requested, amount)
	amount -= taken
	if amount <= 0:
		remove_from_group(GROUP)
		remove_from_group("dropped_" + resource_type)
		queue_free()
	else:
		_refresh_scale()
	return taken


func is_empty() -> bool:
	return amount <= 0
