class_name ResourceNode
extends StaticBody3D

## A depletable world resource (tree, water, ...) that citizens gather directly
## via command_gather / the auto-job AI. Shrinks visually as it's consumed and
## dims when empty. 3D port: lives on the ground plane.

@export var resource_type: String = "wood"  # "wood", "food", "water"
@export var amount: int = 120
@export var resource_group: String = "wood_sources"

var max_amount: int
var selected: bool = false
var _selection_ring: MeshInstance3D = null
# Base scale applied by MeshSwapper — stored here so _refresh_visual can
# shrink the model proportionally without referencing the autoload directly.
var _mesh_base_scale: Vector3 = Vector3.ONE * 18.0

@onready var sprite: Node = get_node_or_null("Mesh")


func _ready() -> void:
	max_amount = amount
	add_to_group("resources")
	add_to_group(resource_group)


func harvest(requested: int) -> int:
	var actual = mini(requested, amount)
	amount -= actual
	_refresh_visual()
	if amount <= 0:
		_deplete()
	return actual


func is_depleted() -> bool:
	return amount <= 0


func set_selected(value: bool) -> void:
	selected = value
	if value and _selection_ring == null:
		_selection_ring = _make_ground_ring(28.0, Color(0, 1, 0, 0.5))
		add_child(_selection_ring)
	if _selection_ring:
		_selection_ring.visible = value


func _make_ground_ring(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.5
	mi.mesh = disc
	mi.position.y = 0.3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = c
	mi.material_override = mat
	return mi


func _refresh_visual() -> void:
	# Scale the visual down as the resource depletes. The swapper names the
	# model root "Mesh" whether it's a Kenney GLB or the placeholder box.
	var mesh_node := get_node_or_null("Mesh")
	if not mesh_node:
		return
	var ratio := float(amount) / float(max_axis_amount())
	# Read the current scale as the base the first time (MeshSwapper may have
	# set it to 18×; a placeholder box sits at scale 1).
	if mesh_node.scale.length() > 0.01:
		_mesh_base_scale = mesh_node.scale
	mesh_node.scale = _mesh_base_scale * maxf(ratio, 0.35)


func max_axis_amount() -> int:
	return max_amount if max_amount > 0 else 1


func _deplete() -> void:
	remove_from_group("resources")
	remove_from_group(resource_group)
	# Hide the model (Kenney GLB or placeholder box) rather than try to
	# override a material we might not own.
	var mesh_node := get_node_or_null("Mesh")
	if mesh_node:
		mesh_node.visible = false
