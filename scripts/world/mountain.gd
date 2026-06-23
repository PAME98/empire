class_name Mountain
extends StaticBody3D

@export var stone_amount: int = 9000
@export var iron_amount: int = 4500  # 0 = an ordinary mountain with no iron

var max_stone: int
var max_iron: int
var selected: bool = false
var _selection_ring: MeshInstance3D = null

func _ready() -> void:
	max_stone = stone_amount
	max_iron = iron_amount
	add_to_group("mountains")
	_refresh_groups()

func remaining(resource: String) -> int:
	match resource:
		"stone": return stone_amount
		"iron": return iron_amount
	return 0

func harvest(resource: String, requested: int) -> int:
	var actual := 0
	match resource:
		"stone":
			actual = mini(requested, stone_amount)
			stone_amount -= actual
		"iron":
			actual = mini(requested, iron_amount)
			iron_amount -= actual
	_refresh_groups()
	return actual

func is_depleted(resource: String = "") -> bool:
	match resource:
		"stone": return stone_amount <= 0
		"iron": return iron_amount <= 0
	return stone_amount <= 0 and iron_amount <= 0

func _refresh_groups() -> void:
	_set_in_group("stone_sources", stone_amount > 0)
	_set_in_group("iron_sources", iron_amount > 0)

func _set_in_group(group_name: String, want: bool) -> void:
	if want and not is_in_group(group_name):
		add_to_group(group_name)
	elif not want and is_in_group(group_name):
		remove_from_group(group_name)

func set_selected(value: bool) -> void:
	selected = value
	if value and _selection_ring == null:
		_selection_ring = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 48.0
		disc.bottom_radius = 48.0
		disc.height = 0.5
		_selection_ring.mesh = disc
		_selection_ring.position.y = 0.3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 1, 0, 0.5)
		_selection_ring.material_override = mat
		add_child(_selection_ring)
	if _selection_ring:
		_selection_ring.visible = value
