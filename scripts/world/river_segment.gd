class_name RiverSegment
extends StaticBody3D
## A single straight stretch of river between two consecutive path points.
## Handles COLLISION ONLY — visuals are handled entirely by the Kenney
## river tile meshes placed by MapGenerator._place_river().
@export var resource_type: String = "water"
@export var amount: int = 99999
@export var resource_group: String = "water_sources"
var max_amount: int

func _ready() -> void:
	max_amount = amount
	add_to_group("resources")
	add_to_group(resource_group)
	add_to_group("rivers")
	add_to_group("obstacles")

## Water is effectively infinite; harvesting (citizens filling water jugs)
## never depletes or removes collision.
func harvest(requested: int) -> int:
	return mini(requested, amount)

func is_depleted() -> bool:
	return false

## Builds one segment's collision stretched and rotated to exactly cover
## the gap between `from` and `to`, with the given width.
## No visual mesh — the Kenney tile placed on top handles the look.
static func build_segment(from: Vector3, to: Vector3, width: float, depth: float = 6.0) -> RiverSegment:
	var seg := RiverSegment.new()
	var mid := (from + to) * 0.5
	var diff := to - from
	var length := diff.length()
	if length < 0.001:
		length = 0.001
	seg.position = mid
	# Orient the segment's local Z axis along the river's direction of travel.
	var yaw := atan2(diff.x, diff.z)
	seg.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, depth, length)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = depth * 0.5
	seg.add_child(col)
	return seg
